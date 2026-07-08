# AIBuilder 架构文档

> 本文基于 AIBuilder 多平台项目（iOS / iPad / macOS 原生） Day 1–20 实际代码撰写，描述系统分层、模块职责、数据流与关键技术决策。
> 所有引用的文件路径均与磁盘一致，技术术语保留英文原文。

---

## 目录

1. [项目概述](#1-项目概述)
2. [分层架构图](#2-分层架构图)
3. [模块职责](#3-模块职责)
4. [数据流](#4-数据流)
5. [关键设计决策](#5-关键设计决策)
6. [技术栈映射](#6-技术栈映射)
7. [测试架构](#7-测试架构)
8. [目录结构](#8-目录结构)

---

## 1. 项目概述

**项目定位**：AIBuilder 是一款 AI Native 多平台 App（iOS / iPad / macOS 原生），基于 SwiftUI + 多 LLM Provider（DeepSeek / Qwen / 端侧 MLX）构建，覆盖流式对话、多轮记忆、RAG 检索增强、ReAct 工具调用、语音输入输出、视觉多模态、Markdown 富文本渲染、TTS 音色可调节、BFF 代理、端侧 MLX 推理、HealthKit 健康洞察、App Intents 系统集成、智能路由与 Fallback、远程配置与遥测、崩溃监控、性能监控、隐私清单等 Day 1–20 全部能力。

**核心能力清单**（20+ 项）：

### Day 1–11 基础能力

1. **流式对话**：基于 OpenAI 兼容 chat completions SSE 流式接口，逐 chunk yield 文本，前端实时打字效果展示。
2. **多轮记忆**：SwiftData 持久化 Conversation + ChatMessage，会话级消息历史注入 LLM 上下文，支持 system prompt 自定义。
3. **RAG 检索增强**：本地知识库（PDF/文本）→ DocumentChunker 分块 → EmbeddingService 嵌入 → 余弦相似度 topK=5 检索 → 拼 `[1][2]` 编号 prompt 注入。
4. **ReAct 工具调用**：基于 function calling，ToolRegistry 注册 iOS 13 个 / macOS 24 个工具（原 4 个 + 新增 20 个：跨平台 6 个 LocationTool / DeviceInfoTool / ClipboardTool / OpenURLTool / ContactsTool / WeatherTool，快捷指令 3 个 RunShortcutTool / ListShortcutsTool / CreateShortcutTool，macOS 独有 11 个 AppleScriptTool / ScreenshotTool / OCRTool / TerminalCommandTool / WindowManagementTool / AppManagementTool / FileOperationTool / FinderTool / SafariControlTool / SystemControlTool / InputAutomationTool，macOS 独有工具用 `#if os(macOS)` 条件注册），最大循环 5 轮，单工具超时 15s 不中断循环。
5. **语音输入输出**：AVAudioSession + SFSpeechRecognizer 实时语音识别写入输入框，AVSpeechSynthesizer 朗读 AI 回复。
6. **视觉多模态**：用户从相册选择图片，base64 编码后以 `image_url` 形式嵌入 content 数组，多模态下发 LLM。
7. **用户偏好记忆**：UserPreference @Model 持久化语气偏好 / 偏好工具 / 自定义事实，注入 systemPrompt 末尾个性化 AI 回复。
8. **调试面板**：DebugInfo 记录最近一次请求的 promptJSON / apiResponse / embeddingDimension / toolCalls，仅当前会话不持久化。
9. **灵动岛 Live Activity**：ActivityKit TimerActivityAttributes，状态机「思考中 → 回复中 → 完成」，iOS 16.1+ 可用低版本静默降级。
10. **BGTaskScheduler + 本地通知**：注册每日刷新后台任务（`com.aibuilder.daily-refresh`），UNUserNotificationCenter 在工具调用成功 / AI 回复完成等场景推送本地通知。

### Day 12–20 扩展能力

11. **Markdown 渲染**：消息气泡支持代码块（`CodeBlockView` + `CodeSyntaxHighlighter` 高亮）/ 表格（`MarkdownTableParser` + `MarkdownTableView`）/ 任务列表（`TaskListView`）/ 标题分级（`HeadingView`）/ 富文本段落（`MarkdownText`），保留行内 code 与 bold/italic。
12. **TTS 音色可调节**：`TTSConfig` 持久化音色 ID / 语速 / 音调 / 音量到 UserDefaults，`TTSVoiceCatalog` 提供系统音色目录，`TTSVoicePickerView` 提供试听，`VoiceService` 在朗读前应用配置。
13. **消息复制与重新提问**：MessageBubble 长按 contextMenu 提供「复制 / 重新提问」操作，复制写入系统剪贴板并 toast 反馈，重新提问将原文回填到输入框并发送。
14. **批量多选删除会话**：会话列表支持编辑模式（多选 / 全选 / 删除选中），含二次确认弹窗，删除走 ChatStorage 批量删除并触发 Spotlight 索引清理。
15. **智能路由（SmartRouter）**：基于规则与历史成功率在多 Provider 间路由（DeepSeek ↔ Qwen），失败自动 Fallback，记录遥测数据。
16. **多 Provider 支持**：`ModelProvider` enum 抽象 DeepSeek / Qwen / 端侧三类，`ModelProviderFactory` 创建对应 client，`FallbackLLMProvider` 包装自动降级，`RateLimiter` 客户端令牌桶限流。
17. **BFF 代理层**：`BFFProxyClient` 走 Cloudflare Workers 网关中转，设备端仅持 `userToken`，不持上游 API Key；`BFFConfig` 承载 endpoint / token / 限流参数，UserDefaults 持久化。
18. **MLX 端侧推理**：`MLXInferenceEngine` 在设备本地运行 Llama-3.2-1B-Instruct Q4_K_M 量化模型，`OnDeviceModelDownloader` 从 HuggingFace CDN 下载并 SHA256 校验，`OfflineLLMProvider` 实现 `LLMProvider` 协议，断网时自动切换。
19. **HealthKit 健康洞察**：`HealthKitService` 读取步数 / 心率 / 睡眠数据，`HealthInsightGenerator` 生成洞察文本并持久化到 `HealthInsight` @Model，`HealthSettingsView` 管理授权与展示。
20. **App Intents / Shortcuts**：`AskAIBuilderIntent` / `NewConversationIntent` / `SwitchConversationIntent` 三个 Intent，集成 Shortcuts / Spotlight / Siri，`IntentChatService` 处理 Intent 触发的会话路由。
21. **Spotlight 索引**：`SpotlightIndexer` 为 Conversation 创建/更新 `CSSearchableItem`，支持系统搜索直达会话。
22. **WatchConnectivity**：`WatchConnectivityService` 与 AIBuilderWatch watchOS App 双向通信，同步 Quick Chat 与健康洞察。
23. **远程配置与遥测**：`RemoteConfigService` 拉取远程开关/限流配置，`TelemetryService` 收集使用指标，`LogUploader` 上传脱敏日志。
24. **崩溃监控**：`CrashReportService` 捕获未捕获异常与信号崩溃，落盘后在下次启动上报。
25. **性能监控**：`PerformanceMonitor` 记录首屏渲染 / 流式首字 / 工具执行等关键耗时指标。
26. **网络监听自动切换**：`NetworkMonitor` 基于 `NWPathMonitor` 实时检测网络状态变化，断网时触发 OnDeviceConfig.autoSwitchOnNetworkLoss 自动切到端侧。
27. **隐私清单与投诉反馈**：`PrivacyInfo.xcprivacy` 声明隐私 API 用途，`PrivacyPolicyView` 展示隐私政策，`FeedbackService` 提供反馈/投诉入口（持久化到 `MessageFeedback` @Model）。
28. **多平台适配**：SwiftUI 原生渲染支持 iOS / iPad / macOS 三端，通过 `#if os(iOS)` 条件编译隔离 iOS-only 框架（BGTaskScheduler / ActivityKit / HealthKit / WatchConnectivity）让 macOS 优雅降级；macOS 加入窗口默认尺寸 1000×700、菜单栏快捷键（⌘N 新建 / ⌘K 搜索 / ⌘, 设置）、⌘Enter 发送；UIKit 组件替换为 SwiftUI 跨平台组件（DocumentPickerView 用 `.fileImporter`、FeedbackService 用 `ProcessInfo`）；SettingsView / KnowledgeBaseView 用 NavigationSplitView 双栏布局适配多平台。
29. **工具能力增强**：ToolRegistry 从 4 个工具扩展到 iOS 13 个 / macOS 24 个，新增 20 个工具分三类：跨平台 6 个（LocationTool / DeviceInfoTool / ClipboardTool / OpenURLTool / ContactsTool / WeatherTool）、macOS 独有 11 个（AppleScriptTool / ScreenshotTool / OCRTool / TerminalCommandTool / WindowManagementTool / AppManagementTool / FileOperationTool / FinderTool / SafariControlTool / SystemControlTool / InputAutomationTool，用 `#if os(macOS)` 守卫）、快捷指令 3 个（RunShortcutTool / ListShortcutsTool / CreateShortcutTool，CreateShortcutTool 通过 WFWorkflow plist 生成 .shortcut 文件支持 open_url / run_script / show_text / copy_to_clipboard 四种动作）。
30. **预设系统提示词**：`PresetPrompts.swift` 提供 11 个预设角色（默认助手 / 开发者 / 学生 / 白领 / 管理者 / 产品经理 / 写作助手 / 技术面试官 / 学习导师 / 翻译官 / 健身教练），每个含详细完整的 system prompt 文本（≥ 150 字）；SettingsView 的 `systemPromptSection` 上方新增「预设角色」Menu，选中后填入 TextEditor 保留可编辑性，复用现有「完成」按钮回写逻辑。
31. **macOS 体验修复**：设置二级 / 三级页面导航修复（`regularLayout` detail 包 `NavigationStack`，二级页 TTS / 隐私政策 / 端侧模型管理有返回按钮）；工具项中文化（SettingsView `preferenceSection` 的 Toggle 用中文 `description` 替代英文 `name`）；macOS markdown 视觉层次修复（MessageBubble.swift NSColor shim 的 systemGray3 / 5 / 6 改为不同灰阶 separatorColor / textBackgroundColor / controlBackgroundColor）；macOS 语音朗读 UI 修复（MarkdownText 加 `parseBlocks` NSCache 缓存 countLimit=200，VoiceService 加 `@MainActor`、`didCancel` 兜底清理、voice nil 降级、移除 spokenText 死状态）；18 个工具文件 + ToolRegistry 补充文件级 / 方法级 / 行内中文注释。

---

## 2. 分层架构图

AIBuilder 采用 7 层分层架构，依赖方向自上而下单向流动。

```
┌─────────────────────────────────────────────────────────────────────┐
│                              Tests                                  │
│  AIBuilderTests (69 文件 / 249 用例) + AIBuilderUITests (2 文件 / 13)│
└─────────────────────────────────────────────────────────────────────┘
                                │ 测试可访问所有层
┌─────────────────────────────────────────────────────────────────────┐
│                              App                                     │
│  AIBuilderApp.swift (@main + ModelContainer + BGTask)               │
│  AppIntents/ (AskAIBuilder / NewConversation / SwitchConversation) │
└─────────────────────────────────────────────────────────────────────┘
        │           │             │              │            │
        ▼           ▼             ▼              ▼            ▼
┌──────────┐ ┌──────────┐ ┌─────────────┐ ┌──────────┐ ┌──────────┐
│   Core   │ │  Models  │ │  ViewModels │ │  Views   │ │ AppIntents│
│ 协议+常量 │ │ SwiftData│ │  @Observable │ │ SwiftUI  │ │  系统集成  │
│ +扩展+   │ │  @Model  │ │  @MainActor  │ │ 6 子模块  │ │  3 Intent │
│ +Models  │ │  7 实体  │ │  4 ViewModel │ │ 28 文件  │ │           │
└──────────┘ └──────────┘ └─────────────┘ └──────────┘ └──────────┘
                  ▲              │              │
                  │              ▼              │
                  │       ┌─────────────┐       │
                  │       │  Services   │       │
                  │       │ 19 个子模块  │       │
                  │       │ Auth/Cache/ │       │
                  └──────│ Connectivity│◄──────┘
                          │ /Crash/     │
                          │ Feedback/   │
                          │ Health/     │
                          │ Intents/    │
                          │ LLM(含BFF)/ │
                          │ Network/    │
                          │ OnDevice/   │
                          │ Performance/│
                          │ RAG/        │
                          │ RemoteConfig│
                          │ /Routing/   │
                          │ Search/     │
                          │ Storage/    │
                          │ Telemetry/  │
                          │ Tools/Voice │
                          └─────────────┘
                              │
                              ▼
                          ┌───────┐
                          │ Core  │
                          │Models │
                          └───────┘
```

**依赖方向说明**：

| 上层模块 | 下层依赖 |
|---------|---------|
| App + AppIntents | Core + Models + ViewModels + Views |
| ViewModels | Services + Models |
| Services | Core + Models |
| Views | ViewModels |
| Tests | 所有层 |

**各层职责概览**：

| 层级 | 职责 | 文件数 |
|------|------|--------|
| App | 程序入口、ModelContainer 配置、BGTaskScheduler 注册、ActivityKit 属性定义 + AppIntents 系统集成 | 4（App 1 + AppIntents 3） |
| Core | 协议契约（LLMProvider / ToolProtocol）+ 常量（APIConfig / ModelProvider）+ 扩展（token 估算）+ Actor（ChatActor 占位）+ 数据模型（BFFConfig / OnDeviceConfig / OnDeviceError） | 9 |
| Models | SwiftData `@Model` 持久化实体（7 个）+ SSE 响应/请求体数据结构 | 7 |
| Services | 19 个子模块业务实现（Auth / Cache / Connectivity / Crash / Feedback / Health / Intents / LLM / Network / OnDevice / Performance / RAG / RemoteConfig / Routing / Search / Storage / Telemetry / Tools / Voice） | 36 |
| ViewModels | `@Observable` 状态管理 + 业务编排（含 TTS / BFF / OnDevice / Health 等字段） | 4 |
| Views | SwiftUI 视图，6 个子模块（Chat / Components / Conversation / OnDevice / RAG / Settings） | 28 |
| Tests | UT 69 文件（249 用例，允许 skipped）+ UIT 2 文件（13 用例） | 71 |

---

## 3. 模块职责

### 3.1 Core 层

Core 层除协议/常量/扩展/Actor 外，新增 `Core/Models` 子目录承载 BFF、端侧推理等配置数据模型（非 SwiftData `@Model`，仅 `Codable + Sendable` 结构）。

| 文件 | 职责 |
|------|------|
| `Core/Actors/ChatActor.swift` | 自定义 `@globalActor`，目前仅占位未实际应用到具体方法上。 |
| `Core/Constants/APIConfig.swift` | 定义 `APIConfig`（DeepSeek 端点 URL + 模型名常量）与 `ChatConfig`（model / systemPrompt / maxTokens / temperature）。 |
| `Core/Constants/ModelProvider.swift` | Day 13 LLM 供应商抽象 enum：`deepseek` / `qwen` / `onDevice` 三 case，承载 displayName / baseURL / chatEndpoint / embeddingEndpoint / defaultChatModel / defaultReasonerModel / defaultEmbeddingModel / keychainAccount / fallback（deepseek ↔ qwen 互备，onDevice 备用 deepseek）。 |
| `Core/Extensions/String+TokenCount.swift` | `estimatedTokens` 扩展，按空格分词后乘 1.3 系数粗略估算 token 数，用于 tokenLimit 截断。 |
| `Core/Models/BFFConfig.swift` | Day 15 BFF 代理配置：enabled / endpointURL / userToken / chatRateLimitPerMin / embedRateLimitPerMin，Codable + Sendable，UserDefaults 持久化（键 `bff_config_cache`）。 |
| `Core/Models/OnDeviceConfig.swift` | Day 16 端侧推理配置：enabled / modelPath / autoSwitchOnNetworkLoss / maxTokens / temperature / modelName / downloadURL / expectedSHA256，UserDefaults 持久化（键 `ondevice_config_cache`）。 |
| `Core/Models/OnDeviceError.swift` | Day 16 端侧推理错误枚举：insufficientMemory / modelNotFound / sha256Mismatch / unsupportedQuantization / loadFailed，`LocalizedError` 提供用户友好描述。 |
| `Core/Protocols/LLMProvider.swift` | `LLMProvider` 协议（chat 流式 + embed）+ `APIMessage` / `ToolCallParam` / `FunctionCall` 数据结构。 |
| `Core/Protocols/ToolProtocol.swift` | `ToolDefinition`（name + description + JSON Schema parameters）+ `ToolProtocol` 协议（definition + execute）。 |

### 3.2 Models 层

| 文件 | 职责 |
|------|------|
| `Models/ChatMessage.swift` | 持久化聊天消息 `@Model`，含 role / content / imageData / attachedImage / toolCallData / toolCallId / toolName，提供 `toAPIMessage()` 转换。 |
| `Models/Conversation.swift` | `Conversation` `@Model`（title / systemPrompt / isPinned / messages cascade 关系）+ `UserPreference` `@Model`（preferredTone / preferredTools / customFact）。 |
| `Models/DocumentChunk.swift` | RAG 文档分块 `@Model`，含 content / source / embedding 向量，供 RAGService 检索。 |
| `Models/HealthInsight.swift` | Day 18 HealthKit 健康洞察 `@Model`：type / summary / detail / generatedAt / relatedDateRange，持久化 `HealthInsightGenerator` 生成结果。 |
| `Models/MessageFeedback.swift` | Day 12 用户反馈 `@Model`：messageId / conversationId / rating（like/dislike）/ comment / createdAt，供 FeedbackService 与 FeedbackBar 使用。 |
| `Models/RemoteConfig.swift` | Day 14 远程配置 `@Model`：featureFlags / rateLimits / updatedAt，缓存 RemoteConfigService 拉取的配置。 |
| `Models/ChatChunk.swift` | SSE 响应数据结构集合：`ChatChunk`（SSE chunk）+ `AccumulatedToolCall`（跨 chunk 累积的工具调用）+ `ParsedChunk`（解析结果）+ `ChatRequestBody`（请求体）+ `ToolDef`（工具定义）+ `AnyCodable`（动态类型包装）+ `EmbeddingResponse`（嵌入响应）+ `LLMError`（统一错误枚举）。 |

### 3.3 Services 层（19 个子模块）

| 子模块 | 文件 | 职责 |
|--------|------|------|
| Auth | `Services/Auth/KeychainManager.swift` | Keychain 单例，封装 API Key 的 save / load / delete，按 `ModelProvider.keychainAccount` 隔离存储。 |
| Cache | `Services/Cache/SemanticCache.swift` | `@MainActor` 语义缓存，基于 embedding 余弦相似度（阈值 0.92）匹配历史 query，命中跳过 LLM 请求；FIFO 容量 100。 |
| Connectivity | `Services/Connectivity/WatchConnectivityService.swift` | Day 17 WatchConnectivity 双向通信，与 AIBuilderWatch 同步 Quick Chat 与健康洞察。 |
| Crash | `Services/Crash/CrashReportService.swift` | Day 14 崩溃监控：捕获未捕获异常与信号崩溃（SIGABRT/SIGSEGV），落盘到本地，下次启动时上报。 |
| Feedback | `Services/Feedback/FeedbackService.swift` | Day 12 用户反馈/投诉：写入 `MessageFeedback` @Model，提供按会话查询与批量导出。 |
| Health | `Services/Health/HealthKitService.swift` | Day 18 HealthKit 读取：步数 / 心率 / 睡眠 / 活动能量，按日期范围查询。 |
| Health | `Services/Health/HealthInsightGenerator.swift` | Day 18 健康洞察生成：基于 HealthKitService 数据生成中文洞察文本，持久化到 `HealthInsight` @Model。 |
| Intents | `Services/Intents/IntentChatService.swift` | Day 18 App Intents 路由：根据 Intent 类型（Ask / NewConversation / SwitchConversation）解析参数并切换/创建会话。 |
| LLM | `Services/LLM/DeepSeekClient.swift` | `nonisolated final class`，实现 `LLMProvider`，提供 DeepSeek chat 流式 + embed。 |
| LLM | `Services/LLM/QwenClient.swift` | Day 13 Qwen 客户端，走阿里云百炼 DashScope OpenAI 兼容端点，实现 `LLMProvider`。 |
| LLM | `Services/LLM/BFFProxyClient.swift` | Day 15 BFF 代理客户端：请求经 Cloudflare Workers 中转，仅传 `userToken`，不持上游 API Key；支持 chat / embed / 限流。 |
| LLM | `Services/LLM/FallbackLLMProvider.swift` | Day 12 Fallback 包装器：primary 失败自动切 fallback provider，记录失败原因与遥测。 |
| LLM | `Services/LLM/ModelProviderFactory.swift` | Day 13 Provider 工厂：根据 `ModelProvider` enum 与当前配置创建对应 client（DeepSeek / Qwen / BFFProxy / Offline）。 |
| LLM | `Services/LLM/RateLimiter.swift` | Day 13 客户端令牌桶限流：按 `BFFConfig.chatRateLimitPerMin` / `embedRateLimitPerMin` 控制请求速率。 |
| LLM | `Services/LLM/SSEParser.swift` | SSE 流解析器，`parseChunk` 解析纯文本 chunk，`parseWithToolAccumulation` 累积跨 chunk 的 tool_calls。 |
| Network | `Services/Network/NetworkMonitor.swift` | Day 16 网络监听：`NWPathMonitor` 实时检测 Wi-Fi/蜂窝/无网状态，触发 OnDeviceConfig.autoSwitchOnNetworkLoss。 |
| OnDevice | `Services/OnDevice/MLXInferenceEngine.swift` | Day 16 MLX 推理引擎：在设备本地运行 Llama-3.2-1B-Instruct Q4_K_M 量化模型，流式生成 token。 |
| OnDevice | `Services/OnDevice/OnDeviceModelDownloader.swift` | Day 16 模型下载器：从 HuggingFace CDN 下载 + SHA256 校验 + 断点续传。 |
| OnDevice | `Services/OnDevice/OfflineLLMProvider.swift` | Day 16 端侧 LLMProvider 实现：包装 MLXInferenceEngine，对外暴露 `LLMProvider` 协议。 |
| Performance | `Services/Performance/PerformanceMonitor.swift` | Day 14 性能监控：首屏渲染 / 流式首字 / 工具执行 / RAG 检索等关键耗时记录。 |
| RAG | `Services/RAG/DocumentChunker.swift` | 基于 `NLTokenizer` 的文档分块器，支持 overlap。 |
| RAG | `Services/RAG/EmbeddingService.swift` | 嵌入服务，封装 LLM embedding API 调用。 |
| RAG | `Services/RAG/PDFExtractor.swift` | 基于 `PDFKit` 的 PDF 文本提取器。 |
| RAG | `Services/RAG/RAGService.swift` | `@MainActor` RAG 检索增强服务，提供 `indexDocument` 索引、`retrieve` topK 检索、`buildAugmentedContext` 构建带 `[1][2]` 编号的 prompt 并复用 queryEmbedding。 |
| RemoteConfig | `Services/RemoteConfig/RemoteConfigService.swift` | Day 14 远程配置拉取：从远端拉取 featureFlags / rateLimits，缓存到 `RemoteConfig` @Model，支持过期重拉。 |
| Routing | `Services/Routing/SmartRouter.swift` | Day 12 智能路由：基于规则与历史成功率在多 Provider 间路由，失败自动 Fallback，记录遥测。 |
| Search | `Services/Search/SpotlightIndexer.swift` | Day 18 Spotlight 索引：为 Conversation 创建/更新 `CSSearchableItem`，删除时清理索引。 |
| Storage | `Services/Storage/ChatStorage.swift` | `@MainActor` SwiftData 持久化服务，封装 Conversation / ChatMessage / UserPreference 的 CRUD，含 `fetchPreference` / `savePreference` / `cleanupEmptyConversations`（批量清理空会话）。 |
| Telemetry | `Services/Telemetry/TelemetryService.swift` | Day 14 遥测采集：收集 Provider 选择 / 路由决策 / Fallback 触发 / 缓存命中等事件，脱敏后批量上报。 |
| Telemetry | `Services/Telemetry/LogUploader.swift` | Day 14 日志上传：脱敏后压缩上传到服务端，配合 CrashReportService 在下次启动时上报崩溃日志。 |
| Tools | `Services/Tools/ToolRegistry.swift` | `@MainActor` 单例工具注册中心，默认注册 4 个工具（AlarmTool / ReminderTool / DateTimeTool / CalculatorTool）+ `DateTimeTool`（时区时间）+ `CalculatorTool`（NSExpression 求值）+ `NotificationService`（UNUserNotificationCenter 本地通知）。 |
| Tools | `Services/Tools/AlarmTool.swift` | 基于 `EventKit EKAlarm` 的闹钟工具。 |
| Tools | `Services/Tools/ReminderTool.swift` | 基于 `EventKit EKReminder` 的提醒工具。 |
| Voice | `Services/Voice/VoiceService.swift` | 语音服务，`AVAudioSession` + `SFSpeechRecognizer` 录音识别 + `AVSpeechSynthesizer` 朗读合成，朗读前应用 `TTSConfig`。 |
| Voice | `Services/Voice/TTSConfig.swift` | Day 19 TTS 配置：voiceID / rate / pitch / volume，Codable + Sendable，UserDefaults 持久化。 |
| Voice | `Services/Voice/TTSVoiceCatalog.swift` | Day 19 TTS 音色目录：枚举 `AVSpeechSynthesisVoice` 系统音色，按语言分组供 Picker 展示。 |

### 3.4 ViewModels 层

ViewModels 文件数无新增（仍为 4 个），但内部字段与编排逻辑随 Day 12–20 扩展。

| 文件 | 职责 |
|------|------|
| `ViewModels/ChatViewModel.swift` | 核心 `@Observable @MainActor` ViewModel，管理消息列表 / 流式输出 / 工具调用 / RAG 检索 / 语音 / 灵动岛，编排 ReAct 循环与缓存读写；新增字段：`modelProvider` / `bffConfig` / `onDeviceConfig` / `ttsConfig` / `healthInsights` / `messageFeedbacks`；新增逻辑：SmartRouter 选择 provider、NetworkMonitor 监听断网切换端侧、BFF 启用时走 BFFProxyClient。 |
| `ViewModels/ConversationListVM.swift` | 会话列表 ViewModel，管理会话 CRUD 与置顶排序；新增编辑模式（多选 / 全选 / 删除选中）与 `cleanupEmptyConversations` 批量清理。 |
| `ViewModels/KnowledgeBaseVM.swift` | 知识库 ViewModel，管理文档索引与删除。 |
| `ViewModels/SettingsViewModel.swift` | 设置 ViewModel，管理 API Key 保存/删除（按 provider 隔离）、用户偏好读写、TTS 配置 / BFF 配置 / OnDevice 配置 / Health 授权状态读写。 |

### 3.5 Views 层（6 个子模块）

| 子模块 | 文件 | 职责 |
|--------|------|------|
| Chat | `ChatView.swift` / `ChatInputBar.swift` / `MessageListView.swift` / `MessageBubble.swift` / `CitationCard.swift` / `StepCardView.swift` / `ErrorOverlay.swift` / `TypingIndicator.swift` | 聊天主界面、输入栏、消息列表、消息气泡、RAG 引用卡片、ReAct 步骤卡片、错误浮层、打字指示器。 |
| Chat | `CodeBlockView.swift` / `CodeSyntaxHighlighter.swift` | Day 19 Markdown 代码块渲染 + 语法高亮（按语言 token 着色，支持复制按钮）。 |
| Chat | `MarkdownText.swift` / `HeadingView.swift` | Day 19 Markdown 富文本段落与标题分级（H1–H6 字号梯度）。 |
| Chat | `MarkdownTableParser.swift` / `MarkdownTableView.swift` | Day 19 Markdown 表格解析与渲染（解析 `|` 分隔符生成行列，滚动视图适配宽表）。 |
| Chat | `TaskListView.swift` | Day 19 任务列表渲染（`- [ ]` / `- [x]` 复选框状态）。 |
| Chat | `FeedbackBar.swift` | Day 12 消息反馈条：like / dislike / 投诉按钮，写入 `MessageFeedback` @Model。 |
| Components | `ErrorBanner.swift` / `SkeletonView.swift` | 通用错误横幅 + 骨架屏组件。 |
| Conversation | `ConversationList.swift` / `ConversationRow.swift` | 会话列表 sheet + 会话行（含 contextMenu 置顶/删除/复制/重新提问 + 编辑模式多选）。 |
| OnDevice | `OnDeviceModelView.swift` | Day 16 端侧模型管理：下载进度 / SHA256 校验 / 启用开关 / 自动切换开关 / 模型路径展示。 |
| RAG | `DocumentPickerView.swift` / `KnowledgeBaseView.swift` | 文档选择器（PDF/文本）+ 知识库管理界面。 |
| Settings | `SettingsView.swift` | 设置界面，含 API Key 管理（多 provider）/ 模型切换 / 系统提示词（`systemPromptSection` 上方新增「预设角色」Menu，选中后填入 TextEditor 保留可编辑性）/ 用户偏好 / RAG+Tools Toggle（Toggle 用中文 description）/ 调试面板（`DebugPanelView`）/ BFF 配置入口 / OnDevice 配置入口 / Health 入口 / TTS 入口；`regularLayout` detail 包 `NavigationStack` 让 macOS 二级页有返回按钮。 |
| Settings | `PresetPrompts.swift` | 预设系统提示词清单：`PresetPrompt`（role + prompt）+ `PresetPrompts` enum 提供 11 个预设角色（默认助手 / 开发者 / 学生 / 白领 / 管理者 / 产品经理 / 写作助手 / 技术面试官 / 学习导师 / 翻译官 / 健身教练），每个含 ≥ 150 字完整 system prompt，供 SettingsView Menu 选择。 |
| Settings | `TTSVoicePickerView.swift` | Day 19 TTS 音色选择：音色 Picker / 语速 / 音调 / 音量 / 试听按钮。 |
| Settings | `HealthSettingsView.swift` | Day 18 Health 授权管理 + 健康洞察列表展示。 |
| Settings | `PrivacyPolicyView.swift` | Day 14 隐私政策展示（Markdown 渲染）+ 投诉反馈入口。 |

---

## 4. 数据流

### 4.1 主流程

从用户输入到 AI 回复的完整数据流，含 Provider 选择与网络监听切换：

```
ChatInputBar.onSend
    │
    ▼
ChatViewModel.sendMessage(in:modelContext:)
    │  (清理 streamingText / isLoading=true / startLiveActivity「思考中」)
    ▼
streamingTask = Task { await processMessage(...) }
    │
    ▼
processMessage(text:conversation:modelContext:)
    │  (读 provider 当前选择 → SmartRouter.route(...) 选定 client)
    │  (注入 preference systemPrompt / 计算 queryEmbedding)
    │
    ▼
[五条分支路径，见下]
    │
    ▼
client.chat(...) → AsyncStream<String / ParsedChunk>
    │  (streamingText += chunkContent → MessageListView 实时更新)
    │  (MarkdownText / CodeBlockView / MarkdownTableView 实时重新渲染)
    ▼
assistantMsg 持久化 → streamingText = "" → isLoading = false
    │  (TTSConfig 应用 → VoiceService.speak 可选朗读)
    ▼
endLiveActivity「完成」
```

### 4.2 路径 1：UITEST_DISABLE_NETWORK 桩回复

**触发条件**：`ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_NETWORK")`

```
processMessage 入口
    │  (检测到 UITEST_DISABLE_NETWORK 启动参数)
    ▼
短路 HTTP / RAG / Tool
    │  (直接追加用户消息 + 4 char/8ms 假打字输出)
    ▼
stubReply = "（UIT 测试模式）已收到：{input}"
    │  (chars.chunked(into: 4) → streamingText += String(piece) → Task.sleep 8ms)
    ▼
追加 assistantMsg → try? modelContext.save() → endLiveActivity → return
```

**用途**：UIT 不触发真实 HTTP，复用缓存命中的假打字路径驱动 UI 状态机。

### 4.3 路径 2：缓存命中

**触发条件**：`!toolsEnabled && !queryEmbedding.isEmpty && cache.get(query:embedding:) != nil`（相似度 > 0.92）

```
SemanticCache.get(query:embedding:)
    │  (cosineSimilarity > similarityThreshold 0.92 → 命中)
    ▼
跳过 RAG / LLM / ReAct
    │  (4 char/8ms 假打字输出缓存 response)
    ▼
streamingText += String(piece) → Task.sleep 8ms
    │
    ▼
追加 assistantMsg → try? modelContext.save() → return
```

### 4.4 路径 3：正常 RAG + LLM + ReAct

**RAG 开启时**：

```
ragService.buildAugmentedContext(query:modelContext:apiKey:)
    │  (embed query → fetch 全部分块 → cosine 相似度排序取前 5)
    ▼
返回 (context: 带 [1][2] 编号的 prompt, citations: [DocumentChunk], queryEmbedding)
    │  (复用 queryEmbedding 写缓存，避免重复调 embed API)
    ▼
apiMessages.insert(system: context, at: 1) → currentCitations = citations
```

**构造 messages + token 截断**：

```
limitTokens(apiMessages, max: tokenLimit)
    │  (从尾部逆序遍历，累计 token 超 max 则截断；默认 maxTokens=2048)
```

**ReAct 循环**（`maxReActLoops=5`）：

```
while loopCount < 5 {
    loopCount += 1
    client.chat(messages:config:tools:apiKey:) → AsyncStream<ParsedChunk>
        │  (yield content → streamingText 更新 → updateLiveActivity「回复中」首字触发)
        │  (yield toolCalls → finalToolCalls 累积)
    │
    ▼
    [有 tool_calls 分支]
        │  (withThrowingTaskGroup 并发执行工具)
        │  (group.addTask: ToolRegistry.execute / group.addTask: Task.sleep toolTimeout=15s)
        │  (first 胜出 / group.cancelAll / 超时标记 failed 继续下一轮不中断循环)
        │  (工具成功 → NotificationService.sendNotification 本地通知)
        │  (yield ToolStep 到 currentToolSteps → StepCardView 显示思维链)
        │  (apiMessages = conversation.messages.map(toAPIMessage) → continue)
    │
    ▼
    [无 tool_calls 分支] → break
}
```

**缓存写入条件**：

```
if !toolsEnabled && !fullResponse.isEmpty && !queryEmbedding.isEmpty {
    cache.set(query:embedding:response:)  // 仅非工具模式且响应非空且 embedding 有效
}
```

### 4.5 路径 4：BFF 代理路径（Day 15）

**触发条件**：`bffConfig.enabled == true`（设置页启用 BFF）

```
ModelProviderFactory.create(provider:) 检测 bffConfig.enabled
    │  (返回 BFFProxyClient 而非直连 DeepSeekClient / QwenClient)
    ▼
BFFProxyClient.chat(messages:apiKey:)
    │  (apiKey 字段实际传 bffConfig.userToken)
    │  (请求经 Cloudflare Workers 网关中转)
    │  (服务端注入上游真实 API Key → 调用 LLM → SSE 流回客户端)
    ▼
RateLimiter.acquire(.chat) 客户端限流
    │  (按 chatRateLimitPerMin 令牌桶控制)
    ▼
AsyncStream<ParsedChunk> 流式回包 → 同路径 3 解析
```

**关键约束**：设备端不持上游 API Key，仅持 `userToken`；上游 Key 仅在 Cloudflare Workers 服务端 secrets 中。

### 4.6 路径 5：端侧推理路径（Day 16）

**触发条件**：`onDeviceConfig.enabled == true` 且（手动切换到 `.onDevice` 或 NetworkMonitor 检测到断网且 `autoSwitchOnNetworkLoss == true`）

```
NetworkMonitor.pathUpdate → status == .unsatisfied
    │  (autoSwitchOnNetworkLoss 触发 → 当前 provider 切到 .onDevice)
    ▼
ModelProviderFactory.create(.onDevice) → OfflineLLMProvider
    │  (包装 MLXInferenceEngine)
    ▼
OnDeviceModelDownloader.ensureModel()
    │  (检查 modelPath 是否存在 → 否则从 downloadURL 下载 + SHA256 校验)
    ▼
MLXInferenceEngine.load(modelPath:) → 流式生成 token
    │  (不走 HTTP，本地推理)
    ▼
AsyncStream<String> yield → streamingText 更新
    │  (maxTokens 受 onDeviceConfig.maxTokens 限制，默认 512)
    ▼
网络恢复 → NetworkMonitor 触发切回原 provider
```

### 4.7 TTS 配置应用流程（Day 19）

```
VoiceService.speak(text:)
    │  (读取 TTSConfig UserDefaults)
    ▼
AVSpeechSynthesisUtterance(text:)
    │  (按 voiceID 选择 AVSpeechSynthesisVoice)
    │  (apply rate / pitch / volume)
    ▼
AVSpeechSynthesizer.speak(utterance)
    │  (支持试听取消与朗读打断)
```

### 4.8 灵动岛状态机

```
sendMessage → startLiveActivity(status: "思考中")
    │
    ▼  (收到首字 chunk)
updateLiveActivity(status: "回复中")
    │
    ▼  (回复结束)
endLiveActivity(status: "完成") → dismissalPolicy: .immediate
```

---

## 5. 关键设计决策

### Day 1–11 基础决策

| # | 决策 | 选型理由 | 对应文件 |
|---|------|---------|---------|
| 1 | MVVM + `@Observable` 不用 Combine | iOS 17+ 新观察模型，比 Combine 更简洁，无需 `ObservableObject` / `@Published` 样板代码。 | `ViewModels/` 4 个文件 |
| 2 | SwiftData 不用 CoreData / Realm | iOS 17+ 原生持久化，`@Model` 宏自动生成 schema 与迁移，与 SwiftUI 深度集成。 | `Models/` 7 个 `@Model` |
| 3 | DeepSeek API 合规优先 | 国内可用、协议兼容 OpenAI chat completions，避免 OpenAI 直连的网络与合规问题。 | `Services/LLM/DeepSeekClient.swift` |
| 4 | `AsyncStream` 流式不用 Combine Publisher | `AsyncStream<String>` / `AsyncStream<ParsedChunk>` 更适合 SSE 流式解析的逐 chunk yield 语义，比 Publisher 更直观。 | `Services/LLM/DeepSeekClient.swift` `chat` 返回值 |
| 5 | `nonisolated DeepSeekClient` 跨 actor | 允许从 `@MainActor` ViewModel 直接调用，避免 actor hop 开销；HTTP 请求本身在 URLSession 内部异步。 | `DeepSeekClient` 类声明 |
| 6 | `@MainActor Service` 线程安全 | `SemanticCache` / `RAGService` / `ToolRegistry` / `ChatStorage` 标 `@MainActor`，与 ViewModel 同 actor 避免 data race。 | 各 Service 文件 |
| 7 | `LLMProvider` 协议注入测试可替换 | `ChatViewModel.init(client:cache:)` 默认 `DeepSeekClient()` / `SemanticCache()` 兜底，测试可注入 mock。 | `ViewModels/ChatViewModel.swift` `init` |
| 8 | `UITEST_DISABLE_NETWORK` 启动参数桩回复 | UIT 不触发真实 HTTP，避免 API Key 缺失 / 网络不稳导致 UIT 随机失败。 | `ChatViewModel.processMessage` 入口分支 |

### Day 12–20 扩展决策

| # | 决策 | 选型理由 | 对应文件 |
|---|------|---------|---------|
| 9 | 智能路由 SmartRouter + 自动 Fallback | 多 Provider 可用时按规则与历史成功率动态选择，单点失败自动切 fallback provider，提升可用性。 | `Services/Routing/SmartRouter.swift` / `Services/LLM/FallbackLLMProvider.swift` |
| 10 | BFF Token 设备端不持上游 API Key | 设备端仅持 `userToken`，上游 Key 仅在 Cloudflare Workers secrets 中，避免 Key 泄露与配额盗用。 | `Core/Models/BFFConfig.swift` / `Services/LLM/BFFProxyClient.swift` |
| 11 | MLX 端侧模型断网自动切换 | `OnDeviceConfig.autoSwitchOnNetworkLoss` 默认 true，NetworkMonitor 检测断网即切端侧推理，网络恢复自动切回，保证离线可用。 | `Services/Network/NetworkMonitor.swift` / `Services/OnDevice/OfflineLLMProvider.swift` |
| 12 | TTSConfig UserDefaults 持久化不用 SwiftData | TTS 配置为轻量键值，UserDefaults 比 SwiftData 更轻量，避免迁移复杂度。 | `Services/Voice/TTSConfig.swift` |
| 13 | `UITEST_RESET_DATA` 数据隔离 | UIT 启动时通过环境变量清理历史会话与缓存，保证用例独立可重复执行，避免脏数据干扰。 | `AIBuilderApp.swift` 启动逻辑 |
| 14 | `batch cleanupEmptyConversations` 后台清理 | 后台任务批量清理空会话（无消息或仅 system prompt），控制 SwiftData 体积。 | `Services/Storage/ChatStorage.swift` `cleanupEmptyConversations` |
| 15 | Markdown 渲染自定义 AttributedString 不引第三方库 | 用 Foundation `AttributedString` + 自定义 parser，避免引入 Down / Ink 等第三方库，控制包体积与依赖。 | `Views/Chat/Markdown*.swift` / `CodeSyntaxHighlighter.swift` |
| 16 | 隐私清单 PrivacyInfo.xcprivacy 显式声明 | App Store 审核要求显式声明 Required Reason API 使用（UserDefaults / FileTimestamp / SystemBootTime 等）。 | `Resources/PrivacyInfo.xcprivacy` |
| 17 | App Intents 三 Intent 设计 | Ask / NewConversation / SwitchConversation 覆盖 Shortcuts / Spotlight / Siri 三入口，最小可用集。 | `AppIntents/*.swift` |
| 18 | 崩溃日志下次启动上报不上传实时 | 实时上报在崩溃瞬间不可靠（进程已死），落盘 + 下次启动上报更稳。 | `Services/Crash/CrashReportService.swift` |
| 19 | 遥测脱敏后批量上报 | 单事件实时上报耗电耗流量，批量 + 脱敏更合规与高效。 | `Services/Telemetry/TelemetryService.swift` |

#### 决策：多平台适配（Day 20 后）

- **方案**：采用 SwiftUI 原生渲染 + `#if os(iOS)` 条件编译，而非 Catalyst 或完全双份代码
- **理由**：SwiftUI 跨平台能力强，单份代码覆盖三端；`#if os(iOS)` 隔离 iOS-only 框架让 macOS 优雅降级（HealthKit 入口隐藏但保留 HealthInsight 模型注册维持 schema 一致性）
- **关键替换**：DocumentPickerView 用 SwiftUI `.fileImporter` 替代 UIKit；FeedbackService 用 `ProcessInfo` 替代 `UIDevice`；SettingsView / KnowledgeBaseView 用 NavigationSplitView 双栏布局
- **macOS 原生 UX**：窗口默认 1000×700，菜单栏 ⌘N 新建 / ⌘K 搜索 / ⌘, 设置，⌘Enter 发送

#### 决策：工具能力增强（Day 20 后）

- **方案**：所有新工具统一实现 `ToolProtocol`（definition + execute），按平台用条件编译注册
- **跨平台工具**：无条件注册（LocationTool 用 CheckedContinuation 包装 CLLocationManager 委托 API，WeatherTool 用 Open-Meteo 免费 API 无需 Key）
- **macOS 独有工具**：整体文件用 `#if os(macOS)` 包裹，ToolRegistry init 中用 `#if os(macOS)` 条件注册
- **快捷指令创建**：CreateShortcutTool 构建 WFWorkflow plist 格式序列化为 .shortcut 文件，用 NSWorkspace.open 让 Shortcuts 应用导入；iOS 端 RunShortcutTool 用 NSUserActivity 触发
- **权限**：Info.plist 新增 NSLocationWhenInUseUsageDescription 和 NSContactsUsageDescription

#### 决策：预设系统提示词（Day 20 后）

- **方案**：在 `systemPromptSection` 上方加 Menu 选择预设角色，选中后写入 `settingsVM.systemPrompt`（填入而非锁定 TextEditor），复用现有「完成」按钮回写逻辑。
- **理由**：零侵入 ViewModel / Model 层，预设角色仅作为快捷输入入口，填入后仍可二次编辑，兼顾「开箱即用」与「灵活定制」。
- **实现**：`PresetPrompts.swift` 用 `enum PresetPrompts` 暴露 `static let all: [PresetPrompt]`，每个 `PresetPrompt` 含 role + prompt（≥ 150 字），共 11 个角色覆盖开发者 / 学生 / 白领 / 管理者 / 产品经理 / 写作助手 / 技术面试官 / 学习导师 / 翻译官 / 健身教练等典型场景。

#### 决策：macOS 体验修复（Day 20 后）

- **方案**：针对 macOS 多处体验塌缩定向修复，不引入新依赖。
- **NavigationStack 包裹 detail**：`regularLayout` 的 detail 栏包 `NavigationStack`，解决 macOS 二级页（TTS / 隐私政策 / 端侧模型管理）无返回按钮的问题。
- **工具项中文化**：`preferenceSection` 的 Toggle 文案从 `toolDef.function.name`（英文）改为 `toolDef.function.description`（中文），零改动 ToolProtocol。
- **NSColor shim 改色**：MessageBubble.swift 的 systemGray3 / 5 / 6 在 macOS 上同色导致 markdown 视觉层次塌缩，改为 separatorColor / textBackgroundColor / controlBackgroundColor 三种不同灰阶。
- **MarkdownText parseBlocks 缓存**：用 NSCache（countLimit=200）缓存 parseBlocks 结果，解决语音朗读时反复重渲染卡顿。
- **VoiceService 兜底**：加 `@MainActor` 隔离、`didCancel` 兜底清理（解决按钮卡死）、voice nil 降级（不崩）、移除 `spokenText` 死状态。

---

## 6. 技术栈映射

| 技术选型 | 实际文件 / 类型 |
|---------|---------------|
| SwiftUI `@Observable` | `Views/` 全部 + `ViewModels/` 全部 |
| SwiftData `@Model` | `Models/ChatMessage.swift` / `Conversation.swift`（含 `UserPreference`）/ `DocumentChunk.swift` / `HealthInsight.swift` / `MessageFeedback.swift` / `RemoteConfig.swift`；`ChatChunk.swift` 为普通 `Codable` 结构 |
| DeepSeek API chat completions | `Services/LLM/DeepSeekClient.swift`（`chat` 流式 + `embed`） |
| Qwen API（阿里云百炼 DashScope OpenAI 兼容） | `Services/LLM/QwenClient.swift` |
| BFF 代理（Cloudflare Workers） | `Services/LLM/BFFProxyClient.swift` + `CloudflareWorkers/worker.js` + `CloudflareWorkers/wrangler.toml` |
| MLX 端侧推理 | `Services/OnDevice/MLXInferenceEngine.swift` / `OfflineLLMProvider.swift` / `OnDeviceModelDownloader.swift` |
| DeepSeek API SSE 流式 | `Services/LLM/SSEParser.swift`（`parseChunk` / `parseWithToolAccumulation`） |
| DeepSeek API function calling | `Services/Tools/ToolRegistry.swift`（`allToolDefs` → `ToolDef`） |
| `AVAudioSession` + `SFSpeechRecognizer` | `Services/Voice/VoiceService.swift`（`startRecording`） |
| `AVSpeechSynthesizer` + TTSConfig | `Services/Voice/VoiceService.swift`（`speak`）/ `TTSConfig.swift` / `TTSVoiceCatalog.swift` |
| EventKit `EKAlarm` | `Services/Tools/AlarmTool.swift` |
| EventKit `EKReminder` | `Services/Tools/ReminderTool.swift` |
| ActivityKit Live Activities | `App/AIBuilderApp.swift` `TimerActivityAttributes` |
| `BGTaskScheduler` | `App/AIBuilderApp.swift` `scheduleDailyRefresh` / `handleDailyRefresh` |
| `UserNotifications` | `Services/Tools/ToolRegistry.swift` `NotificationService` |
| Keychain | `Services/Auth/KeychainManager.swift`（按 provider 隔离 account） |
| PDFKit | `Services/RAG/PDFExtractor.swift` |
| NLTokenizer | `Services/RAG/DocumentChunker.swift` |
| NSExpression | `Services/Tools/ToolRegistry.swift` `CalculatorTool` |
| HealthKit | `Services/Health/HealthKitService.swift` / `HealthInsightGenerator.swift` |
| App Intents | `AppIntents/AskAIBuilderIntent.swift` / `NewConversationIntent.swift` / `SwitchConversationIntent.swift` |
| Spotlight（CoreSpotlight） | `Services/Search/SpotlightIndexer.swift` |
| Handoff（NSUserActivity） | `AIBuilderTests/ConversationActivityTests.swift` 覆盖的 NSUserActivity 恢复逻辑 |
| CrashReportService | `Services/Crash/CrashReportService.swift` |
| FeedbackService | `Services/Feedback/FeedbackService.swift` |
| WatchConnectivity | `Services/Connectivity/WatchConnectivityService.swift` + `AIBuilderWatch/` |
| NWPathMonitor | `Services/Network/NetworkMonitor.swift` |
| RemoteConfig | `Services/RemoteConfig/RemoteConfigService.swift` |
| Telemetry | `Services/Telemetry/TelemetryService.swift` / `LogUploader.swift` |
| PerformanceMonitor | `Services/Performance/PerformanceMonitor.swift` |
| PrivacyInfo.xcprivacy | `Resources/PrivacyInfo.xcprivacy` |
| AttributedString（Markdown） | `Views/Chat/Markdown*.swift` / `CodeSyntaxHighlighter.swift` |
| XCTest | `AIBuilderTests/` 69 文件（249 用例） |
| XCUITest | `AIBuilderUITests/` 2 文件（13 用例） |
| GitHub Actions | `.github/workflows/ci.yml` |
| CoreLocation | CLLocationManager + CLGeocoder | LocationTool 定位与反地理编码 |
| Contacts | CNContactStore | ContactsTool 通讯录搜索 |
| Vision | VNRecognizeTextRequest | OCRTool 图片文字识别（macOS） |
| CoreGraphics | CGDisplayCreateImage / CGEvent | ScreenshotTool 截屏 + InputAutomationTool 输入模拟（macOS） |
| NSAppleScript | NSAppleScript | AppleScriptTool / SafariControlTool / SystemControlTool / FinderTool（macOS） |
| NSWorkspace | NSWorkspace | AppManagementTool / OpenURLTool / FileOperationTool（macOS 部分） |
| Process | Foundation.Process | TerminalCommandTool + ShortcutsTool CLI（macOS） |
| Shortcuts CLI | shortcuts run / shortcuts list | RunShortcutTool / ListShortcutsTool（macOS） |

---

## 7. 测试架构

### 7.1 单元测试（UT）

- **Target**：`AIBuilderTests`
- **规模**：69 个测试文件，249 用例（246 pass / 3 skip / 0 failures）
- **分层覆盖**：

| 层级 | 测试文件 | 文件数 |
|------|---------|--------|
| Service 层 | `DeepSeekClientTests` / `QwenClientTests` / `BFFProxyClientTests` / `FallbackLLMProviderTests` / `ModelProviderTests` / `RateLimiterTests` / `SSEParserTests` / `SemanticCacheTests` / `SemanticCacheEdgeTests` / `DocumentChunkerTests` / `EmbeddingServiceTests` / `RAGServiceTests` / `PDFExtractorTests` / `ChatStorageTests` / `KeychainManagerTests` / `KeychainManagerMultiProviderTests` / `ToolRegistryTests` / `AlarmToolTests` / `ReminderToolTests` / `CalculatorToolTests` / `DateTimeToolTests` / `NotificationServiceTests` / `VoiceServiceTests` / `TTSConfigTests` / `TTSVoiceCatalogTests` / `SmartRouterTests` / `NetworkMonitorTests` / `OfflineLLMProviderTests` / `OnDeviceConfigTests` / `RemoteConfigServiceTests` / `TelemetryServiceTests` / `LogUploaderTests` / `CrashReportServiceTests` / `PerformanceMonitorTests` / `SpotlightIndexerTests` / `IntentChatServiceTests` / `HealthKitServiceTests` / `HealthInsightGeneratorTests` / `FeedbackServiceTests` / `WatchConnectivityServiceTests` | 58 |
| Model 层 | `ChatMessageTests` / `ConversationModelTests` / `MessageFeedbackTests` / `StringTokenCountTests` / `APIConfigTests` / `PresetPromptsTests` | 6 |
| ViewModel 层 | `ChatViewModelTests` / `ConversationListVMTests` / `KnowledgeBaseVMTests` / `SettingsViewModelTests` | 4 |
| 跨层 / 行为 | `ConversationActivityTests`（NSUserActivity / Handoff） | 1 |
| 合计 | — | 69 |

- **新增关键测试文件**：
  - `TTSConfigTests.swift`：TTS 配置持久化与默认值
  - `TTSVoiceCatalogTests.swift`：系统音色目录枚举与语言分组
  - `RoutingServiceTests.swift`（实为 `SmartRouterTests.swift`）：智能路由规则与 Fallback 触发
  - `BFFProxyClientTests.swift`：BFF 代理请求构造与 userToken 注入
  - `OfflineLLMProviderTests.swift` / `OnDeviceConfigTests.swift`：端侧推理与配置
  - `HealthKitServiceTests.swift` / `HealthInsightGeneratorTests.swift`：HealthKit 数据读取与洞察生成
  - `IntentChatServiceTests.swift`：App Intents 路由
  - `SpotlightIndexerTests.swift`：Spotlight 索引创建/清理
  - `CrashReportServiceTests.swift` / `PerformanceMonitorTests.swift` / `TelemetryServiceTests.swift` / `LogUploaderTests.swift`：监控与遥测
  - `FeedbackServiceTests.swift` / `MessageFeedbackTests.swift`：反馈持久化
  - `WatchConnectivityServiceTests.swift`：Watch 通信
  - `PresetPromptsTests.swift`：预设系统提示词清单（11 个角色完整性 / prompt 非空 / 角色唯一 / ≥ 150 字校验，4 用例）

- **skip 场景**：Keychain 不可用（模拟器 entitlement 限制）/ 语音识别器不可用 / NLTokenizer 未切分多块 / 权限拒绝 / HealthKit 授权未授予 / MLX 模型未下载 / 网络环境依赖等场景，用 `XCTSkip` / `XCTSkipUnless` 兜底。

### 7.2 UI 测试（UIT）

- **Target**：`AIBuilderUITests`
- **规模**：2 个测试文件，13 用例（11 pass / 2 skip / 0 failures）
- **文件拆分**：

| 文件 | 用例数 | 覆盖端到端流 |
|------|--------|-------------|
| `AIBuilderUITests.swift` | 12 | 启动 / 会话列表 / 创建会话 / API Key 保存/删除 / RAG+Tools Toggle / 模型切换 / 系统提示词 / 用户偏好 / contextMenu / 搜索 / 错误条 / 预设角色（修复 switch 标签定位与 flaky tap） |
| `AIBuilderUITestsLaunchUITests.swift` | 1 | launch 用例 |

- **启动参数**：
  - `UITEST_DISABLE_NETWORK`：短路真实 HTTP，注入桩回复「（UIT 测试模式）已收到：{input}」
  - `UITEST_RESET_DATA`：启动时清理历史会话与缓存，保证用例独立可重复执行
- **skip 场景**：contextMenu 在模拟器上不稳定 / Picker / Section 滚动时机差异 / alert 未在超时内消失等，用 `throw XCTSkip` 兜底。

### 7.3 持续集成（CI）

- **配置文件**：`.github/workflows/ci.yml`
- **触发条件**：push to `main` + pull_request to `main`
- **Runner**：`macos-14`
- **执行步骤**：

| 步骤 | 命令 |
|------|------|
| Checkout | `actions/checkout@v4` |
| Build | `xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO` |
| Test (UT + UIT) | `xcodebuild test ... -resultBundlePath TestResults.xcresult CODE_SIGNING_ALLOWED=NO` |
| Upload artifact | `actions/upload-artifact@v4`（`if: always()`，name: `test-results-xcresult`） |

- **Destination**：iPhone 17 模拟器。

---

## 8. 目录结构

完整目录树，与磁盘一致：

```
AIBuilder/
├── App/
│   └── AIBuilderApp.swift
├── AppIntents/
│   ├── AskAIBuilderIntent.swift
│   ├── NewConversationIntent.swift
│   └── SwitchConversationIntent.swift
├── Core/
│   ├── Actors/
│   │   └── ChatActor.swift
│   ├── Constants/
│   │   ├── APIConfig.swift
│   │   └── ModelProvider.swift
│   ├── Extensions/
│   │   └── String+TokenCount.swift
│   ├── Models/
│   │   ├── BFFConfig.swift
│   │   ├── OnDeviceConfig.swift
│   │   └── OnDeviceError.swift
│   └── Protocols/
│       ├── LLMProvider.swift
│       └── ToolProtocol.swift
├── Models/
│   ├── ChatChunk.swift
│   ├── ChatMessage.swift
│   ├── Conversation.swift
│   ├── DocumentChunk.swift
│   ├── HealthInsight.swift
│   ├── MessageFeedback.swift
│   └── RemoteConfig.swift
├── Resources/
│   ├── Assets.xcassets/
│   │   ├── AccentColor.colorset/
│   │   │   └── Contents.json
│   │   ├── AppIcon.appiconset/
│   │   │   ├── AppIcon-1024.png
│   │   │   └── Contents.json
│   │   └── Contents.json
│   ├── Info.plist
│   └── PrivacyInfo.xcprivacy
├── Services/
│   ├── Auth/
│   │   └── KeychainManager.swift
│   ├── Cache/
│   │   └── SemanticCache.swift
│   ├── Connectivity/
│   │   └── WatchConnectivityService.swift
│   ├── Crash/
│   │   └── CrashReportService.swift
│   ├── Feedback/
│   │   └── FeedbackService.swift
│   ├── Health/
│   │   ├── HealthInsightGenerator.swift
│   │   └── HealthKitService.swift
│   ├── Intents/
│   │   └── IntentChatService.swift
│   ├── LLM/
│   │   ├── BFFProxyClient.swift
│   │   ├── DeepSeekClient.swift
│   │   ├── FallbackLLMProvider.swift
│   │   ├── ModelProviderFactory.swift
│   │   ├── QwenClient.swift
│   │   ├── RateLimiter.swift
│   │   └── SSEParser.swift
│   ├── Network/
│   │   └── NetworkMonitor.swift
│   ├── OnDevice/
│   │   ├── MLXInferenceEngine.swift
│   │   ├── OfflineLLMProvider.swift
│   │   └── OnDeviceModelDownloader.swift
│   ├── Performance/
│   │   └── PerformanceMonitor.swift
│   ├── RAG/
│   │   ├── DocumentChunker.swift
│   │   ├── EmbeddingService.swift
│   │   ├── PDFExtractor.swift
│   │   └── RAGService.swift
│   ├── RemoteConfig/
│   │   └── RemoteConfigService.swift
│   ├── Routing/
│   │   └── SmartRouter.swift
│   ├── Search/
│   │   └── SpotlightIndexer.swift
│   ├── Storage/
│   │   └── ChatStorage.swift
│   ├── Telemetry/
│   │   ├── LogUploader.swift
│   │   └── TelemetryService.swift
│   ├── Tools/
│   │   ├── AlarmTool.swift
│   │   ├── AppManagementTool.swift                # macOS
│   │   ├── AppleScriptTool.swift                  # macOS
│   │   ├── ClipboardTool.swift                    # 含 ReadClipboardTool + WriteClipboardTool
│   │   ├── ContactsTool.swift
│   │   ├── DeviceInfoTool.swift
│   │   ├── FileOperationTool.swift                # macOS
│   │   ├── FinderTool.swift                       # macOS
│   │   ├── InputAutomationTool.swift              # macOS
│   │   ├── LocationTool.swift
│   │   ├── OCRTool.swift                          # macOS
│   │   ├── OpenURLTool.swift
│   │   ├── ReminderTool.swift
│   │   ├── SafariControlTool.swift                # macOS
│   │   ├── ScreenshotTool.swift                   # macOS
│   │   ├── ShortcutsTool.swift                    # 含 RunShortcutTool + ListShortcutsTool + CreateShortcutTool
│   │   ├── SystemControlTool.swift                # macOS
│   │   ├── TerminalCommandTool.swift              # macOS
│   │   ├── ToolRegistry.swift
│   │   ├── WeatherTool.swift
│   │   └── WindowManagementTool.swift             # macOS
│   └── Voice/
│       ├── TTSConfig.swift
│       ├── TTSVoiceCatalog.swift
│       └── VoiceService.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   ├── ConversationListVM.swift
│   ├── KnowledgeBaseVM.swift
│   └── SettingsViewModel.swift
└── Views/
    ├── Chat/
    │   ├── ChatInputBar.swift
    │   ├── ChatView.swift
    │   ├── CitationCard.swift
    │   ├── CodeBlockView.swift
    │   ├── CodeSyntaxHighlighter.swift
    │   ├── ErrorOverlay.swift
    │   ├── FeedbackBar.swift
    │   ├── HeadingView.swift
    │   ├── MarkdownTableParser.swift
    │   ├── MarkdownTableView.swift
    │   ├── MarkdownText.swift
    │   ├── MessageBubble.swift
    │   ├── MessageListView.swift
    │   ├── StepCardView.swift
    │   ├── TaskListView.swift
    │   └── TypingIndicator.swift
    ├── Components/
    │   ├── ErrorBanner.swift
    │   └── SkeletonView.swift
    ├── Conversation/
    │   ├── ConversationList.swift
    │   └── ConversationRow.swift
    ├── OnDevice/
    │   └── OnDeviceModelView.swift
    ├── RAG/
    │   ├── DocumentPickerView.swift
    │   └── KnowledgeBaseView.swift
    └── Settings/
        ├── HealthSettingsView.swift
        ├── PresetPrompts.swift
        ├── PrivacyPolicyView.swift
        ├── SettingsView.swift
        └── TTSVoicePickerView.swift

AIBuilderWatch/                  # watchOS App
├── Views/
│   ├── WatchHealthInsightView.swift
│   └── WatchQuickChatView.swift
└── WatchApp.swift

CloudflareWorkers/               # BFF 代理网关
├── worker.js
└── wrangler.toml

AIBuilderTests/                  # 69 个 UT 文件 / 249 用例
├── APIConfigTests.swift
├── AlarmToolTests.swift
├── BFFProxyClientTests.swift
├── CalculatorToolTests.swift
├── ChatMessageTests.swift
├── ChatStorageTests.swift
├── ChatViewModelTests.swift
├── ConversationActivityTests.swift
├── ConversationListVMTests.swift
├── ConversationModelTests.swift
├── CrashReportServiceTests.swift
├── DateTimeToolTests.swift
├── DeepSeekClientTests.swift
├── DocumentChunkerTests.swift
├── EmbeddingServiceTests.swift
├── FallbackLLMProviderTests.swift
├── FeedbackServiceTests.swift
├── HealthInsightGeneratorTests.swift
├── HealthKitServiceTests.swift
├── IntentChatServiceTests.swift
├── KeychainManagerMultiProviderTests.swift
├── KeychainManagerTests.swift
├── KnowledgeBaseVMTests.swift
├── LogUploaderTests.swift
├── MessageFeedbackTests.swift
├── ModelProviderTests.swift
├── NetworkMonitorTests.swift
├── NotificationServiceTests.swift
├── OfflineLLMProviderTests.swift
├── OnDeviceConfigTests.swift
├── PDFExtractorTests.swift
├── PerformanceMonitorTests.swift
├── PresetPromptsTests.swift
├── QwenClientTests.swift
├── RAGServiceTests.swift
├── RateLimiterTests.swift
├── ReminderToolTests.swift
├── RemoteConfigServiceTests.swift
├── SSEParserTests.swift
├── SemanticCacheEdgeTests.swift
├── SemanticCacheTests.swift
├── SettingsViewModelTests.swift
├── SmartRouterTests.swift
├── SpotlightIndexerTests.swift
├── StringTokenCountTests.swift
├── TTSConfigTests.swift
├── TTSVoiceCatalogTests.swift
├── TelemetryServiceTests.swift
├── ToolRegistryTests.swift
├── VoiceServiceTests.swift
└── WatchConnectivityServiceTests.swift

AIBuilderUITests/                # 2 个 UIT 文件 / 13 用例
├── AIBuilderUITests.swift
├── AIBuilderUITestsLaunchUITests.swift
└── Info.plist

AIBuilder.xcodeproj/             # Xcode 工程文件
doc/
├── ARCHITECTURE.md              # 本文件
├── USAGE.md
├── MANUAL_TEST_CHECKLIST.md
├── ReleaseChecklist.md
├── BFF_DEPLOYMENT.md
├── plans/
│   ├── 2026-07-06-day1-streaming-chat.md
│   └── 2026-07-06-day2-conversation-memory.md
└── AI Builder 实战计划.md
.github/workflows/ci.yml
.trae/specs/                     # 43 个 spec 目录（Day 1–20 + 修复 + 补充 + 文档更新）
README.md
.gitignore
```
