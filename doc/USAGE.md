# AIBuilder 使用文档

> AI Native App，基于 SwiftUI + DeepSeek API 构建，支持 iOS / iPad / macOS 三端原生。本文件描述环境要求、安装运行、API Key 配置、Day 1-20 全部用户可见功能（19 项核心能力）、多平台支持、工具能力清单、开发与测试工作流、CI、权限与常见问题。

## 目录

1. [环境要求](#1-环境要求)
2. [快速开始](#2-快速开始)
3. [配置 API Key](#3-配置-api-key)
4. [核心功能使用流程](#4-核心功能使用流程)
   - 4.1 [流式对话](#41-流式对话)
   - 4.2 [多轮对话与会话管理](#42-多轮对话与会话管理)
   - 4.3 [RAG 知识库](#43-rag-知识库)
   - 4.4 [工具调用 ReAct](#44-工具调用-react)
   - 4.5 [语音输入](#45-语音输入)
   - 4.6 [语音朗读 TTS](#46-语音朗读-tts)
   - 4.7 [视觉多模态](#47-视觉多模态)
   - 4.8 [用户偏好](#48-用户偏好)
   - 4.9 [调试面板](#49-调试面板)
   - 4.10 [Markdown 渲染](#410-markdown-渲染)
   - 4.11 [TTS 音色可调节](#411-tts-音色可调节)
   - 4.12 [消息复制与重新提问](#412-消息复制与重新提问)
   - 4.13 [批量多选删除会话](#413-批量多选删除会话)
   - 4.14 [HealthKit 健康洞察](#414-healthkit-健康洞察)
   - 4.15 [App Intents / Shortcuts 集成](#415-app-intents--shortcuts-集成)
   - 4.16 [BFF 代理层配置](#416-bff-代理层配置)
   - 4.17 [端侧推理 MLX](#417-端侧推理-mlx)
   - 4.18 [隐私政策与投诉反馈](#418-隐私政策与投诉反馈)
   - 4.19 [预设系统提示词](#419-预设系统提示词)
5. [多平台支持](#5-多平台支持)
6. [工具能力清单](#6-工具能力清单)
7. [开发工作流](#7-开发工作流)
8. [CI 说明](#8-ci-说明)
9. [权限说明](#9-权限说明)
10. [常见问题（FAQ）](#10-常见问题faq)

---

## 1. 环境要求

| 项 | 要求 | 说明 |
|---|---|---|
| Xcode | 16+ | 编译 SwiftData / Observation 等新 API |
| iOS Deployment Target | 17.0+ | 真机与模拟器均需 ≥ iOS 17 |
| macOS | 14+ | 运行 Xcode 16 与 iOS 模拟器 |
| DeepSeek API Key | 必备（云端模式） | 用户自行在 https://platform.deepseek.com 申请 |
| mlx-swift SPM 依赖 | 端侧推理可选 | 真机集成后启用 MLX，模拟器走占位实现 |

> 备注：本项目依赖 SwiftUI、SwiftData、ActivityKit、HealthKit、AppIntents、AVFoundation 等系统框架，无需安装额外第三方包（除端侧推理的可选 mlx-swift）。所有依赖均通过 Swift Package / 系统库提供。

---

## 2. 快速开始

```bash
# 1. clone 仓库
git clone <repo-url>
cd AIBuiler

# 2. 用 Xcode 打开
open AIBuilder.xcodeproj
```

在 Xcode 中：

1. 顶部 Scheme 选择 `AIBuilder`
2. 目标设备选择 **iPhone 17 模拟器**
3. 按 `Cmd + R` 运行

> **首次启动行为说明**：App 启动后**不会主动创建会话**（避免阻塞主线程与 body 重算打断 TextField）。仅当用户在底部输入框发送**第一条消息**时，才会创建首个 Conversation。
>
> 对应代码：`AIBuilder/Views/Chat/ChatView.swift` 中 `viewModel.loadConversations()` 注释明确说明「只 load 会话列表，不创建新对话」。

---

## 3. 配置 API Key

调用 DeepSeek / Qwen API 前必须先配置 API Key。

1. App 启动后进入主界面，点击**顶部工具栏的「设置」按钮**（齿轮图标，accessibilityLabel="设置"）打开设置页。
2. 滚动到 **「API 配置」Section**（按当前选中的供应商切换显示 DeepSeek / Qwen 输入框；端侧推理供应商则提示无需 API Key）。
3. 在 `SecureField` 中输入 API Key。
4. 点击 **「保存 API Key」** 按钮：
   - 调用 `KeychainManager.shared.saveAPIKey(_:)`
   - 存储方式：iOS Keychain，`kSecClassGenericPassword`
   - `kSecAttrService` = `com.aibuilder.apikey`，`kSecAttrAccount` = `apikey`
   - 保存采用「先 `SecItemDelete` 再 `SecItemAdd`」策略，幂等保存避免 `errSecDuplicateItem`
5. 点击 **「删除 API Key」**（destructive 样式按钮）：
   - 弹出 alert「删除 API Key」二次确认（按钮：取消 / 删除）
   - 确认后调用 `deleteAPIKey()`（幂等，无记录不报错）

> **DeepSeek API Key 申请地址**：https://platform.deepseek.com

对应代码：`AIBuilder/Services/Auth/KeychainManager.swift`、`AIBuilder/Views/Settings/SettingsView.swift`

---

## 4. 核心功能使用流程

共 19 项核心功能，每项给出「触发路径」「操作步骤」「预期行为」与「对应代码路径」。

### 4.1 流式对话

- **触发路径**：在底部输入框（`ChatInputBar`）输入消息 → 点击右侧「发送」按钮
- **预期行为**：
  - 走真实 SSE 流式：通过 `SSEParser` 解析 DeepSeek `stream=true` 返回的 chunk，文字逐字显示（打字机效果）
  - 真实流式按 SSE chunk 到达速度更新
  - **缓存命中时**走「假打字」模式：按 `4 字符 / 8ms` 速率从 `SemanticCache` 命中的完整回复逐段推送，保持 UI 状态机一致
- **对应代码**：`AIBuilder/Services/LLM/SSEParser.swift`、`AIBuilder/ViewModels/ChatViewModel.swift`（`streamingText` + `Task.sleep(nanoseconds: 8_000_000)` 即 8ms/4chars）

### 4.2 多轮对话与会话管理

- **触发路径**：点击工具栏「会话列表」按钮（accessibilityLabel="会话列表"）打开 sheet
- **操作步骤**：
  - 点击右上角「+」按钮「新建对话」创建新会话
  - 点击已有会话行切换到该会话
  - **长按**会话行触发 `contextMenu`，提供：重命名 / 置顶 / 删除
  - 顶部搜索框实时过滤会话标题（不区分大小写）
- **预期行为**：
  - 会话列表按 **置顶 + 创建时间** 排序
  - 搜索实时过滤
- **对应代码**：`AIBuilder/Views/Conversation/ConversationList.swift`、`AIBuilder/ViewModels/ConversationListVM.swift`、`AIBuilder/Views/Conversation/ConversationRow.swift`

### 4.3 RAG 知识库

- **触发路径**：设置页开启 **「启用 RAG 知识库」Toggle** → 主界面工具栏点击「知识库」按钮
- **导入流程**：
  1. 通过 `DocumentPickerView` 选择 PDF
  2. `PDFExtractor` 提取文本
  3. `DocumentChunker` 自动分块：`maxTokens = 512`、`overlap = 128`（实际取 `overlap * 4` 字符作为重叠文本）
  4. 分句使用 `NLTokenizer(unit: .sentence)`
  5. `EmbeddingService.embedBatch` 批量生成向量并写入 SwiftData
- **使用流程**：
  1. 回到主界面发送问题
  2. `RAGService.retrieve(query:topK:modelContext:apiKey:)` 检索 **topK = 5** 最相关分块
  3. 通过 `buildAugmentedContext` 拼接 `[1] [2]` 编号的参考 prompt
  4. 回复中包含 `CitationCard` 引用卡片
- **对应代码**：`AIBuilder/Services/RAG/*`、`AIBuilder/Views/RAG/*`、`AIBuilder/Views/Chat/CitationCard.swift`

### 4.4 工具调用 ReAct

- **触发路径**：设置页开启 **「启用工具调用」Toggle**
- **示例输入**：「5 分钟后提醒我开会」
- **预期行为**：
  - `StepCardView` 显示思维链：**Thought / Action / Observation**
  - ReAct 循环每轮发起一次 chat 请求，若返回 `tool_calls` 则执行工具后继续下一轮，否则结束循环
- **关键参数**（`ChatViewModel`）：
  - `maxReActLoops = 5`：最大循环轮次
  - `toolTimeout: TimeInterval = 15`：单工具执行超时 15 秒
- **超时行为**：
  - 通过 `ThrowingTaskGroup` 同时跑工具执行 + `Task.sleep(toolTimeout)`
  - 超时后抛出 `ToolTimeout` 错误，**标记该工具 `status = failed` 后继续下一轮 ReAct**，不中断循环
- **对应代码**：`AIBuilder/ViewModels/ChatViewModel.swift`、`AIBuilder/Services/Tools/ToolRegistry.swift`、`AIBuilder/Views/Chat/StepCardView.swift`

> 全部 24 个工具（按 macOS 计；iOS 13 个）的能力清单见 [§6 工具能力清单](#6-工具能力清单)。

### 4.5 语音输入

- **触发路径**：点击底部输入框左侧的麦克风按钮（图标在 `isRecording` 时切换为 `stop.fill`，否则 `mic.fill`）
- **权限**：首次使用需授权 **麦克风 + 语音识别** 两个权限
- **预期行为**：
  - `VoiceService.startRecording` 启动录音与识别
  - 实时将识别文本填入输入框
  - 再次点击同一按钮停止录音
- **技术栈**：`SFSpeechRecognizer` 中文识别
- **对应代码**：`AIBuilder/Services/Voice/VoiceService.swift`、`AIBuilder/Views/Chat/ChatInputBar.swift`

### 4.6 语音朗读 TTS

- **触发路径**：点击**助手消息气泡右下角**的扬声器按钮
- **预期行为**：
  - `AVSpeechSynthesizer` 以中文朗读该条消息
  - 再次点击同一按钮停止朗读
  - 点击其他消息的扬声器按钮会**中断当前朗读**并切换到新消息
- **对应代码**：`AIBuilder/Services/Voice/VoiceService.swift`、`AIBuilder/Views/Chat/MessageBubble.swift`

### 4.7 视觉多模态

- **触发路径**：点击输入框左侧的附件按钮 → `PhotosPicker` 选择图片（`.images` 类型）
- **预期行为**：
  - 选中后图片预览显示在输入框上方
  - 发送时图片以 base64 编码
  - 请求 `content` 字段改为数组结构 `[text, image_url]`（多模态消息格式）
- **对应代码**：`AIBuilder/Views/Chat/ChatInputBar.swift`（`PhotosPicker(selection:matching:.images)`）、`AIBuilder/ViewModels/ChatViewModel.swift`

### 4.8 用户偏好

- **触发路径**：设置页 → 滚动到 **「用户偏好」Section**
- **可配置项**：
  - **语气 Picker**：默认 / 正式 / 轻松
  - **偏好工具 Toggle**（多选）：选项从 `ToolRegistry.allToolDefs` 动态生成，列表中显示**中文描述**（如「获取当前设备地理位置与逆地理编码结果」），而非英文函数名（如 `get_location`），便于用户理解；选中后注入到 system prompt 中的仍是**英文函数名**（如「偏好工具：get_location、get_weather」），供 LLM 识别调用
  - **自定义事实 TextEditor**：例如「我是素食者」
- **持久化**：
  - 点击「完成」→ `onDisappear` 时写入 SwiftData `UserPreference` 实体
  - 用户偏好内容注入到 systemPrompt
- **对应代码**：`AIBuilder/Views/Settings/SettingsView.swift`、`AIBuilder/ViewModels/SettingsViewModel.swift`

### 4.9 调试面板

- **触发路径**：设置页 → **「调试面板」Section** → 点击 **「查看调试信息」**
- **预期行为**：sheet 展示 `DebugPanelView`，包含以下 Section：
  1. **性能指标**：从 `PerformanceMonitor.shared` 异步读取各项操作的耗时（ms），可清除
  2. **远程配置 / 遥测**：展示 `RemoteConfigService` 当前配置版本 / 拉取时间 / 默认供应商 / 维护模式 / 缓冲事件数 / 上次上报时间与状态，提供「立即上报」「重新拉取配置」按钮
  3. **供应商与降级**：当前供应商 / 选中模型 / 上一次请求是否触发降级
  4. **最近 Prompt JSON**：展示 `lastDebugInfo.promptJSON`（等宽字体，可选中复制）
  5. **API 原始响应**：展示 `lastDebugInfo.apiResponse`
  6. **Embedding 维度**：展示 `lastDebugInfo.embeddingDimension`（例如「1024 维」）
  7. **工具调用**：列出每次工具调用的 toolName / arguments / result
- **对应代码**：`AIBuilder/Views/Settings/SettingsView.swift`（`DebugPanelView`）

### 4.10 Markdown 渲染

- **触发路径**：助手消息回复中包含 Markdown 标记时自动渲染（无需手动触发）
- **操作步骤**：发送任何请求，让 AI 返回带 Markdown 语法的回复
- **预期行为**：助手消息气泡通过 `MarkdownText` 解析为多种 block 类型并分别渲染：
  - **代码块**：用 \`\`\` 包裹的代码段，识别首行作为语言标签（如 \`\`\`swift），通过 `CodeBlockView` 渲染深色背景 + 等宽字体 + 圆角 + 横向滚动 + 顶部语言标签栏
  - **语法高亮**：`CodeSyntaxHighlighter` 基于正则匹配关键字 / 字符串 / 注释 / 数字，使用类似 Xcode 深色主题配色；**支持 11 种语言**：Swift、Python、JavaScript、JSON、Java、Kotlin、Go、Rust、C、C++、SQL（未知语言尝试大小写不敏感匹配所有关键字合集）
  - **表格**：连续 `|` 分隔的行通过 `MarkdownTableParser` 解析为 `MarkdownTable`（含表头、对齐方式与数据行），由 `MarkdownTableView` 渲染为横向滚动表格，奇偶行交替背景
  - **任务列表**：以 `- [x]` 或 `- [ ]` 开头的行通过 `TaskListView` 渲染，完成项显示 `checkmark.circle.fill` 蓝色图标 + 文本删除线
  - **标题分级**：`#` ~ `######`（H1-H6）通过 `HeadingView` 渲染，H1 用 `.title` 加粗、H2 用 `.title2` 加粗并附带分割线、H3 用 `.title3` 半粗、H4-H6 统一 `.body` 半粗
  - **普通文本**：通过 `AttributedString(markdown:options:.full)` 解析行内 Markdown（粗体 / 斜体 / 链接 / 行内代码），支持文本选中复制
- **对应代码**：`AIBuilder/Views/Chat/MarkdownText.swift`、`AIBuilder/Views/Chat/CodeBlockView.swift`、`AIBuilder/Views/Chat/CodeSyntaxHighlighter.swift`、`AIBuilder/Views/Chat/HeadingView.swift`、`AIBuilder/Views/Chat/MarkdownTableParser.swift`、`AIBuilder/Views/Chat/MarkdownTableView.swift`、`AIBuilder/Views/Chat/TaskListView.swift`

### 4.11 TTS 音色可调节

- **触发路径**：设置页 → 滚动到 **「语音朗读」Section**
- **操作步骤**：
  1. 点击 **「音色」** NavigationLink 进入 `TTSVoicePickerView`
  2. 在按语言分组的列表中选择系统音色
  3. 返回设置页，拖动 **语速 Slider**（0~1，步进 0.05，默认 0.5）
  4. 拖动 **音调 Slider**（0.5~2.0，步进 0.1，默认 1.0）
  5. 拖动 **音量 Slider**（0~1，步进 0.05，默认 1.0）
  6. 点击 **「试听示例」** 按钮，用当前配置朗读示例句「你好,我是 AI Builder,很高兴为你服务。」
- **预期行为**：
  - 音色列表分组排序：**zh-CN 永远第一组**（含「系统默认」选项），其次 zh-TW / zh-HK，再 en-US，最后其他语言按字母序
  - 每行显示音色名、质量标签（标准 / 增强 / 优质 / 未知，对应 compact / enhanced / premium / unknown）、下载状态与选中 checkmark
  - 增强或优质音色首次使用时系统会自动下载，未下载时行尾显示「需下载」橙色标签
  - 选中后立即回写 `settingsVM.ttsConfig.voiceIdentifier` 并同步到 `chatViewModel.ttsConfig`，写入 UserDefaults（key=`ttsConfig`，JSON 编码）
  - Slider 拖动结束后同步到 ChatViewModel，朗读时使用最新配置
  - 试听按钮在朗读中显示「停止试听」，可中断
- **持久化**：`TTSConfig`（含 `voiceIdentifier` / `rate` / `pitchMultiplier` / `volume`）通过 `JSONEncoder` 序列化为 Data 写入 UserDefaults；读取失败时回退 `defaultValue`（系统默认 zh-CN、rate=0.5、pitch=1.0、volume=1.0）
- **对应代码**：`AIBuilder/Services/Voice/TTSConfig.swift`、`AIBuilder/Services/Voice/TTSVoiceCatalog.swift`、`AIBuilder/Views/Settings/TTSVoicePickerView.swift`、`AIBuilder/Services/Voice/VoiceService.swift`、`AIBuilder/Views/Settings/SettingsView.swift`

### 4.12 消息复制与重新提问

- **触发路径**：在消息列表中 **长按任意消息气泡** 触发 `contextMenu`（仅在非流式状态可用）
- **操作步骤**：
  - **用户消息**：长按弹出两个选项——「复制」（`doc.on.doc` 图标）与「重新提问」（`arrow.clockwise` 图标）
  - **助手消息**：长按仅弹出「复制」一项
- **预期行为**：
  - **复制**：调用 `UIPasteboard.general.string = message.content`，将消息内容写入系统剪贴板；同时在消息列表底部 overlay 显示 **toast「已复制」**，2 秒后自动消失（通过 `Task.sleep(for: .seconds(2))` 清空 `feedbackToast`）
  - **重新提问**：调用 `ChatViewModel.resendMessage(content:in:modelContext:)`，将原消息内容回填到 `inputText` 并立即触发 `sendMessage`，相当于以同样内容重新发起一次请求
- **对应代码**：`AIBuilder/Views/Chat/MessageBubble.swift`（`contextMenu` + `onCopy` / `onResend` 回调）、`AIBuilder/ViewModels/ChatViewModel.swift`（`resendMessage`）、`AIBuilder/Views/Chat/MessageListView.swift`（toast overlay 与剪贴板写入）

### 4.13 批量多选删除会话

- **触发路径**：会话列表 sheet 左上角 **「编辑」** 按钮（仅当存在会话时显示）
- **操作步骤**：
  1. 点击「编辑」进入编辑模式（按钮文案变为「完成」），右上角「+」按钮隐藏
  2. 每行左侧出现 **圆形 checkbox**（`checkmark.circle.fill` 蓝色 / `circle` 灰色），点击行切换选中状态
  3. 底部出现工具栏：左侧「全选 / 取消全选」按钮，右侧「删除选中(N)」destructive 按钮
  4. 点击「全选」一次性选中所有过滤后的会话，文案切换为「取消全选」
  5. 点击「删除选中(N)」→ 弹出 alert「批量删除」二次确认
  6. 确认后调用 `ConversationListVM.deleteConversations(_:)` 删除所有选中会话，清空选中集合并退出编辑模式
  7. 点击「完成」退出编辑模式并清空选中集合
- **预期行为**：
  - 编辑模式下点击会话行不再切换会话，而是切换选中状态
  - 「删除选中」按钮在选中集合为空时 disabled
  - 删除后 alert 文案为「确定删除选中的 N 个对话？删除后无法恢复。」
- **对应代码**：`AIBuilder/Views/Conversation/ConversationList.swift`（`isEditMode` / `selectedConversations` / `showBatchDeleteConfirm` 状态与底部 `safeAreaInset` 工具栏）、`AIBuilder/ViewModels/ConversationListVM.swift`（`deleteConversations`）、`AIBuilder/Views/Conversation/ConversationRow.swift`（`showsCheckbox` + `isSelected`）

### 4.14 HealthKit 健康洞察

- **触发路径**：设置页 → **「健康」Section** → 点击「健康管理」NavigationLink 进入 `HealthSettingsView`
- **操作步骤**：
  1. 在「授权状态」Section 点击 **「请求授权」** 按钮，向 HealthKit 申请读取心率 / 睡眠 / 步数权限（系统弹窗）
  2. 授权成功后「当前状态」显示「已授权」（绿色），失败显示「未授权」并提示错误
  3. 可点击「跳转系统设置」打开系统设置 App
  4. 在「健康上下文」Section 开启 **「注入健康上下文」Toggle**
  5. 在「洞察」Section 点击 **「立即生成洞察」** 按钮
- **预期行为**：
  - **健康上下文注入**：开启后发送消息时，system prompt 中会注入最近 24 小时的睡眠时长 / 平均心率 / 步数聚合数据，AI 会给出针对性建议
  - **立即生成洞察**：调用 `HealthInsightGenerator.generateInsight(days:7)`，读取最近 7 天 HealthKit 数据，构造 prompt（含平均 / 最高 / 最低心率、平均睡眠小时、平均步数）调用 LLM 生成 3 条建议，追加免责声明「⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。」，写入 SwiftData `HealthInsight` 实体，并通过 `UNUserNotificationCenter` 推送本地通知「健康洞察已生成」
  - 生成的洞察按时间倒序在「洞察」Section 列出，显示 `insightType` 标签、时间戳与内容（5 行截断）
  - 每天 09:00 由后台任务自动生成一次（见 `BGTaskScheduler` 标识 `com.aibuilder.daily-refresh`）
  - 未授权或设备不支持 HealthKit 时所有查询返回空数据（不抛错），洞察生成会写入「无数据」提示
- **对应代码**：`AIBuilder/Services/Health/HealthKitService.swift`、`AIBuilder/Services/Health/HealthInsightGenerator.swift`、`AIBuilder/Models/HealthInsight.swift`、`AIBuilder/Views/Settings/HealthSettingsView.swift`

### 4.15 App Intents / Shortcuts 集成

- **触发路径**：系统「快捷指令」App 中创建快捷指令，或对 Siri 说出注册短语
- **操作步骤与预期行为**：本 App 通过 `AppShortcutsProvider` 注册了 3 个 AppShortcut：
  1. **Ask AIBuilder**（短语：「向 AIBuilder 提问」/「问 AIBuilder」）
     - 接受一个 `query` 参数（用户问题）
     - 调用 `IntentChatService.shared.ask(query:)` 走真实 LLM 流程返回完整回复
     - 空回复兜底「AI Builder 未返回内容，请重试。」
     - API Key 未配置或 LLM 失败时返回「AI Builder 暂时无法回复：{错误描述}」（不抛错打断 Siri）
  2. **New Conversation**（短语：「新建对话 AIBuilder」/「新对话 AIBuilder」）
     - 创建独立的 `ModelContainer`（与主 App 同 schema，读写同一 SQLite 文件）
     - 插入新 `Conversation` 并 `context.save()`
     - 返回 `conversationId.uuidString` 供后续 intent / Handoff 使用
  3. **Switch Conversation**（短语：「切换会话 AIBuilder」/「查找会话 AIBuilder」）
     - 接受 `keyword` 参数
     - 用 `#Predicate { $0.title.localizedStandardContains(keyword) }` 查询 title 包含关键词的会话，按 `createdAt` 降序取首个
     - 未匹配时返回「未找到匹配会话」
- **对应代码**：`AIBuilder/AppIntents/AskAIBuilderIntent.swift`、`AIBuilder/AppIntents/NewConversationIntent.swift`、`AIBuilder/AppIntents/SwitchConversationIntent.swift`、`AIBuilder/Services/Intents/IntentChatService.swift`

### 4.16 BFF 代理层配置

- **触发路径**：设置页 → **「BFF 代理」Section**
- **操作步骤**：
  1. 开启 **「启用 BFF 代理」Toggle**（默认关闭）
  2. 在 `TextField` 中输入 BFF endpoint URL（如 `https://aibuilder-bff.example.com`），键盘类型为 `.URL`，关闭自动纠错与大小写自动转换；输入合法 URL 时回写，非法输入保持原值
  3. 在 `SecureField` 中输入 **BFF Token**（`textContentType=.password`）
  4. 用 Stepper 调整 **chat 限流（每分钟）**：范围 5...60，默认 20
  5. 用 Stepper 调整 **embed 限流（每分钟）**：范围 5...30，默认 10
- **预期行为**：
  - 启用后 LLM 请求经 BFF 网关（Cloudflare Workers）中转，**API Key 由服务端保护**，设备只持有 BFF Token
  - 请求 Header 携带 `X-BFF-Token`（鉴权）与 `X-Provider`（路由目标上游供应商，如 `deepseek` / `qwen`）
  - 请求体结构与 DeepSeekClient 一致，SSE 解析复用 `SSEParser`
  - HTTP 错误处理：**401 → "BFF Token 无效"**；**429 → 解析 `Retry-After` Header（缺省 60 秒）抛 `rateLimited`**；**5xx → "BFF 服务异常"**；其他 → `apiError`
  - 客户端令牌桶限流：`RateLimiter` actor 隔离，请求前先 `acquireChat` / `acquireEmbed`，耗尽抛 `rateLimited(retryAfter:60)`，每 60 秒补充至上限
  - 离开设置页时通过 `settingsVM.saveBFFConfig()` 持久化到 UserDefaults（key=`bff_config_cache`，JSON 编码）
- **对应代码**：`AIBuilder/Services/LLM/BFFProxyClient.swift`、`AIBuilder/Core/Models/BFFConfig.swift`、`AIBuilder/Services/LLM/RateLimiter.swift`、`AIBuilder/Views/Settings/SettingsView.swift`

### 4.17 端侧推理 MLX

- **触发路径**：设置页 → **「端侧推理」Section**
- **操作步骤**：
  1. 开启 **「启用端侧推理」Toggle**（默认关闭）
  2. 点击 **「管理端侧模型」** NavigationLink 进入 `OnDeviceModelView`
     - 「当前模型」Section：展示模型名、本地路径（已下载 / 未下载）、SHA256 校验状态
     - 「下载」Section：点击「下载模型」从 Hugging Face CDN 下载（默认 `Llama-3.2-1B-Instruct-4bit`，约 700MB），下载中显示进度条与「取消下载」按钮，每 200ms 轮询 `OnDeviceModelDownloader.shared.progress` 更新
     - 「管理」Section：「删除模型」按钮（destructive，未下载时 disabled）
     - 「切换模型」Section：Picker 可选 `Llama-3.2-1B-Instruct-Q4_K_M` / `Qwen2-0.5B-Instruct-Q4_K_M` / `Phi-3-mini-4k-instruct-Q4_K_M`
  3. 返回设置页，开启 **「断网自动切换」Toggle**（默认开启）
  4. 用 Stepper 调整 **maxTokens**：范围 128...2048，默认 512
  5. 用 Slider 调整 **temperature**：范围 0.0...1.0，默认 0.7
- **预期行为**：
  - 启用后断网时（`NetworkMonitor` 监听到 `.unavailable`）自动切换到 `MLXInferenceEngine` 本地推理，联网后切回云端
  - 模型加载流程：内存检查（设备需 ≥ 4GB 物理内存）→ 文件存在性检查 → SHA256 完整性校验（分块 4MB 读取）→ `ModelContainer.load`
  - 流式生成按 token yield，`Task.isCancelled` 时中断
  - **条件编译**：`#if canImport(MLX)`——真机集成 mlx-swift SPM 后调用真正 MLX API；模拟器或未集成时走占位实现，返回「端侧推理不可用：mlx-swift 未集成」
  - 离开设置页时 `settingsVM.saveOnDeviceConfig()` 持久化到 UserDefaults（key=`ondevice_config_cache`）
  - 错误类型 `OnDeviceError`：`insufficientMemory` / `modelNotFound` / `sha256Mismatch` / `loadFailed`
- **对应代码**：`AIBuilder/Services/OnDevice/MLXInferenceEngine.swift`、`AIBuilder/Services/OnDevice/OfflineLLMProvider.swift`、`AIBuilder/Services/OnDevice/OnDeviceModelDownloader.swift`、`AIBuilder/Views/OnDevice/OnDeviceModelView.swift`、`AIBuilder/Core/Models/OnDeviceConfig.swift`、`AIBuilder/Core/Models/OnDeviceError.swift`、`AIBuilder/Services/Network/NetworkMonitor.swift`

### 4.18 隐私政策与投诉反馈

- **触发路径**：设置页 → **「关于」Section**
- **操作步骤与预期行为**：
  - **隐私政策**：点击「隐私政策」NavigationLink 进入 `PrivacyPolicyView`，展示「AI Builder 隐私政策」（更新日期 2026年7月）包含四个段落：
    1. **数据收集范围**：对话内容（用于上下文与缓存）/ 健康数据（仅授权后读取，用于洞察）/ 使用统计（性能埋点与崩溃日志）
    2. **第三方 SDK**：DeepSeek API、阿里云百炼 Qwen API、Bugly 崩溃监控
    3. **用户权利**：查看已收集数据（调试面板）/ 删除对话记录 / 撤回 HealthKit 授权 / 关闭遥测上报
    4. **联系方式**：feedback@aibuilder.app
  - **投诉反馈**：点击「投诉反馈」按钮（envelope 图标）
    - 设备支持邮件时（`MFMailComposeViewController.canSendMail()` 为 true）弹出系统邮件 composer `MailComposerView`，预填收件人 `feedback@aibuilder.app`、主题「AI Builder 用户反馈」、正文末尾追加设备信息（设备型号 / iOS 版本 / App 版本与构建号）
    - 设备不支持邮件时降级为 `FeedbackService.shared.mailtoURL()` 构造 `mailto:` URL（subject 与 body 已 URL 编码），通过 `Environment(\.openURL)` 打开系统邮件 App
  - **版本号**：Section 末尾展示 `CFBundleShortVersionString (CFBundleVersion)` 等宽字体
- **对应代码**：`AIBuilder/Views/Settings/PrivacyPolicyView.swift`、`AIBuilder/Services/Feedback/FeedbackService.swift`（`MailComposerView` UIViewControllerRepresentable 桥接 `MFMailComposeViewController`）、`AIBuilder/Views/Settings/SettingsView.swift`

### 4.19 预设系统提示词

- **触发路径**：设置页 → 滚动到 **「功能与偏好」Section** → 「系统提示词」区域
- **预设角色 Menu**：在系统提示词 `TextEditor` 上方新增「预设角色」`Menu`，提供 11 个预设角色。点击 Menu 选择角色后，`TextEditor` 自动填入该角色的完整 system prompt，可继续编辑后点击「完成」保存
- **11 个预设角色**：

| # | 角色 | 定位说明 |
|---|---|---|
| 1 | 默认助手 | 通用 AI 助手，回答各类问题，语气友好中立 |
| 2 | 开发者 | 资深全栈工程师，擅长多语言 / 架构 / 坑点 / 方案对比，回答偏技术深度 |
| 3 | 学生 | 学习伙伴，以引导思考、举一反三的方式辅助理解概念与解题 |
| 4 | 白领 | 职场效率助手，擅长邮件 / 文档 / 会议纪要 / 日程等办公场景 |
| 5 | 管理者 | 团队管理顾问，侧重目标拆解、决策权衡、组织协同与项目推进 |
| 6 | 产品经理 | 产品设计与需求分析，擅长用户故事、PRD、原型评审与优先级排序 |
| 7 | 写作助手 | 文字创作伙伴，擅长润色、改写、文案、散文与结构优化 |
| 8 | 技术面试官 | 模拟面试场景，针对算法 / 系统设计 / 项目经验提问并点评 |
| 9 | 学习导师 | 学习路径规划与答疑，针对薄弱点给出练习建议与复习计划 |
| 10 | 翻译官 | 多语言互译，保留语义与风格，支持中英 / 中日 / 中韩等 |
| 11 | 健身教练 | 训练与营养建议，结合用户目标给出运动计划与饮食参考（非医疗建议） |

- **使用方式**：
  1. 进入「设置 → 功能与偏好 → 系统提示词」Section
  2. 点击「预设角色」Menu，从 11 个角色中选择一个
  3. `TextEditor` 自动填入该角色的完整 system prompt
  4. 在 `TextEditor` 中可继续编辑（增删改提示词内容）
  5. 点击「完成」保存
- **预期行为**：
  - 选中角色后 `TextEditor` 内容立即被替换为该角色的预设提示词
  - 保存后该 system prompt 会注入到每次对话的 system message 中
  - 与「用户偏好」其他配置（语气 / 偏好工具 / 自定义事实）共同拼接到最终 system prompt
- **对应代码**：`AIBuilder/Views/Settings/SettingsView.swift`、`AIBuilder/ViewModels/SettingsViewModel.swift`

---

## 5. 多平台支持

AIBuilder 已从 iOS-only 适配为 **iOS / iPad / macOS 三端原生**应用，基于 SwiftUI 原生渲染 + `#if os(iOS)` / `#if os(macOS)` 条件编译实现平台分流，**非 Mac Catalyst**。三端共享同一份 SwiftUI 代码与 SwiftData schema，仅在系统 API 差异处用条件编译分流。

### 5.1 支持平台

| 平台 | 渲染方式 | 主布局 | 说明 |
|---|---|---|---|
| iOS | SwiftUI 原生 | 单栏 `NavigationStack` | 含 HealthKit、BGTaskScheduler、ActivityKit 灵动岛、WatchConnectivity |
| iPad | SwiftUI 原生 | 双栏 `NavigationSplitView` | 自适应横屏 / 竖屏 |
| macOS | SwiftUI 原生（非 Catalyst） | 双栏 `NavigationSplitView` | 窗口 1000×700、菜单栏快捷键、⌘Enter 发送 |

### 5.2 iOS 端

- 单栏 `NavigationStack` 导航
- **HealthKit 健康洞察入口**：设置页「健康」Section（详见 [4.14](#414-healthkit-健康洞察)）
- **BGTaskScheduler 后台任务**：标识 `com.aibuilder.daily-refresh`，每日 09:00 自动生成健康洞察
- **ActivityKit 灵动岛**：`TimerActivityAttributes`（`NSSupportsLiveActivities = true`）
- **WatchConnectivity**：与配套 watchOS 端通信

### 5.3 iPad 端

- 双栏 `NavigationSplitView`，自适应横屏 / 竖屏
- 其余能力与 iOS 端一致

### 5.4 macOS 端

- **窗口默认尺寸 1000×700**（`frame(minWidth:minHeight:)`）
- **菜单栏快捷键**：
  - ⌘N 新建会话
  - ⌘K 搜索（会话列表）
  - ⌘, 打开设置
- **⌘Enter 发送消息**（Enter 为换行）
- **双栏 NavigationSplitView 布局**：`SettingsView` / `KnowledgeBaseView` 在 macOS 下使用 `NavigationSplitView` 双栏布局
- **设置二级页面可返回**：macOS 上点击设置中的二级项（如「TTS 音色选择」、「隐私政策」、「端侧模型管理」）进入二级页面后，页面顶部显示返回按钮（`<`），点击可返回到当前分类的根 Form。切换左侧 sidebar 分类时，右侧 detail 会自动回到该分类的根 Form
- **HealthKit 入口隐藏**：macOS 不支持 HealthKit，设置页「健康」Section 隐藏；但 `HealthInsight` 数据模型**保留注册**以维持 SwiftData schema 一致性（避免三端 schema 分裂），未来若 macOS 支持 HealthKit 可直接启用而无需迁移
- **BGTaskScheduler / ActivityKit / WatchConnectivity 优雅降级**：相关代码用 `#if os(iOS)` 包裹，macOS 编译期排除，运行期不触发

### 5.5 跨平台文件选择

- `DocumentPickerView` 用 SwiftUI 原生 `.fileImporter` 替代 UIKit `UIDocumentPickerViewController`，三端统一调用入口（RAG 知识库导入 PDF 复用此组件）

### 5.6 跨平台设备信息

- `FeedbackService` 用 `ProcessInfo` 替代 `UIDevice` 获取设备型号 / OS 版本，三端统一；电量与可用存储在 iOS 用 `UIDevice`、macOS 用 `ProcessInfo` 分流

---

## 6. 工具能力清单

开启「启用工具调用」后（见 [4.4](#44-工具调用-react)），LLM 通过 ReAct 循环调用以下工具。共 **24 个工具**（按 macOS 计；iOS 仅注册其中 13 个）。

> **平台可用性**：
> - **跨平台（iOS + macOS）**：4 原有 + 6 跨平台新增 + 3 快捷指令 = **13 个**，两端均可用
> - **macOS 独有**：**11 个**，用 `#if os(macOS)` 条件编译，iOS 上 `ToolRegistry` 不注册，LLM 不会看到其定义

> **工具项中文化展示**：在「设置 → 用户偏好 → 偏好工具」列表中，工具项以**中文描述**展示（如「获取当前设备地理位置与逆地理编码结果」），而非英文函数名（如 `get_location`），便于用户直观理解每个工具的用途。选中偏好工具后，注入到 system prompt 中的仍是**英文函数名**（如「偏好工具：get_location、get_weather」），以便 LLM 识别与调用。下方清单中「函数」列对应 LLM 实际调用的英文函数名。

### 6.1 原有工具（4 个）

| # | 工具名 | 函数 | 用途 |
|---|---|---|---|
| 1 | AlarmTool | — | 设闹钟（时间 + 标签），创建 `EKAlarm` |
| 2 | ReminderTool | — | 设提醒（标题 + 日期 `yyyy-MM-dd HH:mm`），创建 `EKReminder` |
| 3 | DateTimeTool | — | 查询当前日期时间 |
| 4 | CalculatorTool | — | 数学计算 |

### 6.2 跨平台新增工具（6 个）

| # | 工具名 | 函数 | 用途 |
|---|---|---|---|
| 5 | LocationTool | `get_location` | 获取当前位置坐标 + 反地理编码中文地址（`CLLocationManager` + `CLGeocoder`），10s 超时 |
| 6 | DeviceInfoTool | `get_device_info` | 设备型号 / OS 版本 / 电量 / 可用存储（iOS 用 `UIDevice`、macOS 用 `ProcessInfo`） |
| 7 | ClipboardTool | `read_clipboard` / `write_clipboard` | 读取 / 写入系统剪贴板（iOS `UIPasteboard` / macOS `NSPasteboard`） |
| 8 | OpenURLTool | `open_url` | 用系统默认方式打开 URL（浏览器、深链接、系统设置；iOS `UIApplication.shared.open` / macOS `NSWorkspace.shared.open`） |
| 9 | ContactsTool | `search_contacts` | 按姓名或电话号码搜索通讯录联系人（`CNContactStore`） |
| 10 | WeatherTool | `get_weather` | 查询城市天气（Open-Meteo 免费 API，无需 Key）；有 `city` 走 Geocoding 查坐标再查 Forecast，无 `city` 复用 `LocationTool`；`weather_code` 映射中文（0=晴 / 1-3=多云 / 45-48=雾 / 51-67=雨 / 71-77=雪 / 95-99=雷暴） |

### 6.3 macOS 独有工具（11 个）

> 以下工具用 `#if os(macOS)` 条件编译，**iOS 不可用**。

| # | 工具名 | 函数 | 用途 |
|---|---|---|---|
| 11 | AppleScriptTool | `run_applescript` | 执行任意 AppleScript 脚本 |
| 12 | ScreenshotTool | `take_screenshot` | 截屏保存 PNG 到临时目录，返回文件路径（`CGDisplayCreateImage`） |
| 13 | OCRTool | `extract_text_from_image` | 识别图片文字（`VNRecognizeTextRequest`，zh-Hans + en，`.accurate` 精度）；无 `image_path` 先截屏再识别 |
| 14 | TerminalCommandTool | `run_terminal_command` | 执行 shell 命令（`Process`，30s 超时）；危险命令防护拒绝 `rm -rf /` / `mkfs` / `dd if=` / `shutdown` / `reboot` |
| 15 | WindowManagementTool | `manage_window` | 窗口管理：`list` 列窗口 / `focus` 聚焦 / `move` 移动 / `resize` 调整大小 / `minimize` 最小化（`CGWindowListCopyWindowInfo` + `AXUIElement`） |
| 16 | AppManagementTool | `manage_app` | 应用管理：`launch` 启动 / `quit` 退出 / `activate` 激活 / `frontmost` 查最前 / `list_running` 列运行中（`NSWorkspace`） |
| 17 | FileOperationTool | `manage_file` | 文件操作：`list` 列文件 / `search` 搜索 / `copy` 复制 / `move` 移动 / `rename` 重命名 / `delete` 移废纸篓（`trashItem`）/ `info` 查信息（`FileManager`） |
| 18 | FinderTool | `finder_action` | Finder 操作：`get_selection` 获取选中项 / `reveal` 在 Finder 中显示 / `open` 打开（AppleScript + `NSWorkspace`） |
| 19 | SafariControlTool | `control_safari` | Safari 自动化：`list_tabs` / `get_url` / `navigate` / `run_js` / `new_tab` / `close_tab`（`NSAppleScript`）；`run_js` 需在 Safari 偏好开启「允许 AppleScript 中的 JavaScript」 |
| 20 | SystemControlTool | `system_control` | 系统控制：`get_brightness` / `set_brightness` / `get_volume` / `set_volume`（AppleScript） |
| 21 | InputAutomationTool | `simulate_input` | 输入模拟：`mouse_move` / `mouse_click` / `mouse_drag` / `key_type` / `key_combo` / `scroll`（`CGEvent`） |

### 6.4 快捷指令工具（3 个，跨平台）

| # | 工具名 | 函数 | 用途 |
|---|---|---|---|
| 22 | RunShortcutTool | `run_shortcut` | 运行快捷指令（参数 `name` + `input`）；macOS 用 `shortcuts run`，iOS 用 `NSUserActivity` 触发 |
| 23 | ListShortcutsTool | `list_shortcuts` | 列出快捷指令；macOS 用 `shortcuts list`，iOS 不支持返回提示 |
| 24 | CreateShortcutTool | `create_shortcut` | 创建快捷指令（参数 `name` + `action`（`open_url` / `run_script` / `show_text` / `copy_to_clipboard`）+ `url` / `script` / `text`）；构建 `WFWorkflow` plist 生成 `.shortcut` 文件，用 `NSWorkspace.open` 让 Shortcuts 应用导入 |

> **说明**：iOS 上可用工具 = 4 原有 + 6 跨平台 + 3 快捷指令 = **13 个**；macOS 独有 11 个在 iOS 不可用。

- **对应代码**：`AIBuilder/Services/Tools/ToolRegistry.swift` 及 `AIBuilder/Services/Tools/*` 各工具实现

---

## 7. 开发工作流

> 以下命令的 **cwd 为项目根目录**（即 `AIBuilder.xcodeproj` 所在目录）。

```bash
# 1. 本地构建
xcodebuild build \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

# 2. 运行 UT（217 用例，8 skipped）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:AIBuilderTests \
  CODE_SIGNING_ALLOWED=NO

# 3. 运行 UIT（12 用例，8 skipped）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:AIBuilderUITests \
  CODE_SIGNING_ALLOWED=NO

# 4. 全量测试（UT + UIT）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

### 当前测试规模

| 测试套件 | 用例总数 | skipped | failures |
|---|---|---|---|
| UT（`AIBuilderTests`） | 217 | 8 | 0 |
| UIT（`AIBuilderUITests`） | 12 | 8 | 0 |

### skipped 原因

- Keychain entitlement（模拟器环境）
- EventKit 权限相关用例
- `contextMenu` 长按在模拟器上行为不稳定
- HealthKit 真机数据相关用例
- MLX 端侧推理（模拟器无 mlx-swift）
- MFMailComposeViewController 仅真机可用

---

## 8. CI 说明

GitHub Actions 配置文件：`.github/workflows/ci.yml`

| 项 | 值 |
|---|---|
| 触发条件 | `push` 到 `main` 分支 + `pull_request` 到 `main` 分支 |
| runner | `macos-14` |
| destination | iPhone 17 模拟器 |
| 步骤 1 | `actions/checkout@v4` |
| 步骤 2 | `xcodebuild build`（Debug，`CODE_SIGNING_ALLOWED=NO`） |
| 步骤 3 | `xcodebuild test`（带 `-resultBundlePath TestResults.xcresult`） |
| 步骤 4 | `actions/upload-artifact@v4` 上传 `TestResults.xcresult`，`if: always()` 确保失败也上传 |

---

## 9. 权限说明

以下权限在 `AIBuilder/Resources/Info.plist` 中声明：

| Info.plist Key | 描述文案 | 对应功能 |
|---|---|---|
| `NSMicrophoneUsageDescription` | 用于语音输入功能 | `VoiceService.startRecording` 录音 |
| `NSSpeechRecognitionUsageDescription` | 用于语音识别功能 | `SFSpeechRecognizer` 识别 |
| `NSCalendarsUsageDescription` | 用于创建闹钟和日历事件提醒 | `AlarmTool` 创建 `EKAlarm` |
| `NSRemindersUsageDescription` | 用于创建提醒事项 | `ReminderTool` 创建 `EKReminder` |
| `NSHealthShareUsageDescription` | 用于读取健康数据生成洞察 | `HealthKitService` 读取心率 / 睡眠 / 步数 |
| `NSSupportsLiveActivities` | `true` | `TimerActivityAttributes` 灵动岛 |
| `BGTaskSchedulerPermittedIdentifiers` | `com.aibuilder.daily-refresh` | `AIBuilderApp` 每日刷新（健康洞察生成） |

---

## 10. 常见问题（FAQ）

### Q1: API Key 保存失败怎么办？

**A**：模拟器下 Keychain 通常正常工作。真机需要配置 `keychain-access-groups` entitlement。若保存失败，可在设置页查看 `saveMessage` 错误提示（`KeychainManager.saveAPIKey` 失败会抛出 `AppError.keychainError`，错误码对应 `OSStatus`）。

### Q2: 语音识别不可用？

**A**：模拟器对 `SFSpeechRecognizer` 支持有限，建议真机测试。真机首次使用需**同时授权麦克风 + 语音识别**两个权限（对应 `NSMicrophoneUsageDescription` 与 `NSSpeechRecognitionUsageDescription`）。

### Q3: RAG 检索无结果？

**A**：`DocumentChunker` 使用 `NLTokenizer(unit: .sentence)` 分句。在 iOS 模拟器上，对**重复英文文本**可能不分句，导致只产生 **1 块**。建议用真实 PDF 或多样化文本测试。检索侧 `RAGService.retrieve` 默认 `topK = 5`，且要求 `queryEmbedding` 非空，否则返回空数组。

### Q4: 工具执行超时？

**A**：单工具默认 **15 秒**超时（`toolTimeout = 15`）。超时后通过 `ThrowingTaskGroup` 抛出 `ToolTimeout` 错误，**标记 `status = failed` 后继续下一轮 ReAct**，不中断循环。如需调整，可修改 `ChatViewModel` 中的 `toolTimeout` 值。若循环达到 `maxReActLoops = 5` 仍无最终回复，会提示「工具调用循环超过 5 轮，已中止」。

### Q5: TTS 音色如何选择？为什么有些音色显示「需下载」？

**A**：进入「设置 → 语音朗读 → 音色」，列表按语言分组，**zh-CN 永远排第一组**（含「系统默认」选项）。每行显示音色名 + 质量标签（标准 / 增强 / 优质）+ 选中 checkmark。**增强（enhanced）与优质（premium）音色首次使用时系统会自动下载**，未下载完成时行尾显示「需下载」橙色标签，下载完成前选中会回退到系统默认 zh-CN。模拟器可用音色有限，建议真机测试以获得完整音色列表。配置存储在 UserDefaults（key=`ttsConfig`），读取失败回退默认值（zh-CN、rate=0.5、pitch=1.0、volume=1.0）。

### Q6: Markdown 不渲染 / 代码块不高亮？

**A**：助手消息通过 `MarkdownText` 自动渲染。常见原因：
1. **代码块未识别语言**：代码块首行需为语言标识（如 \`\`\`swift），不含空格。未知语言会尝试用所有关键字合集做大小写不敏感匹配，效果较弱。
2. **代码块语法错误**：必须用 \`\`\` 配对包裹，奇数个 \`\`\` 会导致解析异常。
3. **用户消息不渲染 Markdown**：仅助手消息走 `MarkdownText`，用户消息走纯 `Text`。
4. **流式中途不渲染**：流式过程中只显示纯文本 + 闪烁光标，**流式结束后**才完整渲染 Markdown。
5. **支持的高亮语言**：Swift / Python / JavaScript / JSON / Java / Kotlin / Go / Rust / C / C++ / SQL 共 11 种。

### Q7: BFF 代理返回 401 怎么办？

**A**：`BFFProxyClient` 在 HTTP 401 时会抛 `LLMError.llmErrorOccurred("BFF Token 无效")` 并发 `.llmErrorOccurred` 通知。请到「设置 → BFF 代理」检查：
1. **BFF Token 是否正确**：与服务端签发的令牌一致。
2. **endpoint URL 是否可达**：默认占位地址 `https://aibuilder-bff.example.com` 需替换为真实部署的 Cloudflare Workers 域名。
3. **Toggle 是否启用**：未启用时仍走直连 DeepSeek/Qwen，不会触发 401。
4. **限流（429）**：若返回 429，会解析 `Retry-After` Header（缺省 60 秒）抛 `rateLimited`，可在「chat 限流」Stepper 调低每分钟请求数。

### Q8: 端侧 MLX 模型下载失败 / 推理不可用？

**A**：常见原因与排查：
1. **模拟器无 mlx-swift**：`MLXInferenceEngine` 用 `#if canImport(MLX)` 条件编译，模拟器走占位分支返回「端侧推理不可用：mlx-swift 未集成」。**端侧推理仅在真机集成 mlx-swift SPM 后可用**。
2. **下载失败**：模型文件约 700MB，建议在 Wi-Fi 下下载。可在「管理端侧模型」页查看 `errorMessage`，支持「取消下载」与「删除模型」重试。
3. **SHA256 校验失败**：若 `OnDeviceConfig.expectedSHA256` 非空且与下载文件不匹配，会抛 `OnDeviceError.sha256Mismatch`。可清空 `expectedSHA256` 跳过校验或重新下载。
4. **内存不足**：设备物理内存需 ≥ 4GB，否则抛 `OnDeviceError.insufficientMemory`。
5. **断网未自动切换**：检查「断网自动切换」Toggle 是否开启，`NetworkMonitor` 监听到 `.unavailable` 时才会切换到端侧。

### Q9: HealthKit 授权失败 / 健康洞察为空？

**A**：
1. **设备不支持**：`HKHealthStore.isHealthDataAvailable()` 返回 false 时（如 iPad）抛 `HealthKitError.notAvailable`。
2. **授权被拒**：可在「健康管理 → 跳转系统设置」重新授权，或到「系统设置 → 隐私 → 健康」撤回 / 重新授权。
3. **模拟器无数据**：模拟器上 HealthKit 可授权但无真实数据，所有查询返回空字典，洞察会写入「无数据」提示。建议真机测试。
4. **注入未生效**：检查「注入健康上下文」Toggle 是否开启；未开启时 system prompt 不含健康数据。

### Q10: UIT 测试不稳定？

**A**：`contextMenu` 长按触发、Picker 导航式选项、邮件 composer 在模拟器上行为有差异，已用 `throw XCTSkip` 兜底跳过不稳定用例。**底层逻辑已由 UT 覆盖**（`ChatStorageTests` / `ConversationListVMTests` / `TTSConfigTests` / `TTSVoiceCatalogTests` 等）。当前 UIT 规模 12 用例（8 skipped，0 failures），UT 规模 217 用例（8 skipped，0 failures）。

### Q11: App Intents / Siri 调用无响应？

**A**：
1. **App 未在前台或最近使用**：AppIntent 由系统调度，可能需要先打开 App 一次。
2. **API Key 未配置**：`AskAIBuilderIntent` 在 LLM 失败时返回「AI Builder 暂时无法回复：{错误描述}」，不抛错打断 Siri。请到设置页配置 DeepSeek API Key。
3. **Siri 权限**：在「系统设置 → Siri 与搜索」中确认 AI Builder 已启用 Siri 快捷指令。
4. **短语识别**：尝试使用注册的标准短语「向 AIBuilder 提问」「新建对话 AIBuilder」「切换会话 AIBuilder」。

### Q12: macOS 上为什么没有 HealthKit 入口？

**A**：macOS 不支持 HealthKit，已在设置页隐藏「健康」入口。但 `HealthInsight` 数据模型**保留注册**以维持 SwiftData schema 一致性（避免三端 schema 分裂），未来若 macOS 支持 HealthKit 可直接启用而无需迁移。

### Q13: macOS 独有工具在 iOS 上能用吗？

**A**：不能。11 个 macOS 独有工具用 `#if os(macOS)` 条件编译，iOS 上 `ToolRegistry` 不注册这些工具，LLM 不会看到它们的定义，因此也不会尝试调用。iOS 上可用工具 = 4 原有 + 6 跨平台 + 3 快捷指令 = **13 个**（详见 [§6 工具能力清单](#6-工具能力清单)）。

### Q14: 如何创建快捷指令？

**A**：用 `CreateShortcutTool`（函数 `create_shortcut`），提供：
- `name`：快捷指令名称
- `action`：动作类型，支持 `open_url` / `run_script` / `show_text` / `copy_to_clipboard`
- 对应参数：`url` / `script` / `text`

工具会构建 `WFWorkflow` plist 生成 `.shortcut` 文件，并用 `NSWorkspace.open` 让 Shortcuts 应用打开导入。运行与列出快捷指令分别用 `RunShortcutTool`（`run_shortcut`）与 `ListShortcutsTool`（`list_shortcuts`）。

### Q15: TerminalCommandTool 会执行危险命令吗？

**A**：不会。工具检测以下危险模式并拒绝执行：
- `rm -rf /`
- `mkfs`
- `dd if=`
- `shutdown`
- `reboot`

命中任一模式即返回拒绝信息。此外，命令执行还有 **30 秒超时**保护，超时后中断进程。
