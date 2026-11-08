# Aether Web Companion (v2.0)

Aether 跨平台 Web 伴侣应用骨架。在浏览器中以与 iOS/macOS 原生端一致的方式接入 Aether BFF 网关，提供对话列表浏览与流式问答能力。

## 当前状态

本目录为 v2.0 的 **HTML/CSS/JS 骨架实现**，用于打通 Web 端与 BFF 网关的交互链路。SwiftWasm 核心模块尚未接入，相关位置以占位说明标注。

## 架构

### 目标架构

```
浏览器 ──(X-BFF-Token)──> CloudflareWorkers BFF ──> 上游 LLM (DeepSeek / Qwen)
   |                                                       |
   |  SwiftWasm (计划)                                       D1 / KV
   |  - 端侧 Token 校验
   |  - 本地加密
   |
   └─ Web Crypto API + IndexedDB（令牌安全存储）
```

- **渲染层**：当前为原生 HTML/CSS/JS；计划迁移至 React + TypeScript。
- **核心层**：计划通过 `WebAssembly.instantiateStreaming` 加载 `aether_core.wasm`（由 SwiftWasm 编译），复用 AetherCore 的端侧能力（Token 本地校验、加密、语义检索等）。
- **网关层**：复用 `CloudflareWorkers/` 中的 BFF 网关，Web 端与 iOS 端共用同一套鉴权与路由约定。

### 目录结构

```
web/
├── index.html          # 应用入口（登录表单 / 对话列表 / 消息区 / 输入框）
├── css/
│   └── style.css       # 样式（DeepSpace 深色主题 + 星空渐变 + 消息气泡 + 响应式）
├── js/
│   ├── config.js       # 配置（BFF 地址 / 版本 / 超时，支持环境变量注入）
│   └── app.js          # 逻辑骨架（BFFClient + UIManager + SecureStorage）
└── README.md           # 本文档
```

### 核心模块（app.js）

| 模块 | 职责 |
| --- | --- |
| `BFFError` | 统一错误类型，区分鉴权 / 限流 / 超时 / 流式错误 |
| `SecureStorage` | Web Crypto API (AES-GCM) + IndexedDB 安全存储 BFF Token |
| `BFFClient` | BFF 网关客户端：`login` / `fetchConversations` / `fetchMessages` / `sendMessage`（SSE 流式） |
| `UIManager` | UI 渲染与交互：`renderConversations` / `renderMessage` / `appendToStream` / 加载状态 |

## 本地运行

Web 端为纯静态资源，使用任意静态服务器即可。推荐使用 Python 内置 HTTP 服务器：

```bash
cd web
python3 -m http.server 8080
```

随后在浏览器打开 <http://localhost:8080>。

> 注意：直接以 `file://` 打开将无法使用 IndexedDB 与 fetch，必须通过 HTTP 服务器访问。

## BFF 网关配置

Web 端通过 `X-BFF-Token` 请求头鉴权，与 iOS `BFFProxyClient` 完全一致。

### 默认配置（`js/config.js`）

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `bff.baseUrl` | `https://aether-bff.example.com` | BFF 网关地址（占位，部署后必须替换） |
| `bff.apiVersion` | `v2` | 客户端逻辑版本标签（BFF 路由无版本前缀） |
| `bff.timeoutMs` | `30000` | 普通请求超时 |
| `bff.streamTimeoutMs` | `120000` | 流式请求（SSE）超时 |
| `bff.provider` | `deepseek` | 默认上游供应商 |
| `bff.model` | `deepseek-chat` | 默认模型 |

### 环境变量注入

静态站点无构建步骤，部署时通过在 `index.html` 加载 `config.js` 之前注入 `window.__AETHER_ENV__` 覆盖默认值：

```html
<script>
  window.__AETHER_ENV__ = {
    BFF_BASE_URL: "https://your-bff.workers.dev",
    BFF_PROVIDER: "qwen",
  };
</script>
<script src="js/config.js"></script>
```

### BFF 端点（与 `CloudflareWorkers/worker.js` 对齐）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/chat/stream` | 流式聊天（SSE） |
| `GET` | `/conversations` | 会话列表（`?limit&offset&pinned=1`） |
| `POST` | `/conversations` | 创建会话 |
| `GET` | `/conversations/:id` | 获取单个会话 |
| `GET` | `/conversations/:id/messages` | 历史消息 |

SSE 事件格式：

```
data: {"type":"delta","content":"xxx"}

data: {"type":"done","conversationId":"...","messageId":"..."}

data: [DONE]
```

### 错误约定

| HTTP 状态 | 含义 |
| --- | --- |
| `401` | BFF Token 缺失或无效 |
| `429` | 服务端限流（携带 `Retry-After`） |
| `5xx` | BFF 服务异常 |

BFF 网关的部署与绑定（KV `bff_tokens`、D1 `DB`、上游 secrets）见 `CloudflareWorkers/README.md` 与 `wrangler.toml`。

## 安全限制

Web 端运行在浏览器沙箱中，无法达到 iOS Keychain / Secure Enclave 的硬件级安全强度。本骨架在可用范围内采用以下措施：

- **令牌存储**：BFF Token 明文 **绝不** 写入 `localStorage` / `sessionStorage`。使用非提取（`extractable=false`）的 AES-GCM 主密钥加密后，密文存入 IndexedDB；主密钥以 `CryptoKey` 对象形式存储，不可导出。
- **令牌 TTL**：客户端侧 90 天 TTL（与 iOS `BFFConfig.tokenTTLSeconds` 对齐），服务端 KV `expiresAt` 为真正过期防线，双端协同。
- **网关中转**：上游 LLM API Key 仅存于 BFF（Workers secrets），Web 端只持有 BFF Token，密钥不落浏览器。
- **同源策略**：依赖浏览器同源策略；部署时建议配置严格的 CSP 与 HTTPS，防范 XSS 窃取令牌。
- **SSL Pinning**：Web 端暂不支持（iOS 端通过 `pinnedSPKIHashes` 启用），Web 端依赖系统证书链校验。

## v2.0 交付范围

- 应用入口与深色主题样式骨架（DeepSpace + 星空渐变 + 消息气泡 + 响应式）
- BFF 网关客户端：登录校验、会话列表、历史消息、SSE 流式发送
- UI 管理器：对话列表渲染、消息渲染、流式追加、加载状态
- 安全令牌存储：Web Crypto API + IndexedDB
- 配置层：环境变量注入 + 默认值兜底

## 后续计划

- 接入 SwiftWasm 核心模块（`aether_core.wasm`），提供端侧 Token 校验与本地加密
- 渲染层迁移至 React + TypeScript
- 引入 Jest 单元测试与 Playwright 端到端测试
- 完整会话管理：创建 / 重命名 / 删除 / 置顶 / 分叉
- 多模态：图片上传、文件附件、Markdown / 代码块渲染
- PWA 离线支持与消息反馈（与 `/messages/:id/feedback` 对齐）
