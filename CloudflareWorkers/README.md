# Aether BFF 跨平台业务网关

基于 Cloudflare Workers 的跨平台业务网关，统一为 iOS / Android / Web 端提供：

- 流式聊天（SSE，集成会话上下文 / 长期记忆 / RAG 知识库）
- 会话与消息管理（CRUD + 反馈）
- 长期记忆（增删查搜）
- RAG 文档管理（上传分块 + 检索）
- 健康摘要（每日上报 / 查询）
- LLM 透传代理（向后兼容旧客户端）

## 架构

```
┌─────────────────────────────────────────────┐
│             Cloudflare Worker               │
│  worker.js (路由入口 + 鉴权 + 限流 + 兜底)   │
│                                             │
│  ┌──────────────┐   ┌──────────────────┐    │
│  │  src/lib/    │   │  src/routes/     │    │
│  │  auth        │   │  chat            │    │
│  │  ratelimit   │   │  conversations   │    │
│  │  llm         │   │  messages        │    │
│  │  memory      │   │  memory          │    │
│  │  rag         │   │  rag             │    │
│  │              │   │  health          │    │
│  └──────────────┘   └──────────────────┘    │
│                                             │
│  绑定：KV bff_tokens │ D1 DB │ Secrets/Vars │
└─────────────────────────────────────────────┘
        │                │              │
        ▼                ▼              ▼
   Cloudflare KV    Cloudflare D1   DeepSeek / Qwen
   (BFF Token)     (业务数据)        (上游 LLM)
```

### 目录结构

```
CloudflareWorkers/
├── worker.js              # 路由入口（鉴权 + 限流 + 分发 + LLM 透传兜底）
├── wrangler.toml          # Cloudflare Workers 配置（KV + D1 + vars）
├── schema.sql             # D1 数据库 schema
├── package.json           # npm 脚本（deploy/dev/test）
├── openapi.yaml           # OpenAPI 3.0.3 契约文档
└── src/
    ├── lib/
    │   ├── auth.js        # 鉴权中间件（X-BFF-Token → KV 查询）
    │   ├── ratelimit.js   # 内存限流（每 userId 每分钟 60 次）
    │   ├── llm.js         # 上游解析 + 流式调用 + 上下文构建
    │   ├── memory.js      # 长期记忆检索（LIKE 文本匹配）
    │   └── rag.js         # RAG 检索 + 文档分块
    └── routes/
        ├── chat.js            # POST /chat/stream（SSE 流式聊天）
        ├── conversations.js   # 会话 CRUD
        ├── messages.js        # 消息列表 / 删除 / 反馈
        ├── memory.js          # 记忆 CRUD + 搜索
        ├── rag.js             # 文档检索 / 上传
        └── health.js          # 健康摘要上报 / 查询
```

## 部署步骤

### 1. 安装依赖

```bash
cd CloudflareWorkers
npm install
```

### 2. 登录 Cloudflare

```bash
npx wrangler login
```

### 3. 创建 KV namespace（BFF Token）

```bash
npx wrangler kv namespace create bff_tokens
```

将输出的 `id` 填入 `wrangler.toml` 的 `[[kv_namespaces]] id`。

写入一个测试 token（键为 token 字符串，值为用户标识，可为 JSON 或纯字符串）：

```bash
npx wrangler kv key put --binding=bff_tokens "test-token-123" '{"userId":"user-1","name":"测试用户"}'
```

### 4. 创建 D1 数据库

```bash
npx wrangler d1 create aether-bff-db
```

将输出的 `database_id` 填入 `wrangler.toml` 的 `[[d1_databases]] database_id`。

### 5. 初始化数据库 schema

```bash
npx wrangler d1 execute aether-bff-db --file=schema.sql
```

本地开发环境加 `--local`：

```bash
npx wrangler d1 execute aether-bff-db --local --file=schema.sql
```

### 6. 配置 Secrets（上游 LLM API Key）

```bash
npx wrangler secret put DEEPSEEK_API_KEY
npx wrangler secret put QWEN_API_KEY
```

### 7. 部署

```bash
npm run deploy
```

### 8. 本地开发

```bash
npm run dev
```

## 环境变量与绑定

| 类型 | 名称 | 说明 |
|------|------|------|
| KV | `bff_tokens` | 键为 BFF Token，值为用户标识/元数据（JSON 或纯字符串） |
| D1 | `DB` | 业务数据库，schema 见 `schema.sql` |
| Secret | `DEEPSEEK_API_KEY` | DeepSeek API Key |
| Secret | `QWEN_API_KEY` | 通义千问 API Key |
| Var | `DEEPSEEK_BASE_URL` | DeepSeek 基址 |
| Var | `QWEN_BASE_URL` | 通义千问基址 |

## API 端点概览

所有受保护端点需在请求头携带 `X-BFF-Token`。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/chat/stream` | 流式聊天（SSE，限流 60/min） |
| GET | `/conversations` | 列出会话 |
| POST | `/conversations` | 创建会话 |
| GET | `/conversations/{id}` | 获取会话 |
| PATCH | `/conversations/{id}` | 更新会话 |
| DELETE | `/conversations/{id}` | 删除会话 |
| GET | `/conversations/{id}/messages` | 列出消息 |
| DELETE | `/messages/{id}` | 删除消息 |
| POST | `/messages/{id}/feedback` | 消息反馈 |
| GET | `/memory` | 列出记忆 |
| POST | `/memory` | 创建记忆 |
| POST | `/memory/search` | 搜索记忆 |
| DELETE | `/memory/{id}` | 删除记忆 |
| POST | `/rag/search` | 检索文档 |
| POST | `/rag/documents` | 上传文档 |
| POST | `/health/summary` | 上报健康摘要 |
| GET | `/health/summary/{date}` | 获取健康摘要 |
| POST | `/*`（兜底） | LLM 透传代理（向后兼容） |

完整契约见 [`openapi.yaml`](./openapi.yaml)。

## 鉴权

请求头携带 BFF Token：

```
X-BFF-Token: <token>
```

Worker 从 KV `bff_tokens` 查询该 token：

- 命中且值为 JSON 对象：取 `userId` / `user_id` / `id` 字段作为用户标识
- 命中且值为纯字符串：直接作为用户标识（向后兼容）
- 未命中：返回 401

## SSE 流式格式

`POST /chat/stream` 返回 `text/event-stream`：

```
data: {"type":"delta","content":"你好"}\n\n
data: {"type":"delta","content":"，有什么"}\n\n
data: {"type":"done","conversationId":"...","messageId":"...","userMessageId":"..."}\n\n
data: [DONE]\n\n
```

错误时：

```
data: {"type":"error","message":"LLM 上游错误 401: ..."}\n\n
```

## 向后兼容

POST 到任意未匹配路径（如 `/v1/chat/completions`、`/v1/embeddings`）走原 LLM 透传代理逻辑：

1. 校验 `X-BFF-Token`（KV）
2. 内存限流（每 token 每分钟 60 次）
3. 按 `X-Provider` 头（默认 `deepseek`）解析上游
4. 剥离 BFF 专有头，注入上游 `Authorization: Bearer <apiKey>`
5. 流式透传响应（TransformStream）

旧客户端无需改动即可继续工作。

## 设计说明

- **时间戳**：D1 一律用 INTEGER 存毫秒（`Date.now()`）
- **数据隔离**：所有业务表按 `user_id` 过滤，避免越权
- **简化检索**：记忆与 RAG 当前用 SQL LIKE 文本匹配，`embedding` 列已预留供后续向量检索
- **无第三方依赖**：仅用 Cloudflare Workers Runtime API
- **ES modules**：全部使用 `export/import` 语法
