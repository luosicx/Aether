/**
 * 长期记忆检索
 *
 * 简化版：基于 SQL LIKE 文本匹配。
 * 后续可扩展为向量检索（embedding 列已预留）。
 */

/**
 * 检索与查询相关的记忆
 * @param {Object} env - 含 D1 绑定 env.DB
 * @param {string} userId
 * @param {string} query - 用户查询文本
 * @param {number} limit - 返回条数上限，默认 5
 * @returns {Promise<Array<{id:string, content:string, category:string|null, importance:number, created_at:number}>>}
 */
export async function fetchRelevantMemories(env, userId, query, limit = 5) {
  if (!env.DB) return [];
  if (!query || typeof query !== "string") return [];

  // 按 query 中的关键词做 LIKE 匹配（取前若干字符避免 SQL 过长）
  const keyword = query.slice(0, 100).replace(/[%_]/g, (s) => "\\" + s);

  try {
    const stmt = env.DB.prepare(
      `SELECT id, content, category, importance, source_conversation_id, created_at
       FROM memories
       WHERE user_id = ?1 AND content LIKE ?2 ESCAPE '\\'
       ORDER BY importance DESC, created_at DESC
       LIMIT ?3`
    );
    const { results } = await stmt.bind(userId, "%" + keyword + "%", limit).all();
    return results || [];
  } catch (err) {
    // D1 未初始化或表不存在时降级为空，不阻断主流程
    console.error("fetchRelevantMemories error:", err && err.message);
    return [];
  }
}

/**
 * 写入一条记忆
 * @param {Object} env
 * @param {Object} memory - { id, user_id, content, category?, importance?, source_conversation_id?, created_at, embedding? }
 * @returns {Promise<boolean>}
 */
export async function createMemory(env, memory) {
  if (!env.DB) return false;
  try {
    await env.DB.prepare(
      `INSERT INTO memories (id, user_id, content, category, importance, embedding, source_conversation_id, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`
    )
      .bind(
        memory.id,
        memory.user_id,
        memory.content,
        memory.category || null,
        typeof memory.importance === "number" ? memory.importance : 0.5,
        memory.embedding || null,
        memory.source_conversation_id || null,
        memory.created_at || Date.now()
      )
      .run();
    return true;
  } catch (err) {
    console.error("createMemory error:", err && err.message);
    return false;
  }
}
