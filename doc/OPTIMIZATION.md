# Aether 优化方案

> 汇总当前已识别或可预见的性能、体验与工程质量优化点，按优先级与可落地性排序。

---

## 1. 性能优化

### 1.1 启动耗时

- **现状**：App 启动时需预热语音引擎、注册 BGTask、拉取远程配置。
- **优化**：将远程配置拉取从 `init()` 移到首屏出现后；BGTask 注册改为首次进入后台时懒注册。
- **验收**：冷启动到可交互 < 1.5s（iPhone 17 模拟器）。

### 1.2 列表滚动

- **现状**：ConversationList 与 MessageList 在长列表下可能因 SwiftUI body 重算掉帧。
- **优化**：引入 `NSCache` 缓存已渲染的 Markdown 解析结果；对会话行使用 `.id` 稳定化。
- **验收**：100 条会话 / 100 条消息滑动 60fps。

### 1.3 端侧模型加载

- **现状**：MLX 模型首次加载阻塞主线程。
- **优化**：模型加载放到后台 `Task`；使用 `TaskGroup` 预加载 tokenizer。macOS 端已引入 Candle（Rust）推理引擎作为 MLX 的跨平台替代方案，safetensors 模型加载性能优于 MLX。
- **验收**：切换端侧推理时 UI 不卡死。

### 1.4 Rust FFI 跨平台性能

- **现状**：Rust `aether-core-ffi` 通过 xcframework 提供 Sha256 / Token / Chunker / Vector / SSE / RateLimiter / Redactor 等核心算法，已替代 Swift 侧重复实现（CryptoKit / NLTokenizer / String.estimatedTokens 等），性能提升 2-10x。
- **优化**：将 Inference（Candle）和 Sandbox（wasmtime）扩展至 iOS 端（当前仅 macOS，受限于 iOS 上 JIT 限制，wasmtime 已用 Pulley 解释器绕过）；持续对比 Rust vs Swift 实现性能，确保 xcframework 在所有平台保持最优。
- **验收**：Sha256 4MB chunk 模式下内存占用 < 10MB；Token 计数与 OpenAI tokenizer 误差 < 5%；Chunker 分块速度是 NLTokenizer 的 2x 以上。

### 1.5 TTS 音色目录主线程阻塞

- **现状**：`AVSpeechSynthesisVoice.speechVoices()` 在主线程调用时可能阻塞 50-100ms（首次访问触发 `speechsynthesisd` 进程启动）。
- **优化**：`TTSVoiceCatalog` 使用 `static cachedVoices` / `static cachedGrouped` 静态缓存，首次访问在后台线程预热，后续直接返回缓存；`VoiceService` 使用实例级 `cachedVoice` / `cachedVoiceIdentifier` 避免每次朗读时重复解析音色。
- **验收**：设置页 TTS 音色选择器打开时无卡顿；连续朗读多条消息无延迟累积。

### 1.5 远程配置延迟拉取

- **现状**：`RemoteConfigService` 在 `init()` 中立即拉取远程配置。
- **优化**：将 `fetch()` 调用从 `init()` 移到首屏 `.task` modifier 出现后执行，避免冷启动时网络请求阻塞。
- **验收**：冷启动时无网络请求发出（首屏渲染后才开始拉取）。

### 1.6 主题持久化同步

- **现状**：主题切换后仅在内存生效，重启后丢失。
- **优化**：Theme 从 SwiftData `UserPreference` @Model 同步，切换主题后立即持久化到 SwiftData 并在下次启动时恢复。
- **验收**：切换主题后 kill 进程重启，主题保持一致。

### 1.7 跨平台文件选择器

- **现状**：`DocumentPickerView` 使用 UIKit `UIDocumentPickerViewController`，macOS 不可用。
- **优化**：替换为 SwiftUI `.fileImporter`，跨平台兼容 iOS / iPad / macOS。
- **验收**：iOS 与 macOS 均可导入 PDF / 文本文件到知识库。

### 1.8 跨平台性能优化（v1.5 已交付）

> v1.5.0 完成 Windows（WPF .NET 8）与 Android（Kotlin + Jetpack Compose）平台扩展，以下为各端性能优化要点。

#### Windows 端（WPF .NET 8）

- **MarkdownRenderer**：Markdig pipeline 单例复用（`MarkdownPipelineBuilder` 只构建一次并缓存到静态字段），避免每条消息重新构建解析管线；FlowDocument 解析结果按消息 ID 缓存到 `Dictionary<string, FlowDocument>`，列表滚动或会话切换时命中缓存直接复用，不重复触发 Markdig 解析。
- **BffConfigStore**：DPAPI 加密（`ProtectedData.Protect` CurrentUser scope）仅在 `Save()` 写盘路径执行一次，运行时读取配置直接返回内存缓存（`_cachedConfig`），不再触发解密；配置变更通过 `INotifyPropertyChanged` 通知 UI 绑定更新。
- **LanguageService**：单例模式（`Lazy<LanguageService>`），8 种 `.resx` 资源在首次访问时一次性加载到 `Dictionary<string, string>` 内存字典，运行时切换语言直接替换内存字典引用，无需重新读取资源文件、无需重启进程。
- **ChatViewModel**：SSE 流式响应按 `\n\n` 增量切分，仅对新增 token 通过 `Dispatcher.Invoke` 异步更新 UI，避免每帧全量重绘 FlowDocument；TypingIndicator 独立线程心跳驱动，不阻塞 SSE 接收线程。

#### Android 端（Kotlin + Jetpack Compose）

- **Room 数据库**：采用「先本地后网络」模式，会话 / 消息列表优先从 Room 读取并立即渲染，再异步请求 BFF 同步增量数据，减少主线程网络等待；`ConversationEntity` 在 `isPinned` + `updatedAt` 上建立复合索引，置顶会话排序走索引扫描而非全表排序。
- **Markwon**：Markwon 实例通过 `remember { Markwon.create(context) }` 在 Compose 顶层缓存，避免每次 `AndroidView` 重组时重新创建（Markwon 实例化含主题插件加载，开销较大）；`AetherThemePlugin` 作为单例挂载到 Application 作用域，所有 Composable 共用同一实例。
- **Rust JNI**：4 个 native 函数（`parseWithTools` / `reset` / `cosineF64` / `redact`）均提供 `*Safe` Kotlin 回退实现，native 路径仅在真机使用（模拟器走回退避免 `UnsatisfiedLinkError` 导致 crash），native 调用统一用 `runCatching` 包裹，失败时自动降级到 `*Safe` 实现。
- **ChatViewModel**：消息列表使用 `StateFlow<List<Message>>`，增量 `emit` 仅追加新消息而非全量替换列表引用，Compose `LazyColumn` 配合 `key { it.id }` 仅重组新增 item，避免长会话场景下全量重组。

## 2. 体验优化

### 2.1 错误提示

- **现状**：网络/API 错误以顶部 ErrorBanner 展示，部分场景提示不够具体。
- **优化**：按错误类型给出可操作建议（如「去设置配置 API Key」「检查网络后重试」）。
- **验收**：UT 覆盖每种错误类型的 userMessage。

### 2.2 空状态与加载

- **现状**：部分页面空状态较简单。
- **优化**：统一 EmptyState 组件，增加插画与引导操作。
- **验收**：ConversationList、KnowledgeBase、OnDeviceModel 空状态一致。

### 2.3 macOS 快捷键

- **现状**：已支持 ⌘N / ⌘K / ⌘, / ⌘Enter。
- **优化**：增加 ⌘T 新建会话、⌘Shift+F 聚焦搜索、Esc 关闭设置 sheet。
- **验收**：快捷键在 macOS 菜单栏可见并可触发。

## 3. 工程质量优化

### 3.1 测试覆盖率

- **现状**：UT 3359 / UIT 30，0 skip。AetherCore SPM 包含 Rust FFI 包装器单元测试。SonarCloud 整体覆盖率 v1.0 已达 **83.79%**（PR #30 修复后由 76.0% 提升，超过原 80% 目标）。
- **优化**：
  - 对齐 `sonar-project.properties` 覆盖率排除配置与 CI `EXCLUDE_PATTERNS`（新增 11 项排除：Health / Connectivity / Crash / Search / AppIntents / AetherDesign / AetherUI + 4 个 macOS-only 工具文件）
  - 为 0% 覆盖率模块补充测试：MCPErrorTests（21 用例）/ SSETransportTests（8 用例）/ StdioTransportTests（8 用例，macOS only）
  - 改进 DocumentChunker 测试可测性：`useRust` 改为 `internal static var`，新增 9 个 Swift fallback 路径测试
  - 新增 6 个 Rust inference.rs 测试（error display / custom config / load_unload cycle / multiple engines）
  - 将 Service 层覆盖率提升到 80%；为 macOS-only 工具补充单元测试；为 Rust FFI 10 个模块补充边界条件测试（空输入 / 超大输入 / 无效 UTF-8 / null 指针返回）
- **验收**：
  - **v1.0（已达成）**：SonarCloud 覆盖率 ≥ 80%（实际 83.79%）
  - **v1.1 目标**：覆盖率 ≥ **85%**（补全 MCP / Agent / Plugin 模块测试）
  - **v2.0 目标**：覆盖率 ≥ **90%**（覆盖跨端同步 / visionOS / 多 Agent 协作等远期方向）

### 3.2 静态检查

- **现状**：已 0 warnings。SonarCloud 0 vulnerabilities / 0 bugs（PR #30 修复 5 个 S1523 安全漏洞 + 9 个 Leak Period CODE_SMELL）。
- **优化**：
  - 修复 5 个 S1523 NSAppleScript 动态执行安全漏洞（NOSONAR 注释移到同一行）
  - 修复 9 个 Leak Period CODE_SMELL：S1186 / S1172 / S116 / S1075 / S3087 / S107
  - 引入 SwiftLint / SwiftFormat；将 `SWIFT_STRICT_CONCURRENCY=complete` 纳入 CI
- **验收**：CI 中 static analysis 0 warnings；SonarCloud 0 vulnerabilities / 0 bugs / Leak Period 0 issues。

### 3.3 文档自动化

- **现状**：文档靠人工同步。
- **优化**：在 CI 中运行脚本提取 i18n key 数、工具数、测试数，检查与 README/ARCHITECTURE 是否一致。
- **验收**：文档数字漂移时 CI 失败。

### 3.4 CI 性能优化（v1.5 跨平台）

- **现状**：v1.5 新增 Windows / Android CI 流水线（`windows-build` job on `windows-latest` runner / `android-build` job on `ubuntu-latest` runner），首次构建未充分缓存导致耗时偏高（windows-build 2m58s / android-build 2m40s）。
- **优化（Windows）**：
  - **.NET NuGet 包缓存**：使用 `actions/cache@v4` 缓存 `~/.nuget/packages`，key 含 `windows/**/packages.lock.json` 与 `*.csproj` hash，命中后 `dotnet restore` 走本地缓存，跳过 nuget.org 拉取。
  - **Rust DLL 构建缓存**：使用 `swatinem/rust-cache@v2` 缓存 `rust/aether-core-ffi/target`，避免每次重新编译 `aether_core_ffi.dll`（Release 构建约 90s → 缓存命中后 10s）。
- **优化（Android）**：
  - **Gradle 缓存**：使用 `actions/cache@v4` 缓存 `~/.gradle/caches` 与 `.gradle` 目录，key 含 `gradle-wrapper.properties` + `*.gradle.kts` hash，命中后跳过依赖下载。
  - **NDK 缓存**：单独缓存 `~/Android/Sdk/ndk` 目录（NDK 下载约 600MB，缓存后跳过下载与解压）。
  - **Rust `.so` 构建缓存**：使用 `swatinem/rust-cache@v2` 按 target（`aarch64-linux-android` / `x86_64-linux-android`）分别缓存 `rust/aether-core-ffi/target`，避免重新交叉编译 `libaether_core_ffi.so`（双架构 Release 构建约 120s → 缓存命中后 15s）。
- **验收**：`windows-build` job 耗时由 2m58s → ≤ 1m30s（缓存命中）；`android-build` job 耗时由 2m40s → ≤ 1m20s（缓存命中）。

---

## 4. 远期优化方向

> 以下章节面向 v1.6~v3.0+ 远期演进（详见 `doc/MASTER_PLAN.md`），描述各方向的优化目标与技术路径。
> **v1.3 / v1.4 已落地**：4.1 端侧多模态性能优化的「内存预算器」与「互斥使用」已实施，详见下方说明。

### 4.1 端侧多模态性能优化方向

- **内存预算器**（v1.3 已实施）：`MemoryBudget`（`public actor`，`Aether/Services/Multimodal/MemoryBudget.swift`）协调 VLM / Whisper / SD 三类大模型同时加载时的内存使用，按 `DeviceCapability` 分级配置总预算（iPhone 1.5-3GB / iPad 3GB / Mac 6GB），通过 `reserve(mb:)` / `release(mb:)` 跟踪已用 / 剩余 / 峰值，超预算时抛 `MultimodalError.memoryBudgetExceeded`。
- **推理加速**（v1.6 规划）：基于 Metal Performance Shaders 与 CoreML 量化推理路径加速 MLX-VLM / Whisper.cpp / MLX-Voice 推理，对比 MLX 默认实现实测目标提升 ≥ 30%。v1.4 已使用 Apple 原生 Vision / Speech / AVSpeech 框架，零外部模型加载，原生路径已具备低延迟优势。
- **模型量化**（v1.6 规划）：将端侧 MLX-VLM / Whisper.cpp / MLX-Voice / SD Mobile 模型统一量化到 Q4（INT4）或 Q8（INT8），在精度可接受范围内将内存占用压缩到原模型的 25% / 50%。
- **互斥使用**（v1.3 已实施）：VLM / Whisper / Stable Diffusion 三个重型模型不可同时加载到内存，通过 `MultimodalFacade` 强制串行调度，避免 OOM 导致系统终止。v1.4 Native 引擎无需加载模型，`isLoaded` 始终为 `true`，进一步降低互斥成本。

### 4.2 跨设备同步效率优化方向

- **增量同步**：基于 `NSPersistentCloudKitContainer` 的增量同步，仅同步变更的字段与对象，避免全量拉取与重复写盘，目标同步数据量降低 ≥ 70%。
- **冲突解决**：默认 LWW（Last-Write-Wins）+ 字段级合并策略，对关键字段（如 `Conversation.title` / `ChatMessage.content`）提供自定义合并回调，避免多端并发编辑时数据丢失。
- **带宽控制**：仅在 Wi-Fi 网络下载大文件（如端侧模型、文档附件），蜂窝网络仅同步文本；同步传输启用 gzip 压缩，目标带宽占用降低 ≥ 50%。
- **后台调度**：通过 `BGTaskScheduler` 注册云端同步后台任务（`com.aether.cloud-sync`），按电量与网络条件自适应调度，低电量 / 蜂窝网络下延后同步。

### 4.3 插件沙箱开销优化方向

- **wasmtime 预编译（AOT）**：将 WASM 插件模块在首次加载时通过 wasmtime 的 `cranelift` AOT 编译为本地机器码缓存到磁盘，后续加载直接映射，目标冷启动耗时降低 ≥ 60%。
- **冷启动优化**：维护 WASM 实例池（按插件 manifest 缓存 1-3 个预热实例），首次调用直接复用预热线程，避免每次调用重新实例化带来的 ~80ms 延迟。
- **内存隔离**：按插件粒度限制单插件最大内存（默认 256MB）与 CPU fuel（默认 100k instructions），通过 wasmtime `Store` 配置 `resource_limit` 强制约束，防止恶意插件耗尽系统资源。

### 4.4 visionOS 渲染性能优化方向

- **RealityView 优化**：对 3D 对话场景中的模型应用 LOD（Level of Detail）分级与视锥剔除（Frustum Culling），仅渲染视口内可见的高精度模型，远距离与背向模型降级为低精度或剔除。
- **帧率保障**：默认目标 60fps，当设备负载过高时启用自适应分辨率（Dynamic Resolution Scaling），渲染分辨率从 1.0x 自适应降至 0.7x，保障 60fps 不掉帧；最低保持 30fps 流畅度下限。
- **内存预算**：visionOS App 内存预算限制为 16GB（Apple Vision Pro 总内存 16GB，需为系统与其他 App 预留空间），通过 `MemoryBudgeter` 监控 RealityView 场景与模型资产总占用，超预算时按优先级卸载未使用的场景资产。
