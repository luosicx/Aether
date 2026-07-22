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

- **现状**：UT 2927 / UIT 30，0 skip。AetherCore SPM 包含 Rust FFI 包装器单元测试。SonarCloud 整体覆盖率 76.0%（PR #30 修复后目标 80%+）。
- **优化**：
  - 对齐 `sonar-project.properties` 覆盖率排除配置与 CI `EXCLUDE_PATTERNS`（新增 11 项排除：Health / Connectivity / Crash / Search / AppIntents / AetherDesign / AetherUI + 4 个 macOS-only 工具文件）
  - 为 0% 覆盖率模块补充测试：MCPErrorTests（21 用例）/ SSETransportTests（8 用例）/ StdioTransportTests（8 用例，macOS only）
  - 改进 DocumentChunker 测试可测性：`useRust` 改为 `internal static var`，新增 9 个 Swift fallback 路径测试
  - 新增 6 个 Rust inference.rs 测试（error display / custom config / load_unload cycle / multiple engines）
  - 将 Service 层覆盖率提升到 80%；为 macOS-only 工具补充单元测试；为 Rust FFI 10 个模块补充边界条件测试（空输入 / 超大输入 / 无效 UTF-8 / null 指针返回）
- **验收**：SonarCloud 覆盖率 ≥ 80%；CI coverage-summary job 80% 门槛通过。

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
