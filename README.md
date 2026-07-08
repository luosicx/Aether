# AIBuilder

> 基于 SwiftUI + DeepSeek API 的 AI Native iOS App，覆盖流式对话、RAG、工具调用、语音、多模态、灵动岛等能力。

## 截图

![主对话界面](screenshots/chat.png)
![设置面板](screenshots/settings.png)

## 核心功能

- 流式对话（SSE 打字机效果）
- 多轮对话与上下文记忆（SwiftData 持久化）
- RAG 本地知识库（PDF 导入 + 分块 + 余弦相似度检索）
- 工具调用 ReAct 循环（闹钟 / 提醒 / 时间 / 计算器）
- 语音输入与朗读（SFSpeechRecognizer + AVSpeechSynthesizer）
- 视觉多模态（PhotosPicker + DeepSeek Vision）
- 用户偏好记忆（语气 / 工具 / 自定义事实）
- 调试面板（查看 prompt / API 响应 / embedding / 工具调用）
- Live Activities 灵动岛
- BGTaskScheduler 后台触发
- 本地通知主动提醒

## 技术栈

- SwiftUI（`@Observable` / `@Bindable` / `@FocusState`）
- SwiftData（`@Model` / 自动迁移）
- DeepSeek API（chat completions SSE 流式 / embedding API / function calling tools）
- AVAudioSession / SFSpeechRecognizer / AVSpeechSynthesizer
- EventKit（闹钟 / 提醒）
- PhotosUI / NSExpression
- ActivityKit（Live Activities 灵动岛）
- BGTaskScheduler
- UserNotifications
- XCTest（113 个单元测试，覆盖 Service / Model / ViewModel / Core 全层）
- XCUITest（13 个 UI 测试，覆盖 12 个端到端流 + 1 个 launch）
- GitHub Actions CI（macos-14 + iPhone 17，result bundle + upload-artifact）

## 环境要求

- Xcode 16+
- iOS 17.0+
- macOS 14+（运行模拟器）
- DeepSeek API Key（用户在 https://platform.deepseek.com 申请）

## 快速开始

1. clone 仓库
2. 用 Xcode 打开 `AIBuilder.xcodeproj`
3. 运行 App，进入设置填入 DeepSeek API Key
4. 选择 iPhone 17 模拟器
5. `Cmd + R` 运行

## 项目结构

```
AIBuilder/
├── App/                    # App 入口
├── Core/                   # 核心协议与常量
│   ├── Actors/
│   ├── Constants/
│   ├── Extensions/
│   └── Protocols/          # ToolProtocol / LLMProvider
├── Models/                 # SwiftData 模型
│   ├── ChatChunk.swift
│   ├── ChatMessage.swift
│   ├── Conversation.swift
│   └── DocumentChunk.swift
├── Services/               # 服务层
│   ├── Auth/               # KeychainManager
│   ├── Cache/              # SemanticCache
│   ├── LLM/                # DeepSeekClient / SSEParser
│   ├── RAG/                # DocumentChunker / EmbeddingService / PDFExtractor / RAGService
│   ├── Storage/            # ChatStorage
│   ├── Tools/              # ToolRegistry（含 DateTimeTool / CalculatorTool / NotificationService） / AlarmTool / ReminderTool
│   └── Voice/              # VoiceService
├── ViewModels/             # MVVM ViewModel
├── Views/                  # SwiftUI 视图
│   ├── Chat/
│   ├── Components/
│   ├── Conversation/
│   ├── RAG/
│   └── Settings/           # SettingsView（含 DebugPanelView）
AIBuilderTests/             # 单元测试（25 个文件，113 用例）
AIBuilderUITests/           # UI 测试（2 个文件，13 用例）
doc/                        # 文档（ARCHITECTURE.md / USAGE.md / plans / 实战计划）
.github/workflows/ci.yml    # CI 配置
```

## 详细文档

- [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) — 架构总览（分层架构图 / 模块职责 / 数据流 / 关键设计决策 / 技术栈映射 / 测试架构）
- [doc/USAGE.md](doc/USAGE.md) — 使用指南（环境要求 / 快速开始 / 9 项核心功能使用流程 / 开发工作流 / CI 说明 / 权限说明 / FAQ）

## 测试说明

```bash
# 全量测试（UT + UIT）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

# 仅 UT（113 用例，8 skipped）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AIBuilderTests \
  CODE_SIGNING_ALLOWED=NO

# 仅 UIT（13 用例，3 skipped）
xcodebuild test \
  -project AIBuilder.xcodeproj \
  -scheme AIBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AIBuilderUITests \
  CODE_SIGNING_ALLOWED=NO
```

测试覆盖（按层分类）：

- **Service 层 UT**（17 文件）：DeepSeekClient / SSEParser / SemanticCache / DocumentChunker / EmbeddingService / RAGService / PDFExtractor / ChatStorage / KeychainManager / ToolRegistry / AlarmTool / ReminderTool / CalculatorTool / DateTimeTool / NotificationService / VoiceService
- **Model 层 UT**（4 文件）：ChatMessage / ConversationModel / StringTokenCount / APIConfig
- **ViewModel 层 UT**（4 文件）：ChatViewModel / ConversationListVM / KnowledgeBaseVM / SettingsViewModel
- **UIT**（2 文件，12 个端到端流 + 1 个 launch）：启动 / 会话列表 / 创建会话 / API Key 保存/删除 / RAG+Tools Toggle / 模型切换 / 系统提示词 / 用户偏好 / contextMenu / 搜索 / 错误条

## CI 说明

GitHub Actions 配置在 `.github/workflows/ci.yml`：

- **触发**：push 到 `main` + `pull_request`
- **runner**：macos-14
- **步骤**：checkout → `xcodebuild build` → `xcodebuild test -resultBundlePath TestResults.xcresult` → `upload-artifact@v4`（if: always() 确保失败也上传）
- **destination**：iPhone 17

## Roadmap

后续 Day 12-18 计划：

- **Day 12**：智能路由（按复杂度动态选择模型）+ 用户反馈闭环
- **Day 13**：通义千问 / Qwen 多模型抽象层
- **Day 14**：远程配置与遥测
- **Day 15**：BFF 代理层（Cloudflare Workers）
- **Day 16**：端侧 MLX 模型
- **Day 17**：watchOS 扩展
- **Day 18**：App Intents / Shortcuts / Spotlight

## License

MIT
