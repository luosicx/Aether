/**
 * RAG 文档分块检索
 *
 * 简化版：基于 SQL LIKE 文本匹配 document_chunks。
 * 后续可扩展为向量检索（embedding 列已预留）。
 */

/**
 * 检索与查询相关的文档分块
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
 * 简单分块：按固定字符数切分文档（中文友好，不按单词）
 * @param {string} text
 * @param {number} chunkSize - 每块字符数，默认 500
 * @param {number} overlap - 重叠字符数，默认 50
 * @returns {Array<string>}
 */
export function chunkText(text, chunkSize = 500, overlap = 50) {
  if (!text || typeof text !== "string") return [];
  const chunks = [];
  const step = Math.max(1, chunkSize - overlap);
  for (let i = 0; i < text.length; i += step) {
    chunks.push(text.slice(i, i + chunkSize));
    if (i + chunkSize >= text.length) break;
  }
  return chunks;
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
  const chunks = chunkText(doc.content || "");

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
