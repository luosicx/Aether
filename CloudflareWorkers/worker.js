/**
 * Aether BFF 跨平台业务网关 - 路由入口
 *
 * 职责：
 * 1. 鉴权：所有受保护端点经 X-BFF-Token (KV `bff_tokens`) 校验
 * 2. 限流：chat 端点每 userId 每分钟 60 次（内存计数器）
 * 3. 路由分发：基于 URL pathname 分发到 src/routes/* 模块
 * 4. 兜底：仅 /v1/chat/completions 与 /v1/embeddings 走 LLM 透传代理（路径/模型白名单 + 1 MiB 上限）
 *
 * 错误约定（与 iOS BFFProxyClient 对齐）：
 * - 401：BFF Token 缺失/无效
 * - 429：服务端限流（携带 Retry-After Header）
 * - 5xx：BFF 服务异常
 *
 * 绑定：
 * - KV `bff_tokens`：键为 BFF Token 字符串，值为用户标识/元数据
 * - D1 `DB`：业务数据库（schema.sql）
 * - env.DEEPSEEK_API_KEY / env.QWEN_API_KEY：secrets
 * - env.DEEPSEEK_BASE_URL / env.QWEN_BASE_URL：vars
 */

import { authenticate } from "./src/lib/auth.js";
import { checkRateLimit, rateLimitResponse } from "./src/lib/ratelimit.js";
import {
  resolveUpstream,
  buildUpstreamHeaders,
  forwardHeaders,
  jsonError,
} from "./src/lib/llm.js";

import { handleChatStream } from "./src/routes/chat.js";
import {
  handleListConversations,
  handleCreateConversation,
  handleGetConversation,
  handleUpdateConversation,
  handleDeleteConversation,
} from "./src/routes/conversations.js";
import {
  handleListMessages,
  handleDeleteMessage,
  handleSubmitFeedback,
} from "./src/routes/messages.js";
import {
  handleListMemory,
  handleCreateMemory,
  handleSearchMemory,
  handleDeleteMemory,
} from "./src/routes/memory.js";
import {
  handleSearchDocuments,
  handleUploadDocument,
} from "./src/routes/rag.js";
import {
  handleUploadHealthSummary,
  handleGetHealthSummary,
} from "./src/routes/health.js";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    try {
      // ============ 受保护的业务端点 ============
      // 需鉴权；chat 端点额外限流
      const routeResult = matchRoute(method, path);
      if (routeResult) {
        return await dispatch(routeResult, request, env, ctx);
      }

      // ============ 兜底：保留原 LLM 透传代理行为 ============
      // 仅允许 POST 到明确的上游路径，避免 BFF 沦为任意路径转发器
      if (method === "POST") {
        return await proxyLLM(request, env, ctx);
      }

      // 未匹配且非 POST：返回 404
      return jsonError(404, "Not Found: " + method + " " + path);
    } catch (err) {
      // 兜底异常：返回 500，避免 Worker 崩溃暴露堆栈
      return jsonError(
        500,
        "BFF 内部错误: " + (err && err.message ? err.message : "unknown")
      );
    }
  },
};

/**
 * 路由匹配：返回 {handler, params, protected} 或 null
 * @param {string} method
 * @param {string} path
 * @returns {{handler:string, params:Object, rateLimited?:boolean}|null}
 */
function matchRoute(method, path) {
  // 去除末尾斜杠（保留根路径）
  const cleanPath = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
  const segments = cleanPath.split("/").filter(Boolean);

  // POST /chat/stream
  if (method === "POST" && segments.length === 2 && segments[0] === "chat" && segments[1] === "stream") {
    return { handler: "chat.stream", params: {}, rateLimited: true };
  }

  // /conversations 系列路由
  if (segments[0] === "conversations") {
    if (segments.length === 1) {
      if (method === "GET") return { handler: "conversations.list", params: {} };
      if (method === "POST") return { handler: "conversations.create", params: {} };
    } else if (segments.length === 2) {
      const id = decodeURIComponent(segments[1]);
      if (method === "GET") return { handler: "conversations.get", params: { id } };
      if (method === "PATCH") return { handler: "conversations.update", params: { id } };
      if (method === "DELETE") return { handler: "conversations.delete", params: { id } };
    } else if (segments.length === 3 && segments[2] === "messages" && method === "GET") {
      const conversationId = decodeURIComponent(segments[1]);
      return { handler: "messages.list", params: { conversationId } };
    }
  }

  // /messages 系列路由
  if (segments[0] === "messages") {
    if (segments.length === 2 && method === "DELETE") {
      const messageId = decodeURIComponent(segments[1]);
      return { handler: "messages.delete", params: { messageId } };
    }
    if (segments.length === 3 && segments[2] === "feedback" && method === "POST") {
      const messageId = decodeURIComponent(segments[1]);
      return { handler: "messages.feedback", params: { messageId } };
    }
  }

  // /memory 系列路由
  if (segments[0] === "memory") {
    if (segments.length === 1) {
      if (method === "GET") return { handler: "memory.list", params: {} };
      if (method === "POST") return { handler: "memory.create", params: {} };
    } else if (segments.length === 2 && segments[1] === "search" && method === "POST") {
      return { handler: "memory.search", params: {} };
    } else if (segments.length === 2 && method === "DELETE") {
      const id = decodeURIComponent(segments[1]);
      return { handler: "memory.delete", params: { id } };
    }
  }

  // /rag 系列路由
  if (segments[0] === "rag") {
    if (segments.length === 2 && segments[1] === "search" && method === "POST") {
      return { handler: "rag.search", params: {} };
    }
    if (segments.length === 2 && segments[1] === "documents" && method === "POST") {
      return { handler: "rag.upload", params: {} };
    }
  }

  // /health 系列路由
  if (segments[0] === "health" && segments[1] === "summary") {
    if (segments.length === 2 && method === "POST") {
      return { handler: "health.upload", params: {} };
    }
    if (segments.length === 3 && method === "GET") {
      const date = decodeURIComponent(segments[2]);
      return { handler: "health.get", params: { date } };
    }
  }

  return null;
}

/**
 * 分发到对应 handler
 * @param {{handler:string, params:Object, rateLimited?:boolean}} route
 * @param {Request} request
 * @param {Object} env
 * @param {Object} ctx - 原始 Workers ctx
 */
async function dispatch(route, request, env, ctx) {
  // 1. 鉴权
  const auth = await authenticate(request, env);
  if (!auth) {
    return jsonError(401, "BFF Token 缺失或无效");
  }

  // 2. 限流（仅 chat 端点）
  if (route.rateLimited) {
    const rl = await checkRateLimit(auth.userId, env, 60);
    if (!rl.allowed) {
      return rateLimitResponse(rl.retryAfter);
    }
  }

  // 3. 构造增强 ctx：注入 auth + 透传 waitUntil
  const routeCtx = {
    auth,
    waitUntil: ctx && typeof ctx.waitUntil === "function" ? ctx.waitUntil.bind(ctx) : undefined,
  };

  const p = route.params;
  switch (route.handler) {
    case "chat.stream":
      return await handleChatStream(request, env, routeCtx);

    case "conversations.list":
      return await handleListConversations(request, env, routeCtx);
    case "conversations.create":
      return await handleCreateConversation(request, env, routeCtx);
    case "conversations.get":
      return await handleGetConversation(request, env, routeCtx, p.id);
    case "conversations.update":
      return await handleUpdateConversation(request, env, routeCtx, p.id);
    case "conversations.delete":
      return await handleDeleteConversation(request, env, routeCtx, p.id);

    case "messages.list":
      return await handleListMessages(request, env, routeCtx, p.conversationId);
    case "messages.delete":
      return await handleDeleteMessage(request, env, routeCtx, p.messageId);
    case "messages.feedback":
      return await handleSubmitFeedback(request, env, routeCtx, p.messageId);

    case "memory.list":
      return await handleListMemory(request, env, routeCtx);
    case "memory.create":
      return await handleCreateMemory(request, env, routeCtx);
    case "memory.search":
      return await handleSearchMemory(request, env, routeCtx);
    case "memory.delete":
      return await handleDeleteMemory(request, env, routeCtx, p.id);

    case "rag.search":
      return await handleSearchDocuments(request, env, routeCtx);
    case "rag.upload":
      return await handleUploadDocument(request, env, routeCtx);

    case "health.upload":
      return await handleUploadHealthSummary(request, env, routeCtx);
    case "health.get":
      return await handleGetHealthSummary(request, env, routeCtx, p.date);

    default:
      return jsonError(404, "未知路由: " + route.handler);
  }
}

/**
 * 原 LLM 透传代理逻辑（向后兼容）
 *
 * 安全约束（P1-5）：
 *   1. 鉴权复用 authenticate()，强制执行 token TTL（expiresAt）
 *   2. 路径白名单：仅 /v1/chat/completions 与 /v1/embeddings，其余路径 404
 *   3. 模型白名单：按 provider 前缀校验，且路径与模型类型匹配
 *   4. 请求体上限 1 MiB，超限返回 413
 *   5. 只向上游转发必要 Header，避免透传客户端凭证/内部头
 */
const PROXY_ALLOWED_PATHS = new Set(["/v1/chat/completions", "/v1/embeddings"]);
const PROXY_MAX_BODY_BYTES = 1024 * 1024;
const PROXY_MODEL_PREFIXES = {
  deepseek: ["deepseek-"],
  qwen: ["qwen-", "qwq-", "text-embedding-"],
};

/**
 * 归一化代理路径：去除末尾斜杠（保留根路径）
 * @param {string} pathname
 * @returns {string}
 */
function normalizeProxyPath(pathname) {
  return pathname.length > 1 && pathname.endsWith("/")
    ? pathname.slice(0, -1)
    : pathname;
}

/**
 * 校验模型是否属于 provider 且与请求路径类型匹配
 * @param {string} provider
 * @param {string} path
 * @param {string} model
 * @returns {boolean}
 */
function isModelAllowed(provider, path, model) {
  const prefixes = PROXY_MODEL_PREFIXES[provider];
  if (!prefixes || typeof model !== "string" || !model) return false;
  if (!prefixes.some((prefix) => model.startsWith(prefix))) return false;
  const isEmbeddingPath = path === "/v1/embeddings";
  return isEmbeddingPath === model.includes("embedding");
}

/**
 * 读取请求体并强制大小上限（不信任 Content-Length，按实际字节数计数）
 * @param {Request} request
 * @param {number} maxBytes
 * @returns {Promise<{data: Uint8Array}|{tooLarge: true}>}
 */
async function readBodyWithLimit(request, maxBytes) {
  if (!request.body) return { data: new Uint8Array(0) };
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        return { tooLarge: true };
      }
      chunks.push(value);
    }
  } finally {
    try {
      reader.releaseLock();
    } catch (_) {
      /* noop */
    }
  }
  const data = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { data };
}

async function proxyLLM(request, env, ctx) {
  // 1. 鉴权：复用统一实现，确保 expiresAt 过期 token 被拒绝
  const auth = await authenticate(request, env);
  if (!auth) {
    return jsonError(401, "BFF Token 缺失或无效");
  }

  // 2. 路径白名单：禁止把 BFF 当作任意路径的上游代理
  const url = new URL(request.url);
  const path = normalizeProxyPath(url.pathname);
  if (!PROXY_ALLOWED_PATHS.has(path)) {
    return jsonError(
      404,
      "不支持的代理路径，仅支持 /v1/chat/completions 与 /v1/embeddings"
    );
  }

  // 3. 限流：按 userId 维度（与业务端点一致）
  const rl = await checkRateLimit(auth.userId, env, 60);
  if (!rl.allowed) {
    return rateLimitResponse(rl.retryAfter);
  }

  // 4. 按 X-Provider 路由到上游
  const provider = request.headers.get("X-Provider") || "deepseek";
  const upstream = resolveUpstream(provider, env);
  if (!upstream || !upstream.baseUrl || !upstream.apiKey) {
    return jsonError(400, "未知或未配置的 X-Provider: " + provider);
  }

  // 5. 读取请求体（大小上限 + JSON 解析 + 模型白名单）
  const bodyResult = await readBodyWithLimit(request, PROXY_MAX_BODY_BYTES);
  if (bodyResult.tooLarge) {
    return jsonError(413, "请求体超过 1 MiB 限制");
  }
  let text;
  let payload;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bodyResult.data);
    payload = JSON.parse(text);
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }
  if (!payload || typeof payload !== "object") {
    return jsonError(400, "请求体必须是 JSON 对象");
  }
  if (!isModelAllowed(provider, path, payload.model)) {
    return jsonError(400, "不支持的 model: " + String(payload.model));
  }

  // 6. 构造上游请求：仅转发必要 Header，注入上游 Authorization
  const upstreamUrl = upstream.baseUrl.replace(/\/$/, "") + path;
  const upstreamReq = new Request(upstreamUrl, {
    method: "POST",
    headers: buildUpstreamHeaders(request.headers, upstream.apiKey),
    body: text,
  });

  // 7. 转发并流式返回
  try {
    const upstreamResp = await fetch(upstreamReq);

    // 上游 2xx：流式透传 SSE
    if (upstreamResp.ok) {
      const respHeaders = forwardHeaders(upstreamResp.headers);
      if (!upstreamResp.body) {
        return new Response(null, {
          status: upstreamResp.status,
          headers: respHeaders,
        });
      }
      const { readable, writable } = new TransformStream();
      if (ctx && typeof ctx.waitUntil === "function") {
        ctx.waitUntil(upstreamResp.body.pipeTo(writable).catch(() => {}));
      } else {
        upstreamResp.body.pipeTo(writable).catch(() => {});
      }
      return new Response(readable, {
        status: upstreamResp.status,
        headers: respHeaders,
      });
    }

    // 上游非 2xx：透传状态码与错误体
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
    return jsonError(
      502,
      "BFF 服务异常: " + (err && err.message ? err.message : "upstream unreachable")
    );
  }
}
