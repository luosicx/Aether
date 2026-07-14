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
- **优化**：模型加载放到后台 `Task`；使用 `TaskGroup` 预加载 tokenizer。
- **验收**：切换端侧推理时 UI 不卡死。

### 1.4 TTS 音色目录主线程阻塞

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

- **现状**：UT 2092 / UIT 30，0 skip。
- **优化**：将 Service 层覆盖率提升到 80%；为 macOS-only 工具补充单元测试。
- **验收**：Codecov / Xcode Coverage 显示覆盖率 ≥ 80%。

### 3.2 静态检查

- **现状**：已 0 warnings。
- **优化**：引入 SwiftLint / SwiftFormat；将 `SWIFT_STRICT_CONCURRENCY=complete` 纳入 CI。
- **验收**：CI 中 static analysis 0 warnings。

### 3.3 文档自动化

- **现状**：文档靠人工同步。
- **优化**：在 CI 中运行脚本提取 i18n key 数、工具数、测试数，检查与 README/ARCHITECTURE 是否一致。
- **验收**：文档数字漂移时 CI 失败。
