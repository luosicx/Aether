/**
 * 租户隔离数据访问层
 *
 * 约定：路由层不得直接持有 env.DB，只能使用 createTenantDB(env, userId) 返回的访问器。
 * 访问器在构造时固定 userId，所有 SQL 由本模块集中编写并绑定租户条件：
 * - 根表（conversations / memories / documents / health_summaries）显式 `user_id = ?`
 * - 子表（messages / document_chunks）通过父表子查询或 JOIN 限定归属
 * 多语句写操作统一走 DB.batch，保证同一事务语义（D1 batch 原子执行）。
 */

import { chunkDocument } from "./rag.js";

/** 生成 UUID（Workers runtime 支持 crypto.randomUUID） */
export function newId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "id-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
}

/** D1 的 changes 在 meta.changes（部分 mock/旧版本在顶层 changes） */
function changesOf(result) {
  return result?.meta?.changes ?? result?.changes ?? 0;
}

/**
 * 创建绑定当前用户的 D1 访问器
 * @param {Object} env
 * @param {string} userId
 * @returns {Object|null} env.DB 或 userId 缺失时返回 null
 */
export function createTenantDB(env, userId) {
  if (!env || !env.DB || !userId) return null;

  const db = env.DB;
  const stmt = (sql, params = []) => db.prepare(sql).bind(...params);

  const fetchConversation = async (id) =>
    stmt(`SELECT * FROM conversations WHERE id = ?1 AND user_id = ?2`, [
      id,
      userId,
    ]).first();

  return {
    // ---------- 会话 ----------

    async listConversations({ limit = 50, offset = 0, pinnedOnly = false } = {}) {
      const sql = pinnedOnly
        ? `SELECT * FROM conversations WHERE user_id = ?1 AND is_pinned = 1 ORDER BY is_pinned DESC, updated_at DESC LIMIT ?2 OFFSET ?3`
        : `SELECT * FROM conversations WHERE user_id = ?1 ORDER BY is_pinned DESC, updated_at DESC LIMIT ?2 OFFSET ?3`;
      const { results } = await stmt(sql, [userId, limit, offset]).all();
      return results || [];
    },

    /**
     * 创建会话并返回完整行（与 GET 响应同形）
     */
    async createConversation({ title = "新会话", systemPrompt = "你是一个有帮助的AI助手。", parentId = null } = {}) {
      const now = Date.now();
      const conversation = {
        id: newId(),
        user_id: userId,
        title,
        parent_id: parentId,
        created_at: now,
        updated_at: now,
        last_message_preview: null,
        is_pinned: 0,
        system_prompt: systemPrompt,
        unread_count: 0,
        order_field: now,
      };
      await stmt(
        `INSERT INTO conversations (id, user_id, title, parent_id, created_at, updated_at, system_prompt, order_field)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
        [
          conversation.id,
          userId,
          title,
          parentId,
          now,
          now,
          systemPrompt,
          now,
        ]
      ).run();
      return conversation;
    },

    async getConversation(id) {
      return fetchConversation(id);
    },

    /**
     * 更新会话白名单字段
     * @returns {{empty:boolean, changed:boolean, conversation:Object|null}}
     */
    async updateConversation(id, patch = {}) {
      const fields = [];
      const values = [];
      if (typeof patch.title === "string") {
        fields.push("title = ?");
        values.push(patch.title);
      }
      if (typeof patch.isPinned === "number" || typeof patch.isPinned === "boolean") {
        fields.push("is_pinned = ?");
        values.push(patch.isPinned ? 1 : 0);
      }
      if (typeof patch.systemPrompt === "string") {
        fields.push("system_prompt = ?");
        values.push(patch.systemPrompt);
      }
      if (typeof patch.orderField === "number") {
        fields.push("order_field = ?");
        values.push(patch.orderField);
      }
      if (fields.length === 0) {
        return { empty: true, changed: false, conversation: null };
      }

      fields.push("updated_at = ?");
      values.push(Date.now());
      values.push(id, userId);

      const result = await db
        .prepare(`UPDATE conversations SET ${fields.join(", ")} WHERE id = ? AND user_id = ?`)
        .bind(...values)
        .run();
      if (changesOf(result) === 0) {
        return { empty: false, changed: false, conversation: null };
      }
      return { empty: false, changed: true, conversation: await fetchConversation(id) };
    },

    /**
     * 级联删除会话及其消息（单事务）
     * @returns {Promise<boolean>} 会话是否存在并被删除
     */
    async deleteConversation(id) {
      const results = await db.batch([
        db.prepare(
          `DELETE FROM messages WHERE conversation_id IN (
             SELECT id FROM conversations WHERE id = ?1 AND user_id = ?2
           )`
        ).bind(id, userId),
        db.prepare(`DELETE FROM conversations WHERE id = ?1 AND user_id = ?2`).bind(id, userId),
      ]);
      return changesOf(results?.[1]) > 0;
    },

    // ---------- 消息 ----------

    /**
     * 列出会话消息（先校验会话归属）
     * @returns {Promise<Array|null>} 会话不存在或非本人时返回 null
     */
    async listMessages(conversationId, { limit = 100, offset = 0, order = "ASC" } = {}) {
      const conv = await stmt(
        `SELECT id FROM conversations WHERE id = ?1 AND user_id = ?2`,
        [conversationId, userId]
      ).first();
      if (!conv) return null;

      const { results } = await stmt(
        `SELECT m.* FROM messages m
         INNER JOIN conversations c ON c.id = m.conversation_id
         WHERE m.conversation_id = ?1 AND c.user_id = ?2
         ORDER BY m.created_at ${order} LIMIT ?3 OFFSET ?4`,
        [conversationId, userId, limit, offset]
      ).all();
      return results || [];
    },

    async deleteMessage(messageId) {
      const result = await stmt(
        `DELETE FROM messages
         WHERE id = ?1 AND conversation_id IN (
           SELECT id FROM conversations WHERE user_id = ?2
         )`,
        [messageId, userId]
      ).run();
      return changesOf(result) > 0;
    },

    async setMessageFeedback(messageId, feedback) {
      const result = await stmt(
        `UPDATE messages SET feedback = ?1
         WHERE id = ?2 AND conversation_id IN (
           SELECT id FROM conversations WHERE user_id = ?3
         )`,
        [feedback, messageId, userId]
      ).run();
      return changesOf(result) > 0;
    },

    // ---------- 长期记忆 ----------

    async listMemories({ limit = 50, offset = 0, category = null } = {}) {
      let sql, params;
      if (category) {
        sql = `SELECT * FROM memories WHERE user_id = ?1 AND category = ?2 ORDER BY importance DESC, created_at DESC LIMIT ?3 OFFSET ?4`;
        params = [userId, category, limit, offset];
      } else {
        sql = `SELECT * FROM memories WHERE user_id = ?1 ORDER BY importance DESC, created_at DESC LIMIT ?2 OFFSET ?3`;
        params = [userId, limit, offset];
      }
      const { results } = await stmt(sql, params).all();
      return results || [];
    },

    /** 写入一条记忆并返回响应行 */
    async createMemory({ content, category = null, importance = 0.5, sourceConversationId = null }) {
      const memory = {
        id: newId(),
        user_id: userId,
        content,
        category,
        importance: typeof importance === "number" ? importance : 0.5,
        source_conversation_id: sourceConversationId,
        created_at: Date.now(),
      };
      await stmt(
        `INSERT INTO memories (id, user_id, content, category, importance, embedding, source_conversation_id, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
        [
          memory.id,
          memory.user_id,
          memory.content,
          memory.category,
          memory.importance,
          null,
          memory.source_conversation_id,
          memory.created_at,
        ]
      ).run();
      return memory;
    },

    /** 关键词检索记忆；D1 不可用时降级为空数组 */
    async searchMemories(query, limit = 5) {
      if (!query || typeof query !== "string") return [];
      const keyword = query.slice(0, 100).replace(/[%_]/g, (s) => "\\" + s);
      try {
        const { results } = await stmt(
          `SELECT id, content, category, importance, source_conversation_id, created_at
           FROM memories
           WHERE user_id = ?1 AND content LIKE ?2 ESCAPE '\\'
           ORDER BY importance DESC, created_at DESC
           LIMIT ?3`,
          [userId, "%" + keyword + "%", limit]
        ).all();
        return results || [];
      } catch (err) {
        console.error("searchMemories error:", err && err.message);
        return [];
      }
    },

    async deleteMemory(id) {
      const result = await stmt(`DELETE FROM memories WHERE id = ?1 AND user_id = ?2`, [
        id,
        userId,
      ]).run();
      return changesOf(result) > 0;
    },

    // ---------- RAG ----------

    /** 关键词检索文档分块；D1 不可用时降级为空数组 */
    async searchChunks(query, limit = 3) {
      if (!query || typeof query !== "string") return [];
      const keyword = query.slice(0, 100).replace(/[%_]/g, (s) => "\\" + s);
      try {
        const { results } = await stmt(
          `SELECT dc.id, dc.document_id, dc.content, dc.metadata, dc.chunk_index, dc.weight,
                  d.title AS document_title
           FROM document_chunks dc
           INNER JOIN documents d ON d.id = dc.document_id
           WHERE d.user_id = ?1 AND dc.content LIKE ?2 ESCAPE '\\'
           ORDER BY dc.weight DESC, dc.chunk_index ASC
           LIMIT ?3`,
          [userId, "%" + keyword + "%", limit]
        ).all();
        return results || [];
      } catch (err) {
        console.error("searchChunks error:", err && err.message);
        return [];
      }
    },

    /**
     * 创建文档及其分块
     * @param {Object} doc - { title?, source?, content }
     * @returns {Promise<{documentId:string, chunkCount:number}|null>}
     */
    async createDocumentWithChunks({ title = "未命名文档", source = null, content = "" }) {
      const documentId = newId();
      const now = Date.now();
      const chunks = await chunkDocument(content);

      try {
        const inserts = [
          db
            .prepare(
              `INSERT INTO documents (id, user_id, title, source, created_at) VALUES (?1, ?2, ?3, ?4, ?5)`
            )
            .bind(documentId, userId, title, source, now),
          ...chunks.map((chunk, idx) =>
            db
              .prepare(
                `INSERT INTO document_chunks (id, document_id, content, metadata, chunk_index, weight, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`
              )
              .bind(newId(), documentId, chunk, JSON.stringify({ index: idx }), idx, 1.0, now)
          ),
        ];
        await db.batch(inserts);
        return { documentId, chunkCount: chunks.length };
      } catch (err) {
        console.error("createDocumentWithChunks error:", err && err.message);
        return null;
      }
    },

    // ---------- 健康摘要 ----------

    async upsertHealthSummary(date, { steps = null, sleepHours = null, restingHeartRate = null } = {}) {
      await stmt(
        `INSERT OR REPLACE INTO health_summaries (user_id, date, steps, sleep_hours, resting_heart_rate)
         VALUES (?1, ?2, ?3, ?4, ?5)`,
        [userId, date, steps, sleepHours, restingHeartRate]
      ).run();
      return {
        user_id: userId,
        date,
        steps,
        sleep_hours: sleepHours,
        resting_heart_rate: restingHeartRate,
      };
    },

    async getHealthSummary(date) {
      return stmt(`SELECT * FROM health_summaries WHERE user_id = ?1 AND date = ?2`, [
        userId,
        date,
      ]).first();
    },

    // ---------- 聊天流 ----------

    /** 加载会话的 system_prompt（同时校验归属） */
    async getConversationPrompt(conversationId) {
      return stmt(`SELECT id, system_prompt FROM conversations WHERE id = ?1 AND user_id = ?2`, [
        conversationId,
        userId,
      ]).first();
    },

    /** 最近历史消息，按时间正序返回 */
    async loadHistory(conversationId, limit = 20) {
      const { results } = await stmt(
        `SELECT m.role, m.content FROM messages m
         INNER JOIN conversations c ON c.id = m.conversation_id
         WHERE m.conversation_id = ?1 AND c.user_id = ?2
         ORDER BY m.created_at DESC LIMIT ?3`,
        [conversationId, userId, limit]
      ).all();
      return (results || []).reverse();
    },

    /**
     * 追加用户消息并刷新会话预览（单事务）
     * @returns {Promise<string>} 用户消息 id
     */
    async appendUserMessage(conversationId, content) {
      const messageId = newId();
      const now = Date.now();
      await db.batch([
        db
          .prepare(
            `INSERT INTO messages (id, conversation_id, role, content, created_at)
             SELECT ?1, ?2, 'user', ?3, ?4
             WHERE EXISTS (SELECT 1 FROM conversations WHERE id = ?2 AND user_id = ?5)`
          )
          .bind(messageId, conversationId, content, now, userId),
        db
          .prepare(
            `UPDATE conversations SET updated_at = ?1, last_message_preview = ?2
             WHERE id = ?3 AND user_id = ?4`
          )
          .bind(now, content.slice(0, 200), conversationId, userId),
      ]);
      return messageId;
    },

    /**
     * 追加助手消息并刷新会话预览（单事务）
     * @returns {Promise<string>} 助手消息 id
     */
    async appendAssistantMessage(conversationId, content, messageId = newId()) {
      const now = Date.now();
      await db.batch([
        db
          .prepare(
            `INSERT INTO messages (id, conversation_id, role, content, created_at)
             SELECT ?1, ?2, 'assistant', ?3, ?4
             WHERE EXISTS (SELECT 1 FROM conversations WHERE id = ?2 AND user_id = ?5)`
          )
          .bind(messageId, conversationId, content, now, userId),
        db
          .prepare(
            `UPDATE conversations SET updated_at = ?1, last_message_preview = ?2
             WHERE id = ?3 AND user_id = ?4`
          )
          .bind(now, content.slice(0, 200), conversationId, userId),
      ]);
      return messageId;
    },
  };
}
