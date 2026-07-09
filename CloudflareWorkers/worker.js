/**
 * Aether BFF 代理 Cloudflare Worker
 *
 * 职责：
 * 1. 校验 X-BFF-Token（从 KV `bff_tokens` 查询合法性）
 * 2. 按 X-Provider 路由到上游（DeepSeek / Qwen），从 Secrets 读取对应上游 API Key 并注入 Authorization
 * 3. 服务端限流：每 token 每分钟 60 次（内存计数器，简化版）
 * 4. 流式转发响应（保持 SSE 连接，用 ReadableStream + TransformStream 透传）
 *
 * 错误约定（与 iOS BFFProxyClient 对齐）：
 * - 401：BFF Token 缺失/无效
 * - 429：服务端限流（携带 Retry-After Header）
 * - 5xx：BFF 服务异常（上游不可达等）
 *
 * 绑定：
 * - KV `bff_tokens`：键为 BFF Token 字符串，值为用户标识/元数据（存在即合法）
 * - env.DEEPSEEK_API_KEY / env.QWEN_API_KEY：通过 `wrangler secret put` 配置，不在 wrangler.toml 明文存储
 * - env.DEEPSEEK_BASE_URL / env.QWEN_BASE_URL：在 wrangler.toml [vars] 中配置
 */

// 服务端限流：每 token 每分钟允许的请求数
const RATE_LIMIT_PER_MIN = 60;

// 内存计数器：token -> { count, windowStart }
// 注意：基于单个 Worker 实例内存，非全局持久化；不同实例间不共享。
// 生产环境如需精确限流，建议改用 Durable Objects 或 KV 计数器。
const rateLimitMap = new Map();

export default {
  async fetch(request, env, ctx) {
    // 仅允许 POST（chat completions / embeddings）
    if (request.method !== "POST") {
      return jsonError(405, "Method Not Allowed");
    }

    // 1. 校验 BFF Token：缺失或 KV 未命中则 401
    const bffToken = request.headers.get("X-BFF-Token");
    if (!bffToken) {
      return jsonError(401, "BFF Token 缺失");
    }
    const tokenRecord = await env.bff_tokens.get(bffToken);
    if (!tokenRecord) {
      return jsonError(401, "BFF Token 无效");
    }

    // 2. 服务端限流：每 token 每分钟 RATE_LIMIT_PER_MIN 次，超额返回 429
    if (isRateLimited(bffToken)) {
      return new Response(JSON.stringify({ error: "rate limited" }), {
        status: 429,
        headers: {
          "Content-Type": "application/json",
          "Retry-After": "60",
        },
      });
    }

    // 3. 按 X-Provider 路由到上游：解析 baseUrl + apiKey
    const provider = request.headers.get("X-Provider") || "deepseek";
    const upstream = resolveUpstream(provider, env);
    if (!upstream) {
      return jsonError(400, "未知的 X-Provider: " + provider);
    }

    // 4. 构造上游请求：保留原 path（/v1/chat/completions 或 /v1/embeddings），
    //    剥离 BFF 专有 Header，注入上游 Authorization
    const url = new URL(request.url);
    const upstreamUrl = upstream.baseUrl + url.pathname;
    const upstreamReq = new Request(upstreamUrl, {
      method: request.method,
      headers: buildUpstreamHeaders(request.headers, upstream.apiKey),
      body: request.body,
    });

    // 5. 转发并流式返回
    try {
      const upstreamResp = await fetch(upstreamReq);

      // 上游 2xx：流式透传 SSE（ReadableStream + TransformStream 透传）
      if (upstreamResp.ok) {
        const { readable, writable } = new TransformStream();
        // 后台管道：上游 body → writable → readable，不阻塞 Response 返回
        ctx.waitUntil(upstreamResp.body.pipeTo(writable).catch(() => {}));
        return new Response(readable, {
          status: upstreamResp.status,
          headers: forwardHeaders(upstreamResp.headers),
        });
      }

      // 上游非 2xx：透传状态码与错误体（iOS 端按 429→rateLimited / 5xx→服务异常 映射）
      // 若上游 429 未携带 Retry-After，补一个默认值
      const respHeaders = forwardHeaders(upstreamResp.headers);
      if (upstreamResp.status === 429 && !respHeaders.has("Retry-After")) {
        respHeaders.set("Retry-After", "60");
      }
      const errBody = await upstreamResp.text();
      return new Response(errBody, {
        status: upstreamResp.status,
        headers: respHeaders,
      });
    } catch (err) {
      // 上游请求失败（DNS / 连接 / 超时）：返回 502 让 iOS 端映射为「BFF 服务异常」
      return jsonError(502, "BFF 服务异常: " + (err && err.message ? err.message : "upstream unreachable"));
    }
  },
};

/// 解析上游 endpoint 与 API Key
/// - deepseek → env.DEEPSEEK_BASE_URL + env.DEEPSEEK_API_KEY
/// - qwen → env.QWEN_BASE_URL + env.QWEN_API_KEY
function resolveUpstream(provider, env) {
  switch (provider) {
    case "deepseek":
      return { baseUrl: env.DEEPSEEK_BASE_URL, apiKey: env.DEEPSEEK_API_KEY };
    case "qwen":
      return { baseUrl: env.QWEN_BASE_URL, apiKey: env.QWEN_API_KEY };
    default:
      return null;
  }
}

/// 构造转发到上游的 Header：移除 BFF 专有头（X-BFF-Token / X-Provider），注入上游 Authorization
function buildUpstreamHeaders(headers, apiKey) {
  const out = new Headers(headers);
  out.delete("X-BFF-Token");
  out.delete("X-Provider");
  out.set("Authorization", "Bearer " + apiKey);
  return out;
}

/// 透传上游响应 Header（保留 Content-Type 等用于 SSE 流式响应）
function forwardHeaders(headers) {
  const out = new Headers();
  for (const [key, value] of headers.entries()) {
    out.set(key, value);
  }
  return out;
}

/// 限流检查：滑动窗口每 60 秒重置，每 token 允许 RATE_LIMIT_PER_MIN 次。
/// 超额返回 true（调用方返回 429）。
function isRateLimited(token) {
  const now = Date.now();
  let entry = rateLimitMap.get(token);
  if (!entry || now - entry.windowStart >= 60_000) {
    entry = { count: 0, windowStart: now };
    rateLimitMap.set(token, entry);
  }
  entry.count += 1;
  return entry.count > RATE_LIMIT_PER_MIN;
}

/// 构造 JSON 错误响应
function jsonError(status, message) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
