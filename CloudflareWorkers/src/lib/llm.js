/**
 * LLM 上游调用封装
 *
 * 从原 worker.js 提取并增强：
 * - resolveUpstream: 按 provider 解析 baseUrl + apiKey
 * - callLLMStream: 流式调用 LLM，返回 async iterable（SSE 增量文本）
 * - buildContext: 构建 OpenAI 兼容的 messages 上下文（system + 历史 + 记忆 + RAG）
 */

/**
 * 解析上游 endpoint 与 API Key
 * @param {string} provider - deepseek / qwen
 * @param {Object} env
 * @returns {{baseUrl: string, apiKey: string}|null}
 */
export function resolveUpstream(provider, env) {
  switch (provider) {
    case "deepseek":
      return { baseUrl: env.DEEPSEEK_BASE_URL, apiKey: env.DEEPSEEK_API_KEY };
    case "qwen":
      return { baseUrl: env.QWEN_BASE_URL, apiKey: env.QWEN_API_KEY };
    default:
      return null;
  }
}

// 上游转发 Header 白名单：仅保留无敏感语义的通用头，其余（Cookie / X-BFF-Token /
// X-Forwarded-* 等）一律剥离；Authorization 由 BFF 注入上游凭证，绝不透传客户端值
const UPSTREAM_ALLOWED_HEADERS = new Set(["content-type", "accept"]);

// 永久拒绝清单：即使通过 extraAllowed（env.UPSTREAM_EXTRA_HEADERS）配置也忽略，
// 防止运维误配置把凭证/代理类敏感头重新放开
const UPSTREAM_DENIED_HEADERS = new Set([
  "authorization",
  "proxy-authorization",
  "cookie",
  "x-bff-token",
  "x-provider",
  "host",
  "forwarded",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-real-ip",
]);

/**
 * 构造转发到上游的 Header：白名单构造 + 注入上游 Authorization
 *
 * 白名单 = 默认集（content-type / accept）∪ extraAllowed（逗号分隔，需小写规范化），
 * 但永久拒绝清单始终优先（交集为空）。
 *
 * @param {Headers} headers - 客户端原始请求头
 * @param {string} apiKey - 上游 API Key（注入 Authorization）
 * @param {string} [extraAllowed] - 附加白名单（逗号分隔 header 名，如 "x-request-id,x-app-version"）
 * @returns {Headers}
 */
export function buildUpstreamHeaders(headers, apiKey, extraAllowed) {
  const allowed = new Set(UPSTREAM_ALLOWED_HEADERS);
  if (typeof extraAllowed === "string" && extraAllowed) {
    for (const name of extraAllowed.split(",")) {
      const h = name.trim().toLowerCase();
      if (h && !UPSTREAM_DENIED_HEADERS.has(h)) {
        allowed.add(h);
      }
    }
  }

  const out = new Headers();
  for (const [key, value] of headers.entries()) {
    if (allowed.has(key.toLowerCase())) {
      out.set(key, value);
    }
  }
  out.set("Authorization", "Bearer " + apiKey);
  return out;
}

/**
 * 拼接上游 URL（归一化 /v1，避免双拼）
 *
 * - baseUrl 末尾斜杠容忍
 * - baseUrl 已以 /v1 结尾且 path 以 /v1/ 开头时去重（Qwen compatible-mode 兼容：
 *   https://x.com/compatible-mode/v1 + /v1/chat/completions → .../v1/chat/completions）
 *
 * @param {string} baseUrl - 上游基础 URL（可带或不带 /v1 后缀）
 * @param {string} path - 以 / 开头的 API 路径（如 /v1/chat/completions）
 * @returns {string}
 */
export function joinUpstreamUrl(baseUrl, path) {
  const base = String(baseUrl || "").replace(/\/+$/, "");
  let p = String(path || "");
  if (!p.startsWith("/")) p = "/" + p;
  if (/\/v1$/.test(base) && p.startsWith("/v1/")) {
    p = p.slice("/v1".length);
  }
  return base + p;
}

/**
 * 透传上游响应 Header（保留 Content-Type 等用于 SSE 流式响应）
 * @param {Headers} headers
 * @returns {Headers}
 */
export function forwardHeaders(headers) {
  const out = new Headers();
  for (const [key, value] of headers.entries()) {
    out.set(key, value);
  }
  return out;
}

/**
 * 构建发送给 LLM 的 messages 上下文（OpenAI 兼容格式）
 *
 * 结构：
 *   1. system prompt（会话级，含 RAG 注入的文档片段）
 *   2. 注入记忆段（若启用 memoryEnabled 且有 memories）
 *   3. 历史消息（user/assistant 交替）
 *   4. 当前用户消息
 *
 * @param {Array<{role:string, content:string}>} history - 历史消息（不含当前消息）
 * @param {Array<{content:string, category?:string, importance?:number}>} memories - 相关记忆
 * @param {Array<{content:string, title?:string}>} relevantDocs - RAG 检索到的文档分块
 * @param {{message:string, systemPrompt?:string}} current - 当前用户消息
 * @returns {Array<{role:string, content:string}>}
 */
export function buildContext(history, memories, relevantDocs, current) {
  const messages = [];

  // 1. system prompt
  const systemParts = [];
  systemParts.push(current.systemPrompt || "你是一个有帮助的AI助手。");

  // 2. 注入 RAG 文档片段
  if (relevantDocs && relevantDocs.length > 0) {
    const docBlock = relevantDocs
      .map((d, i) => `[文档${i + 1}]${d.title ? "《" + d.title + "》" : ""}\n${d.content}`)
      .join("\n\n");
    systemParts.push("以下是可参考的知识库文档片段，请在回答时酌情引用：\n" + docBlock);
  }

  // 3. 注入记忆
  if (memories && memories.length > 0) {
    const memBlock = memories
      .map((m) => `- ${m.content}${m.category ? "（" + m.category + "）" : ""}`)
      .join("\n");
    systemParts.push("以下是关于该用户的长期记忆，回答时请考虑这些信息：\n" + memBlock);
  }

  messages.push({ role: "system", content: systemParts.join("\n\n") });

  // 4. 历史消息
  for (const m of history || []) {
    if (m && m.role && m.content != null) {
      messages.push({ role: m.role, content: m.content });
    }
  }

  // 5. 当前用户消息
  messages.push({ role: "user", content: current.message });

  return messages;
}

/**
 * 流式调用 LLM，返回 async iterable，逐个 yield 增量文本片段
 *
 * 兼容 OpenAI / DeepSeek / Qwen 的 /v1/chat/completions SSE 格式：
 *   data: {"choices":[{"delta":{"content":"xxx"}}]}
 *
 * @param {Object} env
 * @param {string} model - 模型名（如 deepseek-chat / qwen-plus）
 * @param {Array<{role:string, content:string}>} messages
 * @param {Object} [opts] - { provider, temperature, max_tokens, signal }
 * @returns {AsyncGenerator<string, void, unknown>}
 */
export async function* callLLMStream(env, model, messages, opts = {}) {
  const provider = opts.provider || "deepseek";
  const upstream = resolveUpstream(provider, env);
  if (!upstream || !upstream.apiKey) {
    throw new Error("LLM 上游未配置: provider=" + provider);
  }

  const upstreamUrl = joinUpstreamUrl(upstream.baseUrl, "/v1/chat/completions");
  const payload = {
    model,
    messages,
    stream: true,
  };
  if (typeof opts.temperature === "number") payload.temperature = opts.temperature;
  if (typeof opts.max_tokens === "number") payload.max_tokens = opts.max_tokens;

  const resp = await fetch(upstreamUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + upstream.apiKey,
    },
    body: JSON.stringify(payload),
  });

  if (!resp.ok) {
    const errText = await resp.text().catch(() => "");
    throw new Error(`LLM 上游错误 ${resp.status}: ${errText}`);
  }

  if (!resp.body) {
    throw new Error("LLM 上游未返回流式响应");
  }

  // 逐行解析 SSE：data: {...}\n\n
  const reader = resp.body.getReader();
  const decoder = new TextDecoder("utf-8");
  let buffer = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // 按 SSE 事件分隔（双换行）
      let idx;
      while ((idx = buffer.indexOf("\n\n")) !== -1) {
        const rawEvent = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 2);
        const delta = await parseSSEEvent(rawEvent);
        if (delta) yield delta;
      }
    }
    // 处理尾部残余
    if (buffer.trim()) {
      const delta = await parseSSEEvent(buffer);
      if (delta) yield delta;
    }
  } finally {
    try {
      reader.releaseLock();
    } catch (_) {
      /* noop */
    }
  }
}

// 顶部：WASM 模块懒加载单例（首次调用 parseSSEEvent 时实例化）
// wasm-bindgen --target web 产物需先调用 default export (init) 完成异步初始化，
// 再实例化 SseState。init 内部有缓存，重复调用无副作用。
let _wasmState = null;
async function getWasmState() {
  if (_wasmState) return _wasmState;
  const mod = await import("../../wasm/aether_sse.js");
  await mod.default();
  _wasmState = new mod.SseState();
  return _wasmState;
}

/**
 * 解析单条 SSE 事件，返回增量文本（若为 [DONE] 或无 content 则返回 null）
 * 实现已迁移至 Rust（aether-core-ffi，wasm-pack 产物），JS 仅做 data: 行提取与 WASM 调用。
 * @param {string} rawEvent
 * @returns {Promise<string|null>}
 */
async function parseSSEEvent(rawEvent) {
  const wasm = await getWasmState();
  // 取 data: 行（保留原多行容错）
  const lines = rawEvent.split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) continue;
    const delta = wasm.extractContent(trimmed);
    if (delta) return delta;
  }
  return null;
}

/**
 * 构造 JSON 错误响应（与原 worker.js jsonError 对齐）
 * @param {number} status
 * @param {string} message
 * @returns {Response}
 */
export function jsonError(status, message) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
