/**
 * RAG 文档分块检索
 *
 * 支持两种检索模式：
 * 1. 向量检索（searchDocumentsByVector）：基于 embedding 余弦相似度，cosine 计算走 Rust WASM
 * 2. 关键词检索（searchDocuments）：SQL LIKE 兜底，embedding 不可用时使用
 */

// WASM VectorMath 懒加载单例（cosine 计算已迁移至 Rust aether-core-ffi）
let _vectorMath = null;
async function getVectorMath() {
  if (_vectorMath) return _vectorMath;
  const mod = await import("../../wasm/aether_sse.js");
  await mod.default();
  _vectorMath = mod.VectorMath;
  return _vectorMath;
}

/**
 * 向量检索：用 embedding 余弦相似度检索最相关分块。
 * 仅返回 embedding 非空的分块；无可用 embedding 时回退到关键词检索。
 * @param {Object} env - 含 D1 绑定 env.DB
 * @param {string} userId
 * @param {number[]} queryEmbedding - 查询向量（与文档 embedding 同维度）
 * @param {number} limit - 返回条数上限，默认 5
 * @returns {Promise<Array>}
 */
export async function searchDocumentsByVector(env, userId, queryEmbedding, limit = 5) {
  if (!env.DB || !queryEmbedding || queryEmbedding.length === 0) return [];

  try {
    // 拉取该用户所有有 embedding 的分块
    const { results } = await env.DB.prepare(
      `SELECT dc.id, dc.document_id, dc.content, dc.metadata, dc.chunk_index, dc.weight,
              d.title AS document_title
       FROM document_chunks dc
       INNER JOIN documents d ON d.id = dc.document_id
       WHERE d.user_id = ?1 AND dc.embedding IS NOT NULL`
    ).bind(userId).all();

    if (!results || results.length === 0) return [];

    // 解析 embedding（JSON 字符串 → number[]）并过滤无效项
    const valid = results
      .map((r) => {
        try {
          const emb = JSON.parse(r.embedding);
          return emb && Array.isArray(emb) && emb.length === queryEmbedding.length
            ? { row: r, embedding: Float32Array.from(emb) }
            : null;
        } catch (_) {
          return null;
        }
      })
      .filter(Boolean);

    if (valid.length === 0) return [];

    // WASM cosine 逐项打分
    const VectorMath = await getVectorMath();
    const queryF32 = Float32Array.from(queryEmbedding);
    const scored = valid.map(({ row, embedding }) => ({
      row,
      score: VectorMath.cosineF32(queryF32, embedding),
    }));

    // 降序取前 limit
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, limit).map((s) => s.row);
  } catch (err) {
    console.error("searchDocumentsByVector error:", err && err.message);
    return [];
  }
}

/**
 * 关键词检索（兜底）：基于 SQL LIKE 文本匹配 document_chunks。
 * embedding 不可用时使用。
 * @param {Object} env - 含 D1 绑定 env.DB
 * @param {string} userId
 * @param {string} query - 用户查询文本
 * @param {number} limit - 返回条数上限，默认 3
 * @returns {Promise<Array<{id:string, document_id:string, content:string, metadata:string|null, chunk_index:number, weight:number}>>}
 */
export async function searchDocuments(env, userId, query, limit = 3) {
  if (!env.DB) return [];
  if (!query || typeof query !== "string") return [];

  const keyword = query.slice(0, 100).replace(/[%_]/g, (s) => "\\" + s);

  try {
    const stmt = env.DB.prepare(
      `SELECT dc.id, dc.document_id, dc.content, dc.metadata, dc.chunk_index, dc.weight,
              d.title AS document_title
       FROM document_chunks dc
       INNER JOIN documents d ON d.id = dc.document_id
       WHERE d.user_id = ?1 AND dc.content LIKE ?2 ESCAPE '\\'
       ORDER BY dc.weight DESC, dc.chunk_index ASC
       LIMIT ?3`
    );
    const { results } = await stmt.bind(userId, "%" + keyword + "%", limit).all();
    return results || [];
  } catch (err) {
    console.error("searchDocuments error:", err && err.message);
    return [];
  }
}

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

/**
 * 生成简单 UUID（Workers 无原生 crypto.randomUUID 兜底）
 * @returns {string}
 */
export function genId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "id-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
}

/**
 * 创建文档及其分块
 * @param {Object} env
 * @param {Object} doc - { user_id, title, source?, content }
 * @returns {Promise<{documentId:string, chunkCount:number}|null>}
 */
export async function createDocumentWithChunks(env, doc) {
  if (!env.DB) return null;
  const documentId = genId();
  const now = Date.now();
  const chunks = await chunkDocument(doc.content || "");

  try {
    // 插入文档
    await env.DB.prepare(
      `INSERT INTO documents (id, user_id, title, source, created_at) VALUES (?1, ?2, ?3, ?4, ?5)`
    )
      .bind(documentId, doc.user_id, doc.title || "未命名文档", doc.source || null, now)
      .run();

    // 批量插入分块（D1 batch）
    const stmts = chunks.map((content, idx) =>
      env.DB.prepare(
        `INSERT INTO document_chunks (id, document_id, content, metadata, chunk_index, weight, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`
      ).bind(genId(), documentId, content, JSON.stringify({ index: idx }), idx, 1.0, now)
    );

    if (stmts.length > 0) {
      await env.DB.batch(stmts);
    }

    return { documentId, chunkCount: chunks.length };
  } catch (err) {
    console.error("createDocumentWithChunks error:", err && err.message);
    return null;
  }
}
