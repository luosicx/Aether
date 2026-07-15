-- Aether BFF D1 数据库 schema
-- 用途：承载会话、消息、长期记忆、RAG 文档分块、健康摘要等跨平台业务数据
-- 时间戳一律用 INTEGER 存毫秒（Date.now()）
-- 外键级联删除：删会话→删消息；删文档→删分块

-- 会话表
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  parent_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_message_preview TEXT,
  is_pinned INTEGER DEFAULT 0,
  system_prompt TEXT DEFAULT '你是一个有帮助的AI助手。',
  unread_count INTEGER DEFAULT 0,
  order_field INTEGER DEFAULT 0
);

-- 消息表
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,            -- user / assistant / system / tool
  content TEXT NOT NULL,
  tool_calls TEXT,               -- JSON 字符串，工具调用
  tool_call_id TEXT,
  tool_name TEXT,
  feedback INTEGER,              -- 1 = 点赞, -1 = 点踩, NULL = 未反馈
  created_at INTEGER NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

-- 长期记忆表
CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT,
  importance REAL DEFAULT 0.5,
  embedding TEXT,                -- JSON 数组，向量检索用
  source_conversation_id TEXT,
  created_at INTEGER NOT NULL
);

-- 文档表（RAG 知识库源）
CREATE TABLE IF NOT EXISTS documents (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  source TEXT,
  created_at INTEGER NOT NULL
);

-- 文档分块表（RAG 检索单元）
CREATE TABLE IF NOT EXISTS document_chunks (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  content TEXT NOT NULL,
  embedding TEXT,                -- JSON 数组，向量检索用
  metadata TEXT,                 -- JSON 字符串
  chunk_index INTEGER DEFAULT 0,
  weight REAL DEFAULT 1.0,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
);

-- 健康摘要表（按 user_id + date 联合主键）
CREATE TABLE IF NOT EXISTS health_summaries (
  user_id TEXT,
  date TEXT,                     -- YYYY-MM-DD
  steps INTEGER,
  sleep_hours REAL,
  resting_heart_rate INTEGER,
  PRIMARY KEY (user_id, date)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_memories_user ON memories(user_id);
CREATE INDEX IF NOT EXISTS idx_documents_user ON documents(user_id);
CREATE INDEX IF NOT EXISTS idx_document_chunks_document ON document_chunks(document_id);
