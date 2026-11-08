# Aether（以太）

<!-- doc-stats: i18n=888 tools=29 tests=3502 -->
<!-- doc-stats-total: iOS/macOS 3502 + Windows 72 + Android 95 = 3669 -->

> 一个跨平台 AI 对话助手，覆盖 iOS / iPad / macOS / Windows / Android 五端，采用**液态玻璃 + 深空主题**视觉语言。基于多 LLM Provider（DeepSeek / Qwen / BFF 代理 / 端侧 MLX），覆盖流式对话、RAG 知识库、ReAct 工具调用、语义缓存、端侧离线推理、语音合成与识别、健康洞察、灵动岛 Live Activity、Watch App、桌面 Widget、DeepLink 等能力。底层引入 Rust 核心引擎（aether-core-ffi，xcframework / DLL / JNI 多形态分发），为 Apple / Windows / Android 平台提供统一的跨平台高性能算法（SHA-256 哈希、Token 计数、文档分块、向量相似度、SSE 解析、WASM 沙箱、Candle 推理、令牌桶限流、敏感信息脱敏）。支持 8 种语言（简中 / 繁中 / 英 / 日 / 韩 / 法 / 德 / 西）。

## 项目愿景

**v1.5 已完成跨平台扩展交付**：在 v1.0 核心能力（MCP / 长期记忆 / Agent / AetherSDK）基础上，v1.1 完成智能体增强（MCP Server 反向暴露 / Agent 多步协作 / 插件市场 MVP / 动态星空背景），v1.2 完成设计升级（AnimationTokens / AetherIcons / 响应式布局），v1.3 落地端侧多模态 Phase 1（协议抽象 + 占位实现 + 4 个多模态工具 + 跨平台 OCR），v1.4 替换为 Apple 原生引擎（NativeVisionEngine 基于 Vision / NativeASREngine 基于 SFSpeech / NativeTTSEngine 基于 AVSpeechSynthesizer），三端开箱即用无需外部模型，v1.5 完成跨平台扩展（Windows 端 WPF .NET 8 + Android 端 Kotlin Jetpack Compose 双端交付，Rust 核心通过 DLL FFI 与 JNI 双通道复用），覆盖 iOS / iPad / macOS / Windows / Android 五端。详见 [变更日志](doc/CHANGELOG.md)。

**远期演进方向（v1.6~v3.0+）**：规划端侧多模态 Phase 2（MLX-VLM / Whisper.cpp / MLX-Voice / SD Mobile）、跨端协作（iCloud / Handoff / visionOS / Web 伴侣）、插件生态（社区市场 / 多 Agent 协作）、智能平台（Apple Intelligence / 本地 RAG / AI Workflow）五大方向，详见 [`doc/MASTER_PLAN.md`](doc/MASTER_PLAN.md)（含 Mermaid 架构图与里程碑规划）。

## 截图

| iOS 主对话 | iOS 设置 | iOS 知识库 | iOS 健康洞察 |
|---|---|---|---|
| ![iOS Chat](screenshots/ios_chat_main.png) | ![iOS Settings](screenshots/ios_settings.png) | ![iOS Knowledge Base](screenshots/ios_knowledge_base.png) | ![iOS Health](screenshots/ios_health_insight.png) |

| iOS 端侧模型 | iOS 预设提示词 | macOS 对话 | macOS 设置 |
|---|---|---|---|
| ![iOS On-Device](screenshots/ios_ondevice_model.png) | ![iOS Presets](screenshots/ios_preset_prompts.png) | ![macOS Chat](screenshots/macos_chat.png) | ![macOS Settings](screenshots/macos_settings.png) |

## 功能特性

- **流式对话**：基于 SSE 打字机效果，支持 DeepSeek / Qwen / BFF 代理 / 端侧 MLX 四种 Provider，逐 chunk 实时输出。
- **ReAct 工具调用**：18 个跨平台工具（含 v1.3 新增 4 个多模态工具：`describe_image` / `transcribe_audio` / `clone_voice` / `generate_image`）+ 11 个 macOS 独有工具，基于 function calling 循环执行，最大 5 轮，单工具超时 15s 不中断。
- **RAG 知识库**：本地文档导入（PDF / 文本）→ 分块 → 嵌入 → 余弦相似度 topK 检索 → `[1][2]` 编号注入 prompt。
- **语义缓存**：基于 embedding 余弦相似度（阈值 0.92）匹配历史 query，命中跳过 LLM 请求，减少重复调用。
- **端侧推理**：MLX 离线模式，设备本地运行 Llama-3.2-1B-Instruct Q4_K_M 量化模型，断网自动切换。
- **语音合成与识别**：SFSpeechRecognizer 实时语音输入，AVSpeechSynthesizer 朗读 AI 回复，TTS 音色可调节。
- **端侧多模态**（v1.4）：基于 Apple 原生 Vision / Speech / AVSpeechSynthesizer 实现图像理解（分类 / 人脸 / 矩形 / 文字 / 条码 5 并发请求）、文件级语音识别、PCM/WAV 语音合成，三端开箱即用无需外部模型；通过 `MultimodalFacade` 统一调度，支持 MLX-VLM / Whisper.cpp / MLX-Voice 后续替换。
- **健康洞察**（iOS）：HealthKit 读取步数 / 心率 / 睡眠，生成中文洞察文本并持久化。
- **灵动岛 Live Activity**（iOS）：ActivityKit 状态机「思考中 → 回复中 → 完成」。
- **SmartRouter 智能模型路由**：基于规则与历史成功率在多 Provider 间动态路由，失败自动 Fallback。
- **Watch App**（iOS 配对）：watchOS 独立 App，TabView 三标签（快速对话 / 健康洞察 / 设置），通过 WatchConnectivity 与主 App 双向同步。⚠️ 需在 Xcode 中手动创建 Watch target。
- **桌面 Widget**：三个 Widget（QuickChat 快捷提问 / HealthInsight 健康洞察 / RecentConversations 最近会话），通过 App Group 共享 SwiftData。⚠️ 需在 Xcode 中手动创建 Widget target。
- **DeepLink 支持**：`aether://ask?query=` 快捷提问、`aether://conversation/<uuid>` 跳转指定会话。
- **多语言支持**：8 种语言（zh-Hans / zh-Hant / en / ja / ko / fr / de / es），App 内切换并提示重启。
- **无障碍**：VoiceOver 标签与提示、Dynamic Type 适配、accessibilityIdentifier 覆盖关键交互控件。
- **深色模式默认 + 液态玻璃 UI**：深空黑基底 + 神秘紫强调 + 电光蓝交互 + 液态玻璃卡片，深色模式开箱即用。
- **跨平台扩展（v1.5）**：
  - **Windows 端（WPF .NET 8）**：会话列表（加载 / 创建 / 删除 / 置顶 / 搜索）、设置页（BFF BaseUrl / Token / 模型 / 主题色 / 语言）、Markdown 渲染（Markdig 0.37.0 → WPF FlowDocument，支持标题 / 代码块 / 表格 / 任务列表 / 引用 / 链接）、8 种语言运行时切换无需重启、BFF 配置 DPAPI 加密存储（`%LOCALAPPDATA%/Aether/bff_config.json`）、SSE 流式聊天 + TypingIndicator、Rust FFI 通过 `aether_core_ffi.dll` P/Invoke。
  - **Android 端（Kotlin + Jetpack Compose）**：RAG 知识库 UI（搜索 + 结果列表）、Health UI（日期选择 + 步数 / 睡眠 / 心率 + 上传）、Room 数据库生产使用（`@Database version=1`，ConversationEntity + MessageEntity，先 Room 后网络模式）、消息长按菜单（复制 / 重发 / 删除）、Markdown 渲染（Markwon 4.6.2 + Compose AndroidView + AetherThemePlugin 自定义主题）、8 种语言 Activity.recreate() 切换、Rust JNI 集成（SseBridge / VectorMath / Redact，含 *Safe 回退）。

## 技术栈

**Apple 端（iOS / iPad / macOS）**：

- **SwiftUI**（`@Observable` / `@Bindable` / `@FocusState` / NavigationSplitView）
- **SwiftData**（`@Model` 宏自动生成 schema 与迁移，7 个持久化实体）
- **Rust**（aether-core-ffi，C ABI 绑定，xcframework 三架构分发，cbindgen 生成头文件）
- **MLX**（端侧推理，Llama-3.2-1B-Instruct Q4_K_M 量化）
- **Candle**（Rust 跨平台推理引擎，safetensors 模型，macOS）
- **wasmtime**（Rust WASM 运行时，Pulley 解释器，无 JIT，macOS）
- **AVFoundation**（AVAudioSession / AVSpeechSynthesizer 语音输入输出）
- **BackgroundTasks**（BGTaskScheduler 后台刷新，iOS）
- **ActivityKit**（Live Activities 灵动岛，iOS）

其他 Apple 依赖：EventKit / PhotosUI / PDFKit / NLTokenizer / Keychain / CoreSpotlight / AppIntents / NetworkExtension / HealthKit / WatchConnectivity / Vision / NSAppleScript / NSWorkspace / Process。

**Windows 端**：

- **WPF .NET 8**（MVVM 数据绑定，自包含 win-x64 发布，无需目标机安装运行时）
- **Markdig 0.37.0**（Markdown 解析，自定义渲染器输出 WPF FlowDocument）
- **DPAPI**（`ProtectedData.Protect` CurrentUser 范围加密 UserToken）
- **Rust FFI**（通过 `aether_core_ffi.dll` P/Invoke 调用 Rust 核心，AetherNativeBridge.cs 桥接层）

**Android 端**：

- **Kotlin + Jetpack Compose**（Material 3，MVVM + ViewModel + StateFlow）
- **Markwon 4.6.2**（Markdown 渲染，Compose AndroidView 嵌入，AetherThemePlugin 自定义主题）
- **Room**（`@Database version=1`，ConversationEntity + MessageEntity，先 Room 后网络模式）
- **Rust JNI**（SseBridge / VectorMath / Redact 三个 Kotlin 桥接类，含 *Safe 回退路径）

## 快速开始

### Apple 端（iOS / iPad / macOS）

1. clone 仓库
2. 用 Xcode 16+ 打开 `Aether.xcodeproj`
3. **Rust 依赖**（可选，xcframework 已预编译）：
   ```bash
   rustup target add aarch64-apple-ios aarch64-apple-ios-simulator aarch64-apple-darwin
   cd rust/aether-core-ffi && cargo build --release
   ```
4. iOS 运行：选 iPhone 17 模拟器 → `Cmd + R`
5. macOS 运行：选 My Mac 目标 → `Cmd + R`
6. 运行后进入设置填入 DeepSeek API Key（https://platform.deepseek.com 申请）

### Windows 端

详见 [`doc/WINDOWS_BUILD.md`](doc/WINDOWS_BUILD.md)。简要步骤：

1. 安装 .NET 8 SDK 与 Visual Studio 2022（含 .NET 桌面开发工作负载）
2. 进入 `windows/` 目录：`dotnet restore`
3. 构建：`dotnet build -c Release`
4. 运行：`dotnet run --project Aether.Windows -c Release`
5. 启动后在设置页填入 BFF BaseUrl 与 UserToken（或直接填入 DeepSeek API Key）

### Android 端

详见 [`doc/ANDROID_BUILD.md`](doc/ANDROID_BUILD.md)。简要步骤：

1. 安装 Android Studio（Hedgehog 或更新版本）与 JDK 17
2. 用 Android Studio 打开 `android/` 目录，等待 Gradle 同步完成
3. 连接 Android 设备（API 29+，开启 USB 调试）或启动模拟器
4. 点击 Run 按钮，或命令行：`./gradlew :app:installDebug`
5. 启动后在设置页填入 BFF BaseUrl 与 UserToken（或直接填入 DeepSeek API Key）

## 项目结构

项目采用 MVVM + Service 分层架构，详见 [架构文档](doc/ARCHITECTURE.md)。简要结构：

```
Aether.xcodeproj/           # Xcode 工程文件
rust/
├── aether-core/             # 纯 Rust 算法 crate（sha2 / unicode-segmentation / tokenizers / candle / wasmtime / regex）
└── aether-core-ffi/         # C ABI 绑定层 + cbindgen.toml（产出 xcframework / aether_core_ffi.dll / libaether_core_ffi.so）
Packages/
└── AetherCore/              # SPM 模块化包
    ├── Sources/
    │   ├── AetherFoundation/  # 核心协议与常量（LLMProvider / ToolProtocol / APIConfig）
    │   ├── AetherRust/        # Rust FFI Swift 包装器（10 个文件）
    │   ├── AetherServices/    # 服务层（LLM / RAG / Cache / Plugin / Telemetry 等）
    │   ├── AetherDesign/      # 设计系统 Token（颜色 / 字体 / 圆角 / 布局）
    │   └── AetherUI/          # 通用 UI 组件（AvatarView / CardStyle / ErrorBanner 等）
    ├── Tests/AetherCoreTests/
    └── aether_core.xcframework/  # Rust 三架构静态库
Aether/                     # 主 App（iOS / iPad / macOS）
├── App/                    # App 入口（AetherApp.swift，含 DeepLink 处理）
├── AppIntents/             # App Intents（AskAether / NewConversation / SwitchConversation）
├── Core/                   # 核心协议与常量（LLMProvider / ToolProtocol / APIConfig）
├── DesignSystem/           # 设计系统 Token（颜色 / 字体 / 间距 / 圆角 / 动画）
├── Models/                 # SwiftData @Model（Conversation / ChatMessage / DocumentChunk 等 7 实体）
├── Resources/              # 资源（Assets / Info.plist / Localizable.xcstrings 8 语言 / PrivacyInfo）
├── Services/               # 服务层（19 子模块：LLM / RAG / Tools / Cache / Voice / OnDevice / Health 等）
├── ViewModels/             # MVVM ViewModel（ChatViewModel / ConversationListVM / KnowledgeBaseVM / SettingsViewModel）
└── Views/                  # SwiftUI 视图（Chat / Components / Conversation / OnDevice / RAG / Settings）
AetherWatch/                # watchOS App（TabView：快速对话 / 健康洞察 / 设置）
AetherWidgets/              # Widget Extension（QuickChat / HealthInsight / RecentConversations）
windows/                    # Windows 端（WPF .NET 8，13 个 .cs 文件 + 72 测试用例）
├── Aether.Windows/         # 主项目（MVVM：ViewModels / Views / Services / Native / Design / Converters）
│   ├── Native/             # Rust FFI 桥接（AetherNativeBridge.cs，P/Invoke aether_core_ffi.dll）
│   ├── Services/           # BffConfigStore（DPAPI 加密）/ MarkdownRenderer（Markdig）/ LanguageService（8 .resx）
│   └── ViewModels/         # ChatViewModel / ConversationListViewModel / SettingsViewModel
├── Aether.Windows.Tests/   # 单元测试（xUnit，72 用例）
└── README.md               # Windows 构建说明
android/                    # Android 端（Kotlin + Jetpack Compose，22 个 .kt 文件 + 95 测试用例）
├── app/src/main/java/com/aether/
│   ├── rust/               # Rust JNI 桥接（SseBridge / VectorMath / Redact，含 *Safe 回退）
│   ├── data/               # data 层（db / repository / api / model）
│   │   ├── db/             # Room 数据库（AetherDatabase.kt，@Database version=1）
│   │   └── api/            # BFF 网关（BffConfigStore / ChatStreamClient / AetherApi）
│   ├── ui/                 # UI 层（chat / conversation / rag / health / settings / theme / navigation）
│   └── app/                # MainActivity.kt 入口
└── app/src/test/           # 单元测试（JUnit / MockK，95 用例）
CloudflareWorkers/          # BFF 代理层（worker.js + wrangler.toml）
AetherTests/                # 单元测试（iOS / macOS，199 文件 / 3502 用例，覆盖 Multimodal / Tools / Services 全模块）
AetherUITests/              # UI 测试（7 文件 / 30 用例）
```

## 文档导航

| 文档 | 用途 |
|------|------|
| [架构文档](doc/ARCHITECTURE.md) | 分层架构图、模块职责、数据流、关键设计决策、技术栈映射、测试架构 |
| [使用文档](doc/USAGE.md) | 环境要求、功能流程、FAQ |
| [API 契约](doc/API.md) | LLMProvider / ToolProtocol 协议、ToolDefinition JSON Schema、SSE 格式 |
| [贡献指南](doc/CONTRIBUTING.md) | 开发环境、代码规范、提交规范、PR 流程 |
| [变更日志](doc/CHANGELOG.md) | Day 1–20 全部里程碑记录 |
| [路线图](doc/ROADMAP.md) | 后续任务方向 |
| [优化方案](doc/OPTIMIZATION.md) | 性能与体验优化 |
| [样式指南](doc/Style%20Guide.md) | 液态玻璃 + 深空主题设计规范 |
| [手测清单](doc/MANUAL_TEST_CHECKLIST.md) | 多平台适配、工具能力等手测模块 |
| [发布清单](doc/ReleaseChecklist.md) | 多平台构建验证、工具数量审计 |
| [BFF 部署](doc/BFF_DEPLOYMENT.md) | Cloudflare Workers 代理层部署指南 |
| [DMG 打包](doc/DMG_PACKAGING.md) | macOS .dmg 打包与公证流程 |
| [Windows 构建](doc/WINDOWS_BUILD.md) | Windows 端 .NET 8 / WPF 开发环境、构建命令、打包流程 |
| [Android 构建](doc/ANDROID_BUILD.md) | Android 端 Kotlin / Jetpack Compose 开发环境、Gradle 构建、调试说明 |
| [架构图](doc/diagrams/README.md) | PlantUML 架构图渲染说明 |

## 路线图摘要

> 完整路线图与里程碑详见 [`doc/ROADMAP.md`](doc/ROADMAP.md)，远期演进方向详见 [`doc/MASTER_PLAN.md`](doc/MASTER_PLAN.md)。

| 版本 | 预计时间 | 关键交付 |
|------|----------|----------|
| v1.1 | 2026-07-24 已发布 | 智能体增强完善（MCP 生态共建 + Agent 多步协作 + 插件市场 MVP + 动态星空背景） |
| v1.2 | 2026-07-25 已发布 | 设计升级（AnimationTokens + AetherIcons + 响应式布局 + 动态星空呼吸效果） |
| v1.3 | 2026-07-25 已发布 | 端侧多模态 Phase 1（协议抽象 + 4 个多模态工具 + 跨平台 OCR + 占位引擎） |
| v1.4 | 2026-07-25 已发布 | 端侧多模态 Phase 1.5（Apple 原生引擎：NativeVision / NativeASR / NativeTTS 替换占位实现） |
| v1.5 | 2026-07-26 已发布 | 跨平台扩展（Windows 端 WPF .NET 8 + Android 端 Kotlin Jetpack Compose 双端交付，Rust 核心通过 DLL FFI 与 JNI 复用） |
| v1.6 | 2027 Q3 | 端侧多模态 Phase 2（MLX-VLM + Whisper.cpp + MLX-Voice + SD Mobile 图像生成） |
| v2.0 | 2027 Q4 | 跨端协作（iCloud 同步 + Handoff + visionOS + Web 伴侣） |
| v2.5 | 2028 Q1 | 生态扩展（社区插件市场 + 多 Agent 协作 + Android 深化） |
| v3.0 | 2028 Q2 | 智能平台（Apple Intelligence + 本地 RAG 增强 + AI Workflow） |
| v3.0+ | 2028 H2 | 远期探索（隐私计算 + 实时协作 + 多模态记忆） |

## 环境要求

**Apple 端**：

- Xcode 16+
- iOS Deployment Target 17.0+
- macOS Deployment Target 14+
- watchOS Deployment Target 10+（Watch App 可选）
- DeepSeek API Key（云端模式）
- mlx-swift SPM 依赖（端侧推理可选）
- Rust 1.75+（构建 aether-core-ffi xcframework 需要，可选）
- App Group `group.com.aether.app`（Widget 共享 SwiftData 可选）

**Windows 端**：

- .NET 8 SDK
- Visual Studio 2022（含 .NET 桌面开发工作负载）或 VS Code + C# Dev Kit
- Windows 10 / 11 x64
- Rust 1.75+（构建 `aether_core_ffi.dll` 需要，可选，预编译 DLL 已包含）

**Android 端**：

- Android Studio Hedgehog（或更新版本）
- JDK 17
- Android SDK API 29+（minSdk 29）
- Kotlin 1.9+
- Rust 1.75+ with `aarch64-linux-android` / `armv7-linux-androideabi` / `x86_64-linux-android` / `i686-linux-android` targets（构建 `libaether_core_ffi.so` 需要，可选，预编译 .so 已包含）

> **Watch App 与 Widget 注意事项**：源代码已就绪（`AetherWatch/` 与 `AetherWidgets/`），但需在 Xcode 中手动创建对应的 target 并关联源文件、配置 App Group 与 Capabilities。详见 [贡献指南](doc/CONTRIBUTING.md) 中的 Watch / Widget 开发指南。

## License

MIT
