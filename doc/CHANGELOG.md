# 变更日志

本项目所有用户可见的变化均记录于此文档。格式参考 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)。

---

## [Unreleased]

首个正式版本 1.0.0 已发布，后续变更将记录于此。

---

## [1.0.0] - 2026-07-15

### 多平台首发版本

Aether v1.0.0 首次以多平台形式发布，覆盖 iOS / macOS / Android / Windows / Cloudflare Workers (BFF) 五端：

- **iOS（iOS 17+）**：SwiftUI 原生 App，含完整对话 / RAG / 工具调用 / 健康洞察 / 端侧 MLX 推理 / Apple Intents / Widget / Watch App。GitHub Release 提供 iOS Simulator 包（unsigned，用于模拟器调试），App Store 分发通过 TestFlight。
- **macOS（macOS 14+）**：与 iOS 共享 SwiftUI / SwiftData 代码，含菜单栏 / 多窗口 / macOS 独有 11 个工具（AppleScript / Terminal / OCR / Screenshot 等）。GitHub Release 提供 unsigned `.dmg`。
- **Android（API 29+）**：Kotlin + Jetpack Compose 客户端，复用 BFF 网关，本地 Room 持久化。GitHub Release 提供 release APK（debug 签名，可直接安装）。
- **Windows（.NET 8 + WPF）**：C# 桌面客户端，复用 BFF 网关。GitHub Release 提供 win-x64 自包含压缩包（无需目标机安装 .NET）。
- **Cloudflare Workers BFF**：跨平台业务网关，统一鉴权 / 限流 / 路由 / RAG 检索。GitHub Release 提供 BFF 源码包。

### 平台产物清单

| 产物 | 平台 | 文件名 | 说明 |
| --- | --- | --- | --- |
| iOS Simulator App | iOS 17+ | `Aether-iOS-1.0.0-simulator.zip` | 无签名 simulator 包，仅供模拟器调试 |
| macOS DMG | macOS 14+ | `Aether-macOS-1.0.0[-unsigned].dmg` | 签名模式由 CI secrets 自动判断（4 个 secrets 齐全时签名+公证，否则 unsigned），未签名版本需手动允许运行 |
| Android APK | Android API 29+ | `Aether-Android-1.0.0.apk` | Release 构建配置 + debug 签名 |
| Windows Zip | Windows 10/11 x64 | `Aether-Windows-1.0.0-x64.zip` | .NET 8 自包含，无需运行时依赖 |
| BFF 源码包 | Cloudflare Workers | `Aether-BFF-1.0.0.zip` | `wrangler deploy` 部署 |
| 源码归档 | 通用 | `Aether-1.0.0-source.tar.gz` / `.zip` | 标签指向的完整源码 |

### 版本号

- iOS / macOS：`CFBundleShortVersionString = 1.0.0`，`CFBundleVersion = 100`
- Android：`versionName = "1.0.0"`，`versionCode = 100`
- Windows：`Version = 1.0.0`，`AssemblyVersion / FileVersion = 1.0.0.0`
- BFF（package.json）：`1.0.0`

### Added
- **多语言扩展至 8 种语言**：`Localizable.xcstrings` 从 3 种语言（zh-Hans / zh-Hant / en）扩展至 8 种（新增 ja 日语 / ko 韩语 / fr 法语 / de 德语 / es 西班牙语），i18n keys 覆盖全部核心 UI 文案
- **Watch App 源代码**：新增 `AetherWatch/` 目录，包含 `WatchApp.swift`（TabView 三标签：快速对话 / 健康洞察 / 设置）、`WatchQuickChatView.swift`（快捷对话发送）、`WatchHealthInsightView.swift`（健康洞察浏览）；通过 `WatchConnectivityService` 与 iOS 主 App 双向同步（transferUserInfo 推送健康洞察）。⚠️ Watch target 需在 Xcode 中手动创建并关联源文件
- **Widget Extension 源代码**：新增 `AetherWidgets/` 目录，包含三个 Widget：`QuickChatWidget`（桌面快捷提问，点击直达对话）、`HealthInsightWidget`（健康洞察摘要展示）、`RecentConversationsWidget`（最近会话列表快捷入口）；使用 `TimelineProvider` + `AppIntentConfiguration`。⚠️ Widget target 需在 Xcode 中手动创建并关联源文件
- **App Group 共享 SwiftData**：新增 App Group 配置（`group.com.aether.app`），主 App 与 Widget Extension 通过共享 `ModelContainer` 读取同一 SwiftData 数据库，Widget 可直接展示最近会话与健康洞察
- **DeepLink 支持**：新增 `aether://` URL Scheme，支持两种 DeepLink：`aether://ask?query=<编码文本>`（快捷提问，打开主界面并自动发送）与 `aether://conversation/<uuid>`（跳转到指定会话）；在 `AetherApp.swift` 中通过 `.onOpenURL` 处理
- **端侧 MLX 推理（条件编译）**：`mlx-swift` 需手动通过 Xcode → File → Add Package Dependencies 添加（`project.pbxproj` 未内置 SPM 包引用），未集成时 `MLXInferenceEngine` 走 `#if canImport(MLXLLM)` 占位实现（抛 `loadFailed` / 返回提示流）；集成后调用真实 `ModelContainer.load` 加载模型并 token 级流式输出；`OnDeviceModelDownloader` 从 HuggingFace CDN 下载 Llama-3.2-1B-Instruct Q4_K_M 量化模型并 SHA256 校验
- **无障碍增强**：Watch App 与 LaunchScreen 补充 `accessibilityLabel`；新增 `accessibilityIdentifier` 覆盖全部关键交互控件（sendButton / messageInputField / voiceInputButton 等 12+ 标识符），VoiceOver 与 UITest 可靠性提升
- **国际化基础设施**：新增 `Localizable.xcstrings` String Catalog（zh-Hans 源语言 + zh-Hant 繁体中文 + en 英文翻译，55 个核心 key）；`developmentRegion` 更新为 `zh-Hans`，`knownRegions` 新增 `zh-Hans`/`zh-Hant`/`en`；SwiftUI `Text`/`Button`/`TextField`/`accessibilityLabel` 字面量由 Xcode 自动提取
- **App 内语言切换**：新增 `LanguageManager`（ObservableObject）与设置页「语言」Section，支持跟随系统 / 简体中文 / 繁体中文 / 英文 / 日语 / 韩语 / 法语 / 德语 / 西班牙语 九选项，切换后写入 `AppleLanguages` UserDefaults 并提示重启 App 生效
- **macOS 应用图标**：基于 1024x1024 源图，通过 `sips` 生成 16/32/64/128/256/512 + @2x 全套 macOS 图标，`AppIcon.appiconset/Contents.json` 新增 10 个 `idiom: "mac"` 条目
- **截图目录**：新增 `screenshots/` 目录与 `README.md` 占位（含截图清单、截图方法、注意事项）
- CONTRIBUTING.md / CHANGELOG.md / API.md 三份开发者文档
- ARCHITECTURE.md 与 BFF_DEPLOYMENT.md 架构图全部 Mermaid 化
- USAGE.md 新增 macOS 系统集成与性能监控章节
- MANUAL_TEST_CHECKLIST.md 手测项四字段结构化（前置条件 / 操作步骤 / 预期结果 / 失败排查）
- ReleaseChecklist.md 新增 4.4-4.7 审计项（多平台构建 / 工具数 / 测试规模 / 文档完整性）
- **完整国际化补全**：`Localizable.xcstrings` 从 55 核心 key 扩展至 888 keys，覆盖 Views / ViewModels / Services / AppIntents / Core；新增 `scripts/` 提取/翻译/合并工具链
- **无障碍全面增强**：7 个核心视图新增约 75 个 `accessibilityLabel` / `accessibilityHint` / `accessibilityIdentifier`
- **项目截图**：`screenshots/` 新增 8 张 iOS / macOS 核心页面截图
- **后续规划文档**：新增 `doc/ROADMAP.md`、`doc/OPTIMIZATION.md`
- **工程质量工具链**：`.swiftlint.yml` 配置完成，启用 `force_unwrapping` / `force_cast` / `force_try` / `implicitly_unwrapped_optional` / `empty_count` / `empty_string` / `explicit_init` 等 opt-in 规则；`.swiftformat` 配置完成（Swift 5.9 / 4 空格缩进）；新增 `scripts/run_swiftlint.sh` CI 集成脚本（未安装时跳过不报错，有 error 时退出码 1 阻断合并）；全量代码格式修复

### Changed
- **Aether 品牌重塑**：AIBuilder → Aether（以太），确立液态玻璃（Liquid Glass）+ 深空（Deep Space）主题设计语言。新增色彩体系（AetherPurple / ElectricBlue / NebulaGlow / Starlight / LiquidGlass / DeepSpace 色板）、字体体系（TypographyTokens）、设计令牌（DesignTokens / ColorTokens）；App 入口 `AIBuilderApp` → `AetherApp`，AppIntent `AskAIBuilderIntent` → `AskAetherIntent`，UITests → `AetherUITests`；新增 `BrandSplash` 开屏品牌动画与 `DesignSystem/` 目录
- **性能优化**：BGTask 调度从 `init()` 延迟到首次进入后台触发（懒调度），减少冷启动耗时；远程配置拉取从 `init()` 移到首屏 `.task` 出现后执行；`CodeBlockView` 语法高亮结果通过 NSCache 缓存，避免重复解析；`ConversationList` `.id` 稳定化，避免列表刷新时全量重建；MLX 模型加载通过 `Task.detached` 在后台线程执行，不阻塞 actor 与 UI 线程；`TTSVoiceCatalog` 静态缓存 `speechVoices()` 结果避免主线程阻塞；`VoiceService` 使用实例级 `cachedVoice` / `cachedVoiceIdentifier` 避免重复音色解析
- **体验优化**：API Key 空值预检——发起对话前检测 Key 是否为空，为空时直接展示 `ErrorBanner` 提示「请先在设置中配置 API Key」而不发起无效网络请求；`ErrorBanner` 组件支持可选「重试」与「前往设置」按钮，便于用户快速恢复；`EmptyStateView` 统一空态展示（会话列表 / 知识库 / 端侧模型管理等场景复用）；macOS 新增 ⌘Shift+F 快捷键聚焦搜索输入框
- **主题持久化同步**：Theme 从 SwiftData 同步，切换主题后立即持久化并在下次启动恢复

### Fixed
- **设置 UI 6 项 Bug 修复**：
  1. macOS 设置页显示异常（`regularLayout` detail 包 `NavigationStack` 修复二级页返回按钮）
  2. API Key 保存失败（Keychain account 按 provider 隔离，保存策略先 Delete 再 Add 幂等）
  3. 主题切换不生效（ThemeManager 环境崩溃修复 + SwiftData 持久化同步）
  4. 头像选择器无法打开（`PhotosPicker` 替代 `fileImporter` 跨平台兼容）
  5. 对话气泡样式切换无响应（`@Binding` 传递修复 + UI 即时刷新）
  6. 字体与间距设置不生效（DesignTokens 绑定修复 + `@AppStorage` 持久化）
- **设备调试 entitlements 修复**：补充 `get-task-allow` 与 `keychain-access-groups` entitlements，解决真机调试时 Keychain 写入失败与断点不生效问题
- **启动性能优化**：`speechVoices()` 调用移到后台线程避免阻塞主线程；`RemoteConfig` 延迟到首屏 `.task` 后拉取；移除启动时 `createConversation` 调用避免 body 重算打断 TextField 焦点
- **键盘关闭手势**：新增下拉手势与点击空白区域关闭键盘（`@FocusState` 管理 + `UIScrollView` intercept 触摸），解决聊天界面键盘无法关闭问题
- **BGTaskScheduler 强制向下转型崩溃风险修复**：`AetherApp.swift` 中 3 处 `task as! BGAppRefreshTask` 改为 `guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }`，任务类型不匹配时安全退出而非崩溃
- **UT/UIT 全部 0 skip**：修复 `testUserPreferencePersistence` 根因（`UserPreference` @Model 未注册到 App `ModelContainer` schema）；修复 7 处 `XCTSkip`
- **Swift 6 并发警告**：修复 `VoiceService` / `ChatViewModel` / `ConversationListVM` / `ClipboardTool` / `OpenURLTool` / `LocationTool` / `SSEParser` 等 7 类警告
- **macOS AppIcon 警告**：清理 3 个未分配子图标

### Removed
- **文档清理**：删除 `doc/DESIGN_UPDATE.md`（内容已被 `Style Guide.md` 完全覆盖）；清空 `doc/plans/` 目录（7 个已完成的过期计划文档：Day 1 / Day 2 / 设计系统优化 / 灵枢品牌系统 / i18n 打磨 / 文档更新 / SonarCloud 配置指南）
- **清理**：移除 9 个根目录一次性临时脚本（pbxproj 注册 / 路径修复等 Ruby 脚本）与 `.wolf/buglog.json.tmp` 临时文件；清理代码与文档中残留的「灵枢」/「LingShu」品牌 KEY，统一为 Aether（以太）

（详见 spec：[finalize-docs-release](../.trae/specs/finalize-docs-release/spec.md)）

---

## [Day 1-11 基础能力] - 2026-07-06 ~ 2026-07-08

### Added
- **Day 1 流式对话**：基于 OpenAI 兼容 chat completions SSE 流式接口，逐 chunk yield 文本，前端实时打字效果展示。（[spec](../.trae/specs/day1-streaming-chat/spec.md)）
- **Day 2 多轮记忆**：SwiftData 持久化 Conversation + ChatMessage，会话级消息历史注入 LLM 上下文，支持 system prompt 自定义。（[spec](../.trae/specs/day2-conversation-memory/spec.md)）
- **Day 3 RAG 检索增强**：本地知识库（PDF/文本）→ DocumentChunker 分块 → EmbeddingService 嵌入 → 余弦相似度 topK=5 检索 → 拼 [1][2] 编号 prompt 注入。（[spec](../.trae/specs/day3-rag-knowledge-base/spec.md)）
- **Day 4 ReAct 工具调用**：基于 function calling，ToolRegistry 注册 4 个工具（AlarmTool / ReminderTool / DateTimeTool / CalculatorTool），最大循环 5 轮，单工具超时 15s 不中断循环。（[spec](../.trae/specs/day4-tool-calling-react/spec.md)）
- **Day 5 语音输入输出**：AVAudioSession + SFSpeechRecognizer 实时语音识别写入输入框，AVSpeechSynthesizer 朗读 AI 回复。（[spec](../.trae/specs/day5-voice-input-output/spec.md)）
- **Day 6 语义缓存**：基于 embedding 余弦相似度（阈值 0.92）匹配历史 query，命中跳过 LLM 请求；FIFO 容量 100。（[spec](../.trae/specs/day6-semantic-cache/spec.md)）
- **Day 7 设置与骨架屏**：SettingsView 含 API Key 管理 / 模型切换 / 系统提示词 / 用户偏好 / RAG+Tools Toggle / 调试面板；SkeletonView 骨架屏。（[spec](../.trae/specs/day7-polish-settings-skeleton/spec.md)）
- **Day 8 ReAct 增强**：StepCardView 展示思维链 thought/action/observation 三段；ReAct 循环可视化。（[spec](../.trae/specs/day8-react-enhancement/spec.md)）
- **Day 9 会话管理**：会话列表 / 置顶 / 删除 / 重命名 / contextMenu 操作；Spotlight 索引。（[spec](../.trae/specs/day9-conversation-management/spec.md)）
- **Day 10 性能与体验优化**：Token 估算与滑动窗口截断；PerformanceMonitor 关键耗时记录。（[spec](../.trae/specs/day10-polish-performance/spec.md)）
- **Day 11 工具与测试扩展**：扩展测试覆盖；工具稳定性增强。（[spec](../.trae/specs/day11-extend-tools-testing/spec.md)）
- **测试体系扩展**：新增 ~14 个单元测试文件覆盖核心 Service / Model / ViewModel（DeepSeekClient / RAGService / DocumentChunker / EmbeddingService / PDFExtractor / SemanticCache / KeychainManager / ChatStorage / ToolRegistry / ChatViewModel / ConversationListVM 等）；新建 AIBuilderUITests target 覆盖 12 个端到端流；App 支持 `UITEST_DISABLE_NETWORK` 启动参数注入桩回复；CI 上传 result bundle artifact。（[spec](../.trae/specs/add-comprehensive-ut-uit/spec.md)）
- **Day 1-11 缺失补充**：补全 Live Activities 灵动岛 / BGTaskScheduler 后台任务 / 本地通知 / 视觉多模态 / 用户偏好记忆 / 调试面板。（[spec](../.trae/specs/supplement-day1-11-missing/spec.md)）

### Fixed
- Day 1-3 输入响应延迟深度修复（[spec](../.trae/specs/fix-day1-3-input-lag-deep/spec.md)）
- Day 4 输入延迟修复（[spec](../.trae/specs/fix-day4-input-lag/spec.md)）
- 输入框无法弹出根因修复：ErrorBanner 的 VStack + Spacer() 占满 overlay 拦截触摸事件，重构布局移除 Spacer 并改 `.overlay(alignment: .top)`（[spec](../.trae/specs/fix-input-not-responding/spec.md)）
- 点击输入框链路根因修复：onAppear 的 Task 在 33ms 后触发 body 重算打断 TextField first responder；改为不在启动时 createConversation，ChatInputBar 加 @FocusState 管理焦点，ChatStorage.createConversation 延迟 save（[spec](../.trae/specs/fix-input-link-block/spec.md)）
- 点击输入框键盘不弹起深度排查修复：URLSession.shared 首次访问主线程阻塞、MessageListView onChange 高频 scrollTo、SwiftData 同步 fetch/save 等主线程阻塞点全面异步化（[spec](../.trae/specs/fix-input-keyboard-not-show/spec.md)）
- Day 5 语音崩溃与音频格式问题修复（[spec](../.trae/specs/fix-day5-voice-crash-audio-format/spec.md)）
- 启动主线程阻塞修复（[spec](../.trae/specs/fix-startup-mainthread-block/spec.md)）
- 手势超时与 Keychain 问题修复（[spec](../.trae/specs/fix-gesture-timeout-keychain/spec.md)）
- 工具调用 HTTP 400 修复：带 tool_calls 的 assistant 消息 content 为空字符串时被 DeepSeek API 拒绝，序列化层改为条件编码跳过空 content（[spec](../.trae/specs/fix-tools-400-error/spec.md)）

---

## [Day 12-20 扩展能力] - 2026-07-08 ~ 2026-07-09

### Added
- **Day 12 智能路由与反馈**：SmartRouter 基于规则与历史成功率在多 Provider 间路由；FallbackLLMProvider 自动降级；MessageFeedback @Model + FeedbackBar 用户反馈。（[spec](../.trae/specs/day12-smart-routing-feedback/spec.md)）
- **Day 13 Qwen 多 Provider**：ModelProvider enum 抽象 DeepSeek / Qwen / 端侧三类；ModelProviderFactory 工厂；RateLimiter 客户端令牌桶限流。（[spec](../.trae/specs/day13-qwen-multi-provider/spec.md)）
- **Day 14 远程配置与遥测**：RemoteConfigService 拉取远程开关；TelemetryService 收集使用指标；CrashReportService 崩溃监控；LogUploader 日志上传。（[spec](../.trae/specs/day14-remote-config-telemetry/spec.md)）
- **Day 15 BFF 代理层**：BFFProxyClient 走 Cloudflare Workers 网关中转；设备端仅持 userToken；BFFConfig 持久化。（[spec](../.trae/specs/day15-bff-proxy-layer/spec.md)）
- **Day 16 MLX 端侧推理**：MLXInferenceEngine 本地运行 Llama-3.2-1B Q4_K_M；OnDeviceModelDownloader 下载 + SHA256 校验；NetworkMonitor 断网自动切换。（[spec](../.trae/specs/day16-on-device-mlx/spec.md)）
- **Day 17 watchOS 扩展**：WatchConnectivityService 双向通信；AIBuilderWatch watchOS App 同步 Quick Chat 与健康洞察。（[spec](../.trae/specs/day17-watchos-extension/spec.md)）
- **Day 18 App Intents 系统集成**：AskAIBuilderIntent / NewConversationIntent / SwitchConversationIntent 三 Intent；Shortcuts / Spotlight / Siri 集成；HealthKitService 健康洞察。（[spec](../.trae/specs/day18-app-intents-system-integration/spec.md)）
- **Day 19 深度打磨与无障碍**：Markdown 渲染（代码块 / 表格 / 任务列表 / 标题分级）；TTS 音色可调节（TTSConfig / TTSVoiceCatalog / TTSVoicePickerView）；消息复制与重新提问；批量多选删除会话。（[spec](../.trae/specs/day19-deep-polish-accessibility/spec.md)）
- **Markdown 渲染与反馈交互**：新增 MarkdownText 组件分段渲染代码块与普通文本；CodeBlockView 深色背景等宽字体；CodeSyntaxHighlighter 正则语法高亮支持 11 种语言；点赞点踩反馈接入 ChatViewModel feedbackStates。（[spec](../.trae/specs/markdown-rendering/spec.md)）
- **TTS 朗读音色可调节**：TTSConfig 持久化到 UserDefaults；TTSVoiceCatalog 按语言分组枚举可用音色；VoiceService.speak 接收 config 参数；SettingsView 新增语音朗读 Section（音色 Picker / 语速 / 音调 / 音量 Slider / 试听按钮）。（[spec](../.trae/specs/tts-voice-customization/spec.md)）
- **消息复制与重新提问**：MessageBubble contextMenu 提供复制与重新提问操作；ChatViewModel 新增 resendMessage 方法；CopyToast 提示。（[spec](../.trae/specs/copy-and-regenerate-message/spec.md)）
- **批量多选删除会话**：ConversationList 编辑模式多选；ConversationRow 选中状态；ConversationListVM 批量删除方法；全选 / 取消全选。（[spec](../.trae/specs/batch-delete-conversations/spec.md)）
- **Day 20 发布准备**：ReleaseChecklist 上架前检查；Manual Test Checklist 手测清单；PrivacyInfo.xcprivacy 隐私清单。（[spec](../.trae/specs/day20-release-preparation/spec.md)）

### Fixed
- Markdown 标题支持修复（[spec](../.trae/specs/markdown-heading-support/spec.md)）
- Markdown 表格扩展修复（[spec](../.trae/specs/markdown-table-extended/spec.md)）
- 启动自动选中最近会话与清理空对话修复：每次打开不再新增空对话，加载会话列表后自动选中最近一条；ChatStorage 新增 cleanupEmptyConversations。（[spec](../.trae/specs/fix-conversation-auto-create/spec.md)）
- 既有测试失败修复：ConversationListVM.load 增加 cleanupEmpty 参数避免测试预置数据被清理；IntentChatService.ask 消除 Keychain 回退反模式；新增 UITEST_RESET_DATA 启动参数支持 UITest 数据隔离。（[spec](../.trae/specs/fix-existing-test-failures/spec.md)）

---

## [多平台适配与工具增强] - 2026-07-09

### Added
- **多平台适配**：SwiftUI 原生渲染支持 iOS / iPad / macOS 三端；`#if os(iOS)` 条件编译隔离 iOS-only 框架；macOS 加入窗口默认尺寸 1000×700、菜单栏快捷键（⌘N / ⌘K / ⌘,）、⌘Enter 发送；UIKit 组件替换为 SwiftUI 跨平台组件。（[spec](../.trae/specs/adapt-multiplatform-ios-ipad-macos/spec.md)）
- **工具能力增强**：ToolRegistry 从 4 个工具扩展到 iOS 13 / macOS 24 个，新增 20 个工具分三类：跨平台 6 个（LocationTool / DeviceInfoTool / ClipboardTool / OpenURLTool / ContactsTool / WeatherTool）、macOS 独有 11 个（AppleScriptTool / ScreenshotTool / OCRTool / TerminalCommandTool / WindowManagementTool / AppManagementTool / FileOperationTool / FinderTool / SafariControlTool / SystemControlTool / InputAutomationTool）、快捷指令 3 个（RunShortcutTool / ListShortcutsTool / CreateShortcutTool）。（[spec](../.trae/specs/enhance-tool-capabilities/spec.md)）

---

## [预设提示词与 macOS 体验修复] - 2026-07-09

### Added
- **预设系统提示词**：PresetPrompts.swift 提供 11 个预设角色（默认助手 / 开发者 / 学生 / 白领 / 管理者 / 产品经理 / 写作助手 / 技术面试官 / 学习导师 / 翻译官 / 健身教练），每个含 ≥ 150 字完整 system prompt；SettingsView systemPromptSection 上方新增预设角色 Menu。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **18 个工具文件中文注释**：文件级 / 方法级 / 行内中文注释补充。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **核心代码注释补全**：为 Service / Model / ViewModel / Core 层核心类型补全 `///` 文档注释与关键方法注释，复杂分支补充行内注释说明「为什么」，不改任何可执行逻辑。（[spec](../.trae/specs/enhance-code-quality-comments/spec.md)）

### Fixed
- **macOS 设置导航修复**：regularLayout detail 栏外层包 NavigationStack，二级页（TTS / 隐私政策 / 端侧模型管理）有返回按钮。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **工具项中文化**：SettingsView preferenceSection Toggle 用中文 description 替代英文 name。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **macOS markdown 视觉层次**：MessageBubble.swift NSColor shim 的 systemGray3 / 5 / 6 改为不同灰阶。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **macOS 语音朗读 UI 修复**：MarkdownText 加 parseBlocks NSCache 缓存；VoiceService 加 @MainActor / didCancel 兜底清理 / voice nil 降级。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **macOS 设置关闭与音色卡死修复**：SettingsView 改用 @Binding isPresented；TTSVoiceCatalog 静态缓存；VoiceService voice 缓存；App 启动预热 speechsynthesisd。（[spec](../.trae/specs/fix-macos-settings-close-voice-freeze/spec.md)）

---

## [文档更新] - 2026-07-09

### Added
- **架构与使用文档生成**：新建 `doc/ARCHITECTURE.md`（分层架构图 / 模块职责 / 数据流 / 关键设计决策 / 技术栈映射 / 测试架构 / 目录结构）与 `doc/USAGE.md`（环境要求 / 快速开始 / 配置 API Key / 各功能使用流程 / 测试运行 / CI 说明 / 常见问题）；更新 README 修正过期信息并指向新文档。（[spec](../.trae/specs/generate-architecture-usage-docs/spec.md)）

### Changed
- **V1 文档同步**：ARCHITECTURE.md / USAGE.md / MANUAL_TEST_CHECKLIST.md / ReleaseChecklist.md 同步 Day 1-20 全部能力。（[spec](../.trae/specs/update-docs-to-latest/spec.md)）
- **V2 文档同步**：补充多平台适配与工具能力增强变更；新增 macOS 系统集成 / 工具能力清单章节；测试规模从 217 更新为 245。（[spec](../.trae/specs/update-docs-to-latest-v2/spec.md)）
- **V3 文档同步**：补充预设系统提示词 / macOS 体验修复 / 工具中文化 / 注释等变更；测试规模更新为 249 UT / 13 UIT。（[spec](../.trae/specs/polish-macos-ui-presets-comments-tests-git/spec.md)）
- **README 更新**：项目定位从「iOS App」更新为「多平台 App」；核心功能从 11 项扩展为 31 项；工具数从 4 更新为 iOS 13 / macOS 24；测试用例数从 113 增至 249 UT / 13 UIT。（[spec](../.trae/specs/update-readme-to-latest/spec.md)）
- **文档体系增强与架构图美化**：ARCHITECTURE.md 与 BFF_DEPLOYMENT.md 全部架构图替换为 Mermaid（flowchart / sequenceDiagram / classDiagram / stateDiagram-v2）；USAGE.md 顶部介绍同步多 Provider 并新增 macOS 系统集成与性能监控章节；MANUAL_TEST_CHECKLIST 手测项四字段结构化；ReleaseChecklist 新增 4.4-4.7 审计项；新建 CONTRIBUTING.md / CHANGELOG.md / API.md 三份开发者文档。（[spec](../.trae/specs/enhance-docs-architecture-diagrams/spec.md)）

---

## [Git 与 GitHub 初始化] - 2026-07-09

### Added
- GitHub 仓库初始化与代码上传：https://github.com/luosicx/AIBuilder
- `.gitignore` 排除 `.trae/` / `xcuserdata/` / `.DS_Store` / `*.rb` 等临时脚本与系统文件（[spec](../.trae/specs/cleanup-unused-files/spec.md)）
- GitHub Actions CI 配置（`.github/workflows/ci.yml`）：macos-14 + iPhone 17，build + test + upload-artifact

### Removed
- 清理 9 个根目录一次性 Ruby 脚本（pbxproj 注册 / 路径修复）与 `.wolf/buglog.json.tmp` 临时文件（[spec](../.trae/specs/cleanup-unused-files/spec.md)）
