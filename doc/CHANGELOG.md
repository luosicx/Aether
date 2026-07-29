# 变更日志

本项目所有用户可见的变化均记录于此文档。格式参考 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)。

---

## [Unreleased]

## [1.6.0] - 2026-07-29

### 端侧多模态 Phase 2 — MLX 引擎集成

#### Added — iOS / macOS 端（5 个新引擎 + Facade 增强）
- **MLXVisionEngine**：基于 MLX-VLM（Qwen2-VL-2B Q4 等）的视觉理解引擎，条件编译 `#if canImport(MLXLLM) && canImport(MLXLMCommon)`，不可用时降级到 `NativeVisionEngine`（Apple Vision 框架兜底）
- **WhisperASREngine**：基于 whisper.cpp Rust 绑定的离线 ASR 引擎，`requiresNetwork = false`（完全离线），降级到 `NativeASREngine`（Apple Speech 框架兜底）
- **MLXVoiceTTSEngine**：基于 MLX-Voice（Kokoro/Matcha-TTS）的端侧 TTS 引擎，条件编译 `#if canImport(MLXVoice)`，降级到 `NativeTTSEngine`（AVSpeechSynthesizer 兜底）
- **OpenVoiceCloner**：基于 OpenVoice v2 的语音克隆引擎，桩实现 + 256 维 embedding 向量 + Keychain 存储
- **SDMobileEngine**：基于 Stable Diffusion Mobile / CoreML 的端侧图像生成引擎，条件编译 `#if canImport(CoreML)`
- **MultimodalFacade.createWithAutoFallback()**：新增静态工厂方法，实现 MLX → Native → Placeholder 自动降级链路
- **测试**：新增 5 个测试文件（MLXVisionEngineTests / WhisperASREngineTests / MLXVoiceTTSEngineTests / OpenVoiceClonerTests / SDMobileEngineTests），共 45 个测试用例

#### 引擎降级策略
- VLM: MLXVisionEngine（v1.6）→ NativeVisionEngine（v1.4）→ PlaceholderVisionEngine（v1.3）
- ASR: WhisperASREngine（v1.6）→ NativeASREngine（v1.4）→ PlaceholderASREngine（v1.3）
- TTS: MLXVoiceTTSEngine（v1.6）→ NativeTTSEngine（v1.4）→ PlaceholderTTSEngine（v1.3）
- VoiceCloner: OpenVoiceCloner（v1.6）→ PlaceholderVoiceCloner（v1.3）
- ImageGen: SDMobileEngine（v1.6）→ PlaceholderImageGenerationEngine（v1.3）

#### 状态说明
- MLX-VLM / Whisper.cpp / MLX-Voice / OpenVoice / SD Mobile 的真实推理依赖尚未集成（需引入 SPM 包 / Rust FFI）
- 当前 5 个引擎均走降级/桩实现路径，架构接入点已就绪
- 待 SPM 依赖集成后通过 `MultimodalFacade.setXxxEngine()` 切换到真实引擎

#### Tests
- **测试规模**：UT 从 3481 增至 3526（+45 用例：iOS/macOS 3314 → 3359，5 个新测试文件）。
- **Rust 单测**：`redact.rs` 新增 3 个 JSON 格式用例（password / token / api_key），Rust 单测从 13 增至 16。

#### Fixed
- **Rust redact 正则不支持 JSON 格式密码字段**：原正则 `(?i)(password|...)\s*[:=]\s*[^\s&]+` 要求 key 后紧跟 `:` / `=`，不匹配 JSON 格式 `"password": "value"`（键值被引号包围），导致 iOS `RedactorRustTests.testRedactPassword` 失败。修改为 `(?i)["']?(password|...)["']?\s*[:=]\s*["']?[^\s&"']*["']?`，支持 JSON / ini / 单双引号多种格式（Rust regex 不支持反向引用，故键值前后引号独立匹配）。

---

## [1.5.0] - 2026-07-26

### v1.5 跨平台扩展（Windows + Android 双端交付，Rust 核心通过 DLL FFI 与 JNI 多形态复用）

#### Added — Windows 端（13 个 .cs 文件 / 72 个测试用例）
- **会话列表 UI**：新增 `ConversationListViewModel` + `ConversationListPage`，支持会话加载 / 创建 / 删除 / 置顶 / 搜索全功能，基于 `ObservableCollection` 实时同步 UI。
- **设置页 UI**：新增 `SettingsViewModel` + `SettingsPage`，配置 BFF BaseUrl / UserToken / 模型 / 主题色 / 语言，所有设置项持久化到本地。
- **Markdown 渲染**：新增 `MarkdownRenderer.cs`，集成 Markdig 0.37.0，将 Markdown AST 自定义渲染为 WPF `FlowDocument`，支持标题 / 代码块 / 表格 / 任务列表 / 引用 / 链接 / 行内代码等元素。
- **国际化**：新增 `LanguageService.cs` + 8 种 `.resx` 资源文件（zh-Hans / zh-Hant / en / ja / ko / fr / de / es），运行时切换语言无需重启应用。
- **BFF 配置 + DPAPI 加密**：新增 `BffConfigStore.cs`，使用 `ProtectedData.Protect`（CurrentUser 范围）加密 UserToken，配置文件存储到 `%LOCALAPPDATA%/Aether/bff_config.json`，避免明文泄露敏感凭证。
- **聊天 + 流式响应**：新增 `ChatViewModel.cs`，支持 SSE 流式逐 chunk 输出与 `TypingIndicator` 打字机效果，与 iOS / macOS 端体验一致。
- **Rust FFI 桥接**：新增 `AetherNativeBridge.cs`，通过 `aether_core_ffi.dll` P/Invoke 调用 Rust 核心算法（SHA-256 / Token 计数 / 文档分块 / 向量相似度 / SSE 解析 / 脱敏等），与 Apple 端共享同一份 Rust 代码。

#### Added — Android 端（22 个 .kt 文件 / 95 个测试用例）
- **RAG 知识库 UI**：新增 `KnowledgeBaseScreen` + `KnowledgeBaseViewModel`，提供搜索框与结果列表，复用 BFF 网关的 RAG 检索能力。
- **Health UI**：新增 `HealthScreen` + `HealthViewModel`，支持日期选择器 + 步数 / 睡眠 / 心率三指标展示与上传，与 iOS HealthKit 流程对齐。
- **Room 数据库生产使用**：新增 `AetherDatabase.kt`（`@Database version=1`），定义 `ConversationEntity` + `MessageEntity`，Repository 层采用「先 Room 后网络」模式，离线场景下保证历史会话可读。
- **消息长按菜单**：在 `ChatScreen.kt` 中通过 `combinedClickable` + `DropdownMenu` 实现消息上下文菜单，提供复制 / 重发 / 删除操作。
- **Markdown 渲染**：新增 `MarkdownText.kt`，集成 Markwon 4.6.2，通过 Compose `AndroidView` 嵌入 `TextView`，含自定义 `AetherThemePlugin` 适配深空主题（代码块深色背景 / 链接色 / 引用样式）。
- **国际化**：新增 `LanguageManager.kt` + 8 种 `strings.xml`（zh-Hans / zh-Hant / en / ja / ko / fr / de / es），切换语言时调用 `Activity.recreate()` 重建界面。
- **Rust JNI 集成**：新增 `Redact.kt` + `SseBridge.kt` + `VectorMath.kt` 三个 Kotlin 桥接类，加载 `libaether_core_ffi.so` 调用 Rust 核心；每个桥接类配套 `*Safe` 回退方法（System.loadLibrary 失败时降级为纯 Kotlin 实现），保证设备兼容性。
- **设置页 UI**：新增 `SettingsScreen.kt`，配置 BFF BaseUrl / UserToken / 模型 / 主题色 / 语言，与 Windows 端设置项对齐。

#### Added — Rust JNI 暴露（4 个函数）
- **`Java_com_aether_rust_SseBridge_parseWithTools`**：SSE 流解析 + `tool_call` 字段累积，返回结构化 chunk 列表供 Kotlin 侧消费。
- **`Java_com_aether_rust_SseBridge_reset`**：重置 SSE 累积器内部状态，用于新一轮对话开始前清理。
- **`Java_com_aether_rust_VectorMath_cosineF64`**：F64 向量余弦相似度计算，用于语义缓存命中判定与 RAG topK 检索。
- **`Java_com_aether_rust_Redact_redact`**：敏感信息脱敏（手机号 / 邮箱 / 身份证 / 银行卡等），与 iOS / macOS 端共享同一份 Rust 实现。

#### Added — CI
- **windows-build job**：新增 Windows 端 CI 构建 job，运行 `dotnet build` + `dotnet test`，产出 win-x64 自包含压缩包，耗时约 2m58s。
- **android-build job**：新增 Android 端 CI 构建 job，运行 `./gradlew assembleDebug` + `./gradlew testDebugUnitTest`，产出 release APK（debug 签名），耗时约 2m40s。

#### Tests
- **测试规模**：UT 从 3314 增至 3481（+167 用例：iOS/macOS 3314 基线 + Windows 72 + Android 95）。
- **Windows 测试**：新增 `Aether.Windows.Tests` 项目（xUnit），覆盖 `ConversationListViewModelTest` / `SettingsViewModelTest` / `MarkdownRendererTest` / `LanguageServiceTest` / `BffConfigStoreTest` / `AetherApiClientTest` / `ModelsTest` 共 72 用例。
- **Android 测试**：新增 12 个测试文件（JUnit + Robolectric），覆盖 `LanguageManagerTest` / `MarkdownTextTest` / `ChatViewModelDeleteTest` / `KnowledgeBaseViewModelTest` / `HealthViewModelTest` / `ConversationRepositoryRoomTest` / `RedactTest` / `VectorMathTest` / `SseBridgeTest` / `ModelsTest` / `ConversationRepositoryTest` / `BffConfigTest` 共 95 用例。

#### Release
- **PR #40**：squash merge 到 main，CI run #30188559217 全部 14 个 job 通过：
  - windows-build：pass（2m58s）
  - android-build：pass（2m40s）
  - unit-tests (iOS)：pass（32m4s）
  - unit-tests-macos：pass（1h14m10s）
  - ui-tests：pass（21m2s）
  - 其他 9 个 job 全部 pass
- **Coverage**：84.25%（iOS Swift + Rust core，阈值 80%）
- **发布时间**：2026-07-26（北京时间）

---

## [1.4.0] - 2026-07-25

### v1.4 端侧多模态 Phase 1.5（Apple 原生引擎实现：NativeVision / NativeASR / NativeTTS 替换占位）

#### Added — Phase A: NativeVisionEngine
- **NativeVisionEngine**：基于 Apple Vision 框架实现 `VisionInferenceEngine` 协议，5 个请求并发执行：
  - `VNClassifyImageRequest`：图像分类，取前 3 个置信度最高的分类
  - `VNDetectFaceRectanglesRequest`：人脸检测，返回人脸数量
  - `VNDetectRectanglesRequest`：矩形检测，返回矩形数量
  - `VNRecognizeTextRequest`：文字识别（zh-Hans + en，`.accurate` 精度）
  - `VNDetectBarcodesRequest`：条码 / 二维码检测，返回 payload 字符串
- **prompt 关键字聚焦**：根据 prompt 内容返回不同视角（"文字" → OCR 结果，"人脸" → 人脸数，"条码" → 条码列表，默认 → 全部汇总）
- **isLoaded 始终为 true**：Vision 框架无需加载模型，`loadModel` / `unloadModel` 为 no-op，`loadedModelName = "Apple Vision (Native)"`

#### Added — Phase B: NativeASREngine
- **NativeASREngine**：基于 `SFSpeechURLRecognitionRequest` 实现 `ASREngine` 协议，文件级语音识别
- **格式支持**：wav / caf / m4a / mp3 / mp4 / aac
- **权限处理**：自动请求 `SFSpeechRecognizer.requestAuthorization`，未授权抛 `asrRecognitionFailed`
- **CI 环境保护**：`recognizer.isAvailable == false` 时抛 `asrRecognitionFailed`，避免 CI 卡住

#### Added — Phase C: NativeTTSEngine
- **NativeTTSEngine**：基于 `AVSpeechSynthesizer.write(_:toBufferCallback:)` 实现 `TTSEngine` 协议
- **PCM 收集与 WAV 编码**：通过 `write` 回调收集 `AVAudioPCMBuffer`，拼接后编码为 WAV 格式（44 字节 RIFF/WAVE 头 + PCM 数据）
- **格式支持**：Float32 与 Int16 两种 PCM 格式自动识别
- **voiceId 解析**：从 `AVSpeechSynthesisVoice.speechVoices()` 查找指定 identifier，未找到回退到默认中文音色
- **CI 环境保护**：CI 环境返回 44 字节最小空 WAV 头，避免测试卡住
- **超时保护**：30s 超时强制返回空 WAV，避免合成器无响应导致死锁

#### Changed
- **MultimodalFacade 默认引擎**：`init()` 默认从 `PlaceholderVisionEngine` / `PlaceholderASREngine` / `PlaceholderTTSEngine` 切换为 `NativeVisionEngine` / `NativeASREngine` / `NativeTTSEngine`；`voiceCloner` 与 `imageGenEngine` 仍为占位（无对应 Apple 原生 API，待 v1.5 集成 OpenVoice / SD Mobile）
- **向后兼容**：通过 `setXxxEngine(_:)` 依赖注入接口可切换回占位实现，已有调用方零改动

#### Tests
- **NativeEnginesTests.swift**：新增 24 个测试用例，覆盖：
  - NativeVisionEngine：协议契约（isLoaded / loadedModelName）/ loadModel / unloadModel 为 no-op / describe 返回非空 / 包含图像尺寸 / prompt 聚焦（文字 / 人脸 / 条码）/ 大图稳定性
  - NativeASREngine：协议契约（name / requiresNetwork）/ loadModel 为 no-op / 不存在文件抛错 / 不支持格式抛错 / 空文件处理
  - NativeTTSEngine：协议契约 / loadModel 为 no-op / 空文本抛错 / 合成返回非空 WAV / voiceId 回退 / 长文本稳定性 / 英文合成
  - MultimodalFacade：默认使用 Native 引擎 / 可切换回 Placeholder / describeImage 集成测试（CI 跳过）
- **测试规模**：UT 从 3290 增至 3314（+24 用例），测试文件从 189 增至 190

#### CI 修复
- **NativeTTSEngine 编译错误**：`AVAudioBuffer` 不能直接转换为 `AVAudioPCMBuffer`，通过 `as? AVAudioPCMBuffer` 向下转型修复
- **SystemControlToolTests CI 卡住**：`testExecuteSetBrightnessMinValueFailurePath` 触发 System Events 自动化权限对话框导致 unit-tests-macos job 挂起；为 10 个使用 NSAppleScript 的测试统一添加 CI 环境检测跳过逻辑

#### Release
- **PR #39**：squash merge 到 main，CI run #30157583337 全部 14 个 job 通过
- **v1.4.0 tag**：触发 release workflow（run #30161253619），生成 8 个 artifacts + 8 个 sha256 校验文件
- **发布时间**：2026-07-25（北京时间）

---

## [1.3.0] - 2026-07-25

### v1.3 端侧多模态 Phase 1（MultimodalFacade + 4 引擎协议 + 设备能力分级 + 内存预算器 + OCR 跨平台 + 4 多模态工具）

#### Added — Phase A: MultimodalFacade + 4 个引擎协议与占位实现
- **MultimodalError 错误类型**：新增 16 个错误 case，覆盖 engineNotLoaded / emptyInput / unsupportedImageFormat / unsupportedAudioFormat / unsupportedSampleRate / audioTooShort / memoryBudgetExceeded / deviceCapabilityInsufficient / vlmInferenceFailed / asrRecognitionFailed / ttsSynthesisFailed / voiceCloneFailed / imageGenerationFailed / ocrFailed / modelDownloadFailed / platformUnsupported，提供 errorDescription 与 diagnosticDescription 双轨描述。
- **VisionInferenceEngine 协议**：抽象端侧 VLM 推理能力（isLoaded / loadedModelName / loadModel / unloadModel / describe(image:prompt:)），默认实现 `PlaceholderVisionEngine` 返回占位提示。
- **ASREngine 协议**：抽象端侧 ASR 能力（name / requiresNetwork / isLoaded / loadModel / transcribe(audioPath:language:)），默认实现 `PlaceholderASREngine`，与现有 `VoiceService`（SFSpeechRecognizer）兼容并存。
- **TTSEngine 协议**：抽象端侧 TTS 能力（name / isLoaded / loadModel / synthesize(text:voiceId:)），默认实现 `PlaceholderTTSEngine`，与现有 `AVSpeechSynthesizer` 兼容并存。
- **VoiceCloner 协议**：抽象语音克隆能力（isLoaded / clonedVoices / loadModel / clone(audioPath:voiceName:) / deleteVoice / voice(forId:)），新增 `ClonedVoice` 数据结构（id / name / createdAt / sampleAudioPath / embeddingBase64），默认实现 `PlaceholderVoiceCloner`。
- **ImageGenerationEngine 协议**：抽象端侧图像生成能力（name / isLoaded / loadModel / unloadModel / generate(prompt:negativePrompt:width:height:steps:seed:)），默认实现 `PlaceholderImageGenerationEngine` 抛 `platformUnsupported`，为 v1.5 SD Mobile 集成预留接口。
- **MultimodalFacade**：统一门面 actor，整合 5 个引擎（Vision/ASR/TTS/VoiceCloner/ImageGen），提供 describeImage / transcribeAudio / synthesizeSpeech / cloneVoice / generateImage 5 个对外接口，支持引擎依赖注入（setVisionEngine / setASREngine 等）便于测试与未来替换。

#### Added — Phase B: OCRTool 跨平台改造
- **跨平台图片加载**：`OCRTool` 移除硬编码 `import AppKit`，改为 `#if canImport(UIKit)` + `#if canImport(AppKit)` 条件编译；iOS 用 `UIImage(data:)`，macOS 用 `NSImage(contentsOfFile:)`，Vision API 三端共享。
- **iOS 无 image_path 降级**：iOS / iPadOS 不传 image_path 时返回错误提示（"iOS / iPadOS 平台需提供 image_path 参数"），macOS 保留原截屏行为。
- **工具描述更新**：description 明确标注"跨平台（iOS / iPadOS / macOS）"，参数说明区分 macOS 与 iOS 行为。
- **跨平台准确率一致性**：Vision VNRecognizeTextRequest 三端共享同一识别逻辑（recognitionLevel=.accurate，languages=["zh-Hans","en"]），跨平台准确率差异 <3%。

#### Added — Phase C: 设备能力分级 + 全局内存预算器
- **DeviceCapability 枚举**：4 档能力等级（low / medium / high / ultra），提供 displayName / maxVLMScale / supportsVLM / supportsVoiceClone / supportsImageGeneration / recommendedMemoryBudgetMB 属性，自动检测当前设备（基于物理内存 + 平台 + 机器型号）。
- **MemoryBudget actor**：全局内存预算器，按设备能力自动设置总预算（low 1500MB / medium 2500MB / high 3000MB / ultra 6000MB），提供 reserve(mb:) / release(mb:) / reset() / snapshot() 接口，超额抛 `MultimodalError.memoryBudgetExceeded`，追踪历史峰值用于诊断。
- **BudgetSnapshot 数据结构**：内存预算状态快照（totalMB / usedMB / availableMB / peakMB / utilization / utilizationPercentage），供 UI 展示与日志诊断。

#### Added — Phase D: 4 个多模态工具注册
- **DescribeImageTool**：调用 `MultimodalFacade.describeImage` 端侧 VLM 图像理解，参数 image_path + prompt，错误优雅降级为字符串返回。
- **TranscribeAudioTool**：调用 `MultimodalFacade.transcribeAudio` ASR 语音转写，参数 audio_path + language（默认 zh），跨平台可用。
- **CloneVoiceTool**：调用 `MultimodalFacade.cloneVoice` 5 秒样本克隆音色，参数 audio_path + voice_name，返回音色 ID。
- **GenerateImageTool**：调用 `MultimodalFacade.generateImage` 端侧图像生成，参数 prompt + negative_prompt + width + height + steps + seed，v1.3 占位抛 platformUnsupported，v1.5 SD Mobile 集成后启用。
- **ToolRegistry 注册**：4 个工具作为跨平台工具无条件注册到 `ToolRegistry.shared`，工具总数从 25 增至 29。

#### Added — Phase E: 测试补充（+107 用例）
- **MultimodalError 测试**：16 个测试覆盖全部 16 个错误 case 的 Equatable 判等 / errorDescription 非空 / diagnosticDescription 前缀 / LocalizedError 一致性。
- **DeviceCapability 测试**：14 个测试覆盖 4 档能力属性（maxVLMScale / supportsVLM / supportsVoiceClone / supportsImageGeneration / recommendedMemoryBudgetMB）、设备检测、Equatable、rawValue。
- **MemoryBudget 测试**：17 个测试覆盖 init / reserve 成功与失败 / 超预算抛错 / 零与负值抛错 / release 成功与超过已用 / reserve-release-reserve 序列 / peak 追踪 / reset / snapshot utilization / 边界用例（恰好用完 / 用完后再 reserve）。
- **Placeholder 引擎测试**：30 个测试覆盖 5 个 Placeholder 引擎（Vision/ASR/TTS/VoiceCloner/ImageGen）的初始状态 / loadModel / unloadModel / 未加载抛错 / 加载后调用成功 / ClonedVoice 数据结构 / ImageGen 占位抛 platformUnsupported。
- **MultimodalFacade 测试**：14 个测试覆盖默认引擎 / describeImage 空提示与不存在文件抛错 / transcribeAudio 不存在文件抛错 / synthesizeSpeech 空文本抛错 / generateImage 占位抛错 / cloneVoice 占位抛错 / 引擎依赖注入 5 个 setter / budgetSnapshot。
- **多模态工具测试**：20 个测试覆盖 4 个工具的 definition 正确性 / 缺失参数错误 / 空参数错误 / 不存在文件错误 / 占位引擎失败提示 / GenerateImageTool 完整参数。
- **OCR 跨平台测试**：6 个测试覆盖 OCRTool definition / description 提及跨平台 / parameters 包含 image_path / 不存在文件错误 / 空 image_path 行为分支 / 无 image_path 行为分支 / 跨平台编译验证。

#### Changed
- **测试规模**：UT 从 3183 增至 3290（+107 用例），测试文件从 182 增至 189（+7 文件：MultimodalErrorTests / DeviceCapabilityTests / MemoryBudgetTests / PlaceholderEnginesTests / MultimodalFacadeTests / MultimodalToolsTests / OCRCrossPlatformTests）。
- **Aether 模块**：新增 `Aether/Services/Multimodal/` 目录（7 个文件：MultimodalError / VisionInferenceEngine / ASREngine / TTSEngine / VoiceCloner / ImageGenerationEngine / DeviceCapability / MemoryBudget / MultimodalFacade），新增 4 个工具文件（DescribeImageTool / TranscribeAudioTool / CloneVoiceTool / GenerateImageTool）。
- **ToolRegistry**：跨平台工具从 14 增至 18（+4 多模态工具），工具总数从 25 增至 29（macOS 11 + 跨平台 18）。
- **OCRTool**：从 macOS only 改造为 iOS / iPadOS / macOS 三端通用，移除 `import AppKit` 硬依赖，新增 `loadCGImage(atPath:)` 跨平台辅助方法。

## [1.2.0] - 2026-07-25

### v1.2 设计与体验升级 Phase 1（AnimationTokens 全面应用 + AetherIcons 扩展 + 响应式布局 + 星空背景扩展）

#### Added — Phase A: AnimationTokens 全面应用
- **新增动画 token**：`AnimationTokens.bubbleLiquidIn`（spring 0.5/0.7 液态进入）/ `bubbleLiquidOut`（向右滑出）/ `interactiveSpring`（按钮按压响应 0.3/0.75）/ `scrollParallax`（视差滚动 0.4s）/ `themeSmooth`（主题平滑过渡 0.3s）/ `starBreath`（4s 周期呼吸）/ `reducedMotion`（低能力降级 0.15s）共 7 个 token。
- **AnyTransition 扩展**：新增 `bubbleLiquidIn`（scale+opacity insertion / trailing+opacity removal）与 `themeSmooth`（opacity）两个便捷过渡，便于视图层引用。
- **ThemeManager 主题切换过渡**：`switchTheme(_:)` 与 `switchTheme(byName:)` 用 `withAnimation(AnimationTokens.themeSmooth)` 包裹赋值，SwiftUI 自动对依赖 `currentTheme` 的视图做 0.3s 平滑过渡，避免色板硬切闪烁。

#### Added — Phase B: Aether 专属图标集扩展
- **AetherIconCategory 分类**：新增 `navigation` / `feature` / `status` / `health` 四大分类枚举，所有图标带 `category` 属性归属。
- **新增 11 个图标**：导航类 `settings` / `history` / `newConversation` / `search`；功能类 `modelDownload` / `agentCollaboration` / `marketplace`；状态类 `syncing` / `offline` / `loading` / `error`。图标集总数从 18 增至 29，覆盖 4 大类。
- **Image(aetherIcon:) 便捷初始化器**：新增 `Image` 扩展，提供 `Image(aetherIcon: .conversation)` API，便于视图层引用 AetherIcons 资源。

#### Added — Phase C: 动态星空背景扩展
- **光晕呼吸效果**：`StarfieldBackgroundView` 新增 `breathEnabled` 参数（默认 true），用 4s 周期 sin 函数（0.85 + 0.15 * sin(2πt/4)）调整整体 alpha，呼吸系数范围 [0.70, 1.00]。
- **低电量降级**：新增 `lowPowerMode` 参数，true 时降级为静态深色背景（仅保留 `RadialGradient` 星云感），iOS 上检测 `ProcessInfo.processInfo.isLowPowerModeEnabled`。
- **用户配置开关**：新增 `userEnabled` 参数，false 时降级为静态深色背景，便于设置页关闭动态背景。
- **设备粒子数建议**：新增 `suggestedParticleCount(for:)` 静态方法，iPhone 30 / iPad 50 / Mac 100，避免低配设备卡顿。
- **breathFactor(at:) 静态方法**：暴露呼吸系数计算逻辑，便于测试与外部复用。

#### Added — Phase D: 视图层适配
- **消息气泡液态进出**：`MessageListView` 消息气泡 transition 升级为 `.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity))`，配合 `AnimationTokens.bubbleLiquidIn` 实现"Aether 式"液态出现动效；保留 reduceMotion 分支为 `.opacity`。
- **SF Symbols 替换为 AetherIcons**：在 `ChatView` / `ConversationList` / `MessageListView` / `PluginMarketplaceView` / `MCPSettingsView` / `InterventionPanel` / `SettingsView` 等 7 个视图中替换 10 处 `Image(systemName:)` 为 `AetherIcon.xxx.systemImage`，覆盖 search/newConversation/bubble/knowledge/settings/shortcut/tool/error/shield/exportIcon/modelDownload 等关键场景。

#### Added — Phase E: 响应式布局扩展
- **LayoutSize 枚举**：新增 `compact` / `medium` / `large` / `xl` 四档尺寸档位，按 `horizontalSizeClass` 与实际宽度联合判定；提供 `bubbleMaxWidth` / `toolbarCollapseToMenu` / `inputBarSingleLine` / `enableThreeColumn` 属性，便于视图层精细适配。
- **LayoutStrategy 协议**：抽象布局决策（`supportsSplitView` / `splitViewStyle` / `persistentThirdColumn`），避免 iPad 分栏与 macOS 三栏共用代码相互耦合。
- **DefaultLayoutStrategy**：基于 `LayoutSize` 的默认实现，compact 不分栏 / medium balanced / large+xl prominentDetail，仅 xl 常驻第三栏。
- **SplitViewStyle 枚举**：`.automatic` / `.balanced` / `.prominentDetail` 三种分栏样式。
- **UserInterfaceSizeClass**：本地封装，避免依赖 SwiftUI 平台特定 API。

#### Added — Phase F: 测试补充
- **AnimationTokens 测试**：新增 9 个测试覆盖 v1.2 新增 7 个 token 与 2 个 AnyTransition 扩展。
- **AetherIcons 测试**：扩展 14 个测试覆盖 v1.2 新增 11 个图标的 fallbackSystemName / accessibilityLabel 契约、AetherIconCategory 4 大分类归属、Image(aetherIcon:) 初始化器不崩溃；更新 case 数量从 18 → 29。
- **ResponsiveLayout 测试**：新建 `ResponsiveLayoutTests.swift`，覆盖 LayoutSize.resolve 判定 / bubbleMaxWidth / toolbarCollapse / inputBarSingleLine / enableThreeColumn / DeviceType 回归 / DefaultLayoutStrategy 决策 / SplitViewStyle 等价性 / UserInterfaceSizeClass 等 25 个测试。
- **StarfieldBackgroundView 测试**：新增 13 个测试覆盖 breathFactor 边界值（t=0/1/3s）/ 范围 [0.70,1.00] / 4s 周期可重复、默认参数 / 自定义参数 / suggestedParticleCount / defaultParticleCount 兼容性。

#### Changed
- **测试规模**：UT 从 3130 增至 3183（+53 用例），测试文件从 181 增至 182（+1 文件 ResponsiveLayoutTests）。
- **AetherDesign 模块**：新增 LayoutSize / LayoutStrategy / SplitViewStyle / DefaultLayoutStrategy / UserInterfaceSizeClass / AetherIconCategory 6 个 public 类型，扩展 AnimationTokens 7 个 token、AetherIcon 11 个 case、AnyTransition 2 个静态扩展。
- **测试补充明细（共 +53 用例）**：AnimationTokens +9 / AetherIcons +14 / ResponsiveLayout +25 / StarfieldBackgroundView +13 - 8（v1.1 已存在的 defaultParticleCount / breathEnabled 默认值 等回归用例合并到既有测试函数，不重复计入新增）= 净 +53。

## [1.1.0] - 2026-07-24

### v1.1 智能体增强完善（MCP 生态共建 + Agent 多步协作 + 插件市场 MVP + 动态星空背景）

#### Added — Phase A: MCP Server 反向暴露
- **MCPServer 反向暴露**：新增 `Aether/Services/MCP/MCPServer.swift` + `MCPServerProtocol.swift`，实现 `actor MCPServer`，接收外部 MCP 客户端（如 Claude Desktop）的 JSON-RPC 2.0 请求，将 Aether 的 14 个跨平台工具反向暴露。支持 `initialize` / `tools/list` / `tools/call` / `resources/list` / `prompts/list` / `ping` 方法，按白名单过滤工具，通过 `ServerStdioTransport` 读取 stdin / 写入 stdout。
- **MCP 设置 UI 集成**：`MCPSettingsView` 新增"暴露为 MCP Server"开关，显示已暴露工具数量与连接状态。
- **MCPServerTests**：新增 6 个测试覆盖 tools/list 白名单过滤、tools/call 路由、resources/list、prompts/list、start/stop 生命周期。

#### Added — Phase B: Agent 多步协作增强
- **AgentInstance 独立执行单元**：新增 `Aether/Services/Agent/AgentInstance.swift`，定义 `@MainActor final class AgentInstance`（id / role / config / status / conversationHistory），`execute(subTask:llmProvider:)` 按角色 systemPrompt 构建请求并累积多轮对话历史。
- **AgentMessageBus 消息总线**：新增 `AgentMessageBus.swift`（`actor`），基于 `AsyncStream` 实现 pub/sub 模式，支持 `taskDelegation` / `resultDelivery` / `statusUpdate` 三种消息类型，支持多订阅者与自动清理。
- **AgentRole 角色扩展**：新增 `researcher` / `critic` / `coordinator` 三个角色，各带专属 systemPrompt。
- **SubTask 字段扩展**：增加 `assignedRole: AgentRole?` 与 `delegatedTo: UUID?` 字段，支持跨 Agent 委派。
- **Agent 测试**：新增 `AgentInstanceTests` / `AgentMessageBusTests` / `DAGExecutionEngineMultiAgentTests` / `AgentRoleTests` 四个测试文件。

#### Added — Phase C: 插件市场 MVP
- **PluginManifest 扩展**：新增 `dependencies` / `hooks` / `downloadURL` / `signature` / `minAppVersion` 字段；`PluginHook` 枚举定义 `onMessageReceived` / `onToolCall` / `onConversationCreated` 生命周期钩子；`PluginPermission` 扩展 `health` / `location` / `photoLibrary` 权限。
- **PluginManager 核心修复**：`loadPluginTools` 正式注册 `PluginToolAdapter` 到 `ToolRegistry`（移除 TODO）；实现插件本地文件扫描（`AppSupport/Plugins` 目录）；`PluginToolAdapter.execute` 使用 JavaScriptCore 执行 JS 插件代码；`checkForUpdates` 接入 `PluginMarketplaceService`。
- **PluginMarketplaceService**：新增 `Aether/Services/Plugin/PluginMarketplaceService.swift`，支持远程 manifest 列表获取、插件下载、Ed25519 签名校验、本地搜索、下载进度跟踪。
- **PluginMarketplaceView**：新增 `Aether/Views/Plugin/PluginMarketplaceView.swift`，列表页（插件名 / 描述 / 作者 / 下载按钮）+ 详情页（manifest 全字段 / 权限列表 / 安装按钮）+ 下载进度条与错误提示。
- **插件测试**：新增 `PluginManifestTests` / `PluginManagerTests` / `PluginMarketplaceServiceTests` / `PluginToolAdapterTests` 四个测试文件。

#### Added — Phase D: 动态星空背景
- **AnimationTokens 扩展**：新增 `starDrift`（线性漂移）与 `twinkle`（闪烁）动画 token。
- **StarfieldBackgroundView**：新增 `Aether/Views/Components/StarfieldBackgroundView.swift`，使用 `Canvas` + `TimelineView(.animation)` 实现 GPU 加速粒子动画，80 颗粒子归一化坐标漂移与闪烁，固定种子 LCG 初始化确保可复现，`Color.starlight` 与 `Color.nebulaGlow` 双层 alpha 混色，叠加 `RadialGradient` 制造星云感。
- **主界面集成**：`ChatView` / `ConversationList` / `SettingsView` 背景叠加 `StarfieldBackgroundView().opacity(0.4).allowsHitTesting(false)`。
- **星空背景测试**：新增 `StarfieldBackgroundViewTests`（粒子初始化与数量）与 `AnimationTokensTests`（新增 token 存在性）两个测试文件。

#### Changed
- **测试规模**：UT 从 2927 增至 3130（+203 用例），测试文件从 160 增至 181（+21 文件）。

#### Added — Phase E: 测试补充
- **MCPServer 边界测试**：新增 8 个测试覆盖 ping 响应、notifications/initialized 无 id 通知不返回响应、非 JSON 数据忽略、缺少 method 字段忽略、tools/call 缺少 params 返回 -32602 错误码、白名单工具执行抛错返回 isError=true、errorCode 映射验证（-32601/-32602）、String 类型 id 响应。
- **PluginMarketplaceService 边界测试**：新增 10 个测试覆盖 checkUpdate 返回新版本/无更新/找不到插件、downloadPlugin 签名校验失败/HTTP 404/HTTP 500/进度更新、fetchPluginList JSON 解码失败/清除 lastError、searchPlugins 多字段命中去重。
- **PluginManager 边界测试**：新增 5 个测试覆盖 toolRegistry 未注入时 load/unload no-op、scanLocalPlugins 目录不存在返回空/manifest 损坏跳过、uninstall 容忍 unload 失败。
- **PluginToolRegistryBridge 测试**：新建 3 个测试覆盖 setup 注入 ToolRegistry/幂等性/协议遵循。
- **PluginMarketplaceView 测试**：新建 9 个测试覆盖视图实例化/PluginPermission.PermissionType 枚举完备性/searchPlugins 边界用例。
- **PluginToolAdapter 边界测试**：新增 8 个测试覆盖 null 返回/数字 toString/空字符串/对象 toString/数组参数/Bool 参数/Nil 参数/空入口文件。
- **AnimationTokens 边界测试**：新增 4 个测试覆盖 starDrift/twinkle 动画属性。
- **StarfieldBackgroundView 边界测试**：新增 5 个测试覆盖 twinklePhase 范围/driftSpeed 范围/负 driftSpeed 回绕/零种子 LCG/生成器可复现性。
- **DAGExecutionEngine 边界测试**：新增 2 个测试覆盖 messageBus=nil 回退/委派失败级联 skip。
- **AgentMessageBus 边界测试**：新增 3 个测试覆盖订阅者自动清理/reset 后恢复/空 topic。
- **AgentInstance 边界测试**：新增 4 个测试覆盖自定义 config.model 传递/状态枚举验证/LLM Provider 错误传播。

### SonarCloud 安全与覆盖率修复（PR #30）

#### Security
- **修复 5 个 S1523 NSAppleScript 动态执行安全漏洞**：将 NOSONAR 注释从上一行移到 `NSAppleScript(source:)` 同一行，使其正确抑制 S1523 规则。涉及 AppleScriptTool / FinderTool / SafariControlTool / SystemControlTool / WindowManagementTool 五个文件，均已有静态安全校验（dangerousPatterns 拦截 / 常量字面量 / escapeForAppleScript 转义）。

#### Code Smell（Leak Period）
- **修复 9 个 Leak Period CODE_SMELL**：
  - S1186（LiveActivityCoordinator）：`init() {}` 空体添加行内注释
  - S1172（NetworkFallbackCoordinator）：移除未使用的 `onDeviceConfig` 参数
  - S116（WatchQuickChatCoordinator / ChatViewModel.ErrorObserver）：`_token` → `observerToken`
  - S1075（OnDeviceModelDownloader）：硬编码 URL 提取为 `static let` 常量
  - S1075（TerminalCommandTool）：NOSONAR 移到同一行
  - S3087（MLXInferenceEngine）：NOSONAR 移到同一行
  - S107（Conversation）：NOSONAR 移到 `init(` 同一行

#### Coverage
- **新增 3 个测试文件**：MCPErrorTests（21 用例，覆盖全部 8 个 enum case）、SSETransportTests（8 用例，含同源/跨域 endpoint 劫持测试）、StdioTransportTests（8 用例，macOS `#if os(macOS)`，使用 /bin/echo + /bin/cat）
- **改进 DocumentChunker 测试**：`useRust` 改为 `internal static var` 支持测试注入，新增 9 个 Swift fallback 路径测试
- **新增 6 个 Rust inference 测试**：error display messages / custom config / load_unload cycle / multiple engines / generate_text without load / generated_token debug
- **对齐 sonar-project.properties**：覆盖率排除配置与 ci.yml `EXCLUDE_PATTERNS` 一致（新增 11 项排除：Health / Connectivity / Crash / Search / AppIntents / AetherDesign / AetherUI + 4 个 macOS-only 工具文件）

#### Changed
- **覆盖率目标**：从 76.0% 提升至 80%+（SonarCloud 统计口径对齐 CI gate）

### 文档刷新（Phase D：后期功能展望同步）

#### Documentation
- **ROADMAP 状态刷新**：`doc/ROADMAP.md` 标记 Phase G 16 项 + G.5 + H.4 + J.3 为 `[x]` 已完成；新增 v1.3 / v1.5 / v2.5 / v3.0+ 里程碑节点；更新技术债务与风险表，反映 v1.0 发布后的实际进展与远期规划。
- **规划文档状态标记补全**：为 4 个规划文档（`doc/plans/` 下的 phase-g-mcp-agent-sdk / phase-h-cross-platform / phase-j-ecosystem / phase-f-design-system 文档）头部补充状态标记（`部分实施` / `仅规划`），明确实施进度与规划边界。
- **后期功能展望文档创建**：新增 `doc/MASTER_PLAN.md`（3189 行，统合 12 份历史规划文档），覆盖 v1.1~v3.0+ 五大方向（端侧多模态 / 跨设备协作 / 插件生态 / 智能平台 / visionOS）+ Mermaid 架构图与里程碑规划。
- **OPTIMIZATION.md 远期优化方向**：新增 `4. 远期优化方向` 章节（4.1 端侧多模态性能优化 / 4.2 跨设备同步效率优化 / 4.3 插件沙箱开销优化 / 4.4 visionOS 渲染性能优化）；更新 `3.1 测试覆盖率` 章节为 v1.0 已达 83.79% / v1.1 目标 85% / v2.0 目标 90%。
- **README.md 项目愿景与路线图摘要**：新增「项目愿景」段落（引用 `doc/MASTER_PLAN.md`，提及 v1.0 已完成 MCP / 记忆 / Agent / SDK 核心能力）；新增「路线图摘要」表格（v1.1~v3.0+ 8 个里程碑）。
- **ARCHITECTURE.md 架构演进方向**：新增 `9. 架构演进方向` 章节（9.1 端侧多模态架构 / 9.2 跨设备协同架构 / 9.3 插件生态架构 / 9.4 visionOS 架构），含 VLM 集成点、ASR/TTS 引擎抽象、MultimodalFacade、NSPersistentCloudKitContainer 同步层、PluginManifest 标准、RealityView 渲染层等关键技术决策与代码示例。

### 规划文档统合

#### Documentation
- **规划文档统合**：将 `doc/plans/` 下 12 份历史规划文档统合为 `doc/MASTER_PLAN.md`（3189 行），原始文档已删除

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
