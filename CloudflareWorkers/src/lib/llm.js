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

/**
 * 构造转发到上游的 Header：移除 BFF 专有头，注入上游 Authorization
 * @param {Headers} headers
 * @param {string} apiKey
 * @returns {Headers}
 */
export function buildUpstreamHeaders(headers, apiKey) {
  const out = new Headers(headers);
  out.delete("X-BFF-Token");
  out.delete("X-Provider");
  out.set("Authorization", "Bearer " + apiKey);
  return out;
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

  const upstreamUrl = upstream.baseUrl.replace(/\/$/, "") + "/v1/chat/completions";
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
        const delta = parseSSEEvent(rawEvent);
        if (delta) yield delta;
      }
    }
    // 处理尾部残余
    if (buffer.trim()) {
      const delta = parseSSEEvent(buffer);
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

/**
 * 解析单条 SSE 事件，返回增量文本（若为 [DONE] 或无 content 则返回 null）
 * @param {string} rawEvent
 * @returns {string|null}
 */
function parseSSEEvent(rawEvent) {
  // 取 data: 行
  const lines = rawEvent.split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) continue;
    const data = trimmed.slice(5).trim();
    if (!data || data === "[DONE]") return null;
    try {
      const obj = JSON.parse(data);
      const delta = obj && obj.choices && obj.choices[0] && obj.choices[0].delta;
      if (delta && typeof delta.content === "string" && delta.content.length > 0) {
        return delta.content;
      }
    } catch (_) {
      // 忽略解析失败的事件（如 keep-alive 注释）
    }
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
