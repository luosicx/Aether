/**
 * Aether BFF 跨平台业务网关 - 路由入口
 *
 * 职责：
 * 1. 鉴权：所有受保护端点经 X-BFF-Token (KV `bff_tokens`) 校验（键为 token 的 SHA-256 哈希）
 * 2. 限流：所有受保护端点按 userId 限流（chat 60/min，其余 600/min，内存令牌桶）；
 *    鉴权失败按来源 IP 限流（120/min），缓解 token 暴力枚举
 * 3. 路由分发：基于 URL pathname 分发到 src/routes/* 模块
 * 4. CORS：OPTIONS 预检 + Origin 白名单（env.ALLOWED_ORIGINS，逗号分隔；未配置则禁止跨域）
 * 5. 兜底：LLM 透传代理仅放行白名单路径（/v1/chat/completions 等），其余 404
 *
 * 错误约定（与 iOS BFFProxyClient 对齐）：
 * - 401：BFF Token 缺失/无效
 * - 429：服务端限流（携带 Retry-After Header）
 * - 5xx：BFF 服务异常（客户端仅收通用信息，细节进服务端日志）
 *
 * 绑定：
 * - KV `bff_tokens`：键为 token 的 SHA-256 哈希（sha256:<hex>），值为用户标识/元数据；
 *   旧明文键在首次命中时自动迁移（见 src/lib/auth.js）
 * - D1 `DB`：业务数据库（schema.sql）
 * - env.DEEPSEEK_API_KEY / env.QWEN_API_KEY：secrets
 * - env.DEEPSEEK_BASE_URL / env.QWEN_BASE_URL / env.ALLOWED_ORIGINS：vars
 */

import { authenticate } from "./src/lib/auth.js";
import { checkRateLimit, rateLimitResponse } from "./src/lib/ratelimit.js";
import {
  resolveUpstream,
  buildUpstreamHeaders,
  forwardHeaders,
  joinUpstreamUrl,
  jsonError,
} from "./src/lib/llm.js";
import { redact } from "./src/lib/redact.js";

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

// LLM 透传代理白名单：仅放行上游对话/嵌入/模型端点，
// 防止任意路径透传 + 注入上游 API Key（等同把上游凭证借给客户端）
const PROXY_ALLOWED_PATHS = new Set([
  "/v1/chat/completions",
  "/v1/completions",
  "/v1/embeddings",
  "/v1/models",
]);

/**
 * CORS：解析 Origin 白名单（env.ALLOWED_ORIGINS，逗号分隔）
 * 未配置白名单或 Origin 不在白名单内时不下发任何 CORS 头（浏览器侧自然拦截）
 */
function corsHeaders(request, env) {
  const origin = request.headers.get("Origin");
  if (!origin) return null;
  const allowed = String(env.ALLOWED_ORIGINS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (!allowed.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-BFF-Token, X-Provider",
    "Access-Control-Expose-Headers": "Retry-After",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

/** OPTIONS 预检响应（204，无 body） */
function preflightResponse() {
  return new Response(null, { status: 204 });
}

/** 为响应附加 CORS 头（Origin 不在白名单或未携带时原样返回） */
function withCors(request, env, resp) {
  const headers = corsHeaders(request, env);
  if (!headers) return resp;
  const out = new Response(resp.body, resp);
  for (const [key, value] of Object.entries(headers)) {
    out.headers.set(key, value);
  }
  return out;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // CORS 预检：在路由匹配前统一拦截
    if (method === "OPTIONS") {
      return withCors(request, env, preflightResponse());
    }

    try {
      // ============ 受保护的业务端点 ============
      // 需鉴权；chat 端点 60/min，其余 600/min（见 dispatch）
      const routeResult = matchRoute(method, path);
      let resp;
      if (routeResult) {
        resp = await dispatch(routeResult, request, env, ctx);
      } else if (method === "POST" && PROXY_ALLOWED_PATHS.has(path)) {
        // ============ LLM 透传代理（仅白名单路径可达）============
        resp = await proxyLLM(request, env, ctx);
      } else {
        // 未匹配：返回 404（不回显 method/path 细节）
        resp = jsonError(404, "Not Found");
      }
      return withCors(request, env, resp);
    } catch (err) {
      // 兜底异常：客户端只返回通用信息，细节进服务端日志
      console.error("BFF 内部错误:", err && err.message);
      return withCors(request, env, jsonError(500, "BFF 内部错误"));
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
    // 鉴权失败按来源 IP 限流，缓解 token 暴力枚举（CF-Connecting-IP 由 Cloudflare 注入）
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const ipRl = await checkRateLimit("authfail:" + ip, env, 120);
    if (!ipRl.allowed) {
      return rateLimitResponse(ipRl.retryAfter);
    }
    return jsonError(401, "BFF Token 缺失或无效");
  }

  // 2. 限流：所有受保护端点统一按 userId 限流
  //    chat 端点维持 60/min（独立键空间）；其余端点 600/min
  //    注：内存令牌桶仅对单个 Worker isolate 生效，跨边缘节点的全局限流待 Durable Objects（第三批）
  const limitKey = route.rateLimited ? "chat:" + auth.userId : "api:" + auth.userId;
  const rl = await checkRateLimit(limitKey, env, route.rateLimited ? 60 : 600);
  if (!rl.allowed) {
    return rateLimitResponse(rl.retryAfter);
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
 * LLM 透传代理（向后兼容，仅白名单路径可达，见 PROXY_ALLOWED_PATHS）
 *
 *   1. 复用 authenticate 校验 BFF Token（SHA-256 哈希 KV 键 + 旧 token 自动迁移）
 *   2. 限流（按 userId，60/min，与 chat 端点同口径）
 *   3. 按 X-Provider 路由到上游，Header 白名单构造并注入 Authorization
 *   4. 流式透传响应（TransformStream pipeTo）；上游错误体经 redact 脱敏后回显
 */
async function proxyLLM(request, env, ctx) {
  // 1. 校验 BFF Token（与业务端点同一套鉴权）
  const auth = await authenticate(request, env);
  if (!auth) {
    return jsonError(401, "BFF Token 缺失或无效");
  }

  // 2. 限流：按 userId，与 chat 端点同口径（60/min）
  const rl = await checkRateLimit("chat:" + auth.userId, env, 60);
  if (!rl.allowed) {
    return rateLimitResponse(rl.retryAfter);
  }

  // 3. 按 X-Provider 路由到上游
  const provider = request.headers.get("X-Provider") || "deepseek";
  const upstream = resolveUpstream(provider, env);
  if (!upstream) {
    return jsonError(400, "未知的 X-Provider");
  }

  // 4. 构造上游请求：URL 归一化（避免 /v1/v1 双拼）+ Header 白名单构造
  const url = new URL(request.url);
  const upstreamUrl = joinUpstreamUrl(upstream.baseUrl, url.pathname);
  const upstreamInit = {
    method: request.method,
    headers: buildUpstreamHeaders(request.headers, upstream.apiKey),
    body: request.body,
  };
  // 流式 body 必须声明 duplex（Node/undici 测试环境要求；Workers runtime 兼容）
  if (upstreamInit.body) upstreamInit.duplex = "half";
  const upstreamReq = new Request(upstreamUrl, upstreamInit);

  // 5. 转发并流式返回
  try {
    const upstreamResp = await fetch(upstreamReq);

    // 上游 2xx：流式透传 SSE
    if (upstreamResp.ok) {
      const { readable, writable } = new TransformStream();
      ctx.waitUntil(upstreamResp.body.pipeTo(writable).catch(() => {}));
      return new Response(readable, {
        status: upstreamResp.status,
        headers: forwardHeaders(upstreamResp.headers),
      });
    }

    // 上游非 2xx：错误体脱敏后透传（不回显内部 trace / 配额信息）
    const respHeaders = forwardHeaders(upstreamResp.headers);
    if (upstreamResp.status === 429 && !respHeaders.has("Retry-After")) {
      respHeaders.set("Retry-After", "60");
    }
    let errBody;
    try {
      errBody = await redact(await upstreamResp.text());
    } catch (_) {
      errBody = JSON.stringify({ error: "upstream error", status: upstreamResp.status });
    }
    return new Response(errBody, {
      status: upstreamResp.status,
      headers: respHeaders,
    });
  } catch (err) {
    console.error("proxyLLM upstream error:", err && err.message);
    return jsonError(502, "BFF 服务异常: 上游不可达");
  }
}
