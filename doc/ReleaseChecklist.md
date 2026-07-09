# AI Builder 上架前发布检查清单

> Day 20 上架准备：Archive / TestFlight / App Store 元数据 / 审核信息 / 提交审核前最终检查

## 1. Archive 检查

- [ ] Xcode 中 Scheme 选择 `AIBuilder` → Destination 选 `Generic iOS Device`（Any iOS Simulator Device 亦可触发 Archive）
- [ ] Product → Archive，等待归档完成
- [ ] 验证 Archive 过程中无 warning（特别注意：隐私清单缺失 / Info.plist 引用错误 / unused import）
- [ ] 在 Xcode Organizer 中确认生成的 `.xcarchive` 文件有效

## 2. TestFlight 上传

- [ ] Xcode Organizer → 选择最新 Archive → Distribute App
- [ ] 分发方式选择 `TestFlight App Store`（内部测试）
- [ ] 上传选项：保持默认（Include bitcode for iOS content / Upload symbols）
- [ ] 等待 Apple 处理（通常 10-30 分钟）
- [ ] 在 App Store Connect → TestFlight 标签确认构建版本已出现
- [ ] 邀请内部测试员并完成首次安装验证

## 3. App Store 元数据

### 3.1 基本信息
- [ ] **名称**：AI Builder（30 字符内，符合 App Store 命名规范）
- [ ] **副标题**：AI 对话助手（30 字符内，突出核心功能）
- [ ] **描述**：覆盖 SwiftUI + SwiftData + 流式对话 / RAG / 工具调用 / 健康洞察等核心特性
- [ ] **关键词**：AI / Chat / 对话 / 助手 / 健康（100 字符内，逗号分隔）
- [ ] **推广文本**：可选，用于临时公告（170 字符内）

### 3.2 截图与预览
- [ ] **6.7" 截图**（iPhone 14 Pro Max / 15 Pro Max）：至少 1 张，建议全部 5-10 张
  - 主对话页 / 设置页 / 健康洞察 / 知识库 / 端侧推理
- [ ] **6.1" 截图**（iPhone 15 Pro）：至少 1 张
- [ ] **App 预览视频**（可选）：30 秒内，展示流式对话核心交互

### 3.3 其他
- [ ] **App 分类**：Productivity 或 Utilities
- [ ] **版权**：© 2026 [开发者/公司名]
- [ ] **URL**：可选，指向产品官网
- [ ] **支持 URL**：指向 feedback@aibuilder.app 或支持页面

## 4. 审核信息

- [ ] **年龄分级**：4+（无不适内容，需在 App Store Connect 中确认问卷）
- [ ] **隐私清单**：在 App Store Connect → App 隐私中如实填写
  - 收集数据类型：对话内容 / 健康数据 / 性能数据 / 崩溃数据
  - 用途：App 功能 / 分析
  - 与用户身份关联：是
  - 用于追踪：否
- [ ] **隐私政策 URL**：指向 App 内隐私政策或可访问的网页版本
- [ ] **权限说明**：Info.plist 中已声明 NSHealthShareUsageDescription / NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription / NSRemindersUsageDescription / NSCalendarsUsageDescription
- [ ] **第三方 SDK 声明**：Bugly / DeepSeek API / Qwen API（在隐私清单中如实披露）
- [ ] **新功能测试方式说明**（建议在审核备注中向 Apple 说明以下新功能的验证路径）：
  - **TTS 音色配置**：进入 设置 → 语音朗读，选择不同音色（系统内置 / AVSpeechSynthesisVoice），调节语速 / 音调 / 音量滑块，点击「试听」预览，发送一条助手回复并点击朗读，验证朗读使用所选音色与参数
  - **Markdown 渲染**：发送一条可触发包含代码块（```swift）、表格、任务列表（- [ ]）、多级标题（#/##/###）的助手回复，验证代码块语法高亮、表格对齐、任务列表勾选状态、标题层级缩进渲染正确
  - **端侧 MLX 模型下载**：进入 设置 → 端侧推理，选择模型（如 Qwen2.5-0.5B-Instruct）开始下载，验证下载进度条更新、中断后重启可断点续传、下载完成自动执行 SHA256 校验；关闭网络后发起对话，验证自动切换为端侧推理并在 UI 标识
  - **HealthKit 授权**：首次进入 设置 → 健康洞察，验证系统弹出 HealthKit 授权弹窗并请求心率 / 睡眠 / 步数读取权限；授权后下拉刷新健康洞察，验证数据读取成功；在对话中验证健康上下文已注入 system prompt（助手可引用近 7 天健康数据）

### 4.1 构建验证
- [ ] iOS 构建：`xcodebuild build -destination 'platform=iOS Simulator,name=iPhone 17'` 成功
- [ ] macOS 构建：`xcodebuild build -destination 'platform=macOS'` 成功
- [ ] 双端构建均无警告（或警告已审查）

### 4.2 工具数量审计
- [ ] iOS 工具数：13 个（4 原有 AlarmTool/ReminderTool/DateTimeTool/CalculatorTool + 6 跨平台 LocationTool/DeviceInfoTool/ClipboardTool(含 Read+Write 两个)/OpenURLTool/ContactsTool/WeatherTool + 3 快捷指令 RunShortcutTool/ListShortcutsTool/CreateShortcutTool）
- [ ] macOS 工具数：24 个（iOS 13 个 + 11 macOS 独有 AppleScriptTool/ScreenshotTool/OCRTool/TerminalCommandTool/WindowManagementTool/AppManagementTool/FileOperationTool/FinderTool/SafariControlTool/SystemControlTool/InputAutomationTool）
- [ ] ToolRegistry.swift 注册数验证：跨平台工具无条件注册，macOS 独有工具用 `#if os(macOS)` 条件注册

### 4.3 测试规模
- [ ] UT 用例数：248
- [ ] UIT 用例数：13（之前 12 + 新增 1）
- [ ] iOS UT 运行：`xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` 全部通过（0 skipped，0 failures）
- [ ] UIT 运行全部通过（0 failures）

### 4.4 预设提示词功能验证
- [ ] 11 个预设角色可正常选择并填入 TextEditor
- [ ] 每个预设 prompt ≥ 150 字（默认助手除外）
- [ ] 预设填入后可编辑
- [ ] PresetPromptsTests 4 个用例通过

### 4.5 macOS 体验修复验证
- [ ] macOS 设置二级页有返回按钮可关闭
- [ ] macOS markdown 表格/气泡视觉层次正常
- [ ] macOS 语音朗读不卡顿、按钮状态正常
- [ ] iOS 端不受影响

### 4.6 工具项中文化验证
- [ ] Settings 偏好工具列表显示中文 description
- [ ] preferredTools 存储仍用英文 name

### 4.7 代码注释验证
- [ ] 18 个工具文件有文件级 `///` 注释
- [ ] ToolRegistry.swift 有注册逻辑注释

## 4.8 国际化与无障碍审计

- [ ] `Localizable.xcstrings` 包含 385 keys，en / zh-Hans / zh-Hant 三者完整
- [ ] 设置 → 语言切换后重启，英文/繁体界面无残留中文
- [ ] VoiceOver 可朗读设置页所有 Toggle / Picker / Button
- [ ] 所有关键交互控件存在 `accessibilityIdentifier`（供 UITest 使用）

## 4.9 截图与元数据审计

- [ ] `screenshots/` 目录包含 8 张核心页面截图
- [ ] README.md 截图表格渲染正常
- [ ] App Store Connect 已上传 6.7" / 6.1" / iPad / macOS 截图

## 4.10 多平台构建验证

### iOS 构建
- [ ] 执行命令构建 iOS Simulator 版本：
  ```bash
  xcodebuild build \
    -project AIBuilder.xcodeproj \
    -scheme AIBuilder \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO
  ```
- [ ] 预期输出：`** BUILD SUCCEEDED **`
- [ ] 无 warning（特别注意 unused import / deprecated API）

### macOS 构建
- [ ] 执行命令构建 macOS 版本：
  ```bash
  xcodebuild build \
    -project AIBuilder.xcodeproj \
    -scheme AIBuilder \
    -destination 'platform=macOS' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO
  ```
- [ ] 预期输出：`** BUILD SUCCEEDED **`
- [ ] macOS 独有工具用 `#if os(macOS)` 守卫，iOS 构建不报错
- [ ] iOS-only 框架（BGTaskScheduler / ActivityKit / HealthKit / WatchConnectivity）用 `#if os(iOS)` 守卫，macOS 构建不报错

## 4.11 工具数量审计

- [ ] iOS 工具数 = 13（DateTimeTool / CalculatorTool / AlarmTool / ReminderTool + 6 跨平台 + 3 快捷指令）
- [ ] macOS 工具数 = 24（上述 13 + 11 macOS 独有）
- [ ] 验证命令：
  ```bash
  # 在 Xcode 中运行 Debug Playground 或在 ChatViewModel 加日志：
  # print("Tools count: \(ToolRegistry.shared.allToolDefs.count)")
  ```
- [ ] 预期：iOS 13，macOS 24
- [ ] ToolRegistry 注册逻辑：14 个跨平台工具无条件注册 + 11 个 macOS 工具用 `#if os(macOS)` 条件注册

## 4.12 测试规模审计

### 单元测试（UT）
- [ ] UT 用例数 = 248（248 pass / 0 skip / 0 failures）
- [ ] UT 文件数 = 69
- [ ] 验证命令：
  ```bash
  xcodebuild test \
    -project AIBuilder.xcodeproj \
    -scheme AIBuilder \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:AIBuilderTests \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  ```
- [ ] 预期输出包含：`Executed 248 tests, with 0 failures, 0 skipped`

### UI 测试（UIT）
- [ ] UIT 用例数 = 13（13 pass / 0 skip / 0 failures）
- [ ] UIT 文件数 = 2
- [ ] 验证命令：
  ```bash
  xcodebuild test \
    -project AIBuilder.xcodeproj \
    -scheme AIBuilder \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:AIBuilderUITests \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  ```
- [ ] 预期输出包含：`Executed 13 tests, with 0 failures, 0 skipped`

## 4.13 文档完整性审计

- [ ] `doc/ARCHITECTURE.md` 存在且章节完整（1-8）
- [ ] `doc/USAGE.md` 存在且章节完整（1-10）
- [ ] `doc/MANUAL_TEST_CHECKLIST.md` 存在且手测项完整
- [ ] `doc/ReleaseChecklist.md` 存在且 4.1-4.14 审计项完整
- [ ] `doc/BFF_DEPLOYMENT.md` 存在且部署步骤完整
- [ ] `doc/CONTRIBUTING.md` 存在（贡献指南）
- [ ] `doc/CHANGELOG.md` 存在（变更日志）
- [ ] `doc/API.md` 存在（API 契约文档）
- [ ] `README.md` 详细文档章节含 8 个文档链接
- [ ] 文档间交叉引用链接全部有效（点击不报 404）

## 4.14 国际化与无障碍审计

### 国际化
- [ ] `Localizable.xcstrings` 存在且已注册到 Resources build phase
- [ ] `developmentRegion = zh-Hans`，`knownRegions` 含 `zh-Hans` / `en` / `Base`
- [ ] SwiftUI `Text`/`Button`/`TextField` 字面量在构建后自动提取到 String Catalog
- [ ] 验证命令：
  ```bash
  # 构建后检查 .xcstrings 是否被编译为 .loctable
  ls ~/Library/Developer/Xcode/DerivedData/AIBuilder-*/Build/Products/Debug-iphonesimulator/AIBuilder.app/*.lproj/
  ```

### 无障碍
- [ ] 13 个视图含 `accessibilityLabel`（MarkdownText / CodeBlockView / MarkdownTableView / HeadingView / ErrorOverlay / CitationCard / ConversationRow / OnDeviceModelView / KnowledgeBaseView / HealthSettingsView / PrivacyPolicyView / DocumentPickerView / PresetPrompts）
- [ ] 13 个关键交互元素含 `accessibilityIdentifier`（sendButton / messageInputField / voiceInputButton / knowledgeBaseButton / settingsButton / conversationListButton / newConversationButton / importDocumentButton / downloadModelButton / deleteModelButton / requestHealthAuthButton / thumbsUpButton / thumbsDownButton）
- [ ] VoiceOver 开启后能正确朗读各视图标签与提示

## 5. 提交审核前最终检查

### 5.1 功能验证
- [ ] **API Key 测试**：DeepSeek / Qwen 两个 provider 都能正常发起对话
- [ ] **网络异常测试**：断网时端侧推理自动切换，联网后切回云端
- [ ] **权限测试**：HealthKit / 麦克风 / 语音识别 / 日历 / 提醒事项均能在首次使用时弹窗授权
- [ ] **后台任务**：每日刷新 / 遥测上报 / 健康洞察生成均能在 BGTaskScheduler 中正常调度

### 5.2 稳定性验证
- [ ] **崩溃监控**：Bugly 已初始化，匿名用户 ID 已设置
- [ ] **错误上报**：LLM 错误已通过 CrashReportService 上报到 Bugly
- [ ] **日志上传**：TelemetryService 缓冲事件能批量上报到 BFF

### 5.3 隐私合规
- [ ] **PrivacyInfo.xcprivacy** 已包含在 Resources build phase
- [ ] **隐私清单中 API Reason**：UserDefaults (CA92.1) / FileTimestamp (C617.1) / SystemBootTime (35F9.1)
- [ ] **不追踪用户**：NSPrivacyTracking = false
- [ ] **数据收集最小化**：仅收集 App 功能与分析所需数据

### 5.4 可访问性
- [ ] VoiceOver 能正确朗读主要控件
- [ ] 动态字体（Dynamic Type）适配正常
- [ ] 高对比度模式 UI 可读

## 6. 提交审核

- [ ] 在 App Store Connect 选择构建版本 → 添加审核备注
- [ ] 审核备注中说明：测试账号（如有）/ 触发特定功能的方法（如端侧模型下载）/ HealthKit 测试方式
- [ ] 审核备注中追加新功能测试方式说明：
  - **TTS 音色配置**：设置 → 语音朗读，切换不同音色、调节语速 / 音调 / 音量、点击试听预览，验证朗读使用所选音色
  - **Markdown 渲染**：发送包含代码块 / 表格 / 任务列表 / 多级标题的助手回复，验证渲染正确
  - **端侧 MLX 模型下载**：设置 → 端侧推理中下载模型，验证下载进度、断点续传、SHA256 校验；断网后自动切换端侧推理
  - **HealthKit 授权**：首次进入健康设置请求授权，验证心率 / 睡眠 / 步数读取，验证健康上下文注入 system prompt
- [ ] 提交审核，等待 Apple 审核反馈（通常 24-48 小时）
