/**
 * RAG 文本处理工具
 *
 * 文档检索与写入的 SQL 在 tenant-db.js（按 user_id 绑定租户），
 * 本模块只保留与 D1 无关的纯函数：分块与 token 估算。
 */

/**
 * 简单分块（兜底）：按固定字符数切分文档（中文友好，不按单词）。
 * 保留供 WASM 不可用时回退，正常流程请用异步 `chunkDocument`。
 * @param {string} text
 * @param {number} chunkSize - 每块字符数，默认 2048
 * @param {number} overlap - 重叠字符数，默认 256
 * @returns {Array<string>}
 */
export function chunkText(text, chunkSize = 2048, overlap = 256) {
  if (!text || typeof text !== "string") return [];
  const chunks = [];
  const step = Math.max(1, chunkSize - overlap);
  for (let i = 0; i < text.length; i += step) {
    chunks.push(text.slice(i, i + chunkSize));
    if (i + chunkSize >= text.length) break;
  }
  return chunks;
}

// Chunker WASM 懒加载单例（文档分块已迁移至 Rust aether-core-ffi，UAX #29 句子边界）
let _chunker = null;
async function getChunker() {
  if (_chunker) return _chunker;
  const mod = await import("../../wasm/aether_sse.js");
  await mod.default();
  _chunker = mod.Chunker;
  return _chunker;
}

/**
 * 文档分块（WASM）：按 UAX #29 句子边界切分，累积到 maxChars 后落盘，
 * 相邻块用 overlapChars 个字符拼接保证上下文连续。
 * 与 Apple `DocumentChunker` 算法一致，统一两端分块质量。
 * @param {string} text
 * @param {number} maxChars - 单块最大字符数，默认 2048
 * @param {number} overlapChars - 相邻块重叠字符数，默认 256
 * @returns {Promise<Array<string>>}
 */
export async function chunkDocument(text, maxChars = 2048, overlapChars = 256) {
  if (!text || typeof text !== "string") return [];
  try {
    const Chunker = await getChunker();
    const json = Chunker.chunkDocument(text, maxChars, overlapChars);
    const chunks = JSON.parse(json);
    return Array.isArray(chunks) ? chunks : [];
  } catch (err) {
    console.error("chunkDocument WASM error, fallback to chunkText:", err && err.message);
    return chunkText(text, maxChars, overlapChars);
  }
}

// TokenCounter WASM 懒加载单例（cosine 计算已迁移至 Rust aether-core-ffi）
let _tokenCounter = null;
async function getTokenCounter() {
  if (_tokenCounter) return _tokenCounter;
  const mod = await import("../../wasm/aether_sse.js");
  await mod.default();
  _tokenCounter = mod.TokenCounter;
  return _tokenCounter;
}

/**
 * 粗略估算字符串的 token 数（与 Swift `String.estimatedTokens` 算法一致）。
 * 算法：英文按空格分词 × 1.3 + 非 ASCII 字符 × 1.5。
 * 用于上下文窗口管理与文档分块预算估算。
 * @param {string} text
 * @returns {Promise<number>} 估算的 token 数
 */
export async function estimateTokens(text) {
  if (!text || typeof text !== "string") return 0;
  const TokenCounter = await getTokenCounter();
  return TokenCounter.estimateTokens(text);
}
