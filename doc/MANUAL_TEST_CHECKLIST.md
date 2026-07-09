# 手测确认清单

本文档汇总 Day 1-20 所有 spec 中无法通过自动化测试（UT/UIT）覆盖、需人工验证的功能点，按功能模块划分。每个测试项采用「前置条件 / 操作步骤 / 预期结果 / 失败排查」四字段结构化格式。

---

## 1. 基础对话与流式响应（Day 1-2）

- [ ] SSE 流式打字机效果正常
  - **前置条件**：API Key 已配置，网络通畅
  - **操作步骤**：
    1. 打开 App 进入主对话界面
    2. 在输入框输入「你好」并点击发送
  - **预期结果**：AI 回复逐字出现，无一次性吐出，无明显卡顿或丢字
  - **失败排查**：检查 DebugPanel.apiResponse 是否有 chunk；检查 URLSession 是否被代理；查看 SSE 解析器是否正确分割 `data:` 行

- [ ] 多轮对话上下文保持
  - **前置条件**：已配置可用 API Key，已新建会话
  - **操作步骤**：
    1. 第 1 轮发送「我叫张三」
    2. 第 2 轮发送「我喜欢蓝色」
    3. 第 3 轮发送「我姓什么？我喜欢什么颜色？」
  - **预期结果**：第 3 轮回复能引用「张三」与「蓝色」
  - **失败排查**：检查 ChatViewModel.messages 是否正确传入 messages 数组；查看 TokenSlidingWindow 是否过早裁剪了早期消息

- [ ] 新建/切换/删除会话
  - **前置条件**：App 启动后进入主界面，已创建至少 2 个会话
  - **操作步骤**：
    1. 点击右上角「新建会话」按钮
    2. 在会话列表中点击不同会话切换
    3. 长按或滑动删除某个会话
  - **预期结果**：会话列表与 SwiftData 持久化一致，重启 App 后状态保持
  - **失败排查**：检查 ConversationStore 是否调用 modelContext.save()；查看 SwiftData schema 是否正确

- [ ] 长按会话行触发 contextMenu
  - **前置条件**：会话列表中至少有 1 个会话
  - **操作步骤**：
    1. 长按会话列表中某一行
  - **预期结果**：弹出 contextMenu，包含「重命名」「置顶」「删除」选项
  - **失败排查**：检查 ConversationRowView 的 contextMenu 修饰符；查看手势冲突

## 2. RAG 知识库（Day 3）

- [ ] 文档导入自动分块与向量化
  - **前置条件**：App 进入主界面，准备 .txt / .md / .pdf 文档各一份
  - **操作步骤**：
    1. 进入设置 → 知识库 → 点击「导入文档」
    2. 选择 .txt / .md / .pdf 文件
  - **预期结果**：文档自动分块，向量化完成后列表显示文档名与分块数
  - **失败排查**：检查 DocumentProcessor.chunkSize 配置；查看 embedding API 是否调用成功

- [ ] RAG 引用知识库内容
  - **前置条件**：已导入至少 1 个文档并完成向量化，RAG 开关已开启
  - **操作步骤**：
    1. 在主界面发送与文档相关的问题
  - **预期结果**：回复引用了知识库内容，消息下方出现 CitationCard
  - **失败排查**：检查 RAGRetriever.topK 配置；查看向量相似度阈值

- [ ] CitationCard 展示来源
  - **前置条件**：开启 RAG 后已发送问题并收到引用
  - **操作步骤**：
    1. 查看助手消息下方的 CitationCard
  - **预期结果**：CitationCard 展示来源文档名与分块内容摘要
  - **失败排查**：检查 CitationCard 视图绑定；查看 source 数据是否正确传递

- [ ] 关闭 RAG 后不引用知识库
  - **前置条件**：RAG 已开启并验证可引用
  - **操作步骤**：
    1. 进入设置关闭 RAG 开关
    2. 发送相同问题
  - **预期结果**：回复不引用知识库，无 CitationCard
  - **失败排查**：检查 RAGService.isEnabled 绑定；查看 SmartRouter 是否仍走 RAG 路径

## 3. 工具调用与 ReAct 循环（Day 4, 8）

- [ ] StepCard 三段展示
  - **前置条件**：工具开关已开启，ReminderTool 已注册
  - **操作步骤**：
    1. 发送「设一个 5 分钟后的提醒」
  - **预期结果**：StepCard 展示 thought / action / observation 三段
  - **失败排查**：检查 ReActEngine.loopIndex 递增；查看 ToolRegistry 是否返回 ReminderTool

- [ ] DateTimeTool 返回当前时间
  - **前置条件**：DateTimeTool 已注册并启用
  - **操作步骤**：
    1. 发送「现在几点」
  - **预期结果**：DateTimeTool 返回当前时间，AI 引用工具结果回复
  - **失败排查**：检查 DateTimeTool.execute 是否抛错；查看 tool_calls 解析

- [ ] CalculatorTool 计算
  - **前置条件**：CalculatorTool 已注册并启用
  - **操作步骤**：
    1. 发送「算一下 (1+2)*3」
  - **预期结果**：CalculatorTool 返回 9
  - **失败排查**：检查表达式解析是否正确；查看特殊字符转义

- [ ] 多工具串联
  - **前置条件**：CalendarTool 与 ReminderTool 均已注册
  - **操作步骤**：
    1. 发送「查看日历然后设提醒」
  - **预期结果**：StepCard 展示多轮，loopIndex 递增
  - **失败排查**：检查 ReAct 循环 maxIterations 配置；查看 observation 是否正确回填

- [ ] 工具超时不卡死
  - **前置条件**：toolTimeout 配置为 0.1s
  - **操作步骤**：
    1. 发送会触发工具调用的消息（如「读取剪贴板」）
  - **预期结果**：ReAct 循环继续，不卡死
  - **失败排查**：检查 ToolExecutor 的 withThrowingTaskGroup 超时分支；查看 cancellation handler

## 4. 语音输入与朗读（Day 5）

- [ ] 麦克风按钮弹出授权弹窗
  - **前置条件**：首次使用语音输入，麦克风权限未授权
  - **操作步骤**：
    1. 点击输入框旁的麦克风按钮
  - **预期结果**：弹出系统授权弹窗请求麦克风访问
  - **失败排查**：检查 Info.plist 是否含 NSMicrophoneUsageDescription；查看 SFSpeechRecognizer 权限请求

- [ ] 实时识别填充输入框
  - **前置条件**：麦克风权限已授权
  - **操作步骤**：
    1. 点击麦克风按钮开始录音
    2. 说话（如「今天天气不错」）
  - **预期结果**：实时识别语音并填充到输入框
  - **失败排查**：检查 SFSpeechAudioBufferRecognitionRequest；查看 audioEngine 输入节点

- [ ] 停止录音
  - **前置条件**：正在录音中
  - **操作步骤**：
    1. 再次点击麦克风按钮
  - **预期结果**：停止录音，麦克风按钮恢复常态
  - **失败排查**：检查 audioEngine.stop() 调用；查看 task cancel

- [ ] TTS 朗读切换
  - **前置条件**：助手消息已生成完成
  - **操作步骤**：
    1. 点击助手消息气泡的扬声器按钮
    2. 朗读中再次点击
  - **预期结果**：第一次开始朗读，第二次停止朗读
  - **失败排查**：检查 AVSpeechSynthesizer 状态；查看 delegate 回调

- [ ] 退出页面音频释放
  - **前置条件**：正在朗读中
  - **操作步骤**：
    1. 朗读过程中返回上一页或退出 App
  - **预期结果**：音频引擎正确释放，无残留播放
  - **失败排查**：检查 onDisappear 中的清理逻辑；查看 AVAudioSession deactive

## 5. 语义缓存与工程优化（Day 6）

- [ ] 缓存命中
  - **前置条件**：SemanticCache 已开启
  - **操作步骤**：
    1. 发送一个问题（如「1+1 等于几」）
    2. 等待回复完成
    3. 重复发送相同问题
  - **预期结果**：第二次命中缓存，DebugPanel 显示 cache hit
  - **失败排查**：检查 SemanticCache.similarity 阈值；查看 embedding 向量是否一致

- [ ] Token 估算与滑动窗口
  - **前置条件**：长对话已超过 20 轮
  - **操作步骤**：
    1. 在长对话中继续发送消息
  - **预期结果**：滑动窗口压缩生效，Token 估算在 DebugPanel 显示
  - **失败排查**：检查 TokenSlidingWindow.maxTokens 配置；查看压缩算法

- [ ] Actor 并发隔离无竞争
  - **前置条件**：项目以 Swift 6 严格并发模式编译
  - **操作步骤**：
    1. 执行 Build
    2. 查看 Build Log 中是否出现 concurrency 相关 warning
  - **预期结果**：Swift 6 严格并发 0 warnings
  - **失败排查**：检查 @MainActor / actor 标注；查看 Sendable conformance

## 6. 产品化与设置面板（Day 7, 9）

- [ ] 设置页字段完整
  - **前置条件**：App 已启动并进入主界面
  - **操作步骤**：
    1. 进入设置页
  - **预期结果**：展示供应商 / API Key / 模型选择 / 系统提示词 / RAG 开关 / 工具开关 / 用户偏好
  - **失败排查**：检查 SettingsView Form 结构；查看各 Section 是否被条件编译遗漏

- [ ] 系统提示词持久化
  - **前置条件**：进入设置 → 系统提示词
  - **操作步骤**：
    1. 修改系统提示词内容
    2. 退出设置页
    3. 重新进入设置页
  - **预期结果**：系统提示词编辑后重进设置仍保留
  - **失败排查**：检查 UserDefaults 持久化 key；查看 onDisappear save

- [ ] 用户偏好的持久化
  - **前置条件**：进入设置 → 用户偏好
  - **操作步骤**：
    1. 修改语气 / 工具 / 事实偏好
    2. 重启 App
  - **预期结果**：偏好持久化，重进 App 后保持
  - **失败排查**：检查 UserPreference Codable；查看 SwiftData 持久化

- [ ] 会话搜索过滤
  - **前置条件**：会话列表至少有 5 个会话
  - **操作步骤**：
    1. 在搜索栏输入关键词
    2. 清空搜索栏
  - **预期结果**：搜索栏过滤正常，清除后恢复完整列表
  - **失败排查**：检查 SearchService.filter 逻辑；查看 list binding

- [ ] 置顶排序
  - **前置条件**：会话列表至少有 3 个会话
  - **操作步骤**：
    1. 长按某个会话选择「置顶」
    2. 长按已置顶会话选择「取消置顶」
  - **预期结果**：置顶/取消置顶后会话列表排序正确（置顶在前）
  - **失败排查**：检查 ConversationStore.sortDescriptors；查看 isPinned 字段

## 7. 质量保障与测试（Day 10-11）

- [ ] 导出 Markdown
  - **前置条件**：当前会话至少有 2 条消息
  - **操作步骤**：
    1. 点击会话顶部「导出」按钮
  - **预期结果**：对话导出为 Markdown 文件功能正常
  - **失败排查**：检查 MarkdownExporter.format；查看 fileExporter

- [ ] BGTaskScheduler 后台提醒
  - **前置条件**：已设置提醒，App 进入后台
  - **操作步骤**：
    1. 设置 1 分钟后提醒
    2. 将 App 切到后台等待
  - **预期结果**：BGTaskScheduler 后台提醒任务按预期触发
  - **失败排查**：检查 BGTaskScheduler.register identifier；查看 trigger conditions

- [ ] Live Activities 灵动岛
  - **前置条件**：iPhone 14 Pro+ 真机
  - **操作步骤**：
    1. 触发 Live Activity（如开始朗读或后台任务）
  - **预期结果**：Live Activities 灵动岛展示正常
  - **失败排查**：检查 ActivityKit 权限；查看 widget extension

- [ ] 本地通知主动提醒
  - **前置条件**：通知权限已授权
  - **操作步骤**：
    1. 设置提醒并触发
  - **预期结果**：本地通知主动提醒按预期弹出
  - **失败排查**：检查 UNUserNotificationCenter；查看 trigger 配置

## 8. 智能路由与反馈闭环（Day 12）

- [ ] 复杂问题切换 Reasoner
  - **前置条件**：SmartRouter 已开启，Reasoner 模型已配置
  - **操作步骤**：
    1. 发送复杂推理问题（如「证明勾股定理」）
  - **预期结果**：复杂问题自动切换到 Reasoner 模型，DebugPanel 显示模型切换
  - **失败排查**：检查 SmartRouter.complexity 阈值；查看 provider switch

- [ ] 简单问题走 Chat
  - **前置条件**：SmartRouter 已开启
  - **操作步骤**：
    1. 发送简单问题（如「1+1」）
  - **预期结果**：简单问题用 Chat 模型快速响应
  - **失败排查**：检查路由判定逻辑；查看 latency

- [ ] 反馈按钮工作
  - **前置条件**：助手消息已生成
  - **操作步骤**：
    1. 点击助手消息下的「赞」或「踩」按钮
  - **预期结果**：用户点赞/踩反馈按钮正常工作
  - **失败排查**：检查 FeedbackButton action；查看按钮状态切换

- [ ] 反馈影响 RAG 权重
  - **前置条件**：已开启 RAG，已对某条引用点踩
  - **操作步骤**：
    1. 对引用 A 的消息点踩
    2. 再次发送相同问题
  - **预期结果**：反馈数据写入 SwiftData 并影响后续 RAG 权重（引用 A 权重降低）
  - **失败排查**：检查 FeedbackStore 持久化；查看 RAG 重新排序逻辑

## 9. 国产大模型多供应商（Day 13）

- [ ] 切换供应商为 Qwen
  - **前置条件**：Qwen API Key 已配置
  - **操作步骤**：
    1. 设置页切换供应商为 Qwen
    2. 发送消息
  - **预期结果**：下次消息走 Qwen API
  - **失败排查**：检查 ModelProviderFactory；查看 endpoint 切换

- [ ] API Key 独立存储
  - **前置条件**：DeepSeek 与 Qwen API Key 均已配置
  - **操作步骤**：
    1. 切换供应商为 Qwen
    2. 切换回 DeepSeek
  - **预期结果**：DeepSeek / Qwen 的 API Key 独立存储，切换供应商不互相影响
  - **失败排查**：检查 Keychain key namespace；查看 provider 绑定

- [ ] 自动降级
  - **前置条件**：开启「自动降级」开关，主备供应商均已配置
  - **操作步骤**：
    1. 故意填错主供应商 API Key（如 401）
    2. 发送消息
  - **预期结果**：主供应商失败（如 401）自动切到备用供应商
  - **失败排查**：检查 FallbackLLMProvider 逻辑；查看错误码识别

- [ ] DebugPanel 展示降级路径
  - **前置条件**：触发自动降级
  - **操作步骤**：
    1. 触发降级后打开 DebugPanel
  - **预期结果**：DebugPanel 展示「主：Qwen（失败）→ 备用：DeepSeek（成功）」
  - **失败排查**：检查 DebugPanel.fallbackLog；查看状态记录

- [ ] 关闭降级直接报错
  - **前置条件**：关闭「自动降级」开关
  - **操作步骤**：
    1. 故意填错主供应商 API Key
    2. 发送消息
  - **预期结果**：关闭「自动降级」后主供应商失败直接报错
  - **失败排查**：检查 FallbackLLMProvider.isEnabled；查看错误冒泡

## 10. 远程配置与遥测（Day 14）

- [ ] 异步拉取远程配置不阻塞主线程
  - **前置条件**：远程配置 endpoint 可访问
  - **操作步骤**：
    1. 启动 App
    2. 观察启动到主界面响应时间
  - **预期结果**：App 启动后异步拉取远程配置，不阻塞主线程
  - **失败排查**：检查 RemoteConfigService.fetch 是否在 background queue；查看 await 调用

- [ ] 远程配置拉取失败回退
  - **前置条件**：断开网络或配置 endpoint 不可达
  - **操作步骤**：
    1. 启动 App
  - **预期结果**：远程配置拉取失败时回退到缓存或默认值，不影响正常使用
  - **失败排查**：检查 RemoteConfigService 缓存逻辑；查看 UserDefaults 兜底

- [ ] 不覆盖用户自定义
  - **前置条件**：用户已自定义 System Prompt / Provider / Fallback
  - **操作步骤**：
    1. 启动 App 等待远程配置拉取
  - **预期结果**：远程配置不覆盖用户已自定义的 System Prompt / Provider / Fallback
  - **失败排查**：检查合并策略 mergeIfAbsent；查看 user override 标志

- [ ] DebugPanel 展示 RemoteConfig
  - **前置条件**：远程配置已成功拉取
  - **操作步骤**：
    1. 打开 DebugPanel
  - **预期结果**：DebugPanel 展示 RemoteConfig：configVersion / fetchedAt / defaultProvider / maintenanceMode
  - **失败排查**：检查 DebugPanel 字段绑定；查看 RemoteConfigService.shared

- [ ] DebugPanel 展示 Telemetry
  - **前置条件**：已发送至少 1 条消息
  - **操作步骤**：
    1. 打开 DebugPanel
  - **预期结果**：DebugPanel 展示 Telemetry：buffer 事件数 / lastUploadAt / lastUploadStatus
  - **失败排查**：检查 TelemetryService.buffer；查看 upload 状态

- [ ] 立即上报按钮
  - **前置条件**：Telemetry buffer 有事件
  - **操作步骤**：
    1. 点击 DebugPanel 中的「立即上报」Button
  - **预期结果**：触发 LogUploader 上传
  - **失败排查**：检查 LogUploader.upload；查看 HTTP 请求

- [ ] 重新拉取配置按钮
  - **前置条件**：远程配置 endpoint 可访问
  - **操作步骤**：
    1. 点击 DebugPanel 中的「重新拉取配置」Button
  - **预期结果**：刷新 RemoteConfig
  - **失败排查**：检查 RemoteConfigService.refresh；查看错误提示

- [ ] 发送消息后 Telemetry 增加
  - **前置条件**：Telemetry 已开启
  - **操作步骤**：
    1. 发送一条消息
    2. 查看 DebugPanel 中 Telemetry buffer 事件数
  - **预期结果**：发送消息后 Telemetry buffer 事件数增加（messageSent 事件）
  - **失败排查**：检查 TelemetryService.track；查看事件类型枚举

- [ ] BGTaskScheduler telemetry-upload 触发
  - **前置条件**：App 已进入后台至少 60 分钟
  - **操作步骤**：
    1. App 进入后台
    2. 等待 60 分钟后查看 DebugPanel
  - **预期结果**：BGTaskScheduler telemetry-upload 任务每 60 分钟触发一次（需后台场景验证）
  - **失败排查**：检查 BGTaskScheduler identifier；查看 trigger interval

## 11. BFF 代理层（Day 15）

- [ ] 设置页 BFF Section 展示
  - **前置条件**：进入设置页
  - **操作步骤**：
    1. 滚动到「BFF 代理」Section
  - **预期结果**：设置页「BFF 代理」Section 展示 Toggle / endpoint / Token / 限流 Stepper
  - **失败排查**：检查 SettingsView 中 BFF Section；查看条件编译

- [ ] 启用 BFF 后请求 Header
  - **前置条件**：BFF endpoint + Token 已配置
  - **操作步骤**：
    1. 启用 BFF 代理 Toggle
    2. 发送消息
    3. 查看 DebugPanel 的 request header
  - **预期结果**：请求 Header 含 X-BFF-Token，不含 Authorization: Bearer
  - **失败排查**：检查 BFFProxyClient.modifyRequest；查看 header 注入

- [ ] 禁用 BFF 回退直连
  - **前置条件**：BFF 代理已启用
  - **操作步骤**：
    1. 关闭 BFF 代理 Toggle
    2. 发送消息
    3. 查看 DebugPanel 的 request header
  - **预期结果**：禁用 BFF 代理后，请求回退到直连模式（含 Authorization: Bearer）
  - **失败排查**：检查 ModelProviderFactory 切换逻辑；查看 fallback 路径

- [ ] 限流触发
  - **前置条件**：BFF 代理已启用，限流阈值默认 20 次/分钟
  - **操作步骤**：
    1. 连续发送 21 条消息
  - **预期结果**：连续发送超过限流阈值触发限流错误条「请求过于频繁，请 60 秒后重试」
  - **失败排查**：检查 RateLimiter token bucket；查看时间窗口

- [ ] 缓存命中不消耗令牌
  - **前置条件**：SemanticCache 已开启，BFF 已启用
  - **操作步骤**：
    1. 发送问题 A 获得回复
    2. 再次发送相同问题 A
  - **预期结果**：SemanticCache 缓存命中时不消耗限流令牌
  - **失败排查**：检查 CacheInterceptor；查看 rate limiter 计数

- [ ] BFF Token 无效提示
  - **前置条件**：BFF Token 填错
  - **操作步骤**：
    1. 发送消息
  - **预期结果**：BFF Token 无效（401）时 UI 提示「BFF Token 无效」
  - **失败排查**：检查 BFFProxyClient 错误码识别；查看 UI 错误条

- [ ] BFF 服务异常提示
  - **前置条件**：BFF endpoint 返回 5xx
  - **操作步骤**：
    1. 发送消息
  - **预期结果**：BFF 服务异常（5xx）时 UI 提示「BFF 服务异常」
  - **失败排查**：检查错误码映射；查看 error alert

- [ ] 配置持久化
  - **前置条件**：BFF endpoint + Token 已修改
  - **操作步骤**：
    1. 修改 BFF endpoint 与 Token
    2. 退出设置页
  - **预期结果**：BFF endpoint + Token 配置在 onDisappear 时持久化到 UserDefaults
  - **失败排查**：检查 onDisappear save；查看 UserDefaults key

- [ ] Cloudflare Workers 部署
  - **前置条件**：已安装 wrangler CLI，已登录 Cloudflare
  - **操作步骤**：
    1. 执行 `wrangler deploy`
  - **预期结果**：Cloudflare Workers 部署脚本（worker.js + wrangler.toml）可正确部署
  - **失败排查**：检查 wrangler.toml 配置；查看 account_id

- [ ] Workers 鉴权失败
  - **前置条件**：Workers 已部署
  - **操作步骤**：
    1. 用错误的 X-BFF-Token 请求 Workers
  - **预期结果**：Workers 鉴权失败时返回 401 + `{"error": "Invalid BFF token"}`
  - **失败排查**：检查 worker.js 中 token 校验逻辑；查看 response.json

## 12. 端侧模型 MLX（Day 16）

- [ ] 设置页端侧推理 Section
  - **前置条件**：进入设置页
  - **操作步骤**：
    1. 滚动到「端侧推理」Section
  - **预期结果**：设置页「端侧推理」Section 展示 Toggle / NavigationLink / 自动切换 / maxTokens / temperature
  - **失败排查**：检查 SettingsView 中 OnDevice Section；查看条件编译

- [ ] OnDeviceModelView 展示
  - **前置条件**：进入端侧模型管理页
  - **操作步骤**：
    1. 查看 OnDeviceModelView
  - **预期结果**：OnDeviceModelView 展示当前模型信息 / 下载进度 / 删除按钮
  - **失败排查**：检查 OnDeviceModelView binding；查看 model state

- [ ] 下载模型进度更新
  - **前置条件**：网络通畅，磁盘空间足够
  - **操作步骤**：
    1. 点击「下载模型」按钮
  - **预期结果**：「下载模型」点击后启动后台下载，进度条 0-100% 更新
  - **失败排查**：检查 Downloader progress callback；查看 URLSession downloadTask

- [ ] 断点续传
  - **前置条件**：下载中途中断
  - **操作步骤**：
    1. 下载过程中杀掉 App
    2. 重启 App 并进入端侧模型管理
  - **预期结果**：下载中断后重启 App 支持断点续传
  - **失败排查**：检查 resumeData 持久化；查看 URLSession resume

- [ ] SHA256 校验
  - **前置条件**：下载已完成
  - **操作步骤**：
    1. 下载完成后查看校验日志
  - **预期结果**：下载完成后校验 SHA256，校验失败提示重试
  - **失败排查**：检查 SHA256 计算；查看 expected hash 对比

- [ ] 删除模型
  - **前置条件**：已下载模型
  - **操作步骤**：
    1. 点击「删除模型」按钮
  - **预期结果**：「删除模型」点击后删除文件，onDeviceConfig.modelPath 置 nil
  - **失败排查**：检查 FileManager.removeItem；查看 modelPath 清空

- [ ] 断网自动切换端侧
  - **前置条件**：autoSwitchOnNetworkLoss == true，端侧模型已就绪
  - **操作步骤**：
    1. 启用自动切换
    2. 断开网络
    3. 发送消息
  - **预期结果**：断网后 autoSwitchOnNetworkLoss == true 时自动切到 .onDevice provider
  - **失败排查**：检查 NetworkMonitor；查看 provider 切换

- [ ] 网络恢复切回
  - **前置条件**：当前为端侧模式
  - **操作步骤**：
    1. 恢复网络
  - **预期结果**：网络恢复后切回原 provider（DeepSeek / Qwen）
  - **失败排查**：检查 NetworkMonitor.pathUpdate；查看 restore provider

- [ ] 端侧流式响应
  - **前置条件**：真机 + mlx-swift 已集成
  - **操作步骤**：
    1. 端侧模式下发送消息
  - **预期结果**：端侧模式下发送消息能收到流式响应
  - **失败排查**：检查 MLXEngine.generate；查看 AsyncStream

- [ ] 端侧不支持工具调用降级
  - **前置条件**：端侧模式已启用
  - **操作步骤**：
    1. 端侧模式下发起工具调用（如「设提醒」）
  - **预期结果**：端侧模式下发起工具调用提示「端侧模型不支持工具调用」并自动降级到云端
  - **失败排查**：检查工具调用前的 provider 判定；查看降级逻辑

- [ ] Shortcuts 中 Ask AIBuilder
  - **前置条件**：App 已安装到真机
  - **操作步骤**：
    1. 打开 Shortcuts app
    2. 查看 AIBuilder 相关动作
  - **预期结果**：Shortcuts app 中出现「Ask AIBuilder」动作，输入 query 返回回复文本
  - **失败排查**：检查 AppIntent 注册；查看 AppShortcutsProvider

- [ ] 内存不足提示
  - **前置条件**：设备内存紧张（如老机型）
  - **操作步骤**：
    1. 尝试加载大模型
  - **预期结果**：设备内存不足时加载模型提示「设备内存不足，无法启用端侧推理」
  - **失败排查**：检查 MLXEngine 内存检测；查看 os_proc_available_memory

- [ ] ModelProvider 列表新增端侧
  - **前置条件**：进入设置 → 供应商选择
  - **操作步骤**：
    1. 查看 ModelProvider Picker
  - **预期结果**：ModelProvider 列表新增「端侧推理」选项
  - **失败排查**：检查 ModelProvider enum；查看 Picker item

## 13. watchOS 扩展（Day 17）

**注意：watchOS target 需在 Xcode 中手动创建并引用 AIBuilderWatch/ 目录下的文件。**

- [ ] HealthKit 授权弹窗
  - **前置条件**：首次进入 HealthSettingsView，HealthKit 未授权
  - **操作步骤**：
    1. 进入设置 → 健康
  - **预期结果**：HealthKit 授权弹窗首次出现时请求读取心率/睡眠/步数
  - **失败排查**：检查 HKAuthorizationRequestPermission；查看 Info.plist HealthShareUsageDescription

- [ ] 授权后展示已授权
  - **前置条件**：HealthKit 已授权
  - **操作步骤**：
    1. 进入 SettingsView「健康」Section
  - **预期结果**：HealthKit 授权后在 SettingsView「健康」Section 显示「已授权」
  - **失败排查**：检查 authorizationStatus；查看 UI 状态绑定

- [ ] 拒绝授权提示
  - **前置条件**：HealthKit 已拒绝
  - **操作步骤**：
    1. 发送需要健康数据的消息
  - **预期结果**：HealthKit 拒绝后返回空数据，UI 提示「请在设置中授权 HealthKit」
  - **失败排查**：检查 authorizationStatus；查看 empty data fallback

- [ ] 请求授权按钮
  - **前置条件**：进入 HealthSettingsView
  - **操作步骤**：
    1. 点击「请求授权」Button
  - **预期结果**：HealthSettingsView「请求授权」Button 点击后触发 HealthKit 授权流程
  - **失败排查**：检查 requestAuthorization 调用；查看 HKStore

- [ ] 跳转系统设置按钮
  - **前置条件**：进入 HealthSettingsView
  - **操作步骤**：
    1. 点击「跳转系统设置」Button
  - **预期结果**：HealthSettingsView「跳转系统设置」Button 点击后跳转到 App 设置页
  - **失败排查**：检查 UIApplication.shared.open；查看 URL scheme

- [ ] 健康上下文注入开启
  - **前置条件**：HealthKit 已授权
  - **操作步骤**：
    1. 开启 Toggle「健康上下文注入」
    2. 发送消息
    3. 查看 DebugPanel 中 system prompt
  - **预期结果**：Toggle「健康上下文注入」开启后，发送消息时 system prompt 含「用户最近 24h：睡眠 Xh，心率 Ybpm，步数 Z」
  - **失败排查**：检查 HealthContextBuilder；查看 system prompt 拼接

- [ ] 健康上下文关闭不注入
  - **前置条件**：「健康上下文注入」已开启
  - **操作步骤**：
    1. 关闭 Toggle
    2. 发送消息
    3. 查看 DebugPanel 中 system prompt
  - **预期结果**：关闭「健康上下文注入」后 system prompt 不含健康数据
  - **失败排查**：检查 Toggle binding；查看 system prompt 拼接条件

- [ ] DebugPanel 展示健康上下文
  - **前置条件**：健康上下文注入已开启
  - **操作步骤**：
    1. 发送消息后打开 DebugPanel
  - **预期结果**：DebugPanel 展示「健康上下文：已注入（24h 睡眠 Xh / 心率 Ybpm / 步数 Z）」
  - **失败排查**：检查 DebugPanel.healthContext；查看字段格式化

- [ ] 立即生成洞察按钮
  - **前置条件**：HealthKit 已授权，已配置 LLM
  - **操作步骤**：
    1. 点击「立即生成洞察」Button
  - **预期结果**：「立即生成洞察」Button 点击后调用 LLM 生成洞察文本
  - **失败排查**：检查 HealthInsightService.generate；查看 LLM 调用

- [ ] 洞察文本含免责声明
  - **前置条件**：洞察文本已生成
  - **操作步骤**：
    1. 查看洞察文本末尾
  - **预期结果**：洞察文本末尾含免责声明「⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议」
  - **失败排查**：检查 HealthInsightService.appendDisclaimer；查看模板

- [ ] 历史 HealthInsight 列表
  - **前置条件**：已生成过洞察
  - **操作步骤**：
    1. 进入 HealthSettingsView List
  - **预期结果**：HealthSettingsView List 展示历史 HealthInsight 记录（按时间倒序）
  - **失败排查**：检查 FetchDescriptor sortDescriptors；查看 SwiftUI List

- [ ] BGTaskScheduler health-insight 触发
  - **前置条件**：App 进入后台至 09:00
  - **操作步骤**：
    1. App 进入后台
    2. 等待至 09:00
  - **预期结果**：BGTaskScheduler health-insight 任务每天 09:00 触发生成洞察
  - **失败排查**：检查 BGTaskScheduler identifier；查看 trigger date

- [ ] 洞察生成后通知
  - **前置条件**：洞察已生成
  - **操作步骤**：
    1. 触发洞察生成
    2. 查看通知中心
  - **预期结果**：洞察生成后推送本地通知「AI 健康洞察已生成，点击查看」
  - **失败排查**：检查 UNUserNotificationCenter；查看 trigger

- [ ] WatchConnectivityService 同步对话
  - **前置条件**：iOS 与 watchOS 均已启动
  - **操作步骤**：
    1. iOS 端切换会话
  - **预期结果**：WatchConnectivityService 在 iOS 端切换对话后发送 activeConversationId 到 watchOS
  - **失败排查**：检查 WCSession.sendMessage；查看 session reachable

- [ ] watchOS 接收对话接力
  - **前置条件**：iOS 已切换会话
  - **操作步骤**：
    1. 查看 watchOS App
  - **预期结果**：watchOS 接收对话接力后展示完整消息历史
  - **失败排查**：检查 didReceiveMessage；查看消息解码

- [ ] watchOS 发送 quickChat
  - **前置条件**：watchOS 与 iOS 已连接
  - **操作步骤**：
    1. watchOS 点击 quickChat 按钮
  - **预期结果**：watchOS 发送 quickChat 消息后 iOS 端处理并回传回复
  - **失败排查**：检查 quickChat handler；查看 iOS 端 LLM 调用

## 14. App Intents 与系统集成（Day 18）

### 14.1 Shortcuts 真实对话

- [ ] Ask AIBuilder 真实回复
  - **前置条件**：API Key 已配置
  - **操作步骤**：
    1. 在 Shortcuts app 中创建快捷指令
    2. 添加「Ask AIBuilder」动作
    3. 输入 query 并运行
  - **预期结果**：Shortcuts app 中「Ask AIBuilder」动作输入 query，返回真实 LLM 回复（非占位文本）
  - **失败排查**：检查 AppIntent.perform；查看 LLM provider 注入

- [ ] 未配置 API Key 时 Intent 提示
  - **前置条件**：API Key 未配置
  - **操作步骤**：
    1. 在 Shortcuts 中执行 Intent
  - **预期结果**：未配置 API Key 时执行 Intent，返回提示「请先在 App 中配置 API Key」
  - **失败排查**：检查 API Key 校验；查看错误文案

- [ ] LLM 调用失败返回错误
  - **前置条件**：API Key 已配置但故意填错
  - **操作步骤**：
    1. 在 Shortcuts 中执行 Intent
  - **预期结果**：LLM 调用失败时返回错误提示文本
  - **失败排查**：检查 error catch；查看错误展示

### 14.2 辅助 App Intent

- [ ] New Conversation 动作
  - **前置条件**：App 已安装
  - **操作步骤**：
    1. 在 Shortcuts 中执行「New Conversation」动作
  - **预期结果**：Shortcuts app 中「New Conversation」动作执行后创建新会话，返回 conversationId
  - **失败排查**：检查 NewConversationIntent.perform；查看 SwiftData 写入

- [ ] Switch Conversation 动作
  - **前置条件**：会话列表至少有 1 个会话
  - **操作步骤**：
    1. 在 Shortcuts 中执行「Switch Conversation」动作
    2. 输入关键词
  - **预期结果**：Shortcuts app 中「Switch Conversation」动作输入关键词，返回匹配会话标题
  - **失败排查**：检查 SwitchConversationIntent 搜索逻辑；查看 predicate

- [ ] 未找到匹配会话提示
  - **前置条件**：会话列表为空或无匹配
  - **操作步骤**：
    1. 在 Shortcuts 中执行「Switch Conversation」动作输入不存在的关键词
  - **预期结果**：未找到匹配会话时返回「未找到匹配会话」
  - **失败排查**：检查空结果 fallback；查看 dialog

### 14.3 NSUserActivity Handoff

- [ ] iPhone 查看 iPad Handoff 图标
  - **前置条件**：iPhone 与 iPad 同一 Apple ID，均开启蓝牙/Wi-Fi
  - **操作步骤**：
    1. 在 iPhone 上查看会话 A
    2. 在 iPad 上打开 App Switcher
  - **预期结果**：在 iPhone 上查看会话 A，iPad App Switcher 出现 AIBuilder Handoff 图标
  - **失败排查**：检查 NSUserActivity userInfo；查看 Handoff 权限

- [ ] 点击 Handoff 打开 App
  - **前置条件**：iPad 上出现 Handoff 图标
  - **操作步骤**：
    1. 点击 iPad 上的 Handoff 图标
  - **预期结果**：点击 Handoff 图标后 iPad 端 App 打开并切换到会话 A
  - **失败排查**：检查 onContinueUserActivity；查看 conversationId 解析

- [ ] Handoff userInfo 字段
  - **前置条件**：Handoff 已触发
  - **操作步骤**：
    1. 查看 userInfo 内容（通过 DebugPanel 或日志）
  - **预期结果**：Handoff userInfo 含 conversationId / title / lastMessage
  - **失败排查**：检查 NSUserActivity.userInfo；查看字段写入

### 14.4 Spotlight 搜索集成

- [ ] Spotlight 搜索会话
  - **前置条件**：会话列表至少有 1 个会话
  - **操作步骤**：
    1. 在 iOS Spotlight 搜索会话标题关键词
  - **预期结果**：iOS Spotlight 搜索会话标题关键词，搜索结果展示匹配的 Conversation
  - **失败排查**：检查 CoreSpotlight index；查看 CSIndexExtension

- [ ] 搜索结果含标题与预览
  - **前置条件**：Spotlight 已索引会话
  - **操作步骤**：
    1. 在 Spotlight 输入会话标题关键词
  - **预期结果**：搜索结果含会话标题与最后一条消息预览
  - **失败排查**：检查 CSSearchableItem attributeset；查看 title/contentDescription

- [ ] 点击搜索结果打开 App
  - **前置条件**：Spotlight 出现搜索结果
  - **操作步骤**：
    1. 点击搜索结果
  - **预期结果**：点击搜索结果打开 App 并切换到对应会话
  - **失败排查**：检查 onContinueUserActivity；查看 identifier 解析

- [ ] 删除会话后 Spotlight 不出现
  - **前置条件**：会话已删除
  - **操作步骤**：
    1. 删除某会话
    2. 在 Spotlight 搜索该会话标题
  - **预期结果**：删除会话后 Spotlight 搜索不再出现该会话
  - **失败排查**：检查 deleteSearchableItems；查看 index 同步

## 15. 深度打磨：性能 / 无障碍 / 深色 / iPad（Day 19）

### 15.1 性能优化

- [ ] 长对话滚动流畅
  - **前置条件**：当前会话已有 50+ 条消息
  - **操作步骤**：
    1. 在长对话中快速上下滑动
  - **预期结果**：对话超过 50 条消息时滚动流畅，无明显卡顿
  - **失败排查**：检查 LazyVStack 使用；查看单元格复用

- [ ] 流式响应期间打字机流畅
  - **前置条件**：流式响应进行中
  - **操作步骤**：
    1. 发送长回复问题
    2. 流式过程中滑动查看
  - **预期结果**：流式响应期间打字机效果仍流畅（throttle 100ms 不影响观感）
  - **失败排查**：检查 throttle 配置；查看 main runloop

- [ ] DebugPanel 性能指标
  - **前置条件**：App 已启动
  - **操作步骤**：
    1. 打开 DebugPanel → 性能指标
  - **预期结果**：DebugPanel「性能指标」Section 展示启动耗时 / 首次响应耗时
  - **失败排查**：检查 PerformanceMonitor；查看 metric 记录

### 15.2 无障碍适配

- [ ] VoiceOver 朗读消息气泡
  - **前置条件**：VoiceOver 已开启
  - **操作步骤**：
    1. 在消息列表滑动选择
  - **预期结果**：VoiceOver 开启后，滑动选择消息气泡朗读完整消息文本（而非"气泡"）
  - **失败排查**：检查 accessibilityLabel；查看 accessibilityElement

- [ ] VoiceOver 朗读发送按钮
  - **前置条件**：VoiceOver 已开启
  - **操作步骤**：
    1. 滑动选择发送按钮
  - **预期结果**：VoiceOver 朗读发送按钮为「发送」+ hint「发送消息」
  - **失败排查**：检查 Button accessibilityLabel；查看 accessibilityHint

- [ ] VoiceOver 朗读麦克风按钮
  - **前置条件**：VoiceOver 已开启
  - **操作步骤**：
    1. 滑动选择麦克风按钮
  - **预期结果**：VoiceOver 朗读麦克风按钮为「语音输入」
  - **失败排查**：检查 accessibilityLabel；查看按钮修饰符

- [ ] VoiceOver 朗读 StepCard
  - **前置条件**：VoiceOver 已开启，已触发工具调用
  - **操作步骤**：
    1. 滑动选择 StepCard
  - **预期结果**：VoiceOver 朗读 StepCard 为「工具步骤：{toolName}」
  - **失败排查**：检查 StepCard accessibilityLabel；查看 toolName 绑定

- [ ] Dynamic Type XL 消息气泡
  - **前置条件**：辅助功能 → 更大文字 → 调到 XL
  - **操作步骤**：
    1. 调到 XL 后查看消息列表
  - **预期结果**：Dynamic Type 调到 XL（辅助功能 → 更大文字），消息气泡不截断
  - **失败排查**：检查 minimumScaleFactor；查看 lineLimit

- [ ] Dynamic Type XL 设置页
  - **前置条件**：Dynamic Type 已调到 XL
  - **操作步骤**：
    1. 进入设置页查看 Toggle / Picker 行
  - **预期结果**：Dynamic Type 调到 XL，设置页 Toggle / Picker 行不截断
  - **失败排查**：检查 FixedSize 修饰；查看 Form row layout

### 15.3 深色模式

- [ ] 深色模式消息气泡对比度
  - **前置条件**：系统切到深色模式
  - **操作步骤**：
    1. 进入主对话界面查看消息气泡
  - **预期结果**：深色模式下消息气泡（用户蓝底白字 / 助手灰底黑字）对比度达标
  - **失败排查**：检查 Color asset dark appearance；查看对比度

- [ ] 深色模式卡片背景可读
  - **前置条件**：深色模式已开启，已触发工具调用与 RAG 引用
  - **操作步骤**：
    1. 查看 StepCard / CitationCard
  - **预期结果**：深色模式下 StepCard / CitationCard 卡片背景可读
  - **失败排查**：检查卡片背景色 asset；查看 textColor 适配

- [ ] 深色模式 Divider 可见
  - **前置条件**：深色模式已开启
  - **操作步骤**：
    1. 查看含 Divider 的页面
  - **预期结果**：深色模式下 Divider / 边框可见
  - **失败排查**：检查 Divider color；查看 separator 适配

- [ ] 深色模式空状态可读
  - **前置条件**：深色模式已开启，无任何会话
  - **操作步骤**：
    1. 进入空状态页面
  - **预期结果**：深色模式下空状态 halo 渐变可读
  - **失败排查**：检查 EmptyStateView 渐变色；查看 opacity

- [ ] 深色模式设置页文字可读
  - **前置条件**：深色模式已开启
  - **操作步骤**：
    1. 进入设置页
  - **预期结果**：深色模式下设置页所有文字可读
  - **失败排查**：检查 foregroundStyle；查看 secondary color 适配

### 15.4 iPad 适配

- [ ] iPad 竖屏双列布局
  - **前置条件**：iPad 真机或模拟器
  - **操作步骤**：
    1. iPad 竖屏打开 App
  - **预期结果**：iPad 竖屏打开 App，左侧侧栏展示会话列表，右侧主区展示对话
  - **失败排查**：检查 NavigationSplitView；查看 horizontalSizeClass

- [ ] iPad 横屏双列布局
  - **前置条件**：iPad 真机或模拟器
  - **操作步骤**：
    1. iPad 横屏打开 App
  - **预期结果**：iPad 横屏打开 App，同上双列布局
  - **失败排查**：检查 NavigationSplitView；查看 size class

- [ ] iPad 侧栏切换会话
  - **前置条件**：iPad 双列布局已展示
  - **操作步骤**：
    1. 点击侧栏不同会话
  - **预期结果**：点击侧栏会话切换主区内容
  - **失败排查**：检查 selection binding；查看 NavigationSplitView

- [ ] iPad 输入框居中
  - **前置条件**：iPad 进入主对话界面
  - **操作步骤**：
    1. 查看输入框位置
  - **预期结果**：iPad 上输入框居中（maxWidth 600），不拉伸整宽
  - **失败排查**：检查 maxWidth 修饰；查看 frame

- [ ] iPhone 竖屏单列布局
  - **前置条件**：iPhone 真机或模拟器
  - **操作步骤**：
    1. iPhone 竖屏打开 App
  - **预期结果**：iPhone 竖屏保持现有单列布局不变
  - **失败排查**：检查 NavigationStack；查看 size class

- [ ] iPhone 横屏双列布局
  - **前置条件**：iPhone Plus 机型
  - **操作步骤**：
    1. iPhone 横屏打开 App
  - **预期结果**：iPhone 横屏（Plus 机型）触发 NavigationSplitView 双列布局
  - **失败排查**：检查 horizontalSizeClass == .regular；查看 size class 判定

## 16. 上架准备：隐私 / 反馈 / 崩溃监控（Day 20）

### 16.1 隐私清单与隐私政策

- [ ] PrivacyInfo.xcprivacy 存在
  - **前置条件**：Xcode 打开 AIBuilder 工程
  - **操作步骤**：
    1. 查看 AIBuilder target Resources
  - **预期结果**：`PrivacyInfo.xcprivacy` 文件存在于 AIBuilder target Resources
  - **失败排查**：检查 Build Phases → Copy Bundle Resources；查看文件位置

- [ ] NSPrivacyTracking = false
  - **前置条件**：打开 PrivacyInfo.xcprivacy
  - **操作步骤**：
    1. 查看 NSPrivacyTracking 字段
  - **预期结果**：NSPrivacyTracking = false
  - **失败排查**：检查 plist 字段；查看 tracking 声明

- [ ] NSPrivacyAccessedAPITypes 声明
  - **前置条件**：打开 PrivacyInfo.xcprivacy
  - **操作步骤**：
    1. 查看 NSPrivacyAccessedAPITypes
  - **预期结果**：NSPrivacyAccessedAPITypes 声明 UserDefaults / FileTimestamp / SystemBootTime
  - **失败排查**：检查 API reason codes；查看 required reason

- [ ] 隐私政策展示
  - **前置条件**：进入设置 → 关于
  - **操作步骤**：
    1. 点击「隐私政策」
  - **预期结果**：设置页「关于」Section 中点击「隐私政策」展示完整政策文本
  - **失败排查**：检查 NavigationLink；查看 PrivacyPolicyView

- [ ] 隐私政策含四段
  - **前置条件**：隐私政策已打开
  - **操作步骤**：
    1. 滚动查看隐私政策
  - **预期结果**：隐私政策含数据收集范围 / 第三方 SDK / 用户权利 / 联系方式四段
  - **失败排查**：检查 PrivacyPolicyView 内容；查看 markdown

### 16.2 投诉反馈

- [ ] 设置页展示版本号
  - **前置条件**：进入设置 → 关于
  - **操作步骤**：
    1. 查看「关于」Section
  - **预期结果**：设置页「关于」Section 展示 App 版本号
  - **失败排查**：检查 Bundle.main.infoDictionary；查看 CFBundleShortVersionString

- [ ] 投诉反馈打开邮件
  - **前置条件**：设备已配置邮件账户
  - **操作步骤**：
    1. 点击「投诉反馈」
  - **预期结果**：点击「投诉反馈」打开系统邮件 composer
  - **失败排查**：检查 MFMailComposeViewController；查看 canSendMail

- [ ] 邮件收件人预填
  - **前置条件**：邮件 composer 已打开
  - **操作步骤**：
    1. 查看收件人字段
  - **预期结果**：邮件收件人预填 feedback@aibuilder.app
  - **失败排查**：检查 setToRecipients；查看 email 配置

- [ ] 邮件主题预填
  - **前置条件**：邮件 composer 已打开
  - **操作步骤**：
    1. 查看主题字段
  - **预期结果**：邮件主题预填「AI Builder 用户反馈」
  - **失败排查**：检查 setSubject；查看主题字符串

- [ ] 邮件正文含设备信息
  - **前置条件**：邮件 composer 已打开
  - **操作步骤**：
    1. 查看正文字段
  - **预期结果**：邮件正文含设备信息（机型 / iOS 版本 / App 版本）
  - **失败排查**：检查 setMessageBody；查看设备信息收集

- [ ] 未配置邮件账户降级
  - **前置条件**：设备未配置邮件账户
  - **操作步骤**：
    1. 点击「投诉反馈」
  - **预期结果**：未配置邮件账户时降级到 mailto: URL 或提示
  - **失败排查**：检查 canSendMail fallback；查看 mailto URL

### 16.3 崩溃监控

- [ ] CrashReportService 初始化
  - **前置条件**：App 启动
  - **操作步骤**：
    1. 启动 App
    2. 查看 Debug 日志
  - **预期结果**：App 启动时 CrashReportService 初始化（Debug 日志输出）
  - **失败排查**：检查 CrashReportService.initialize；查看日志开关

- [ ] 匿名用户标识生成
  - **前置条件**：App 首次启动
  - **操作步骤**：
    1. 启动 App
    2. 查看 UserDefaults
  - **预期结果**：匿名用户标识生成并存储到 UserDefaults
  - **失败排查**：检查 UUID 生成；查看 UserDefaults key

- [ ] LLM 失败调用 reportException
  - **前置条件**：API Key 故意填错
  - **操作步骤**：
    1. 发送消息触发 LLM 调用失败
  - **预期结果**：LLM 调用失败时 CrashReportService.reportException 被调用
  - **失败排查**：检查 catch 中 reportException 调用；查看 error 类型

- [ ] Bugly 未集成时占位分支
  - **前置条件**：未集成 Bugly SDK
  - **操作步骤**：
    1. 启动 App
    2. 触发错误
  - **预期结果**：Bugly SDK 未集成时 App 正常运行（走占位分支）
  - **失败排查**：检查 #if canImport(Bugly)；查看 placeholder

- [ ] Info.plist Bugly 配置项
  - **前置条件**：Xcode 打开 Info.plist
  - **操作步骤**：
    1. 查看 BuglyAppKey / BuglyAppChannel
  - **预期结果**：Info.plist 含 BuglyAppKey / BuglyAppChannel 配置项
  - **失败排查**：检查 Info.plist；查看字段类型

### 16.4 发布检查

- [ ] Archive 构建
  - **前置条件**：Xcode 选 Generic iOS Device
  - **操作步骤**：
    1. Product → Archive
  - **预期结果**：Archive 构建无 warning（Scheme: Generic iOS Device）
  - **失败排查**：查看 Build Log；修复 warning

- [ ] TestFlight 上传
  - **前置条件**：Archive 已生成
  - **操作步骤**：
    1. Distribute App → TestFlight
  - **预期结果**：TestFlight 上传成功
  - **失败排查**：查看上传日志；检查证书

- [ ] App Store 元数据
  - **前置条件**：登录 App Store Connect
  - **操作步骤**：
    1. 填写名称 / 副标题 / 描述 / 关键词
  - **预期结果**：App Store 元数据填写完整（名称 / 副标题 / 描述 / 关键词）
  - **失败排查**：检查字段长度限制；查看本地化

- [ ] App Store 截图上传
  - **前置条件**：已生成截图
  - **操作步骤**：
    1. 上传 6.7" 与 6.1" 截图
  - **预期结果**：App Store 截图上传（6.7" / 6.1" 各 5-6 张）
  - **失败排查**：检查截图尺寸；查看格式要求

- [ ] 年龄分级设置
  - **前置条件**：进入 App Store Connect 年龄分级
  - **操作步骤**：
    1. 设置 17+
  - **预期结果**：年龄分级设置（17+，含 AI 生成内容）
  - **失败排查**：检查年龄分级问卷；查看 AI 内容选项

- [ ] ReleaseChecklist 完成
  - **前置条件**：发布前
  - **操作步骤**：
    1. 参照 [ReleaseChecklist.md](file:///Users/xuchen/Documents/AIBuiler/doc/ReleaseChecklist.md) 完成最终检查
  - **预期结果**：参照 ReleaseChecklist.md 完成最终检查
  - **失败排查**：查看 ReleaseChecklist 各项

## 17. Markdown 渲染（补充迭代）

- [ ] 代码块渲染
  - **前置条件**：助手消息含 markdown 代码块
  - **操作步骤**：
    1. 发送要求 AI 返回代码块的问题
    2. 查看渲染效果
  - **预期结果**：助手消息中代码块以深色背景卡片展示，含语言标签与复制按钮
  - **失败排查**：检查 CodeBlockView；查看 markdown parser

- [ ] 代码块语法高亮
  - **前置条件**：助手返回含代码块
  - **操作步骤**：
    1. 测试 Python / Swift / JavaScript / JSON / Bash 等语言
  - **预期结果**：代码块语法高亮正确（测试 Python / Swift / JavaScript / JSON / Bash 等语言）
  - **失败排查**：检查 Highlightr 集成；查看主题

- [ ] Markdown 表格渲染
  - **前置条件**：助手消息含 markdown 表格
  - **操作步骤**：
    1. 发送要求 AI 返回表格的问题
  - **预期结果**：Markdown 表格正确渲染为带边框表格，列对齐正确
  - **失败排查**：检查 MarkdownTableParser；查看 TableColumn alignment

- [ ] 任务列表渲染
  - **前置条件**：助手消息含 `- [ ]` 或 `- [x]`
  - **操作步骤**：
    1. 发送要求返回任务列表的问题
  - **预期结果**：任务列表 `- [ ]` / `- [x]` 渲染为可点击 checkbox（仅展示，不可交互）
  - **失败排查**：检查 CheckboxView；查看 markdown parser

- [ ] 标题分级
  - **前置条件**：助手消息含 H1-H6
  - **操作步骤**：
    1. 发送要求返回多级标题的问题
  - **预期结果**：标题 H1-H6 字号与样式分级正确，H1/H2 下方有 Divider
  - **失败排查**：检查 HeadingView；查看字号映射

## 18. TTS 音色可调节（补充迭代）

- [ ] 音色 Picker 分组
  - **前置条件**：进入设置 → 语音朗读
  - **操作步骤**：
    1. 查看音色 Picker
  - **预期结果**：设置 → 语音朗读 → 音色 Picker 按语言分组（zh-CN 优先）
  - **失败排查**：检查 Picker items；查看分组逻辑

- [ ] 切换音色立即生效
  - **前置条件**：音色 Picker 已展示
  - **操作步骤**：
    1. 选择不同音色
    2. 触发朗读
  - **预期结果**：选择不同音色后立即生效，下次朗读使用新音色
  - **失败排查**：检查 AVSpeechSynthesisVoice；查看 voice binding

- [ ] 语速 Slider 试听
  - **前置条件**：进入语音朗读设置
  - **操作步骤**：
    1. 调节语速 Slider
    2. 点击「试听」
  - **预期结果**：语速 Slider 调节后试听预览生效
  - **失败排查**：检查 AVSpeechUtterance.rate；查看 slider binding

- [ ] 音调 Slider 试听
  - **前置条件**：进入语音朗读设置
  - **操作步骤**：
    1. 调节音调 Slider
    2. 点击「试听」
  - **预期结果**：音调 Slider 调节后试听预览生效
  - **失败排查**：检查 AVSpeechUtterance.pitchMultiplier；查看 slider binding

- [ ] 音量 Slider 试听
  - **前置条件**：进入语音朗读设置
  - **操作步骤**：
    1. 调节音量 Slider
    2. 点击「试听」
  - **预期结果**：音量 Slider 调节后试听预览生效
  - **失败排查**：检查 AVSpeechSynthesizer volume；查看 slider binding

- [ ] 试听按钮
  - **前置条件**：进入语音朗读设置
  - **操作步骤**：
    1. 点击「试听」按钮
    2. 朗读中再次点击
  - **预期结果**：点击「试听」按钮播放预览语音，再次点击停止
  - **失败排查**：检查试听 player；查看 stop logic

- [ ] 配置持久化
  - **前置条件**：已修改 TTS 配置
  - **操作步骤**：
    1. 退出设置页
    2. 查看 UserDefaults 中 ttsConfig
  - **预期结果**：配置离开设置页后持久化（UserDefaults key: ttsConfig）
  - **失败排查**：检查 UserDefaults 写入；查看 Codable 持久化

## 19. 消息复制与重新提问（补充迭代）

- [ ] 用户消息 contextMenu
  - **前置条件**：会话有用户消息
  - **操作步骤**：
    1. 长按用户消息气泡
  - **预期结果**：长按用户消息气泡弹出 contextMenu 含「复制」和「重新提问」
  - **失败排查**：检查 contextMenu；查看 menu items

- [ ] 助手消息 contextMenu
  - **前置条件**：助手消息已生成完成
  - **操作步骤**：
    1. 长按助手消息气泡
  - **预期结果**：长按助手消息气泡弹出 contextMenu 含「复制」（流式输出中不显示）
  - **失败排查**：检查 contextMenu；查看 isStreaming 判定

- [ ] 复制 toast
  - **前置条件**：contextMenu 已展开
  - **操作步骤**：
    1. 点击「复制」
  - **预期结果**：点击「复制」后底部显示 2 秒 toast「已复制」
  - **失败排查**：检查 UIPasteboard.string；查看 toast 实现

- [ ] 重新提问
  - **前置条件**：长按用户消息触发 contextMenu
  - **操作步骤**：
    1. 点击「重新提问」
  - **预期结果**：点击「重新提问」后输入框填充原消息内容并自动发送
  - **失败排查**：检查 input text binding；查看 send 触发

- [ ] 流式中不显示 contextMenu
  - **前置条件**：助手消息正在流式输出
  - **操作步骤**：
    1. 长按流式中的消息
  - **预期结果**：流式输出中的消息不显示 contextMenu
  - **失败排查**：检查 contextMenu availability；查看 isStreaming 判定

## 20. 批量多选删除会话（补充迭代）

- [ ] 进入编辑模式
  - **前置条件**：会话列表已展示
  - **操作步骤**：
    1. 点击会话列表左上角「编辑」按钮
  - **预期结果**：会话列表左上角「编辑」按钮点击后进入编辑模式
  - **失败排查**：检查 EditMode binding；查看 toggle

- [ ] 选中状态切换
  - **前置条件**：已进入编辑模式
  - **操作步骤**：
    1. 点击每行左侧圆形 checkbox
  - **预期结果**：编辑模式下每行左侧出现圆形 checkbox，点击切换选中状态
  - **失败排查**：检查 selection Set；查看 toggle gesture

- [ ] 底部工具栏
  - **前置条件**：已进入编辑模式
  - **操作步骤**：
    1. 查看底部工具栏
  - **预期结果**：底部工具栏显示「全选」与「删除选中」按钮
  - **失败排查**：检查 toolbar；查看按钮显示条件

- [ ] 全选与取消全选
  - **前置条件**：已进入编辑模式
  - **操作步骤**：
    1. 点击「全选」
    2. 再次点击
  - **预期结果**：点击「全选」选中所有会话，再点击取消全选
  - **失败排查**：检查 selection Set 全选逻辑；查看 toggle

- [ ] 删除确认 alert
  - **前置条件**：已选中至少 1 个会话
  - **操作步骤**：
    1. 点击「删除选中」
  - **预期结果**：点击「删除选中」弹出确认 alert（取消 / 删除）
  - **失败排查**：检查 alert binding；查看 confirmationDialog

- [ ] 删除生效
  - **前置条件**：删除 alert 已展示
  - **操作步骤**：
    1. 点击「删除」
  - **预期结果**：确认删除后选中的会话从列表与 SwiftData 中移除
  - **失败排查**：检查 modelContext.delete；查看 save 调用

- [ ] 退出编辑模式
  - **前置条件**：已进入编辑模式
  - **操作步骤**：
    1. 点击「完成」按钮
  - **预期结果**：点击「完成」按钮退出编辑模式
  - **失败排查**：检查 EditMode.active → .inactive；查看按钮

## 21. 多平台适配（iOS / iPad / macOS）

### 21.1 iOS 端

- [ ] iOS App 启动进入主界面
  - **前置条件**：iOS 17+ 真机或模拟器
  - **操作步骤**：
    1. 启动 App
    2. 等待进入主界面
  - **预期结果**：iOS 模拟器启动 App，进入主界面
  - **失败排查**：检查 SceneDelegate；查看 launch screen

- [ ] 单栏 NavigationStack 布局
  - **前置条件**：iOS 17+ 真机或模拟器
  - **操作步骤**：
    1. 启动 App
    2. 查看主界面布局
  - **预期结果**：单栏 NavigationStack，顶部工具栏含设置按钮
  - **失败排查**：检查 SettingsView compactLayout 分支；查看 NavigationStack

- [ ] 会话列表与聊天切换流畅
  - **前置条件**：会话列表至少有 1 个会话
  - **操作步骤**：
    1. 在会话列表与聊天界面间切换
  - **预期结果**：会话列表与聊天界面切换流畅
  - **失败排查**：检查 NavigationStack push/pop；查看动画

- [ ] 健康设置入口可见
  - **前置条件**：iOS 端进入设置页
  - **操作步骤**：
    1. 进入 Settings
    2. 查看 HealthKit 入口
  - **预期结果**：健康设置入口可见（Settings 中 HealthKit）
  - **失败排查**：检查 SettingsView HealthKit Section；查看条件编译

- [ ] 麦克风按钮可点击授权
  - **前置条件**：iOS 端进入主对话界面
  - **操作步骤**：
    1. 点击麦克风按钮
  - **预期结果**：麦克风按钮可点击授权，弹出权限弹窗
  - **失败排查**：检查 NSMicrophoneUsageDescription；查看 SFSpeechRecognizer 权限

- [ ] 灵动岛 Live Activity 显示
  - **前置条件**：iPhone 14 Pro+ 真机
  - **操作步骤**：
    1. 触发 Live Activity
  - **预期结果**：灵动岛 Live Activity 显示正常（iOS 16.1+）
  - **失败排查**：检查 ActivityKit 权限；查看 widget extension

- [ ] 后台任务 BGTaskScheduler 注册
  - **前置条件**：iOS 端 App 启动
  - **操作步骤**：
    1. 启动 App
    2. 查看注册日志
  - **预期结果**：后台任务 BGTaskScheduler 注册成功
  - **失败排查**：检查 BGTaskScheduler.register；查看 identifier

### 21.2 iPad 端

- [ ] iPad App 启动进入主界面
  - **前置条件**：iPad 真机或模拟器
  - **操作步骤**：
    1. 启动 App
    2. 等待进入主界面
  - **预期结果**：iPad 模拟器启动 App，进入主界面
  - **失败排查**：检查 SceneDelegate；查看 launch screen

- [ ] 双栏 NavigationSplitView 布局
  - **前置条件**：iPad 真机或模拟器
  - **操作步骤**：
    1. 启动 App
    2. 查看主界面布局
  - **预期结果**：双栏 NavigationSplitView 布局正常（左侧会话列表 + 右侧聊天）
  - **失败排查**：检查 NavigationSplitView；查看 horizontalSizeClass

- [ ] 横竖屏切换布局自适应
  - **前置条件**：iPad 已进入主界面
  - **操作步骤**：
    1. 横屏切换到竖屏
    2. 竖屏切换到横屏
  - **预期结果**：横竖屏切换布局自适应
  - **失败排查**：检查 SceneDelegate orientation；查看 size class 变化

- [ ] 健康设置入口可见
  - **前置条件**：iPad 端进入设置页
  - **操作步骤**：
    1. 进入 Settings
    2. 查看 HealthKit 入口
  - **预期结果**：健康设置入口可见
  - **失败排查**：检查 SettingsView HealthKit Section；查看条件编译

### 21.3 macOS 端

- [ ] macOS App 启动进入主界面
  - **前置条件**：macOS 14+ 真机
  - **操作步骤**：
    1. 启动 App
    2. 等待进入主界面
  - **预期结果**：macOS 启动 App，进入主界面
  - **失败排查**：检查 SceneDelegate / NSWindow；查看 launch

- [ ] 窗口默认尺寸 1000×700
  - **前置条件**：macOS 启动 App
  - **操作步骤**：
    1. 查看默认窗口尺寸
  - **预期结果**：窗口默认尺寸 1000×700
  - **失败排查**：检查 WindowGroup defaultSize；查看 frame 配置

- [ ] 菜单栏命令可用
  - **前置条件**：macOS 进入主界面
  - **操作步骤**：
    1. 测试 ⌘N 新建会话
    2. 测试 ⌘K 搜索
    3. 测试 ⌘, 打开设置
  - **预期结果**：菜单栏命令：⌘N 新建会话、⌘K 搜索、⌘, 打开设置
  - **失败排查**：检查 CommandGroup；查看 keyboardShortcut

- [ ] ⌘Enter 发送消息
  - **前置条件**：macOS 进入主对话界面
  - **操作步骤**：
    1. 输入框输入文本
    2. 按 ⌘Enter
    3. 测试 Enter 换行
  - **预期结果**：⌘Enter 发送消息（Enter 换行）
  - **失败排查**：检查 keyboardShortcut；查看 onSubmit

- [ ] 双栏 NavigationSplitView 布局
  - **前置条件**：macOS 进入主界面
  - **操作步骤**：
    1. 查看主界面布局
  - **预期结果**：双栏 NavigationSplitView 布局正常
  - **失败排查**：检查 NavigationSplitView；查看 column visibility

- [ ] HealthKit 入口隐藏
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 查看设置项
  - **预期结果**：HealthKit 入口隐藏（Settings 中无健康设置项）
  - **失败排查**：检查 `#if os(iOS)` 守卫；查看 Section 隐藏

- [ ] HealthInsight 模型仍注册
  - **前置条件**：macOS 启动 App
  - **操作步骤**：
    1. 查看 SwiftData schema
  - **预期结果**：HealthInsight 模型仍注册（SwiftData schema 无报错）
  - **失败排查**：检查 ModelContainer schema；查看 model registration

- [ ] 优雅降级
  - **前置条件**：macOS 启动 App
  - **操作步骤**：
    1. 触发 BGTaskScheduler / ActivityKit / WatchConnectivity 相关功能
  - **预期结果**：BGTaskScheduler / ActivityKit / WatchConnectivity 优雅降级（无崩溃）
  - **失败排查**：检查 `#if os(iOS)` 守卫；查看 placeholder 实现

- [ ] DocumentPickerView 文件选择
  - **前置条件**：macOS 进入知识库导入页
  - **操作步骤**：
    1. 点击「导入文档」
  - **预期结果**：DocumentPickerView 用 `.fileImporter` 正常选择文件
  - **失败排查**：检查 fileImporter；查看 allowedContentTypes

- [ ] FeedbackService 设备信息
  - **前置条件**：macOS 进入投诉反馈
  - **操作步骤**：
    1. 打开邮件 composer
    2. 查看正文
  - **预期结果**：FeedbackService 用 ProcessInfo 获取设备信息正常
  - **失败排查**：检查 ProcessInfo.processInfo；查看 device info 拼接

## 22. 工具能力增强（20 个新工具）

### 22.1 跨平台工具（iOS + macOS）

- [ ] LocationTool 返回坐标与逆地理编码
  - **前置条件**：定位权限已授权，网络通畅
  - **操作步骤**：
    1. 发送「定位」
  - **预期结果**：返回经纬度与逆地理编码（10s 内返回坐标 + 中文地址）
  - **失败排查**：检查 CLLocationManager；查看 reverse geocode 调用

- [ ] DeviceInfoTool 返回设备信息
  - **前置条件**：工具已注册并启用
  - **操作步骤**：
    1. 发送「设备信息」
  - **预期结果**：返回设备型号 / OS 版本 / 电量 / 可用存储
  - **失败排查**：检查 UIDevice / ProcessInfo；查看字段获取

- [ ] ClipboardTool 读写剪贴板
  - **前置条件**：工具已注册并启用
  - **操作步骤**：
    1. 发送「读剪贴板」查看返回内容
    2. 发送「写剪贴板：xxx」查看写入成功
  - **预期结果**：读返回剪贴板内容；写返回写入成功
  - **失败排查**：检查 UIPasteboard.general；查看 clipboard 操作

- [ ] OpenURLTool 打开 URL
  - **前置条件**：工具已注册并启用
  - **操作步骤**：
    1. 发送「打开 https://apple.com」
  - **预期结果**：系统浏览器打开 https://apple.com
  - **失败排查**：检查 UIApplication.shared.open；查看 URL 校验

- [ ] ContactsTool 搜索联系人
  - **前置条件**：通讯录权限已授权
  - **操作步骤**：
    1. 发送「搜索联系人 张三」
  - **预期结果**：返回匹配的联系人信息
  - **失败排查**：检查 CNContactStore；查看 NSContactsUsageDescription

- [ ] WeatherTool 查询天气
  - **前置条件**：网络通畅
  - **操作步骤**：
    1. 发送「北京天气」
    2. 发送「天气」（无 city 参数）
  - **预期结果**：北京天气返回天气信息；无 city 参数返回当前位置天气
  - **失败排查**：检查 Weather API 调用；查看 city 参数解析

### 22.2 macOS 独有工具

- [ ] AppleScriptTool 执行脚本
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「用 AppleScript 弹窗」
  - **预期结果**：AppleScriptTool：run_applescript 执行 `return "hello"` 返回 hello
  - **失败排查**：检查 NSAppleScript；查看 executionPolicy

- [ ] ScreenshotTool 截屏
  - **前置条件**：macOS 平台，屏幕录制权限已授权
  - **操作步骤**：
    1. 发送「截屏」
  - **预期结果**：截屏保存 PNG 到临时目录
  - **失败排查**：检查 CGWindowListCreateImage；查看权限

- [ ] OCRTool 识别文字
  - **前置条件**：macOS 平台，已准备图片
  - **操作步骤**：
    1. 发送图片 OCR 识别（有 image_path）
    2. 发送「OCR 识别」（无 image_path，自动截屏）
  - **预期结果**：识别图片文字并返回
  - **失败排查**：检查 Vision framework；查看 image_path 解析

- [ ] TerminalCommandTool 执行命令
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「执行 ls -la」
    2. 发送「执行 rm -rf /」
  - **预期结果**：执行 `echo hello` 返回 hello；危险命令 `rm -rf /` 被拒绝
  - **失败排查**：检查 Process；查看黑名单

- [ ] WindowManagementTool 管理窗口
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「最小化窗口」
    2. 发送「列出所有窗口」
  - **预期结果**：action=list 列出窗口；action=minimize 最小化
  - **失败排查**：检查 NSWorkspace.runningApplications；查看 window list API

- [ ] AppManagementTool 管理应用
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「打开 Safari」
    2. 发送「列出运行中应用」
  - **预期结果**：action=list_running 列出运行中应用；action=open 打开指定应用
  - **失败排查**：检查 NSWorkspace.open；查看 app identifier 解析

- [ ] FileOperationTool 文件操作
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「读取 ~/Documents/test.txt」
    2. 发送「列出 ~/Downloads 目录」
    3. 发送「删除 ~/Documents/test.txt」
  - **预期结果**：action=list 列出目录文件；action=delete 移到废纸篓
  - **失败排查**：检查 FileManager；查看权限

- [ ] FinderTool Finder 操作
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「在 Finder 显示 ~/Documents」
    2. 发送「获取 Finder 选中项」
  - **预期结果**：action=get_selection 获取 Finder 选中项；action=reveal 在 Finder 显示
  - **失败排查**：检查 NSWorkspace.activateFileViewerSelecting；查看 AppleScript

- [ ] SafariControlTool 控制 Safari
  - **前置条件**：macOS 平台，Safari 已运行
  - **操作步骤**：
    1. 发送「在 Safari 打开 apple.com」
    2. 发送「列出 Safari 标签页」
  - **预期结果**：action=list_tabs 列出 Safari 标签页；action=open_url 打开 URL
  - **失败排查**：检查 AppleScript 控制 Safari；查看 script 编译

- [ ] SystemControlTool 系统控制
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「锁定屏幕」
    2. 发送「获取音量」
  - **预期结果**：action=get_volume 获取音量；action=lock_screen 锁定屏幕
  - **失败排查**：检查 AppleScript；查看 system events

- [ ] InputAutomationTool 模拟输入
  - **前置条件**：macOS 平台，辅助功能权限已授权
  - **操作步骤**：
    1. 发送「模拟输入 hello」
  - **预期结果**：action=key_type 输入字符
  - **失败排查**：检查 CGEvent；查看辅助功能权限

### 22.3 快捷指令工具（跨平台）

- [ ] RunShortcutTool 运行快捷指令
  - **前置条件**：macOS 平台，已安装 Shortcuts app，至少有 1 个快捷指令
  - **操作步骤**：
    1. 发送「运行快捷指令 测试」
  - **预期结果**：运行一个已有快捷指令（macOS）
  - **失败排查**：检查 ShortcutsEvents.runShortcut；查看 name 解析

- [ ] ListShortcutsTool 列出快捷指令
  - **前置条件**：已安装 Shortcuts app
  - **操作步骤**：
    1. 发送「列出快捷指令」
  - **预期结果**：列出快捷指令（macOS 返回列表，iOS 返回提示）
  - **失败排查**：检查 ShortcutsEvents；查看 iOS 限制说明

- [ ] CreateShortcutTool 创建快捷指令
  - **前置条件**：macOS 平台，已安装 Shortcuts app
  - **操作步骤**：
    1. 测试 open_url 动作：发送「创建快捷指令 打开 apple.com」
    2. 测试 run_script 动作：发送「创建快捷指令 运行脚本 hello」
    3. 测试 show_text 动作：发送「创建快捷指令 显示文本 hello」
    4. 测试 copy_to_clipboard 动作：发送「创建快捷指令 复制到剪贴板 hello」
  - **预期结果**：创建快捷指令，测试 4 种动作均生成 .shortcut 文件
  - **失败排查**：检查 shortcut builder；查看 4 种 action 实现

## 23. macOS 设置导航修复

- [ ] TTS 音色选择二级页返回
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 点击「TTS 音色选择」
    2. 查看二级页顶部
  - **预期结果**：macOS 点击「TTS 音色选择」进入二级页，顶部出现返回按钮（<）
  - **失败排查**：检查 NavigationSplitView detail binding；查看 toolbar

- [ ] 返回按钮回到 Form
  - **前置条件**：已进入 TTS 音色二级页
  - **操作步骤**：
    1. 点击返回按钮
  - **预期结果**：点击返回按钮，回到「功能与偏好」Section 的 Form
  - **失败排查**：检查 dismiss；查看 navigation path

- [ ] 隐私政策二级页返回
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 点击「隐私政策」
    2. 查看返回按钮
    3. 点击返回
  - **预期结果**：macOS 点击「隐私政策」进入二级页，有返回按钮，可返回
  - **失败排查**：检查 NavigationLink；查看 toolbar 修饰

- [ ] 端侧模型管理二级页返回
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 点击「端侧模型管理」
    2. 查看返回按钮
    3. 点击返回
  - **预期结果**：macOS 点击「端侧模型管理」进入二级页，有返回按钮，可返回
  - **失败排查**：检查 NavigationLink；查看 toolbar 修饰

- [ ] sidebar 切换 detail 回根
  - **前置条件**：已进入某二级页
  - **操作步骤**：
    1. 切换左侧 sidebar 到其他分类
  - **预期结果**：在二级页时切换左侧 sidebar 到其他分类，右侧 detail 回到新分类的根 Form
  - **失败排查**：检查 selection binding；查看 NavigationSplitView

- [ ] iOS 端设置导航不受影响
  - **前置条件**：iOS 端进入设置页
  - **操作步骤**：
    1. 进入二级页
    2. 点击返回
  - **预期结果**：iOS 端设置导航不受影响（NavigationStack 正常）
  - **失败排查**：检查 NavigationStack；查看 `#if os(macOS)` 守卫

## 24. macOS markdown 视觉修复

- [ ] 表格三色可区分
  - **前置条件**：macOS 端，助手返回含 markdown 表格
  - **操作步骤**：
    1. 发送要求返回表格的问题
    2. 查看表头背景、交替行背景、气泡背景
  - **预期结果**：macOS 上 AI 回复含 markdown 表格，表头背景、交替行背景、气泡背景三色可区分
  - **失败排查**：检查 MarkdownTableView background；查看 color asset

- [ ] StreamingBubbleView 背景对比
  - **前置条件**：macOS 端，流式回复中
  - **操作步骤**：
    1. 发送消息触发流式回复
    2. 查看流式中的气泡背景
  - **预期结果**：macOS 上 StreamingBubbleView（流式回复中）背景与气泡背景有对比
  - **失败排查**：检查 StreamingBubbleView background；查看 streaming state

- [ ] 代码块/标题/任务列表渲染
  - **前置条件**：macOS 端，助手返回含代码块/标题/任务列表
  - **操作步骤**：
    1. 发送要求返回 markdown 多元素的问题
  - **预期结果**：macOS 上代码块、标题、任务列表渲染正常
  - **失败排查**：检查各 markdown 元素 view；查看 macOS color 适配

- [ ] iOS markdown 渲染不受影响
  - **前置条件**：iOS 端，助手返回含 markdown
  - **操作步骤**：
    1. 发送要求返回 markdown 的问题
  - **预期结果**：iOS 上 markdown 渲染不受影响（颜色仍用系统原生 UIColor）
  - **失败排查**：检查 `#if os(macOS)` 守卫；查看 UIColor 分支

## 25. macOS 语音朗读 UI 修复

- [ ] 朗读 UI 不卡顿
  - **前置条件**：macOS 端，已生成助手消息
  - **操作步骤**：
    1. 点击消息朗读按钮
  - **预期结果**：macOS 上点击消息朗读按钮，UI 不卡顿（MarkdownText 解析结果已缓存）
  - **失败排查**：检查 MarkdownText cache；查看 main thread

- [ ] 朗读中按钮变红色 stop
  - **前置条件**：macOS 端，朗读中
  - **操作步骤**：
    1. 查看朗读按钮图标
  - **预期结果**：朗读中按钮变红色 stop 图标
  - **失败排查**：检查 button systemImage；查看 state 切换

- [ ] 朗读自然结束按钮恢复
  - **前置条件**：macOS 端，朗读进行中
  - **操作步骤**：
    1. 等待朗读自然结束
  - **预期结果**：朗读自然结束后按钮恢复为 speaker 图标
  - **失败排查**：检查 AVSpeechSynthesizerDelegate didFinish；查看 state 重置

- [ ] 朗读中再次点击停止
  - **前置条件**：macOS 端，朗读中
  - **操作步骤**：
    1. 再次点击同一消息的朗读按钮
  - **预期结果**：朗读中再次点击同一消息，停止朗读，按钮恢复
  - **失败排查**：检查 stopReading；查看 state 重置

- [ ] 切换消息朗读
  - **前置条件**：macOS 端，朗读中
  - **操作步骤**：
    1. 点击另一条消息的朗读按钮
  - **预期结果**：朗读中切换到另一条消息朗读，先停旧的再开始新的
  - **失败排查**：检查 currentReadingMessage 切换；查看 stop then start

- [ ] 系统取消朗读按钮恢复
  - **前置条件**：macOS 端，朗读中
  - **操作步骤**：
    1. 通过系统抢占音频（如播放音乐）触发朗读取消
  - **预期结果**：（可选）系统取消朗读后（如音频被抢占），按钮自动恢复（不卡红）
  - **失败排查**：检查 AVSpeechSynthesizerDelegate didCancel；查看 state 重置

## 26. 预设系统提示词

- [ ] 预设角色 Menu 展示
  - **前置条件**：进入设置 → 功能与偏好 → 系统提示词
  - **操作步骤**：
    1. 打开系统提示词 Section
    2. 查看「预设角色」Menu
  - **预期结果**：打开「设置 → 功能与偏好 → 系统提示词」，看到「预设角色」Menu
  - **失败排查**：检查 PresetRoleMenu；查看 Picker items

- [ ] Menu 含 11 个角色
  - **前置条件**：预设角色 Menu 已展开
  - **操作步骤**：
    1. 点击 Menu
  - **预期结果**：点击 Menu 看到 11 个角色选项
  - **失败排查**：检查 PresetRole enum；查看 allCases

- [ ] 选择开发者填入 prompt
  - **前置条件**：Menu 已展开
  - **操作步骤**：
    1. 选择「开发者」
  - **预期结果**：选择「开发者」，TextEditor 填入开发者预设 prompt（≥ 150 字）
  - **失败排查**：检查 PresetRole.developer.promptText；查看 TextEditor binding

- [ ] TextEditor 可继续编辑
  - **前置条件**：已填入预设 prompt
  - **操作步骤**：
    1. 在 TextEditor 中继续编辑
  - **预期结果**：在 TextEditor 中可继续编辑已填入的 prompt
  - **失败排查**：检查 TextEditor binding；查看 state 持久化

- [ ] 完成保存并沿用
  - **前置条件**：已编辑 prompt
  - **操作步骤**：
    1. 点击「完成」
    2. 新建对话
  - **预期结果**：点击「完成」保存，新建对话沿用该 prompt
  - **失败排查**：检查 save 逻辑；查看 conversation 创建时引用

- [ ] 11 个角色全部测试
  - **前置条件**：Menu 已展开
  - **操作步骤**：
    1. 依次选择每个角色：默认助手/开发者/学生/白领/管理者/产品经理/写作助手/技术面试官/学习导师/翻译官/健身教练
  - **预期结果**：依次测试每个角色均能正确填入
  - **失败排查**：检查每个角色的 promptText；查看 allCases

## 多平台适配手测（细化）

本节对 iOS / iPad / macOS 三端逐项细化，作为发布前必验证项。

### iOS 端

- [ ] App 启动后单栏 NavigationStack 布局
  - **前置条件**：iOS 17+ 真机或模拟器
  - **操作步骤**：
    1. 启动 App
    2. 查看主界面布局
  - **预期结果**：单栏 NavigationStack，顶部工具栏含设置按钮
  - **失败排查**：检查 SettingsView compactLayout 分支；查看 NavigationStack

- [ ] 健康设置入口可见
  - **前置条件**：iOS 端进入设置页
  - **操作步骤**：
    1. 进入 Settings
    2. 查看 HealthKit Section
  - **预期结果**：健康设置入口可见，可点击进入 HealthSettingsView
  - **失败排查**：检查 `#if os(iOS)` 守卫；查看 Section 显示条件

- [ ] 麦克风按钮可点击授权
  - **前置条件**：iOS 端进入主对话界面
  - **操作步骤**：
    1. 点击麦克风按钮
    2. 在系统弹窗中点击「允许」
  - **预期结果**：麦克风按钮可点击授权，授权后开始录音
  - **失败排查**：检查 NSMicrophoneUsageDescription；查看 SFSpeechRecognizer 权限请求

### iPad 端

- [ ] App 启动后双栏 NavigationSplitView 布局
  - **前置条件**：iPad 真机或模拟器，iPadOS 17+
  - **操作步骤**：
    1. 启动 App
    2. 查看主界面布局
  - **预期结果**：双栏 NavigationSplitView 布局，左侧会话列表 + 右侧聊天
  - **失败排查**：检查 NavigationSplitView；查看 horizontalSizeClass == .regular

- [ ] 横竖屏切换布局自适应
  - **前置条件**：iPad 已进入主界面
  - **操作步骤**：
    1. 横屏切换到竖屏
    2. 竖屏切换到横屏
    3. 观察布局变化
  - **预期结果**：横竖屏切换布局自适应，双栏布局保持稳定，无内容丢失
  - **失败排查**：检查 SceneDelegate orientation change；查看 size class 变化处理

### macOS 端

- [ ] App 启动后窗口默认尺寸 1000×700
  - **前置条件**：macOS 14+ 真机
  - **操作步骤**：
    1. 启动 App
    2. 查看默认窗口尺寸
  - **预期结果**：窗口默认尺寸 1000×700
  - **失败排查**：检查 WindowGroup.defaultSize；查看 frame 配置

- [ ] 菜单栏「文件 → 新建会话」(⌘N) 可用
  - **前置条件**：macOS 进入主界面
  - **操作步骤**：
    1. 按下 ⌘N 或点击菜单栏「文件 → 新建会话」
  - **预期结果**：创建新会话并切换到新会话
  - **失败排查**：检查 CommandGroup；查看 keyboardShortcut("n", modifiers: .command)

- [ ] 菜单栏「编辑 → 搜索」(⌘K) 可用
  - **前置条件**：macOS 进入主界面
  - **操作步骤**：
    1. 按下 ⌘K 或点击菜单栏「编辑 → 搜索」
  - **预期结果**：弹出搜索框或聚焦到搜索栏
  - **失败排查**：检查 keyboardShortcut("k", modifiers: .command)；查看 focus binding

- [ ] 菜单栏「App → 设置」(⌘,) 可用
  - **前置条件**：macOS 进入主界面
  - **操作步骤**：
    1. 按下 ⌘, 或点击菜单栏「App → 设置」
  - **预期结果**：打开设置页
  - **失败排查**：检查 SettingsLink；查看 keyboardShortcut(",", modifiers: .command)

- [ ] 在输入框按 ⌘Enter 发送消息
  - **前置条件**：macOS 进入主对话界面
  - **操作步骤**：
    1. 输入框输入文本
    2. 按 ⌘Enter
    3. 测试 Enter 是否换行
  - **预期结果**：⌘Enter 发送消息，Enter 换行
  - **失败排查**：检查 keyboardShortcut；查看 onSubmit 修饰

- [ ] 设置页 NavigationSplitView 双栏布局
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 查看设置页布局
  - **预期结果**：设置页 NavigationSplitView 双栏布局，左侧分类，右侧详情
  - **失败排查**：检查 SettingsView NavigationSplitView；查看 column visibility

- [ ] 设置二级页有返回按钮
  - **前置条件**：macOS 进入设置页某二级页（如 TTS 音色）
  - **操作步骤**：
    1. 进入二级页
    2. 查看顶部返回按钮
  - **预期结果**：设置二级页有返回按钮，点击可返回
  - **失败排查**：检查 toolbar 修饰；查看 dismiss

- [ ] HealthKit 入口在 macOS 隐藏（但 HealthInsight 模型仍注册）
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 查看设置页是否含 HealthKit Section
    2. 查看 SwiftData schema 是否含 HealthInsight
  - **预期结果**：HealthKit 入口隐藏，HealthInsight 模型仍注册（无 schema 报错）
  - **失败排查**：检查 `#if os(iOS)` 守卫；查看 ModelContainer schema

## 工具能力增强手测

本节对每个工具逐项细化，作为工具能力验证清单。

### 跨平台工具 6 项

- [ ] LocationTool：发送「定位」→ 返回经纬度与逆地理编码
  - **前置条件**：定位权限已授权，网络通畅
  - **操作步骤**：
    1. 在主对话界面发送「定位」
  - **预期结果**：返回经纬度与逆地理编码（中文地址，10s 内返回）
  - **失败排查**：检查 CLLocationManager；查看 reverse geocode 调用；查看定位权限

- [ ] DeviceInfoTool：发送「设备信息」→ 返回设备型号、系统版本、电池状态
  - **前置条件**：工具已注册并启用
  - **操作步骤**：
    1. 在主对话界面发送「设备信息」
  - **预期结果**：返回设备型号 / OS 版本 / 电量 / 可用存储
  - **失败排查**：检查 UIDevice / ProcessInfo；查看字段获取逻辑

- [ ] ClipboardTool：发送「读剪贴板」→ 返回剪贴板内容；发送「写剪贴板：xxx」→ 写入成功
  - **前置条件**：工具已注册并启用
  - **操作步骤**：
    1. 发送「读剪贴板」查看返回内容
    2. 发送「写剪贴板：hello world」
    3. 再次发送「读剪贴板」验证写入
  - **预期结果**：读返回剪贴板当前内容；写返回写入成功，再次读取返回新内容
  - **失败排查**：检查 UIPasteboard.general；查看 clipboard 字符串解析

- [ ] OpenURLTool：发送「打开 https://apple.com」→ 系统浏览器打开
  - **前置条件**：工具已注册并启用，URL 合法
  - **操作步骤**：
    1. 发送「打开 https://apple.com」
  - **预期结果**：系统默认浏览器打开 https://apple.com
  - **失败排查**：检查 UIApplication.shared.open / NSWorkspace.open；查看 URL 校验

- [ ] ContactsTool：发送「搜索联系人 张三」→ 返回联系人信息
  - **前置条件**：通讯录权限已授权，通讯录中存在「张三」
  - **操作步骤**：
    1. 发送「搜索联系人 张三」
  - **预期结果**：返回匹配的联系人信息（电话 / 邮箱等）
  - **失败排查**：检查 CNContactStore；查看 NSContactsUsageDescription；查看 predicate

- [ ] WeatherTool：发送「北京天气」→ 返回天气信息
  - **前置条件**：网络通畅，Weather API key 已配置
  - **操作步骤**：
    1. 发送「北京天气」
    2. 发送「天气」（无 city 参数，测试当前位置）
  - **预期结果**：返回当前天气信息（温度 / 湿度 / 天气状况）
  - **失败排查**：检查 Weather API 调用；查看 city 参数解析；查看定位 fallback

### macOS 独有工具 11 项

- [ ] AppleScriptTool：发送「用 AppleScript 弹窗」
  - **前置条件**：macOS 平台，自动化权限已授权
  - **操作步骤**：
    1. 发送「用 AppleScript 弹窗」
  - **预期结果**：弹出系统对话框，返回执行结果
  - **失败排查**：检查 NSAppleScript；查看 executionPolicy；查看自动化权限

- [ ] ScreenshotTool：发送「截屏」
  - **前置条件**：macOS 平台，屏幕录制权限已授权
  - **操作步骤**：
    1. 发送「截屏」
    2. 查看返回的图片路径
  - **预期结果**：截屏保存 PNG 到临时目录，返回文件路径
  - **失败排查**：检查 CGWindowListCreateImage；查看屏幕录制权限；查看路径返回

- [ ] OCRTool：发送图片 OCR 识别
  - **前置条件**：macOS 平台，已准备含文字的图片
  - **操作步骤**：
    1. 发送「OCR 识别 /path/to/image.png」
    2. 发送「OCR 识别」（无 image_path，自动截屏后识别）
  - **预期结果**：识别图片文字并返回识别结果
  - **失败排查**：检查 Vision framework VNRecognizeTextRequest；查看 image_path 解析；查看 fallback 截屏

- [ ] TerminalCommandTool：发送「执行 ls -la」
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「执行 ls -la」
    2. 发送「执行 rm -rf /」（测试危险命令拒绝）
  - **预期结果**：ls -la 返回目录列表；rm -rf / 被拒绝并返回提示
  - **失败排查**：检查 Process；查看黑名单；查看 stdout/stderr 捕获

- [ ] WindowManagementTool：发送「最小化窗口」
  - **前置条件**：macOS 平台，已打开多个窗口
  - **操作步骤**：
    1. 发送「最小化窗口」
    2. 发送「列出所有窗口」
  - **预期结果**：最小化当前窗口；列出所有可见窗口
  - **失败排查**：检查 NSWorkspace.runningApplications；查看 window list API；查看 AppleScript

- [ ] AppManagementTool：发送「打开 Safari」
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「打开 Safari」
    2. 发送「列出运行中应用」
  - **预期结果**：Safari 启动；列出当前运行的应用列表
  - **失败排查**：检查 NSWorkspace.open；查看 app identifier 解析；查看 runningApplications

- [ ] FileOperationTool：发送「读取 ~/Documents/test.txt」
  - **前置条件**：macOS 平台，文件存在
  - **操作步骤**：
    1. 发送「读取 ~/Documents/test.txt」
    2. 发送「列出 ~/Downloads 目录」
    3. 发送「删除 ~/Documents/test.txt」
  - **预期结果**：读取返回文件内容；列出返回目录文件；删除移到废纸篓
  - **失败排查**：检查 FileManager；查看权限；查看 trash 调用

- [ ] FinderTool：发送「在 Finder 显示」
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「在 Finder 显示 ~/Documents」
    2. 发送「获取 Finder 选中项」
  - **预期结果**：Finder 打开并显示指定路径；返回 Finder 当前选中项
  - **失败排查**：检查 NSWorkspace.activateFileViewerSelecting；查看 AppleScript 实现

- [ ] SafariControlTool：发送「在 Safari 打开 apple.com」
  - **前置条件**：macOS 平台，Safari 已运行
  - **操作步骤**：
    1. 发送「在 Safari 打开 apple.com」
    2. 发送「列出 Safari 标签页」
  - **预期结果**：Safari 新标签页打开 apple.com；列出所有标签页 URL
  - **失败排查**：检查 AppleScript 控制 Safari；查看 script 编译；查看 Safari 权限

- [ ] SystemControlTool：发送「锁定屏幕」
  - **前置条件**：macOS 平台
  - **操作步骤**：
    1. 发送「锁定屏幕」
    2. 发送「获取音量」
  - **预期结果**：屏幕锁定；返回当前系统音量
  - **失败排查**：检查 AppleScript；查看 system events；查看 CGSession

- [ ] InputAutomationTool：发送「模拟输入 hello」
  - **前置条件**：macOS 平台，辅助功能权限已授权，焦点在输入框
  - **操作步骤**：
    1. 发送「模拟输入 hello」
  - **预期结果**：在当前焦点输入框输入字符「hello」
  - **失败排查**：检查 CGEvent；查看辅助功能权限；查看焦点判定

### 快捷指令工具 3 项

- [ ] RunShortcutTool：运行已有快捷指令
  - **前置条件**：macOS 平台，已安装 Shortcuts app，至少有 1 个快捷指令
  - **操作步骤**：
    1. 发送「运行快捷指令 测试」
  - **预期结果**：执行指定快捷指令并返回结果
  - **失败排查**：检查 ShortcutsEvents.runShortcut；查看 name 解析；查看 macOS 权限

- [ ] ListShortcutsTool：列出系统快捷指令
  - **前置条件**：已安装 Shortcuts app
  - **操作步骤**：
    1. 发送「列出快捷指令」
  - **预期结果**：macOS 返回快捷指令列表；iOS 返回限制说明提示
  - **失败排查**：检查 ShortcutsEvents；查看 iOS 限制说明；查看 macOS 列表获取

- [ ] CreateShortcutTool：创建 .shortcut 文件（4 种动作 open_url / run_script / show_text / copy_to_clipboard）
  - **前置条件**：macOS 平台，已安装 Shortcuts app
  - **操作步骤**：
    1. 发送「创建快捷指令 open_url https://apple.com」
    2. 发送「创建快捷指令 run_script echo hello」
    3. 发送「创建快捷指令 show_text 你好」
    4. 发送「创建快捷指令 copy_to_clipboard hello」
  - **预期结果**：4 种动作均生成对应 .shortcut 文件并可导入到 Shortcuts app
  - **失败排查**：检查 shortcut builder；查看 4 种 action 实现；查看文件写入路径

## 27. 国际化与无障碍强化

### 国际化基础设施

- [ ] String Catalog 正确注册
  - **前置条件**：Xcode 打开 AIBuilder.xcodeproj
  - **操作步骤**：
    1. 在 Project navigator 中展开 Resources → 确认 `Localizable.xcstrings` 存在
    2. 选中 `Localizable.xcstrings`，确认右侧 Inspector 显示 sourceLanguage = `zh-Hans`
    3. 构建后查看 Build Products 中是否生成 `.lproj` 目录
  - **预期结果**：文件存在，sourceLanguage 为 zh-Hans，构建后 app bundle 含 zh-Hans.lproj 与 en.lproj
  - **失败排查**：检查 pbxproj 中 `developmentRegion` 是否为 `zh-Hans`；检查 Resources build phase 是否含 Localizable.xcstrings

- [ ] 系统语言切换验证
  - **前置条件**：iOS 真机或模拟器
  - **操作步骤**：
    1. 设置 → 通用 → 语言与地区 → iPhone 语言 → 切换为 English
    2. 重启 App
    3. 观察界面文案
  - **预期结果**：核心按钮文案（如「发送」「设置」「知识库」）显示为英文
  - **失败排查**：String Catalog 中对应 key 是否有 en 翻译；检查是否使用了硬编码 String

### 无障碍支持

- [ ] VoiceOver 朗读主对话页
  - **前置条件**：VoiceOver 已开启（设置 → 辅助功能 → VoiceOver）
  - **操作步骤**：
    1. 打开 App 进入主对话界面
    2. 单指左右滑动遍历各元素
  - **预期结果**：依次朗读「消息输入框」「发送」「知识库」「语音输入」「会话列表」「设置」等标签
  - **失败排查**：检查对应视图是否含 `accessibilityLabel`

- [ ] VoiceOver 朗读代码块
  - **前置条件**：发送一条含代码块的 AI 回复
  - **操作步骤**：
    1. VoiceOver 聚焦到代码块
  - **预期结果**：朗读「Swift 代码块」+ 代码内容
  - **失败排查**：检查 CodeBlockView 是否含 `accessibilityLabel`/`accessibilityValue`

- [ ] VoiceOver 朗读会话列表项
  - **前置条件**：存在至少一个会话
  - **操作步骤**：
    1. 打开会话列表
    2. VoiceOver 聚焦到某个会话行
  - **预期结果**：朗读会话标题 + 最后消息内容，并提示「打开此会话」
  - **失败排查**：检查 ConversationRow 是否含 `accessibilityElement(children: .combine)` + `accessibilityLabel`

### macOS 应用图标

- [ ] macOS 图标显示正确
  - **前置条件**：macOS 构建
  - **操作步骤**：
    1. 构建 macOS App
    2. 在 Finder 或 Dock 中查看 App 图标
  - **预期结果**：显示正确的 App 图标（非默认齿轮），16x16 ~ 512x512 各尺寸清晰
  - **失败排查**：检查 AppIcon.appiconset/Contents.json 是否含 mac idiom 条目；检查 PNG 文件是否存在

## 28. 国际化与语言切换

- [ ] 语言切换生效
  - **前置条件**：App 安装后至少完成一次启动
  - **操作步骤**：
    1. 设置 → 语言 → 选择「英文」
    2. 重启 App
  - **预期结果**：设置页、主界面、工具描述全部显示英文
  - **失败排查**：检查 `AppleLanguages` 是否写入；检查 `Localizable.xcstrings` 是否包含对应 key

- [ ] 繁体中文显示正常
  - **前置条件**：语言设置为「繁体中文」
  - **操作步骤**：浏览设置、对话、知识库、健康洞察页面
  - **预期结果**：无乱码、无简体残留
  - **失败排查**：检查 `zh-Hant` 翻译覆盖率

## 29. 无障碍与旁白

- [ ] VoiceOver 可朗读关键控件
  - **前置条件**：系统设置开启 VoiceOver
  - **操作步骤**：
    1. 打开 App 主界面
    2. 单指滑动聚焦发送按钮、输入框、设置按钮
  - **预期结果**：每个控件朗读出有意义的中文标签
  - **失败排查**：检查对应 View 是否添加 `accessibilityLabel`

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

**P0（核心路径，必须验证）**：1, 2, 3, 9, 10, 11, 16, 21（多平台适配，发布前必须验证三端启动与基础功能），23（macOS 设置导航修复，核心交互修复），27（国际化与无障碍，发布前必须验证 String Catalog 注册与 VoiceOver 基础朗读）
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
| 多平台适配手测（细化） | P0 | 三端逐项细化步骤，发布前必验证 |
| 工具能力增强手测（细化） | P1 | 跨平台 6 + macOS 11 + 快捷指令 3 逐项验证 |
| 国际化与无障碍（27） | P0 | String Catalog 注册、VoiceOver 朗读、macOS 图标，发布前必验证 |
| 其他现有模块 | 保持原优先级 | 见上方分级说明 |

## 手测执行记录表

每次执行手测时填写下表，便于追溯与回归。

| 执行人 | 时间 | 平台 | 模块 | 测试项 | 结果 | 备注 |
|--------|------|------|------|--------|------|------|
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |
|        |      |      |      |        |      |      |

字段说明：
- **执行人**：测试人员姓名或工号
- **时间**：执行时间，格式 YYYY-MM-DD HH:mm
- **平台**：iOS / iPad / macOS / watchOS
- **模块**：对应本文档章节号（如 1、21.1、22.2）
- **测试项**：测试项名称
- **结果**：PASS / FAIL / BLOCK
- **备注**：失败原因、阻塞说明或回归记录
