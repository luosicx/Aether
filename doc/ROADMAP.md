# Aether 路线图

> 本文档描述 Aether（以太）在 Day 20 之后的演进方向与里程碑。优先级：P0（必须） / P1（重要） / P2（增强）。
> 品牌愿景：**无形，无处不在，智能**——Aether 致力于成为最懂用户的端侧 AI 助手，以液态玻璃 + 深空美学为视觉语言，覆盖 iOS / iPad / macOS 三端。

---

## 当前基线（Day 1-20 + 品牌重塑 + 优化）

### 工程基线

- iOS / iPad / macOS 三端原生 SwiftUI 渲染，`#if os(iOS)` 条件编译优雅降级
- **25 个工具**（14 跨平台 + 11 macOS 独有），ReAct 循环最大 5 轮
- **8 种语言** i18n（zh-Hans / zh-Hant / en / ja / ko / fr / de / es），887 keys
- **2092 UT** + 30 UIT，0 failures / 0 skips
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

- [ ] MCP（Model Context Protocol）客户端接入
- [ ] 支持外部 MCP Server 动态发现与连接
- [ ] MCP 工具自动注册到 ToolRegistry
- [ ] MCP 资源（Resources）与提示词（Prompts）模板支持

### G.2 长期记忆系统

- [ ] 跨会话长期记忆向量库（remember / recall）
- [ ] 用户偏好自动提取与持久化（UserPreference @Model 扩展）
- [ ] 上下文窗口管理：重要消息压缩 + 过期消息摘要
- [ ] 语义记忆检索：基于 embedding 相似度召回历史对话

### G.3 Agent 任务规划

- [ ] 多步目标分解（Goal → SubTasks → Actions）
- [ ] Agent 任务编排引擎（DAG 执行图）
- [ ] 任务状态持久化与断点续执行
- [ ] 多 Agent 协作（多个 LLM 角色分工）

### G.4 插件系统

- [ ] 插件化工具市场（外部工具动态注册，无需重新编译）
- [ ] 插件沙箱隔离与权限管理
- [ ] 插件版本管理与热更新
- [ ] 社区插件分发渠道

---

## Phase H：体验与设计升级（P1）

> 目标：将液态玻璃 + 深空美学推向极致，建立行业标杆级 AI 助手视觉体验。

### H.1 设计系统深化

- [x] Aether 色彩 / 字体 / 圆角 Token 体系（已完成）
- [x] 深色模式默认 + 液态玻璃 UI（已完成）
- [ ] 动画与过渡效果统一（AnimationTokens 全面应用）
- [ ] 自定义图标集（SF Symbols 之外的 Aether 专属图标）
- [ ] 响应式布局适配（iPhone SE / iPad Pro / macOS 超宽屏）

### H.2 交互升级

- [ ] macOS 多窗口与拖拽支持（多对话并行）
- [ ] 对话分支与版本管理（对话树）
- [ ] 富媒体消息支持（卡片 / 链接预览 / 内嵌图表）
- [ ] 手势快捷操作（滑动删除 / 长按菜单 / 拖拽排序）
- [ ] macOS 菜单栏常驻模式（MenuBarExtra）

### H.3 个性化

- [x] 主题切换（深空 / 黎明 / 极光等多套色彩主题）（已完成基础主题切换）
- [x] 自定义头像与 AI 人设（已完成 PhotosPicker 头像选择器）
- [x] 对话气泡样式可选（液态玻璃 / 极简 / 卡片）（已完成气泡样式切换）
- [x] 字体大小与行距可调（已完成字体与间距设置）

---

## Phase I：端侧多模态与本地化（P2）

> 目标：让 Aether 在无网络环境下也能提供丰富的多模态 AI 能力。

### I.1 端侧多模态

- [ ] 端侧视觉理解（CLIP / LLaVA 离线模型）
- [ ] 端侧语音识别（Whisper / Speech 库离线 STT）
- [ ] 端侧图像生成（Stable Diffusion Mobile / Draw Things API）
- [ ] 端侧 TTS 自然语音合成（超过 AVSpeechSynthesizer 默认音色）

### I.2 本地化扩展

- [x] 新增日语 / 韩语 / 法语 / 德语 / 西班牙语支持（已完成 8 种语言）
- [ ] 区域化模型推荐（中国区推荐 Qwen，海外推荐 Llama）
- [ ] RTL 语言支持（阿拉伯语 / 希伯来语）
- [ ] 本地化文案质量审计（母语审校）

---

## Phase J：跨设备协同与生态（P2）

> 目标：构建 Aether 生态系统，实现跨设备无缝协作。

### J.1 跨设备同步

- [ ] 对话历史 iCloud 同步（CloudKit / NSPersistentCloudKitContainer）
- [ ] 跨设备连续对话（Handoff）
- [~] watchOS 独立 App（无需 iPhone 配对）（源代码已就绪，需手动创建 Xcode target）
- [ ] visionOS 适配（空间计算体验）

### J.2 协作与分享

- [ ] 团队知识库共享（组织级 RAG 知识库）
- [ ] 对话分享与导出（Markdown / PDF / 链接）
- [ ] 对话模板与预设角色市场
- [ ] Web / Android 伴侣应用（跨平台数据互通）

### J.3 开发者生态

- [ ] Aether SDK（第三方应用集成 Aether AI 能力）
- [x] URL Scheme 与 x-callback-url 支持（已完成 `aether://` DeepLink）
- [ ] Shortcuts 深度集成（更多 App Intents）
- [ ] 开发者文档与示例代码

---

## 品牌愿景与 Liquid Glass 演进路径

### 愿景

**Aether（以太）** 取自古希腊神话中的天空之神，象征着**无处不在的纯粹能量**。Aether AI 助手致力于成为用户数字生活中「无形而无处不在」的智能伙伴——在你需要时即刻出现，在你不注意时默默学习，以最自然的方式融入日常。

### Liquid Glass 演进

| 阶段 | 特征 | 状态 |
|------|------|------|
| v1.0 | 深空背景 + 液态玻璃卡片 + 紫蓝渐变 | ✅ 已完成 |
| v1.1 | 动态星空背景（粒子动画）+ 毛玻璃深度分层 | 🔜 计划中 |
| v1.2 | 流体动画（消息气泡液态进出）+ 光晕呼吸效果 | 📋 设计中 |
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
| v1.0 | App Store 首发 | 工程化完善、审核通过、首版上架 | 2026 Q3 |
| v1.1 | 智能体增强 | MCP 接入、长期记忆、Agent 规划 | 2026 Q4 |
| v1.2 | 设计升级 | 动画统一、多窗口、个性化主题 | 2027 Q1 |
| v1.3 | 端侧多模态 | 离线视觉/语音/图像生成 | 2027 Q2 |
| v2.0 | 跨端协作 | iCloud 同步、Web 伴侣、团队协作 | 2027 Q3 |
| v3.0 | 生态平台 | SDK、插件市场、visionOS | 2028 |

---

## 技术债务与风险

### 已知技术债务

| 债务项 | 影响 | 计划 |
|--------|------|------|
| ChatViewModel 圈复杂度高 | processMessage 难以维护 | v1.1 重构为状态机模式 |
| MLX 流式输出为假流式 | 端侧推理体验不佳 | v1.3 实现真 token 流式 |
| BFF 令牌桶仅客户端 | 可被绕过 | v2.0 服务端限流强化 |
| SwiftUI 长列表性能 | 100+ 消息可能掉帧 | v1.2 虚拟化列表 |

### 风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| App Store 审核被拒（工具权限） | 中 | 延迟上架 | 提前与审核团队沟通，准备权限说明文档 |
| MLX 端侧推理内存不足 | 高 | 端侧功能不可用 | 动态内存检测 + 模型降级推荐 |
| DeepSeek API 限流 | 中 | 用户体验下降 | SmartRouter 自动切换 + 语义缓存 |
| 多平台维护成本 | 高 | 迭代速度下降 | 抽象跨平台组件库，减少 `#if os` 分支 |
