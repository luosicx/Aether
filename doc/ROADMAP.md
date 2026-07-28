# Aether 路线图

> 本文档描述 Aether（以太）在 Day 20 之后的演进方向与里程碑。优先级：P0（必须） / P1（重要） / P2（增强）。
> 品牌愿景：**无形，无处不在，智能**——Aether 致力于成为最懂用户的端侧 AI 助手，以液态玻璃 + 深空美学为视觉语言，覆盖 iOS / iPad / macOS / Windows / Android 五端。

---

## 当前基线（Day 1-20 + 品牌重塑 + 优化）

### 工程基线

- iOS / iPad / macOS / Windows / Android 五端跨平台渲染（Apple 端 SwiftUI + Windows WPF .NET 8 + Android Kotlin/Compose），`#if os(iOS)` 条件编译优雅降级
- **Windows 端**（WPF .NET 8）：会话列表 / 设置页 / Markdown（Markdig）/ i18n（8 种 .resx）/ DPAPI 加密 / 流式聊天 / Rust FFI（DLL）
- **Android 端**（Kotlin + Jetpack Compose）：RAG UI / Health UI / Room 数据库生产使用 / 消息长按菜单 / Markdown（Markwon 4.6.2）/ i18n / Rust JNI（4 函数）
- **29 个工具**（18 跨平台含 4 多模态 + 11 macOS 独有），ReAct 循环最大 5 轮
- **8 种语言** i18n（zh-Hans / zh-Hant / en / ja / ko / fr / de / es），888 keys
- **3481 UT**（iOS/macOS 3314 + Windows 72 + Android 95）+ 30 UIT，0 failures / 0 skips
- 多 Provider（DeepSeek / Qwen / MLX 端侧）+ SmartRouter + Fallback 自动降级
- SwiftLint + SwiftFormat 代码质量工具链，CI 集成脚本
- **Watch App 源代码**就绪（`AetherWatch/`，⚠️ 需手动创建 Xcode target）
- **Widget Extension 源代码**就绪（`AetherWidgets/`，⚠️ 需手动创建 Xcode target）
- **DeepLink 支持**（`aether://ask?query=` / `aether://conversation/<uuid>`）
- **App Group 共享 SwiftData**（`group.com.aether.app`）

### 品牌与设计基线

- **Aether（以太）品牌**：液态玻璃 + 深空主题视觉语言
- **色彩体系**：deepSpace / aetherPurple / electricBlue / liquidGlass / nebulaGlow / starlight / duskGray + aetherGradient
- **字体体系**：aetherTitle（28pt）/ aetherDisplay（48pt）/ aetherBody（16pt）
- **圆角体系**：small 12 / medium 16 / large 24（液态玻璃柔和圆角）
- **深色模式默认**：`.preferredColorScheme(.dark)` 开箱即用
- **4 个 PlantUML 架构图** + 多个 Mermaid 图表

### 性能优化基线

- BGTask 调度懒注册（首次进入后台触发）
- 远程配置拉取移到首屏 `.task`
- Markdown 解析 NSCache 缓存（countLimit=200）+ CodeBlockView 语法高亮缓存（countLimit=100）
- ConversationList `.id` 稳定化
- MLX 模型异步加载 + TaskGroup tokenizer 预热

---

## Phase F：工程质量与上架准备（P0）

> 目标：完成 App Store 上架所需的全部工程化准备。

### F.1 上架准备

- [ ] App Store 元数据与截图最终确认（含 Aether 品牌截图）
- [ ] PrivacyInfo.xcprivacy 与隐私问卷对齐
- [ ] 真机测试（iPhone / iPad / Mac，覆盖 iOS 17+ / macOS 14+）
- [ ] TestFlight 内测与崩溃监控验证
- [ ] CI 构建时长优化与缓存策略（DerivedData 缓存 + SPM 缓存）

### F.2 质量保障

- [ ] Service 层测试覆盖率 ≥ 80%（含 macOS-only 工具）
- [ ] SwiftLint warnings 降至 ≤ 20（仅保留安全模式 force_unwrapping）
- [ ] 端侧 MLX 推理真机验证（Llama-3.2-1B Q4_K_M 量化模型）
- [ ] 内存泄漏与性能回归测试（Instruments Leaks / Time Profiler）
- [ ] 无障碍完整审计（VoiceOver / Dynamic Type / Reduce Motion）

---

## Phase G：智能体能力增强（P1）

> 目标：从单轮对话工具调用进化到多步 Agent 协作与记忆系统。

### G.1 MCP 协议接入

- [x] MCP（Model Context Protocol）客户端接入（代码：`Aether/Services/MCP/` 16 文件）
- [x] 支持外部 MCP Server 动态发现与连接（代码：`Aether/Services/MCP/` 16 文件）
- [x] MCP 工具自动注册到 ToolRegistry（代码：`Aether/Services/MCP/` 16 文件）
- [x] MCP 资源（Resources）与提示词（Prompts）模板支持（代码：`Aether/Services/MCP/` 16 文件）

### G.2 长期记忆系统

- [x] 跨会话长期记忆向量库（remember / recall）（代码：`Aether/Services/Memory/` 12 文件）
- [x] 用户偏好自动提取与持久化（UserPreference @Model 扩展）（代码：`Aether/Services/Memory/` 12 文件）
- [x] 上下文窗口管理：重要消息压缩 + 过期消息摘要（代码：`Aether/Services/Memory/` 12 文件）
- [x] 语义记忆检索：基于 embedding 相似度召回历史对话（代码：`Aether/Services/Memory/` 12 文件）

### G.3 Agent 任务规划

- [x] 多步目标分解（Goal → SubTasks → Actions）（代码：`Aether/Services/Agent/` 10 文件）
- [x] Agent 任务编排引擎（DAG 执行图）（代码：`Aether/Services/Agent/` 10 文件）
- [x] 任务状态持久化与断点续执行（代码：`Aether/Services/Agent/` 10 文件）
- [x] 多 Agent 协作（多个 LLM 角色分工）（代码：`Aether/Services/Agent/` 10 文件）

### G.4 插件系统

- [x] 插件化工具市场（外部工具动态注册，无需重新编译）（代码：`Aether/Services/Plugin/PluginMarketplaceService.swift` + `PluginToolRegistryBridge.swift`，v1.1 MVP）
- [x] 插件沙箱隔离与权限管理（代码：`Packages/AetherCore/Sources/AetherServices/Plugin/`）
- [ ] 插件版本管理与热更新
- [x] 社区插件分发渠道（代码：`Aether/Views/Plugin/PluginMarketplaceView.swift` + `PluginMarketplaceService.swift`，v1.1 MVP：远程 manifest 列表 + 下载 + Ed25519 签名校验）

### G.5 MCP 安全加固

- [x] MCP Server 签名校验（代码：`Aether/Services/MCP/` 安全加固模块）
- [x] MCP 调用审计日志（代码：`Aether/Services/MCP/` 安全加固模块）
- [x] MCP 工具调用速率限制（代码：`Aether/Services/MCP/` 安全加固模块）
- [x] MCP 前缀防注入（代码：`Aether/Services/MCP/` 安全加固模块）

---

## Phase H：体验与设计升级（P1）

> 目标：将液态玻璃 + 深空美学推向极致，建立行业标杆级 AI 助手视觉体验。

### H.1 设计系统深化

- [x] Aether 色彩 / 字体 / 圆角 Token 体系（已完成）
- [x] 深色模式默认 + 液态玻璃 UI（已完成）
- [x] 动画与过渡效果统一（AnimationTokens 全面应用，v1.2 已交付）
- [x] 自定义图标集（AetherIcons 4 类 11 图标，v1.2 已交付）
- [x] 响应式布局适配（LayoutSize / Strategy / SplitViewStyle，v1.2 已交付）

### H.2 交互升级

- [ ] macOS 多窗口与拖拽支持（多对话并行）
- [x] 对话分支与版本管理（对话树）（代码：`Views/Conversation/ConversationTreeView.swift`）
- [x] 富媒体消息支持（卡片 / 链接预览 / 内嵌图表）（代码：`Views/Chat/InlineChartView.swift` / `RichMessageCard.swift` / `LinkPreviewCard.swift`）
- [ ] 手势快捷操作（滑动删除 / 长按菜单 / 拖拽排序）
- [x] macOS 菜单栏常驻模式（MenuBarExtra）（代码：`Views/MenuBarExtra/MenuBarPanel.swift`）

### H.3 个性化

- [x] 主题切换（深空 / 黎明 / 极光等多套色彩主题）（已完成基础主题切换）
- [x] 自定义头像与 AI 人设（已完成 PhotosPicker 头像选择器）
- [x] 对话气泡样式可选（液态玻璃 / 极简 / 卡片）（已完成气泡样式切换）
- [x] 字体大小与行距可调（已完成字体与间距设置）

### H.4 性能优化

- [x] VirtualizedMessageList 虚拟化列表（代码：`Views/Chat/VirtualizedMessageList.swift`）

---

## Phase I：端侧多模态与本地化（P2）

> 目标：让 Aether 在无网络环境下也能提供丰富的多模态 AI 能力。

### I.1 端侧多模态

- [~] 端侧视觉理解（v1.3 协议 + 占位已交付；v1.4 替换为 NativeVisionEngine 基于 Apple Vision 框架；MLX-VLM 待 v1.6 集成）
- [~] 端侧语音识别（v1.3 协议 + 占位已交付；v1.4 替换为 NativeASREngine 基于 SFSpeech 文件识别；Whisper.cpp 待 v1.6 集成）
- [~] 端侧 TTS 语音合成（v1.3 协议 + 占位已交付；v1.4 替换为 NativeTTSEngine 基于 AVSpeechSynthesizer.write；MLX-Voice 待 v1.6 集成）
- [ ] 端侧图像生成（Stable Diffusion Mobile / Draw Things API，v1.3 占位已交付，v1.6 集成 SD Mobile）
- [ ] 端侧语音克隆（OpenVoice v2 蒸馏，v1.3 占位已交付，v1.6 集成真实克隆）
- [x] 跨平台 OCR（v1.3 改造 OCRTool 跨平台，iOS + macOS 均可用，基于 Vision `VNRecognizeTextRequest`）

### I.2 本地化扩展

- [x] 新增日语 / 韩语 / 法语 / 德语 / 西班牙语支持（已完成 8 种语言）
- [ ] 区域化模型推荐（中国区推荐 Qwen，海外推荐 Llama）
- [ ] RTL 语言支持（阿拉伯语 / 希伯来语）
- [ ] 本地化文案质量审计（母语审校）

---

## Phase J：跨设备协同与生态（P2）

> 目标：构建 Aether 生态系统，实现跨设备无缝协作。

### J.1 跨设备同步

- [~] 对话历史 iCloud 同步（CloudKit / NSPersistentCloudKitContainer）（代码存在但 entitlements 未配置，部分实施）
- [ ] 跨设备连续对话（Handoff）
- [~] watchOS 独立 App（无需 iPhone 配对）（源代码已就绪，需手动创建 Xcode target）
- [ ] visionOS 适配（空间计算体验）

### J.2 协作与分享

- [ ] 团队知识库共享（组织级 RAG 知识库）
- [ ] 对话分享与导出（Markdown / PDF / 链接）
- [ ] 对话模板与预设角色市场
- [~] Web / Android 伴侣应用（Android 已交付 v1.5；Web 待 v2.0，跨平台数据互通）

### J.3 开发者生态

- [x] Aether SDK（第三方应用集成 Aether AI 能力）（代码：`Packages/AetherCore/Sources/AetherSDK/` 12 文件 + Documentation.docc）
- [x] URL Scheme 与 x-callback-url 支持（已完成 `aether://` DeepLink）
- [ ] Shortcuts 深度集成（更多 App Intents）
- [ ] 开发者文档与示例代码

---

## Phase K：跨平台扩展（v1.5 已交付）

> 目标：将 Aether 从 Apple 三端扩展到 Windows 与 Android，实现五端覆盖与 Rust 核心跨端复用。CI 14 个 job 全部 pass，Coverage 84.25%。

### K.1 Windows 端交付

- [x] 会话列表 / 设置页 UI（WPF .NET 8）
- [x] Markdown 渲染（Markdig）
- [x] i18n（8 种 .resx 资源文件）
- [x] DPAPI 凭证加密
- [x] 流式聊天接入
- [x] Rust FFI（DLL 调用 aether-core-ffi）

### K.2 Android 端交付

- [x] RAG UI 与 Health UI（Kotlin + Jetpack Compose）
- [x] Room 数据库生产使用
- [x] 消息长按菜单
- [x] Markdown 渲染（Markwon 4.6.2）
- [x] i18n
- [x] Rust JNI 接入

### K.3 Rust JNI 暴露

- [x] `parseWithTools`（带工具的 SSE 流式解析）
- [x] `reset`（解析器状态重置）
- [x] `cosineF64`（向量余弦相似度，双精度）
- [x] `redact`（敏感信息脱敏）

---

## 品牌愿景与 Liquid Glass 演进路径

### 愿景

**Aether（以太）** 取自古希腊神话中的天空之神，象征着**无处不在的纯粹能量**。Aether AI 助手致力于成为用户数字生活中「无形而无处不在」的智能伙伴——在你需要时即刻出现，在你不注意时默默学习，以最自然的方式融入日常。

### Liquid Glass 演进

| 阶段 | 特征 | 状态 |
|------|------|------|
| v1.0 | 深空背景 + 液态玻璃卡片 + 紫蓝渐变 | ✅ 已完成 |
| v1.1 | 动态星空背景（粒子动画）+ 毛玻璃深度分层 | ✅ 已完成 |
| v1.2 | 流体动画（消息气泡液态进出）+ 光晕呼吸效果 + AetherIcons + 响应式布局 | ✅ 已完成 |
| v1.3 | 端侧多模态 Phase 1（协议抽象 + 占位实现 + 跨平台 OCR + 4 个多模态工具） | ✅ 已完成 |
| v1.4 | 端侧多模态 Phase 1.5（Apple 原生引擎：NativeVision / NativeASR / NativeTTS） | ✅ 已完成 |
| v1.5 | 跨平台扩展（Windows WPF .NET 8 + Android Kotlin/Compose + Rust JNI） | ✅ 已完成 |
| v1.6 | 端侧多模态 Phase 2（MLX-VLM + Whisper + MLX-Voice + SD Mobile） | 📋 规划中 |
| v2.0 | 全沉浸式 3D 交互（visionOS 空间计算） | 🔮 远期 |

### 设计哲学

1. **深邃而不压抑**：深空背景营造专注感，紫蓝渐变点缀带来希望
2. **通透而不模糊**：液态玻璃材质传达层次感，内容始终清晰可读
3. **流动而不杂乱**：动画自然流畅，引导注意力而非分散
4. **智能而不冰冷**：科技感中保留人文温度，以太品牌名传递东方哲学

---

## 里程碑时间表

| 里程碑 | 目标 | 关键交付 | 预计版本 |
|--------|------|----------|----------|
| v1.0 ✅ | App Store 首发 | 工程化完善、审核通过、首版上架 | 2026 Q3（已完成） |
| v1.1 ✅ | 智能体增强完善（MCP 生态共建 + Agent 多步协作 + 插件市场 MVP） | MCP Server 反向暴露、Agent 多步协作、插件市场 MVP、动态星空背景 | 2026-07-24 已发布 |
| v1.2 ✅ | 设计升级 | AnimationTokens、AetherIcons、响应式布局、动态星空呼吸效果 | 2026-07-25 已发布 |
| v1.3 ✅ | 端侧多模态 Phase 1 | 协议抽象、4 个多模态工具、跨平台 OCR、占位引擎 | 2026-07-25 已发布 |
| v1.4 ✅ | 端侧多模态 Phase 1.5 | NativeVisionEngine / NativeASREngine / NativeTTSEngine 替换占位实现 | 2026-07-25 已发布 |
| v1.5 ✅ | 跨平台扩展 | Windows WPF .NET 8 + Android Kotlin/Compose + Rust JNI 暴露 | 2026-07-26 已发布 |
| v1.6 | 端侧多模态 Phase 2 | MLX-VLM、Whisper.cpp、MLX-Voice、SD Mobile 图像生成 | 2027 Q3 |
| v2.0 | 跨端协作 | iCloud 同步、Web 伴侣、团队协作、Windows ARM64 工具链 | 2027 Q4 |
| v2.5 | 生态扩展 | 社区插件市场、多 Agent 协作、Android 深化（端侧 MLX/NNAPI 推理） | 2028 Q1 |
| v3.0 | 生态平台 | SDK、插件市场、visionOS | 2028 Q2 |
| v3.0+ | 远期探索 | 隐私计算、实时协作、多模态记忆 | 2028 下半年 |

---

## 技术债务与风险

### 已知技术债务

| 债务项 | 影响 | 计划 |
|--------|------|------|
| BFF 令牌桶仅客户端 | 可被绕过 | v2.0 服务端限流强化 |
| Candle iOS 受限 | iOS 端侧推理能力受限 | v1.3 评估 MLX 替代方案 |
| ~~Vision OCR 仅 macOS~~ | ~~iOS 无法离线 OCR~~ | ✅ v1.3 已改造跨平台 OCR |
| 多模态引擎为 Apple 原生（无 MLX） | 自然度不及 MLX-VLM/Whisper.cpp/MLX-Voice | v1.6 集成 MLX 后端，原生引擎作为兜底 |
| Plugin 热更新未实现 | 插件版本管理占位 | v2.5 实现热更新与依赖解析 |
| visionOS target 缺失 | 空间计算体验缺失 | v2.0 新增 visionOS target |
| Windows 仅 x64 / 无 ARM64 | Windows on ARM 设备不可用 | v2.0 评估 ARM64 工具链与发布 |
| Android 无端侧 MLX 推理 | Android 端侧多模态能力缺失 | v2.5 评估 MLX Android / NNAPI 路径 |
| JNI 累积器 thread_local 兜底 | 多线程 JNI 调用存在状态隔离风险 | v2.0 重构为显式上下文句柄 |

### 风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| App Store 审核被拒（工具权限） | 中 | 延迟上架 | 提前与审核团队沟通，准备权限说明文档 |
| 多平台维护成本 | 高 | 迭代速度下降 | 抽象跨平台组件库，减少 `#if os` 分支 |
| 端侧多模态内存预算 | 高 | 多模态并发 OOM | 全局内存预算器、超限自动降级 |
| visionOS 生态不确定 | 中 | ROI 不足 | 共享 70% 代码、控制投入 |
| 社区插件安全审核 | 高 | 恶意插件 | 签名校验 + 沙箱隔离 + 市场审核 |
| Apple Intelligence API 变动 | 中 | 兜底失效 | 保留 SD 路径作为备选 |
