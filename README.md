# AIBuilder

> AI Native 多平台 App（iOS / iPad / macOS 原生），基于 SwiftUI + 多 LLM Provider（DeepSeek / Qwen / 端侧 MLX），覆盖流式对话、RAG、工具调用、语音、视觉多模态、灵动岛等 31 项能力。

## 截图

| iOS 主对话 | iOS 设置 | iOS 知识库 | iOS 健康洞察 |
|---|---|---|---|
| ![iOS Chat](screenshots/ios_chat_main.png) | ![iOS Settings](screenshots/ios_settings.png) | ![iOS Knowledge Base](screenshots/ios_knowledge_base.png) | ![iOS Health](screenshots/ios_health_insight.png) |

| iOS 端侧模型 | iOS 预设提示词 | macOS 对话 | macOS 设置 |
|---|---|---|---|
| ![iOS On-Device](screenshots/ios_ondevice_model.png) | ![iOS Presets](screenshots/ios_preset_prompts.png) | ![macOS Chat](screenshots/macos_chat.png) | ![macOS Settings](screenshots/macos_settings.png) |

## 核心功能

### Day 1-11 基础能力

- 流式对话（SSE 打字机效果）
- 多轮对话与上下文记忆（SwiftData 持久化）
- RAG 本地知识库（PDF 导入 + 分块 + 余弦相似度检索）
- ReAct 工具调用循环（ToolRegistry）
- 语音输入与朗读（SFSpeechRecognizer + AVSpeechSynthesizer）
- 视觉多模态（PhotosPicker + DeepSeek Vision）
- 用户偏好记忆（语气 / 工具 / 自定义事实）
- 调试面板（查看 prompt / API 响应 / embedding / 工具调用）
- Live Activities 灵动岛
- BGTaskScheduler 后台触发
- 本地通知主动提醒

### Day 12-20 扩展能力

- Markdown 渲染（代码块 / 表格 / 任务列表 / 标题 / 富文本）
- TTS 音色可调节（TTSConfig + TTSVoiceCatalog + TTSVoicePickerView）
- 消息复制与重新提问
- 批量多选删除会话
- 智能路由 SmartRouter
- 多 Provider 支持（DeepSeek / Qwen / 端侧）
- BFF 代理层（Cloudflare Workers）
- MLX 端侧推理（Llama-3.2-1B-Instruct Q4_K_M）
- HealthKit 健康洞察
- App Intents / Shortcuts / Spotlight / Siri 集成

### 多平台与工具增强

- 多平台适配（iOS / iPad / macOS 三端，`#if os(iOS)` 条件编译，NavigationSplitView，macOS 菜单栏 ⌘N / ⌘K / ⌘, 与 ⌘Enter 发送）
- 工具能力增强（从 4 个扩展到 iOS 13 / macOS 24 个，跨平台 6 + macOS 独有 11 + 快捷指令 3）
- 预设系统提示词（11 个预设角色：默认助手 / 开发者 / 学生 / 白领 / 管理者 / 产品经理 / 写作助手 / 技术面试官 / 学习导师 / 翻译官 / 健身教练）

### macOS 体验修复

- 设置二级 / 三级页面导航修复 + 工具项中文化 + macOS Markdown 视觉层次 + macOS 语音朗读 UI 修复 + 18 个工具文件中文注释

### 工程质量强化

- **国际化基础设施**：String Catalog（`Localizable.xcstrings`，zh-Hans 源 + zh-Hant 繁体 + en 翻译，385 keys），`developmentRegion = zh-Hans`，SwiftUI 字面量自动提取
- **App 内语言切换**：`LanguageManager` + 设置页「语言」Section，支持跟随系统 / 简体中文 / 繁体中文 / 英文四选项，切换后写入 `AppleLanguages` 并提示重启
- **macOS 应用图标**：16/32/64/128/256/512 + @2x 全套 macOS iconset
- **无障碍支持**：13 个视图新增 `accessibilityLabel`/`accessibilityHint`/`accessibilityElement`，13 个关键交互元素新增 `accessibilityIdentifier`（UITest 可靠性提升）
- **潜在问题修复**：BGTaskScheduler 3 处 `as!` 强制向下转型改为 `guard let ... as?` 安全转型

### 系统级能力

- WatchConnectivity（iOS only）
- 远程配置与遥测（RemoteConfigService / TelemetryService）
- 崩溃监控（CrashReportService）
- 性能监控（PerformanceMonitor）
- 网络监听自动切换（NetworkMonitor / NWPathMonitor）
- 隐私清单与投诉反馈（PrivacyPolicyView / FeedbackService）

## 工具调用说明

工具通过 `ToolRegistry` 统一注册与调度，按平台条件编译：

- **iOS 13 个工具**：DateTimeTool / CalculatorTool / AlarmTool / ReminderTool / LocationTool / DeviceInfoTool / ClipboardTool / OpenURLTool / ContactsTool / WeatherTool / RunShortcutTool / ListShortcutsTool / CreateShortcutTool
- **macOS 24 个工具**：上述 13 个 + AppleScriptTool / ScreenshotTool / OCRTool / TerminalCommandTool / WindowManagementTool / AppManagementTool / FileOperationTool / FinderTool / SafariControlTool / SystemControlTool / InputAutomationTool（用 `#if os(macOS)` 守卫）
- **三类新增**：跨平台 6 / macOS 独有 11 / 快捷指令 3

## 技术栈

- SwiftUI（`@Observable` / `@Bindable` / `@FocusState` / NavigationSplitView）
- SwiftData（`@Model` / 自动迁移）
- DeepSeek API（chat completions SSE 流式 / embedding API / function calling tools）
- Qwen API（多 Provider）
- MLX（端侧推理，Llama-3.2-1B-Instruct Q4_K_M）
- AVAudioSession / SFSpeechRecognizer / AVSpeechSynthesizer
- EventKit（闹钟 / 提醒）
- PhotosUI / NSExpression
- ActivityKit（Live Activities 灵动岛）
- BGTaskScheduler
- UserNotifications
- CoreLocation / Contacts / Vision（OCR） / CoreGraphics
- NSAppleScript / NSWorkspace / Process（macOS 独有工具）
- HealthKit / WatchConnectivity（iOS only，`#if os(iOS)`）
- NetworkExtension（NWPathMonitor 网络监听）
- AppIntents（Shortcuts / Spotlight / Siri）
- XCTest（248 个单元测试，0 skip，覆盖 Service / Model / ViewModel / Core 全层）
- XCUITest（13 个 UI 测试，0 skip，覆盖 12 个端到端流 + 1 个 launch）
- GitHub Actions CI（macos-14 + iPhone 17，result bundle + upload-artifact）

## 环境要求

- Xcode 16+
- iOS Deployment Target 17.0+
- macOS Deployment Target 14+（作为目标平台）
- DeepSeek API Key（云端模式，https://platform.deepseek.com 申请）
- mlx-swift SPM 依赖（端侧推理可选）

## 文档导航

- [使用文档](doc/USAGE.md) — 环境、功能流程、FAQ
- [架构文档](doc/ARCHITECTURE.md) — 分层、模块、数据流
- [API 契约](doc/API.md) — LLMProvider / ToolProtocol / SSE
- [贡献指南](doc/CONTRIBUTING.md) — 规范、提交流程
- [变更日志](doc/CHANGELOG.md)
- [手测清单](doc/MANUAL_TEST_CHECKLIST.md)
- [发布清单](doc/ReleaseChecklist.md)
- [BFF 部署](doc/BFF_DEPLOYMENT.md)
- [路线图](doc/ROADMAP.md) — 后续任务方向
- [优化方案](doc/OPTIMIZATION.md) — 性能与体验优化
- [设计更新](doc/DESIGN_UPDATE.md) — UI/UX 演进计划

## 快速开始

1. clone 仓库
2. 用 Xcode 打开 `AIBuilder.xcodeproj`
3. iOS 运行：选 iPhone 17 模拟器 → `Cmd + R`
4. macOS 运行：选 My Mac 目标 → `Cmd + R`
5. 运行后进入设置填入 DeepSeek API Key

## 项目结构

```
AIBuilder/
├── App/                    # App 入口（AIBuilderApp.swift）
├── AppIntents/             # App Intents（AskAIBuilder / NewConversation / SwitchConversation）
├── Core/                   # 核心协议与常量
│   ├── Actors/             # ChatActor
│   ├── Constants/          # APIConfig / ModelProvider
│   ├── Extensions/         # String+TokenCount
│   ├── Models/             # BFFConfig / OnDeviceConfig / OnDeviceError
│   └── Protocols/          # ToolProtocol / LLMProvider
├── Models/                 # SwiftData 模型（Conversation / ChatMessage / DocumentChunk / MessageFeedback / HealthInsight / RemoteConfig / ChatChunk）
├── Resources/              # 资源
│   ├── Assets.xcassets/    # 图标与颜色（AppIcon 含 iOS + macOS 全套）
│   ├── Info.plist
│   ├── PrivacyInfo.xcprivacy
│   └── Localizable.xcstrings  # String Catalog（zh-Hans 源 + en 翻译）
├── Services/               # 服务层
│   ├── Auth/               # KeychainManager
│   ├── Cache/              # SemanticCache
│   ├── Connectivity/       # WatchConnectivityService
│   ├── Crash/              # CrashReportService
│   ├── Feedback/           # FeedbackService
│   ├── Health/             # HealthKitService / HealthInsightGenerator
│   ├── Intents/            # IntentChatService
│   ├── LLM/                # DeepSeekClient / QwenClient / BFFProxyClient / SSEParser / SmartRouter / FallbackLLMProvider / ModelProviderFactory / RateLimiter
│   ├── Network/            # NetworkMonitor
│   ├── OnDevice/           # MLXInferenceEngine / OfflineLLMProvider / OnDeviceModelDownloader
│   ├── Performance/        # PerformanceMonitor
│   ├── RAG/                # DocumentChunker / EmbeddingService / PDFExtractor / RAGService
│   ├── RemoteConfig/       # RemoteConfigService
│   ├── Routing/            # SmartRouter
│   ├── Search/             # SpotlightIndexer
│   ├── Storage/            # ChatStorage
│   ├── Telemetry/          # TelemetryService / LogUploader
│   ├── Tools/              # ToolRegistry + 21 个工具文件（iOS 13 / macOS 24 个工具）
│   └── Voice/              # VoiceService / TTSConfig / TTSVoiceCatalog
├── ViewModels/             # MVVM ViewModel（ChatViewModel / ConversationListVM / KnowledgeBaseVM / SettingsViewModel）
├── Views/                  # SwiftUI 视图（含 accessibilityLabel/Hint/Identifier 无障碍支持）
│   ├── Chat/               # ChatView / MessageBubble / MarkdownText / CodeBlockView / MarkdownTableView / TaskListView / HeadingView / StepCardView / FeedbackBar / CitationCard / TypingIndicator / ErrorOverlay / ChatInputBar / MessageListView / CodeSyntaxHighlighter / MarkdownTableParser
│   ├── Components/         # ErrorBanner / SkeletonView
│   ├── Conversation/       # ConversationList / ConversationRow
│   ├── OnDevice/           # OnDeviceModelView
│   ├── RAG/                # DocumentPickerView / KnowledgeBaseView
│   └── Settings/           # SettingsView / TTSVoicePickerView / PresetPrompts / HealthSettingsView / PrivacyPolicyView
AIBuilderTests/             # 单元测试（69 个文件，248 用例，0 skip）
AIBuilderUITests/           # UI 测试（2 个文件，13 用例，0 skip）
doc/                        # 文档（ARCHITECTURE.md / USAGE.md / MANUAL_TEST_CHECKLIST.md / ReleaseChecklist.md / BFF_DEPLOYMENT.md / CONTRIBUTING.md / CHANGELOG.md / API.md / plans / 实战计划）
screenshots/                # 截图目录（含 README 占位，待补充实际截图）
.github/workflows/ci.yml    # CI 配置
```

## 测试说明

```bash
# 全量测试（UT + UIT）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

# 仅 UT（248 用例，0 skip）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AIBuilderTests \
  CODE_SIGNING_ALLOWED=NO

# 仅 UIT（13 用例，0 skip）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AIBuilderUITests \
  CODE_SIGNING_ALLOWED=NO
```

测试覆盖（按层分类）：

- **Service 层 UT**：DeepSeekClient / SSEParser / SemanticCache / DocumentChunker / EmbeddingService / RAGService / PDFExtractor / ChatStorage / KeychainManager / ToolRegistry + 21 个工具测试 / VoiceService / TTSVoiceCatalog / TTSConfig / BFFProxyClient / FallbackLLMProvider / ModelProvider / RateLimiter / SmartRouter / NetworkMonitor / OfflineLLMProvider / OnDeviceConfig / HealthKitService / HealthInsightGenerator / IntentChatService / SpotlightIndexer / CrashReportService / FeedbackService / LogUploader / PerformanceMonitor / RemoteConfigService / TelemetryService / WatchConnectivityService / NotificationService / PresetPrompts
- **Model 层 UT**：ChatMessage / ConversationModel / StringTokenCount / APIConfig / MessageFeedback
- **ViewModel 层 UT**：ChatViewModel / ConversationListVM / KnowledgeBaseVM / SettingsViewModel
- **UIT**（2 文件，12 个端到端流 + 1 个 launch）：启动 / 会话列表 / 创建会话 / API Key 保存删除 / RAG+Tools Toggle / 模型切换 / 系统提示词 / 用户偏好 / contextMenu / 搜索 / 错误条

## CI 说明

GitHub Actions 配置在 `.github/workflows/ci.yml`：

- **触发**：push 到 `main` + `pull_request`
- **runner**：macos-14
- **步骤**：checkout → `xcodebuild build` → `xcodebuild test -resultBundlePath TestResults.xcresult` → `upload-artifact@v4`（if: always() 确保失败也上传）
- **destination**：iPhone 17

## 已完成里程碑

- Day 1-11：基础能力（流式对话 / RAG / 工具调用 / 语音 / 多模态 / 灵动岛 / 后台任务）
- Day 12-20：扩展能力（Markdown / TTS 音色 / SmartRouter / 多 Provider / BFF / MLX / HealthKit / App Intents）
- 多平台适配（iOS / iPad / macOS 三端原生）
- 工具能力增强（iOS 13 / macOS 24 个工具）
- 预设系统提示词（11 个预设角色）
- macOS 体验修复（导航 / 中文化 / Markdown 视觉 / 语音朗读 UI / 中文注释）
- 工程质量强化（国际化基础设施 / macOS 应用图标 / 无障碍支持 / 潜在问题修复）

## 详细文档

- [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) — 架构总览（分层架构图 / 模块职责 / 数据流 / 关键设计决策 / 技术栈映射 / 测试架构 / 31 项核心能力）
- [doc/USAGE.md](doc/USAGE.md) — 使用指南（环境要求 / 快速开始 / 21 项核心功能使用流程 / 多平台支持 / 工具能力清单 / 开发工作流 / CI / 权限 / FAQ）
- [doc/MANUAL_TEST_CHECKLIST.md](doc/MANUAL_TEST_CHECKLIST.md) — 手动测试清单（多平台适配 / 工具能力增强 / macOS 体验 等手测模块）
- [doc/ReleaseChecklist.md](doc/ReleaseChecklist.md) — 发布审核清单（多平台构建验证 / 工具数量审计 / 测试规模）
- [doc/BFF_DEPLOYMENT.md](doc/BFF_DEPLOYMENT.md) — BFF 代理层部署指南（Cloudflare Workers 配置）
- [doc/CONTRIBUTING.md](doc/CONTRIBUTING.md) — 贡献指南（开发环境 / 代码规范 / 提交规范 / PR 流程 / spec 驱动开发）
- [doc/CHANGELOG.md](doc/CHANGELOG.md) — 变更日志（Day 1-20 全部里程碑按 Keep a Changelog 格式记录）
- [doc/API.md](doc/API.md) — API 契约文档（LLMProvider / ToolProtocol 协议 / ToolDefinition JSON Schema / SSE 格式 / 三种 endpoint 请求示例）

## License

MIT
