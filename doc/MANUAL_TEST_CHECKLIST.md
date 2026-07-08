# 手测确认清单

本文档汇总 Day 1-20 所有 spec 中无法通过自动化测试（UT/UIT）覆盖、需人工验证的功能点，按功能模块划分。

---

## 1. 基础对话与流式响应（Day 1-2）

- [ ] 发送消息后 SSE 流式打字机效果正常显示，无卡顿/丢字
- [ ] 多轮对话上下文保持（第 3 轮回复能引用第 1 轮内容）
- [ ] 新建/切换/删除会话功能正常，会话列表与 SwiftData 持久化一致
- [ ] 长按会话行触发 contextMenu（重命名/置顶/删除）

## 2. RAG 知识库（Day 3）

- [ ] 导入 .txt/.md/.pdf 文档后自动分块与向量化
- [ ] 开启 RAG 后发送相关问题，回复引用了知识库内容
- [ ] CitationCard 展示来源文档名与分块内容
- [ ] 关闭 RAG 后回复不引用知识库

## 3. 工具调用与 ReAct 循环（Day 4, 8）

- [ ] 「设一个 5 分钟后的提醒」→ StepCard 展示 thought/action/observation 三段
- [ ] 「现在几点」→ DateTimeTool 返回当前时间
- [ ] 「算一下 (1+2)*3」→ CalculatorTool 返回 9
- [ ] 多工具串联「查看日历然后设提醒」→ StepCard 展示多轮，loopIndex 递增
- [ ] 工具超时（toolTimeout=0.1）时 ReAct 循环继续，不卡死

## 4. 语音输入与朗读（Day 5）

- [ ] 点击麦克风按钮弹出语音授权弹窗
- [ ] 授权后实时识别语音并填充到输入框
- [ ] 再次点击麦克风停止录音
- [ ] 助手消息气泡的扬声器按钮可切换 TTS 朗读/停止
- [ ] 退出页面后音频引擎正确释放，无残留播放

## 5. 语义缓存与工程优化（Day 6）

- [ ] 重复发送相同问题，第二次命中缓存（DebugPanel 显示 cache hit）
- [ ] Token 估算与滑动窗口压缩在长对话中生效
- [ ] Actor 并发隔离无数据竞争（Swift 6 严格并发 0 warnings）

## 6. 产品化与设置面板（Day 7, 9）

- [ ] 设置页展示：供应商/API Key/模型选择/系统提示词/RAG 开关/工具开关/用户偏好
- [ ] 系统提示词编辑后重进设置仍保留
- [ ] 用户偏好（语气/工具/事实）持久化，重进 App 后保持
- [ ] 会话搜索栏过滤正常，清除后恢复完整列表
- [ ] 置顶/取消置顶后会话列表排序正确（置顶在前）

## 7. 质量保障与测试（Day 10-11）

- [ ] 对话导出为 Markdown 文件功能正常
- [ ] BGTaskScheduler 后台提醒任务按预期触发
- [ ] Live Activities 灵动岛展示正常（需真机）
- [ ] 本地通知主动提醒按预期弹出

## 8. 智能路由与反馈闭环（Day 12）

- [ ] 复杂问题自动切换到 Reasoner 模型（DebugPanel 显示模型切换）
- [ ] 简单问题用 Chat 模型快速响应
- [ ] 用户点赞/踩反馈按钮正常工作
- [ ] 反馈数据写入 SwiftData 并影响后续 RAG 权重

## 9. 国产大模型多供应商（Day 13）

- [ ] 设置页切换供应商为 Qwen，下次消息走 Qwen API
- [ ] DeepSeek / Qwen 的 API Key 独立存储，切换供应商不互相影响
- [ ] 开启「自动降级」后，主供应商失败（如 401）自动切到备用供应商
- [ ] DebugPanel 展示「主：Qwen（失败）→ 备用：DeepSeek（成功）」
- [ ] 关闭「自动降级」后主供应商失败直接报错

## 10. 远程配置与遥测（Day 14）

- [ ] App 启动后异步拉取远程配置，不阻塞主线程
- [ ] 远程配置拉取失败时回退到缓存或默认值，不影响正常使用
- [ ] 远程配置不覆盖用户已自定义的 System Prompt / Provider / Fallback
- [ ] DebugPanel 展示 RemoteConfig：configVersion / fetchedAt / defaultProvider / maintenanceMode
- [ ] DebugPanel 展示 Telemetry：buffer 事件数 / lastUploadAt / lastUploadStatus
- [ ] 「立即上报」Button 点击后触发 LogUploader 上传
- [ ] 「重新拉取配置」Button 点击后刷新 RemoteConfig
- [ ] 发送消息后 Telemetry buffer 事件数增加（messageSent 事件）
- [ ] BGTaskScheduler telemetry-upload 任务每 60 分钟触发一次（需后台场景验证）

## 11. BFF 代理层（Day 15）

- [ ] 设置页「BFF 代理」Section 展示 Toggle / endpoint / Token / 限流 Stepper
- [ ] 启用 BFF 代理后，请求 Header 含 X-BFF-Token，不含 Authorization: Bearer
- [ ] 禁用 BFF 代理后，请求回退到直连模式（含 Authorization: Bearer）
- [ ] 连续发送超过限流阈值（默认 20 次/分钟）触发限流错误条「请求过于频繁，请 60 秒后重试」
- [ ] SemanticCache 缓存命中时不消耗限流令牌
- [ ] BFF Token 无效（401）时 UI 提示「BFF Token 无效」
- [ ] BFF 服务异常（5xx）时 UI 提示「BFF 服务异常」
- [ ] BFF endpoint + Token 配置在 onDisappear 时持久化到 UserDefaults
- [ ] Cloudflare Workers 部署脚本（worker.js + wrangler.toml）可正确部署
- [ ] Workers 鉴权失败时返回 401 + `{"error": "Invalid BFF token"}`

## 12. 端侧模型 MLX（Day 16）

- [ ] 设置页「端侧推理」Section 展示 Toggle / NavigationLink / 自动切换 / maxTokens / temperature
- [ ] OnDeviceModelView 展示当前模型信息 / 下载进度 / 删除按钮
- [ ] 「下载模型」点击后启动后台下载，进度条 0-100% 更新
- [ ] 下载中断后重启 App 支持断点续传
- [ ] 下载完成后校验 SHA256，校验失败提示重试
- [ ] 「删除模型」点击后删除文件，onDeviceConfig.modelPath 置 nil
- [ ] 断网后 autoSwitchOnNetworkLoss == true 时自动切到 .onDevice provider
- [ ] 网络恢复后切回原 provider（DeepSeek / Qwen）
- [ ] 端侧模式下发送消息能收到流式响应（需真机 + mlx-swift 集成）
- [ ] 端侧模式下发起工具调用提示「端侧模型不支持工具调用」并自动降级到云端
- [ ] Shortcuts app 中出现「Ask AIBuilder」动作，输入 query 返回回复文本
- [ ] 设备内存不足时加载模型提示「设备内存不足，无法启用端侧推理」
- [ ] ModelProvider 列表新增「端侧推理」选项

## 13. watchOS 扩展（Day 17）

**注意：watchOS target 需在 Xcode 中手动创建并引用 AIBuilderWatch/ 目录下的文件。**

- [ ] HealthKit 授权弹窗首次出现时请求读取心率/睡眠/步数
- [ ] HealthKit 授权后在 SettingsView「健康」Section 显示「已授权」
- [ ] HealthKit 拒绝后返回空数据，UI 提示「请在设置中授权 HealthKit」
- [ ] HealthSettingsView「请求授权」Button 点击后触发 HealthKit 授权流程
- [ ] HealthSettingsView「跳转系统设置」Button 点击后跳转到 App 设置页
- [ ] Toggle「健康上下文注入」开启后，发送消息时 system prompt 含「用户最近 24h：睡眠 Xh，心率 Ybpm，步数 Z」
- [ ] 关闭「健康上下文注入」后 system prompt 不含健康数据
- [ ] DebugPanel 展示「健康上下文：已注入（24h 睡眠 Xh / 心率 Ybpm / 步数 Z）」
- [ ] 「立即生成洞察」Button 点击后调用 LLM 生成洞察文本
- [ ] 洞察文本末尾含免责声明「⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议」
- [ ] HealthSettingsView List 展示历史 HealthInsight 记录（按时间倒序）
- [ ] BGTaskScheduler health-insight 任务每天 09:00 触发生成洞察
- [ ] 洞察生成后推送本地通知「AI 健康洞察已生成，点击查看」
- [ ] WatchConnectivityService 在 iOS 端切换对话后发送 activeConversationId 到 watchOS
- [ ] watchOS 接收对话接力后展示完整消息历史
- [ ] watchOS 发送 quickChat 消息后 iOS 端处理并回传回复

## 14. App Intents 与系统集成（Day 18）

### 14.1 Shortcuts 真实对话

- [ ] Shortcuts app 中「Ask AIBuilder」动作输入 query，返回真实 LLM 回复（非占位文本）
- [ ] 未配置 API Key 时执行 Intent，返回提示「请先在 App 中配置 API Key」
- [ ] LLM 调用失败时返回错误提示文本

### 14.2 辅助 App Intent

- [ ] Shortcuts app 中「New Conversation」动作执行后创建新会话，返回 conversationId
- [ ] Shortcuts app 中「Switch Conversation」动作输入关键词，返回匹配会话标题
- [ ] 未找到匹配会话时返回「未找到匹配会话」

### 14.3 NSUserActivity Handoff

- [ ] 在 iPhone 上查看会话 A，iPad App Switcher 出现 AIBuilder Handoff 图标
- [ ] 点击 Handoff 图标后 iPad 端 App 打开并切换到会话 A
- [ ] Handoff userInfo 含 conversationId / title / lastMessage

### 14.4 Spotlight 搜索集成

- [ ] iOS Spotlight 搜索会话标题关键词，搜索结果展示匹配的 Conversation
- [ ] 搜索结果含会话标题与最后一条消息预览
- [ ] 点击搜索结果打开 App 并切换到对应会话
- [ ] 删除会话后 Spotlight 搜索不再出现该会话

## 15. 深度打磨：性能 / 无障碍 / 深色 / iPad（Day 19）

### 15.1 性能优化

- [ ] 对话超过 50 条消息时滚动流畅，无明显卡顿
- [ ] 流式响应期间打字机效果仍流畅（throttle 100ms 不影响观感）
- [ ] DebugPanel「性能指标」Section 展示启动耗时 / 首次响应耗时

### 15.2 无障碍适配

- [ ] VoiceOver 开启后，滑动选择消息气泡朗读完整消息文本（而非"气泡"）
- [ ] VoiceOver 朗读发送按钮为「发送」+ hint「发送消息」
- [ ] VoiceOver 朗读麦克风按钮为「语音输入」
- [ ] VoiceOver 朗读 StepCard 为「工具步骤：{toolName}」
- [ ] Dynamic Type 调到 XL（辅助功能 → 更大文字），消息气泡不截断
- [ ] Dynamic Type 调到 XL，设置页 Toggle / Picker 行不截断

### 15.3 深色模式

- [ ] 深色模式下消息气泡（用户蓝底白字 / 助手灰底黑字）对比度达标
- [ ] 深色模式下 StepCard / CitationCard 卡片背景可读
- [ ] 深色模式下 Divider / 边框可见
- [ ] 深色模式下空状态 halo 渐变可读
- [ ] 深色模式下设置页所有文字可读

### 15.4 iPad 适配

- [ ] iPad 竖屏打开 App，左侧侧栏展示会话列表，右侧主区展示对话
- [ ] iPad 横屏打开 App，同上双列布局
- [ ] 点击侧栏会话切换主区内容
- [ ] iPad 上输入框居中（maxWidth 600），不拉伸整宽
- [ ] iPhone 竖屏保持现有单列布局不变
- [ ] iPhone 横屏（Plus 机型）触发 NavigationSplitView 双列布局

## 16. 上架准备：隐私 / 反馈 / 崩溃监控（Day 20）

### 16.1 隐私清单与隐私政策

- [ ] `PrivacyInfo.xcprivacy` 文件存在于 AIBuilder target Resources
- [ ] NSPrivacyTracking = false
- [ ] NSPrivacyAccessedAPITypes 声明 UserDefaults / FileTimestamp / SystemBootTime
- [ ] 设置页「关于」Section 中点击「隐私政策」展示完整政策文本
- [ ] 隐私政策含数据收集范围 / 第三方 SDK / 用户权利 / 联系方式四段

### 16.2 投诉反馈

- [ ] 设置页「关于」Section 展示 App 版本号
- [ ] 点击「投诉反馈」打开系统邮件 composer
- [ ] 邮件收件人预填 feedback@aibuilder.app
- [ ] 邮件主题预填「AI Builder 用户反馈」
- [ ] 邮件正文含设备信息（机型 / iOS 版本 / App 版本）
- [ ] 未配置邮件账户时降级到 mailto: URL 或提示

### 16.3 崩溃监控

- [ ] App 启动时 CrashReportService 初始化（Debug 日志输出）
- [ ] 匿名用户标识生成并存储到 UserDefaults
- [ ] LLM 调用失败时 CrashReportService.reportException 被调用
- [ ] Bugly SDK 未集成时 App 正常运行（走占位分支）
- [ ] Info.plist 含 BuglyAppKey / BuglyAppChannel 配置项

### 16.4 发布检查

- [ ] Archive 构建无 warning（Scheme: Generic iOS Device）
- [ ] TestFlight 上传成功
- [ ] App Store 元数据填写完整（名称 / 副标题 / 描述 / 关键词）
- [ ] App Store 截图上传（6.7" / 6.1" 各 5-6 张）
- [ ] 年龄分级设置（17+，含 AI 生成内容）
- [ ] 参照 [ReleaseChecklist.md](file:///Users/xuchen/Documents/AIBuiler/doc/ReleaseChecklist.md) 完成最终检查

## 17. Markdown 渲染（补充迭代）

- [ ] 助手消息中代码块以深色背景卡片展示，含语言标签与复制按钮
- [ ] 代码块语法高亮正确（测试 Python / Swift / JavaScript / JSON / Bash 等语言）
- [ ] Markdown 表格正确渲染为带边框表格，列对齐正确
- [ ] 任务列表 `- [ ]` / `- [x]` 渲染为可点击 checkbox（仅展示，不可交互）
- [ ] 标题 H1-H6 字号与样式分级正确，H1/H2 下方有 Divider

## 18. TTS 音色可调节（补充迭代）

- [ ] 设置 → 语音朗读 → 音色 Picker 按语言分组（zh-CN 优先）
- [ ] 选择不同音色后立即生效，下次朗读使用新音色
- [ ] 语速 Slider 调节后试听预览生效
- [ ] 音调 Slider 调节后试听预览生效
- [ ] 音量 Slider 调节后试听预览生效
- [ ] 点击「试听」按钮播放预览语音，再次点击停止
- [ ] 配置离开设置页后持久化（UserDefaults key: ttsConfig）

## 19. 消息复制与重新提问（补充迭代）

- [ ] 长按用户消息气泡弹出 contextMenu 含「复制」和「重新提问」
- [ ] 长按助手消息气泡弹出 contextMenu 含「复制」（流式输出中不显示）
- [ ] 点击「复制」后底部显示 2 秒 toast「已复制」
- [ ] 点击「重新提问」后输入框填充原消息内容并自动发送
- [ ] 流式输出中的消息不显示 contextMenu

## 20. 批量多选删除会话（补充迭代）

- [ ] 会话列表左上角「编辑」按钮点击后进入编辑模式
- [ ] 编辑模式下每行左侧出现圆形 checkbox，点击切换选中状态
- [ ] 底部工具栏显示「全选」与「删除选中」按钮
- [ ] 点击「全选」选中所有会话，再点击取消全选
- [ ] 点击「删除选中」弹出确认 alert（取消 / 删除）
- [ ] 确认删除后选中的会话从列表与 SwiftData 中移除
- [ ] 点击「完成」按钮退出编辑模式

## 21. 多平台适配（iOS / iPad / macOS）

### 21.1 iOS 端

- [ ] iOS 模拟器启动 App，进入主界面
- [ ] 单栏 NavigationStack 布局正常
- [ ] 会话列表与聊天界面切换流畅
- [ ] 健康设置入口可见（Settings 中 HealthKit）
- [ ] 灵动岛 Live Activity 显示正常（iOS 16.1+）
- [ ] 后台任务 BGTaskScheduler 注册成功

### 21.2 iPad 端

- [ ] iPad 模拟器启动 App，进入主界面
- [ ] 双栏 NavigationSplitView 布局正常（左侧会话列表 + 右侧聊天）
- [ ] 横竖屏切换布局自适应
- [ ] 健康设置入口可见

### 21.3 macOS 端

- [ ] macOS 启动 App，进入主界面
- [ ] 窗口默认尺寸 1000×700
- [ ] 菜单栏命令：⌘N 新建会话、⌘K 搜索、⌘, 打开设置
- [ ] ⌘Enter 发送消息（Enter 换行）
- [ ] 双栏 NavigationSplitView 布局正常
- [ ] HealthKit 入口隐藏（Settings 中无健康设置项）
- [ ] HealthInsight 模型仍注册（SwiftData schema 无报错）
- [ ] BGTaskScheduler / ActivityKit / WatchConnectivity 优雅降级（无崩溃）
- [ ] DocumentPickerView 用 `.fileImporter` 正常选择文件
- [ ] FeedbackService 用 ProcessInfo 获取设备信息正常

## 22. 工具能力增强（20 个新工具）

### 22.1 跨平台工具（iOS + macOS）

- [ ] LocationTool：get_location 返回坐标 + 中文地址（10s 内）
- [ ] DeviceInfoTool：get_device_info 返回型号 / OS 版本 / 电量 / 可用存储
- [ ] ReadClipboardTool：read_clipboard 读取剪贴板内容
- [ ] WriteClipboardTool：write_clipboard 写入文本到剪贴板
- [ ] OpenURLTool：open_url 用系统默认方式打开 URL（如 https://www.apple.com）
- [ ] ContactsTool：search_contacts 按姓名搜索联系人（需授权）
- [ ] WeatherTool：get_weather 查询城市天气（有 city 参数 + 无 city 参数两种）

### 22.2 macOS 独有工具

- [ ] AppleScriptTool：run_applescript 执行 `return "hello"` 返回 hello
- [ ] ScreenshotTool：take_screenshot 截屏保存 PNG 到临时目录
- [ ] OCRTool：extract_text_from_image 识别图片文字（有 image_path + 无 image_path 两种）
- [ ] TerminalCommandTool：run_terminal_command 执行 `echo hello` 返回 hello；危险命令 `rm -rf /` 被拒绝
- [ ] WindowManagementTool：manage_window action=list 列出窗口
- [ ] AppManagementTool：manage_app action=list_running 列出运行中应用
- [ ] FileOperationTool：manage_file action=list 列出目录文件；action=delete 移到废纸篓
- [ ] FinderTool：finder_action action=get_selection 获取 Finder 选中项
- [ ] SafariControlTool：control_safari action=list_tabs 列出 Safari 标签页
- [ ] SystemControlTool：system_control action=get_volume 获取音量
- [ ] InputAutomationTool：simulate_input action=key_type 输入字符

### 22.3 快捷指令工具（跨平台）

- [ ] RunShortcutTool：run_shortcut 运行一个已有快捷指令（macOS）
- [ ] ListShortcutsTool：list_shortcuts 列出快捷指令（macOS 返回列表，iOS 返回提示）
- [ ] CreateShortcutTool：create_shortcut 创建快捷指令，测试 4 种动作：
  - [ ] open_url 动作
  - [ ] run_script 动作
  - [ ] show_text 动作
  - [ ] copy_to_clipboard 动作

## 23. macOS 设置导航修复

- [ ] macOS 点击「TTS 音色选择」进入二级页，顶部出现返回按钮（<）
- [ ] 点击返回按钮，回到「功能与偏好」Section 的 Form
- [ ] macOS 点击「隐私政策」进入二级页，有返回按钮，可返回
- [ ] macOS 点击「端侧模型管理」进入二级页，有返回按钮，可返回
- [ ] 在二级页时切换左侧 sidebar 到其他分类，右侧 detail 回到新分类的根 Form
- [ ] iOS 端设置导航不受影响（NavigationStack 正常）

## 24. macOS markdown 视觉修复

- [ ] macOS 上 AI 回复含 markdown 表格，表头背景、交替行背景、气泡背景三色可区分
- [ ] macOS 上 StreamingBubbleView（流式回复中）背景与气泡背景有对比
- [ ] macOS 上代码块、标题、任务列表渲染正常
- [ ] iOS 上 markdown 渲染不受影响（颜色仍用系统原生 UIColor）

## 25. macOS 语音朗读 UI 修复

- [ ] macOS 上点击消息朗读按钮，UI 不卡顿（MarkdownText 解析结果已缓存）
- [ ] 朗读中按钮变红色 stop 图标
- [ ] 朗读自然结束后按钮恢复为 speaker 图标
- [ ] 朗读中再次点击同一消息，停止朗读，按钮恢复
- [ ] 朗读中切换到另一条消息朗读，先停旧的再开始新的
- [ ] （可选）系统取消朗读后（如音频被抢占），按钮自动恢复（不卡红）

## 26. 预设系统提示词

- [ ] 打开「设置 → 功能与偏好 → 系统提示词」，看到「预设角色」Menu
- [ ] 点击 Menu 看到 11 个角色选项
- [ ] 选择「开发者」，TextEditor 填入开发者预设 prompt（≥ 150 字）
- [ ] 在 TextEditor 中可继续编辑已填入的 prompt
- [ ] 点击「完成」保存，新建对话沿用该 prompt
- [ ] 依次测试每个角色（默认助手/开发者/学生/白领/管理者/产品经理/写作助手/技术面试官/学习导师/翻译官/健身教练）均能正确填入

---

## 手测环境要求

| 功能模块 | 设备要求 | 备注 |
|---------|---------|------|
| 基础对话 / RAG / 工具 / 语音 | iPhone 模拟器或真机 | 需配置 DeepSeek API Key |
| BFF 代理层 | 真机或模拟器 + 部署 Cloudflare Workers | 需自定义域名 |
| 端侧 MLX 推理 | Apple Silicon 真机（A17 Pro+） | 模拟器无 MLX 加速，需集成 mlx-swift SPM |
| HealthKit | 真机 | 模拟器无真实健康数据 |
| watchOS 扩展 | Apple Watch 真机 + iPhone | 需手动创建 watchOS target |
| Live Activities / 灵动岛 | 真机（iPhone 14 Pro+） | 模拟器不支持灵动岛 |
| Shortcuts / App Intents | 真机或模拟器 | 需安装 Shortcuts app |
| Handoff 跨设备接力 | iPhone + iPad（同 Apple ID） | 需同一 iCloud 账号 |
| Spotlight 搜索 | 真机或模拟器 | 模拟器 Spotlight 可能有限制 |
| 无障碍 VoiceOver | 真机或模拟器 | 设置 → 辅助功能 → VoiceOver |
| 深色模式 | 真机或模拟器 | 设置 → 显示与亮度 → 深色 |
| iPad 多列布局 | iPad 真机或模拟器 | 需选择 iPad 目标设备 |
| 隐私清单 / 崩溃监控 | 真机或模拟器 | Bugly SDK 集成后需真机验证崩溃上报 |
| TestFlight / App Store | 真机 | 需 Apple Developer 账号 |
| Markdown 渲染 / TTS 音色 / 消息复制重发 / 批量删除 | iPhone 模拟器或真机 | 补充迭代功能，无特殊设备需求 |

## 手测执行优先级

**P0（核心路径，必须验证）**：1, 2, 3, 9, 10, 11, 16, 21（多平台适配，发布前必须验证三端启动与基础功能），23（macOS 设置导航修复，核心交互修复）
**P1（重要功能，应验证）**：4, 5, 6, 7, 8, 12, 14, 15, 17, 18, 19, 20, 22（工具能力增强，重要新增功能，建议每次发布前验证），24（macOS markdown 视觉修复），25（macOS 语音朗读 UI 修复），26（预设系统提示词）
**P2（增强功能，可选验证）**：13（需 watchOS 硬件），14.3（需 iPhone + iPad）

| 手测模块 | 优先级 | 说明 |
|---------|--------|------|
| 多平台适配（21） | P0 | 核心平台支持，发布前必须验证三端启动与基础功能 |
| macOS 设置导航修复（23） | P0 | 核心交互修复，二级页返回按钮为关键回归点 |
| 工具能力增强（22） | P1 | 重要新增功能，建议每次发布前验证 |
| macOS markdown 视觉修复（24） | P1 | macOS 三色可分列为平台视觉一致性关键 |
| macOS 语音朗读 UI 修复（25） | P1 | 朗读卡顿与按钮恢复为体验关键点 |
| 预设系统提示词（26） | P1 | 11 个预设角色 Menu，新手引导路径 |
| 其他现有模块 | 保持原优先级 | 见上方分级说明 |
