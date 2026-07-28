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

- [ ] Shortcuts 中 Ask Aether
  - **前置条件**：App 已安装到真机
  - **操作步骤**：
    1. 打开 Shortcuts app
    2. 查看以太相关动作
  - **预期结果**：Shortcuts app 中出现「Ask Aether」动作，输入 query 返回回复文本
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

**注意：watchOS target 需在 Xcode 中手动创建并引用 AetherWatch/ 目录下的文件。**

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

- [ ] Ask Aether 真实回复
  - **前置条件**：API Key 已配置
  - **操作步骤**：
    1. 在 Shortcuts app 中创建快捷指令
    2. 添加「Ask Aether」动作
    3. 输入 query 并运行
  - **预期结果**：Shortcuts app 中「Ask Aether」动作输入 query，返回真实 LLM 回复（非占位文本）
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
  - **预期结果**：在 iPhone 上查看会话 A，iPad App Switcher 出现 Aether Handoff 图标
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
  - **前置条件**：Xcode 打开 Aether 工程
  - **操作步骤**：
    1. 查看 Aether target Resources
  - **预期结果**：`PrivacyInfo.xcprivacy` 文件存在于 Aether target Resources
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
  - **预期结果**：邮件收件人预填 feedback@aether.app
  - **失败排查**：检查 setToRecipients；查看 email 配置

- [ ] 邮件主题预填
  - **前置条件**：邮件 composer 已打开
  - **操作步骤**：
    1. 查看主题字段
  - **预期结果**：邮件主题预填「以太用户反馈」
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
    1. 参照 [ReleaseChecklist.md](ReleaseChecklist.md) 完成最终检查
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
  - **前置条件**：Xcode 打开 Aether.xcodeproj
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

## 30. 设置 UI 修复验证

> 验证 6 项设置 UI Bug 修复：macOS 设置显示、API Key 保存、主题切换、头像选择器、气泡样式、字体/行间距。

- [ ] macOS 设置页可正常滚动
  - **前置条件**：macOS 进入设置页
  - **操作步骤**：
    1. 打开设置页
    2. 上下滚动浏览所有 Section
  - **预期结果**：macOS 设置页可正常上下滚动，所有 Section 完整可见，无内容截断
  - **失败排查**：检查 SettingsView ScrollView / Form 布局；查看 `#if os(macOS)` 守卫下的布局分支

- [ ] API Key 保存后重启仍保留
  - **前置条件**：进入设置 → API 配置
  - **操作步骤**：
    1. 输入 DeepSeek API Key 并点击「保存 API Key」
    2. 退出设置页
    3. 重启 App
    4. 重新进入设置 → API 配置
  - **预期结果**：API Key 保存后重启 App 仍保留（Keychain 持久化），输入框非空
  - **失败排查**：检查 KeychainManager.shared.saveAPIKey；查看 `kSecAttrService` / `kSecAttrAccount` 一致性

- [ ] 主题切换即时生效并持久化
  - **前置条件**：进入设置 → 外观
  - **操作步骤**：
    1. 切换主题（如深空 / 黎明 / 极光）
    2. 观察界面颜色变化
    3. 重启 App
  - **预期结果**：主题切换即时生效（界面颜色立即变化），重启 App 后主题保持一致（从 SwiftData UserPreference 同步）
  - **失败排查**：检查 Theme 从 SwiftData UserPreference @Model 同步逻辑；查看 UserDefaults / SwiftData 持久化

- [ ] 头像选择器可正常选择图片
  - **前置条件**：进入设置 → AI 人设
  - **操作步骤**：
    1. 点击头像区域
    2. 从 PhotosPicker 选择一张图片
    3. 确认头像已更新
  - **预期结果**：PhotosPicker 头像选择器在 iOS 与 macOS 均可正常选择图片，选择后头像立即更新
  - **失败排查**：检查 PhotosPicker 跨平台兼容性；查看 PhotosPicker selection binding

- [ ] 气泡样式切换正常
  - **前置条件**：进入设置 → 外观
  - **操作步骤**：
    1. 切换气泡样式（液态玻璃 / 极简 / 卡片）
    2. 返回主对话界面发送消息
  - **预期结果**：气泡样式切换后，消息气泡按所选样式渲染（液态玻璃含毛玻璃效果 / 极简纯色 / 卡片带边框）
  - **失败排查**：检查 MessageBubble 样式分支；查看 bubbleStyle binding

- [ ] 字体大小与行距可调
  - **前置条件**：进入设置 → 外观
  - **操作步骤**：
    1. 调节字体大小 Slider
    2. 调节行距 Slider
    3. 返回主对话界面查看消息
  - **预期结果**：字体大小与行距调节后，消息气泡中的文字按新设置渲染
  - **失败排查**：检查 FontSize / LineSpacing 持久化；查看 MessageBubble font / lineSpacing 修饰符

## 31. 设备调试与性能修复验证

> 验证 3 项修复：entitlements 设备调试、启动性能优化、键盘关闭手势。

- [ ] iOS 真机调试可正常安装运行
  - **前置条件**：iPhone 真机已连接，开发者证书已配置
  - **操作步骤**：
    1. Xcode 选择 iPhone 真机目标
    2. 按 Cmd + R 构建并安装
  - **预期结果**：App 在 iPhone 真机上可正常安装运行，无 entitlements 签名错误
  - **失败排查**：检查 entitlements 文件中 keychain-access-groups / app-groups 配置；查看 Provisioning Profile

- [ ] 冷启动到可交互 < 1.5s
  - **前置条件**：iPhone 17 模拟器
  - **操作步骤**：
    1. 冷启动 App（先 kill 再启动）
    2. 用秒表或 Instruments 计时启动到主界面可交互的时间
  - **预期结果**：冷启动到可交互 < 1.5s（远程配置拉取已从 init() 移到首屏 .task，BGTask 懒注册）
  - **失败排查**：检查 RemoteConfigService.fetch 调用时机；查看 BGTaskScheduler 注册时机；查看 PerformanceMonitor 启动耗时指标

- [ ] 键盘下拉手势关闭
  - **前置条件**：iOS 端进入主对话界面，键盘已弹出
  - **操作步骤**：
    1. 在键盘弹出状态下，从输入框上方下拉
    2. 或点击输入框外空白区域
  - **预期结果**：下拉手势或点击空白区域可关闭键盘
  - **失败排查**：检查 keyboard dismiss gesture；查看 `.onTapGesture` / `FocusState` 重置

## 32. 多语言与无障碍强化验证

> 验证 8 种语言切换与 VoiceOver 完整朗读。

- [ ] 8 种语言切换全部生效
  - **前置条件**：App 安装后至少完成一次启动
  - **操作步骤**：
    1. 依次切换语言为：简体中文 → 繁体中文 → English → 日本語 → 한국어 → Français → Deutsch → Español
    2. 每次切换后重启 App，检查界面文案
  - **预期结果**：8 种语言切换后，设置页、主界面、工具描述、错误提示全部显示对应语言，无残留中文
  - **失败排查**：检查 `Localizable.xcstrings` 是否包含 8 种语言翻译；检查 `AppleLanguages` UserDefaults 写入；查看是否有硬编码字符串

- [ ] VoiceOver 完整朗读所有页面
  - **前置条件**：系统设置开启 VoiceOver
  - **操作步骤**：
    1. 打开 App 主界面，单指滑动遍历各元素
    2. 进入设置页，遍历所有 Section 与控件
    3. 触发工具调用，遍历 StepCard
    4. 进入知识库页面，遍历文档列表
  - **预期结果**：VoiceOver 可正确朗读所有页面元素，包括消息气泡、发送按钮、设置 Toggle、StepCard、CitationCard 等，标签有意义且无「按钮」等无意义朗读
  - **失败排查**：检查各视图 accessibilityLabel；查看 accessibilityElement(children: .combine) 使用

## 33. 平台扩展功能验证

> 验证 Watch App 快速聊天、Widget 显示交互、端侧模型下载推理。

- [ ] Watch App 快速聊天
  - **前置条件**：Watch App target 已创建，iPhone 与 Apple Watch 配对，WatchConnectivity 已连接
  - **操作步骤**：
    1. 在 Apple Watch 上打开 Aether App
    2. 在「快速对话」标签输入或选择预设问题
    3. 发送消息
  - **预期结果**：Watch App 通过 WatchConnectivity 将消息转发到 iPhone，iPhone 处理后将回复返回 Watch 显示
  - **失败排查**：检查 WCSession.sendMessage；查看 session reachable 状态；检查 iPhone 端 quickChat handler

- [ ] Widget 显示与交互
  - **前置条件**：Widget Extension target 已创建，主 App 至少有 1 个会话
  - **操作步骤**：
    1. 在 iOS 主屏幕长按 → 添加 Widget
    2. 分别添加 QuickChat / HealthInsight / RecentConversations 三个 Widget
    3. 点击 QuickChat Widget 输入问题并发送
    4. 点击 RecentConversations Widget 中的会话
  - **预期结果**：三个 Widget 均正常显示数据，QuickChat 点击后通过 deepLink 跳转主 App 并发送消息，RecentConversations 点击后跳转对应会话
  - **失败排查**：检查 App Group 共享 SwiftData 配置；查看 WidgetCenter.reloadAllTimelines 调用；检查 deepLink URL Scheme

- [ ] 端侧模型下载与推理
  - **前置条件**：Apple Silicon 真机（A17 Pro+），mlx-swift SPM 已集成
  - **操作步骤**：
    1. 进入设置 → 端侧推理
    2. 选择模型（如 Llama-3.2-1B-Instruct Q4_K_M）开始下载
    3. 等待下载完成与 SHA256 校验
    4. 切换供应商为「端侧推理」
    5. 发送消息验证流式推理
  - **预期结果**：模型下载进度正常更新，校验通过后可加载推理；端侧模式下发送消息收到 token 级流式响应（非假流式）
  - **失败排查**：检查 mlx-swift SPM 解析；查看 ModelContainer.load；检查 MLXEngine.generate AsyncStream；查看内存检测 os_proc_available_memory

## 34. Rust FFI 核心能力验证

> 验证 10 个 Rust FFI 模块（aether-core-ffi → AetherRustBin xcframework）在 iOS/macOS 上的正确性。

### 34.1 Sha256 流式哈希

- [ ] 文件哈希计算正确
  - **前置条件**：iOS/macOS 端，已知任意文件路径
  - **操作步骤**：
    1. 在代码中调用 `aetherSha256(of: filePath)`
    2. 对比系统 `shasum -a 256` 结果
  - **预期结果**：Rust 哈希与系统 shasum 结果一致
  - **失败排查**：检查 `AetherRustSha256.update` 分块读取；查看 `finalize` hex 编码

- [ ] 大文件（> 100MB）分块哈希无内存溢出
  - **前置条件**：准备好 > 100MB 测试文件
  - **操作步骤**：
    1. 调用 `aetherSha256(of: largeFilePath)`
    2. 监控内存占用
  - **预期结果**：4MB chunk 分块读取，内存占用稳定，不溢出
  - **失败排查**：检查 chunk 大小配置；查看 autoreleasepool 使用

### 34.2 Token 计数估算

- [ ] 中文/英文/混合文本 Token 计数合理
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 调用 `AetherRustToken.estimateTokens("你好世界")` 
    2. 调用 `AetherRustToken.estimateTokens("Hello World")`
    3. 调用 `AetherRustToken.estimateTokens("你好 Hello 世界 World")`
  - **预期结果**：中文约 4 个 token，英文约 2 个 token，混合文本合理
  - **失败排查**：检查 Rust 侧 token 计数算法；对比 `String.estimatedTokens` 粗估结果

### 34.3 Chunker 文档分块

- [ ] 中文文档按句子边界分块
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 准备一段中文长文本（含多句话）
    2. 调用 `AetherRustChunker.chunkDocument(text, maxChars: 200, overlapChars: 50)`
  - **预期结果**：分块按句子边界断开，不会在句子中间截断，chunk 之间有 overlap
  - **失败排查**：检查 `unicode-segmentation` UAX #29 实现；查看 maxChars/overlapChars 参数

- [ ] 英文文档分块正确处理标点
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 准备一段英文长文本
    2. 调用分块方法
  - **预期结果**：按英文句号/问号/感叹号边界分块
  - **失败排查**：检查 Unicode 句子边界检测；对比 NLTokenizer 结果

### 34.4 Vector 向量运算

- [ ] 余弦相似度计算正确
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 调用 `AetherRustVector.cosine(vecA, vecB)` 计算相同向量 → 应为 1.0
    2. 计算正交向量 → 应为 0.0
    3. 计算随机向量对
  - **预期结果**：相同向量 = 1.0，正交 ≈ 0.0，f32/f64 结果一致
  - **失败排查**：检查 Rust 侧 dot product 与 norm 计算；查看 f32/f64 精度

- [ ] Top-K 检索返回正确排序
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 准备一组向量 + 查询向量
    2. 调用 `AetherRustVector.topK(query, vectors, k: 3)`
  - **预期结果**：返回余弦相似度最高的 3 条，按相似度降序排列
  - **失败排查**：检查 JSON 序列化/反序列化；查看返回数组排序

### 34.5 SSE 流解析

- [ ] 普通 SSE 事件解析正确
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 创建 `AetherRustSSEParser`
    2. 调用 `parseChunk("data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\n")`
    3. 调用 `extractContent()`
  - **预期结果**：提取到 "你好" 内容
  - **失败排查**：检查 SSE 解析状态机；查看 data: 字段解析

- [ ] tool_calls 跨 chunk 累积正确
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 创建 `AetherRustSSEParser`
    2. 分多次调用 `parseWithTools` 传入 tool_calls delta（跨多个 chunk）
    3. 查看累积的 tool_calls 结果
  - **预期结果**：tool_calls 跨 chunk 正确累积，最终工具名和参数完整
  - **失败排查**：检查 `AetherSseState` 跨 chunk 累积逻辑；查看 tool_calls JSON 合并

### 34.6 Sandbox WASM 沙箱（macOS）

- [ ] WASM 模块加载与执行
  - **前置条件**：macOS 端，已编译 WASM 插件
  - **操作步骤**：
    1. 创建 `AetherRustSandbox`
    2. 编译 WASM 模块 → `AetherRustSandboxModule`
    3. 创建实例 → `AetherRustSandboxInstance`
    4. 调用 `execute` 方法
  - **预期结果**：WASM 插件正常加载并执行，返回结果
  - **失败排查**：检查 `wasmtime` Pulley 解释器；查看 CPU fuel 配置

- [ ] 资源限制生效（CPU fuel + 内存）
  - **前置条件**：macOS 端，已加载 WASM 实例
  - **操作步骤**：
    1. 配置极低 CPU fuel 与内存限额
    2. 执行计算密集型 WASM 插件
  - **预期结果**：超限时插件被终止，不导致宿主崩溃
  - **失败排查**：检查 `wasmtime` Store 配置；查看 fuel/memory 限制

### 34.7 Inference 推理引擎（macOS）

- [ ] 模型加载成功
  - **前置条件**：macOS 端，已下载 safetensors 模型
  - **操作步骤**：
    1. 创建 `AetherRustInferenceEngine`，传入模型目录路径
    2. 配置 `AetherRustInferenceConfig`（temperature/maxTokens/repeatPenalty/topP/seed）
  - **预期结果**：模型加载成功，无报错
  - **失败排查**：检查 Candle 框架 safetensors 加载；查看模型路径

- [ ] 流式生成正确
  - **前置条件**：模型已加载
  - **操作步骤**：
    1. 调用 `generate(prompt)` 获取流式 token 数组
    2. 调用 `generateText(prompt)` 获取一次性完整文本
  - **预期结果**：流式返回 token 数组，一次性返回完整文本，内容连贯
  - **失败排查**：检查 Candle generate 实现；查看 temperature/topP 采样

### 34.8 RateLimiter 令牌桶限流

- [ ] 令牌获取与消耗正确
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 创建 `AetherRustTokenBucket(capacity: 10, refillRate: 1.0)`
    2. 调用 `acquire(nowMs, tokens: 1)` 10 次
    3. 第 11 次调用 `acquire`
  - **预期结果**：前 10 次成功，第 11 次返回 false（令牌不足）
  - **失败排查**：检查连续 refill 算法；查看 `nowMs` 时间戳计算

- [ ] 令牌随时间恢复
  - **前置条件**：iOS/macOS 端，已消耗全部令牌
  - **操作步骤**：
    1. 等待 2 秒后再次调用 `acquire(nowMs + 2000, tokens: 1)`
  - **预期结果**：令牌恢复 2 个，可成功获取
  - **失败排查**：检查 refill 速率计算；查看 `availableTokens` 方法

### 34.9 Redactor 敏感信息脱敏

- [ ] UUID 脱敏正确
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 调用 `AetherRustRedactor.redact("ID: 550e8400-e29b-41d4-a716-446655440000")`
  - **预期结果**：UUID 被替换为 `[REDACTED-UUID]`
  - **失败排查**：检查 Rust `regex` crate UUID 正则

- [ ] 邮箱/URL/Token 脱敏正确
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 调用 `AetherRustRedactor.redact("contact: user@example.com, url: https://secret.com, token: sk-abc123def")`
  - **预期结果**：邮箱 → `[REDACTED-EMAIL]`，URL → `[REDACTED-URL]`，Token → `[REDACTED-TOKEN]`
  - **失败排查**：检查各 RE2 正则模式；查看脱敏替换逻辑

### 34.10 FFIError 错误处理

- [ ] nullResult 错误正确抛出
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 模拟 Rust 侧返回 null 指针的情况
  - **预期结果**：Swift 侧抛出 `AetherRustError.nullResult`
  - **失败排查**：检查 C 指针校验；查看 `AetherRustError` 错误描述

- [ ] invalidUTF8 错误正确抛出
  - **前置条件**：iOS/macOS 端
  - **操作步骤**：
    1. 模拟 Rust 侧返回无效 UTF-8 字节
  - **预期结果**：Swift 侧抛出 `AetherRustError.invalidUTF8`
  - **失败排查**：检查 `String(cString:)` 初始化；查看错误捕获

## 35. v1.2 设计升级

> 验证 AnimationTokens / AetherIcons / 响应式布局 / Starfield 呼吸效果 / SF Symbols 替换 / 消息气泡动画（v1.2 已交付）。

### 35.1 AnimationTokens 动画统一

- [ ] 动画时长与曲线统一
  - **三端一致**：所有过渡动画时长统一（如 fast=0.2s / medium=0.35s / slow=0.6s），曲线为 `easeInOut` 或自定义 spring
  - **操作步骤**：1. 启动 App 进入主对话界面 2. 触发各类过渡：切换会话、打开设置、展开 StepCard、长按 contextMenu 3. 观察动画时长与曲线
  - **失败排查**：检查 `DesignTokens/AnimationTokens.swift` 中 7 个新增 token；查看各 View 的 `.animation` 修饰符

- [ ] 主题切换 0.3s 平滑过渡
  - **三端一致**：主题切换通过 `ThemeManager` 0.3s 平滑过渡，无突变
  - **操作步骤**：1. 进入设置 → 外观 2. 切换主题（深空 / 黎明 / 极光） 3. 观察界面颜色变化
  - **失败排查**：检查 `ThemeManager` 中 `.animation(.easeInOut(duration: 0.3))` 修饰符

### 35.2 AetherIcons 自定义图标集

- [ ] AetherIcons 4 类 11 图标渲染
  - **三端一致**：11 个新图标（如 `aether.sparkle` / `aether.memory` / `aether.health` 等）正确渲染，非默认 SF Symbols
  - **操作步骤**：1. 进入主对话界面、设置页、知识库页、健康洞察页 2. 查看 4 类图标（导航 / 操作 / 状态 / 装饰）渲染
  - **失败排查**：检查 `AetherIcons` Image initializer；查看 Asset Catalog 中对应 PNG/SVG 资源

- [ ] 图标多尺寸清晰
  - **iOS**：在 Dynamic Type S / M / XL 下查看图标清晰度
  - **iPad**：同 iOS
  - **macOS**：在系统字号设置下查看图标清晰度
  - **操作步骤**：1. 在不同字号下查看图标 2. 观察 16×16 / 24×24 / 32×32 / 64×64 各尺寸渲染
  - **失败排查**：检查 Asset Catalog 中多尺寸 PNG；查看 Image resizable

### 35.3 Starfield 星空背景呼吸效果

- [ ] 4s 呼吸动画持续
  - **三端一致**：星空背景以 4s 周期呼吸（亮度 / 缓慢移动 / 透明度变化），无卡顿
  - **操作步骤**：1. 启动 App 后保持主界面静止 2. 观察星空背景至少 10 秒
  - **失败排查**：检查 `StarfieldBackgroundView` 中 4s 呼吸动画；查看 TimelineView 调度

- [ ] 粒子数三端差异
  - **iOS**：30 个粒子（`suggestedParticleCount`）
  - **iPad**：50 个粒子
  - **macOS**：100 个粒子
  - **操作步骤**：1. 启动 App 进入主对话界面 2. 观察星空背景粒子密度
  - **失败排查**：检查 `StarfieldBackgroundView.swift:192-200` 中 `suggestedParticleCount` 实现

- [ ] 低电量降级（未实际启用）
  - **iOS**：`currentLowPowerMode` 静态属性存在（`#if canImport(UIKit)` 编译），但所有调用方都用 `StarfieldBackgroundView()` 默认初始化，未传入 `lowPowerMode` 参数，降级路径实际未生效
  - **iPad**：同 iOS，降级未生效
  - **macOS**：`currentLowPowerMode` 在 macOS 下不编译，`lowPowerMode` 默认 false，永不降级
  - **操作步骤**：1. iOS 真机电量降到 <20% 2. 启动 App 观察星空背景 3. 观察是否有降级行为（关闭呼吸 / 减少粒子）
  - **失败排查**：检查 `StarfieldBackgroundView.swift:54-99, 202-207` 中 `lowPowerMode` 参数；确认调用方是否传入该参数（实际未传入，降级路径未生效）

### 35.4 响应式布局

- [ ] horizontalSizeClass 三端差异
  - **iOS**：iPhone compact（竖屏）`horizontalSizeClass == .compact` → 单栏 `chatDetail` 布局；iPhone Plus/Max 横屏 `horizontalSizeClass == .regular` → 双栏 NavigationSplitView
  - **iPad**：竖屏 / 横屏 `horizontalSizeClass == .regular` → 双栏；分屏（1/3 屏）`horizontalSizeClass == .compact` → 单栏
  - **macOS**：始终 `regular` → 双栏
  - **操作步骤**：1. iPhone SE 竖屏启动 App 查看单栏布局 2. iPhone 17 Pro Max 横屏查看双栏布局 3. iPad Pro 竖屏查看双栏 4. iPad 分屏 1/3 屏查看单栏 5. Mac 启动查看双栏
  - **失败排查**：检查 `Aether/Views/Chat/ChatView.swift:7-8` 的 `@Environment(\.horizontalSizeClass)`；项目不存在 `LayoutSize` 类型，所有布局判定通过 SwiftUI 原生 sizeClass 实现

- [ ] macOS 多窗口与窗口尺寸
  - **iOS**：❌ 不开放，单窗口
  - **iPad**：❌ 不开放，单窗口
  - **macOS**：主窗口 minWidth 800, minHeight 500, defaultSize 1000×700；通过 `WindowGroup("New Conversation", for: UUID.self)` + `openWindow` 打开多窗口；MenuBarExtra 菜单栏常驻面板
  - **操作步骤**：1. macOS 启动 App 查看主窗口尺寸 2. 拖动窗口改变宽度（500 ~ 1500）观察布局 3. 通过菜单 / 命令打开新对话窗口 4. 查看菜单栏 MenuBarExtra 面板
  - **失败排查**：检查 `Aether/App/AetherApp-macOS.swift:14-85` 中 WindowGroup 与 MenuBarExtra 配置；项目未使用 `navigationSplitViewStyle(...)` 修饰符，采用默认样式

### 35.5 消息气泡动画

- [ ] 气泡液态进出动画
  - **三端一致**：消息气泡以液态动画（scale + opacity + spring）入场，非生硬淡入
  - **操作步骤**：1. 进入主对话界面 2. 发送一条消息 3. 观察 AI 回复气泡入场
  - **失败排查**：检查 `MessageBubble` 中 `.transition(.scale.combined(with: .opacity))` 修饰符

- [ ] 10 个 SF Symbols 替换为 AetherIcons
  - **三端一致**：10 处原 SF Symbols 已替换为 AetherIcons，无残留 `systemName` 引用
  - **操作步骤**：1. 进入主界面与设置页 2. 查看发送按钮 / 设置按钮 / 麦克风按钮 / 知识库按钮等 10 处
  - **失败排查**：检查各 View 中 `Image(systemName:)` 是否被 `Image(aetherIcon:)` 替代

## 36. v1.3 端侧多模态 Phase 1（协议抽象 + 占位 + 工具 + 跨平台 OCR）

> 验证 MultimodalFacade 门面、5 个引擎协议、4 个多模态工具、跨平台 OCR 改造、MemoryBudget 预算器（v1.3 已交付）。

### 36.1 MultimodalFacade 门面

- [ ] 创建 Facade 默认引擎
  - **三端一致**：v1.3 默认返回 `PlaceholderVisionEngine` / `PlaceholderASR` / `PlaceholderTTS` / `PlaceholderVoiceCloner` / `PlaceholderImageGen`（v1.4 切换为 Native，见第 37 章）；MultimodalFacade / MemoryBudget / DeviceCapability 三端代码一致，无平台差异
  - **操作步骤**：1. 在代码中创建 `MultimodalFacade()` 2. 查询 `visionEngineName` / `asrEngineName` / `ttsEngineName` / `voiceClonerName` / `imageGenEngineName`
  - **失败排查**：检查 `MultimodalFacade.init()` 默认实现

- [ ] 引擎依赖注入切换
  - **三端一致**：切换后 name 反映新引擎
  - **操作步骤**：1. 调用 `setVisionEngine(_:)` / `setASREngine(_:)` / `setTTSEngine(_:)` / `setVoiceCloner(_:)` / `setImageGenEngine(_:)` 注入自定义引擎 2. 查询引擎 name
  - **失败排查**：检查 `setXxxEngine` actor 方法；查看引擎存储属性

- [ ] budgetSnapshot 返回内存预算
  - **三端一致**：返回 `BudgetSnapshot`，含 `totalMB / usedMB / availableMB / peakMB / utilizationPercentage` 均为非负值
  - **操作步骤**：1. 创建 `MultimodalFacade()` 2. 调用 `facade.budgetSnapshot()`
  - **失败排查**：检查 `MemoryBudget.shared`；查看 `DeviceCapability.recommendedMemoryBudgetMB`

### 36.2 4 个多模态工具调用（v1.3 占位行为）

- [ ] describe_image 工具被 LLM 调用（占位返回）
  - **iOS**：文件路径必须来自 `.fileImporter` 用户选择，不能直接传 `/tmp/photo.png`
  - **iPad**：同 iOS
  - **macOS**：sandbox 禁用，可直接传 `/tmp/photo.png` 等任意路径
  - **操作步骤**：1. 开启工具开关 2. iOS / iPad 通过 `.fileImporter` 选择图片；macOS 直接传路径 3. 发送「分析这张图片」
  - **预期结果**：v1.3 占位实现返回提示字符串（如"VLM 引擎未加载"或固定文本），StepCard 展示工具调用
  - **失败排查**：检查 `DescribeImageTool.execute`；查看 `MultimodalFacade.describeImage` 调用；iOS 端检查 `DocumentPickerView.swift:13` 的 `.fileImporter`

- [ ] transcribe_audio 工具被 LLM 调用
  - **iOS**：音频文件路径必须来自 `.fileImporter` 用户选择
  - **iPad**：同 iOS
  - **macOS**：可直接传 `/tmp/audio.wav` 等任意路径
  - **操作步骤**：1. 准备音频文件 2. iOS / iPad 通过 `.fileImporter` 选择；macOS 直接传路径 3. 发送「转写音频」
  - **预期结果**：v1.3 占位实现返回提示字符串（如"ASR 引擎未加载"）
  - **失败排查**：检查 `TranscribeAudioTool.execute`；查看文件路径来源

- [ ] clone_voice 工具未加载抛错
  - **三端一致**：占位实现抛 `engineNotLoaded`，StepCard observation 显示错误信息
  - **操作步骤**：1. PlaceholderVoiceCloner 未 loadModel 2. 发送「克隆我的声音 /tmp/sample.wav voice1」
  - **失败排查**：检查 `CloneVoiceTool.execute` 错误处理

- [ ] generate_image 工具抛 platformUnsupported
  - **三端一致**：占位实现抛 `platformUnsupported`，StepCard observation 显示错误信息
  - **操作步骤**：1. PlaceholderImageGenerationEngine 2. 发送「画一只猫」
  - **失败排查**：检查 `GenerateImageTool.execute`

### 36.3 跨平台 OCR（v1.3 改造）

- [ ] OCRTool 三端图片识别
  - **iOS**：v1.3 升级为跨平台，必须传入 `image_path`，不传时返回错误「iOS / iPadOS 平台需提供 image_path 参数」；图片加载用 `UIImage(data:)`
  - **iPad**：同 iOS
  - **macOS**：支持自动截屏，不传 `image_path` 时调用 `ScreenshotTool`（走 `CGDisplayCreateImage`，**非 ScreenCaptureKit**）截屏后做 OCR；图片加载用 `NSImage(contentsOfFile:)`
  - **操作步骤**：1. 准备含中文 / 英文文字的 PNG 图片 2. iOS / iPad 通过 `.fileImporter` 选图后传 `image_path`；macOS 可直接传 `/tmp/text.png` 3. 发送「OCR 识别 /tmp/text.png」
  - **预期结果**：基于 Vision `VNRecognizeTextRequest`（zh-Hans + en，`.accurate`）返回识别文字
  - **失败排查**：检查 `OCRTool.swift:55-66`（`#if os(macOS)` 调用 ScreenshotTool；`#else` 返回错误）；`OCRTool.swift:106-119`（跨平台图片加载）

- [ ] OCR 无 image_path 自动截屏（仅 macOS）
  - **iOS**：❌ 不开放，返回错误「iOS / iPadOS 平台需提供 image_path 参数」
  - **iPad**：❌ 不开放，同 iOS
  - **macOS**：✅ 不传 `image_path` 时调用 `ScreenshotTool`（`CGDisplayCreateImage`）截屏后识别屏幕文字
  - **操作步骤**：1. macOS 屏幕录制权限已授权 2. 发送「OCR 识别」（无 image_path 参数） 3. 观察自动截屏并识别
  - **失败排查**：检查 `OCRTool.swift` 中 `#if os(macOS)` 分支调用 `ScreenshotTool`；查看 `CGDisplayCreateImage` 实现（非 ScreenCaptureKit）；权限请求

### 36.4 MemoryBudget 与 DeviceCapability

- [ ] DeviceCapability 自动检测
  - **iOS**：iPhone SE → low / iPhone 15 → medium / iPhone 15 Pro → high
  - **iPad**：iPad Pro M4 → ultra
  - **macOS**：Mac → ultra
  - **操作步骤**：1. 在代码中查询 `DeviceCapability.current` 2. 验证设备档位
  - **失败排查**：检查 `DeviceCapability.detect()` 中 `ProcessInfo.thermalState` / 内存 / 芯片判定

- [ ] MemoryBudget 超额抛错
  - **三端一致**：抛 `MultimodalError.memoryBudgetExceeded(requestedMB:availableMB:)`
  - **操作步骤**：1. 创建 `MemoryBudget.shared` 2. 调用 `reserve(mb: total + 100)` 故意超额申请
  - **失败排查**：检查 `MemoryBudget.reserve` 逻辑；查看 `available` 计算

## 37. v1.4 端侧多模态 Phase 1.5（Apple 原生引擎）

> 验证 NativeVisionEngine / NativeASREngine / NativeTTSEngine 三个 Apple 原生引擎实现（v1.4 已交付，默认替换占位）。

### 37.1 NativeVisionEngine（基于 Vision 框架）

- [ ] 默认使用 NativeVisionEngine
  - **三端一致**：返回含 `NativeVisionEngine` 关键字；Vision 框架三端原生可用，无平台条件编译
  - **操作步骤**：1. 创建 `MultimodalFacade()` 2. 查询 `visionEngineName`
  - **失败排查**：检查 `MultimodalFacade.init()` 默认引擎

- [ ] isLoaded 始终为 true
  - **三端一致**：三种状态下 `isLoaded` 均为 true，`loadedModelName = "Apple Vision (Native)"`
  - **操作步骤**：1. 创建 NativeVisionEngine 2. 查询 `engine.isLoaded` 3. 调用 `loadModel(at:modelName:)` 后再查询 4. 调用 `unloadModel()` 后再查询
  - **失败排查**：检查 `NativeVisionEngine` 中 isLoaded 实现

- [ ] 5 个 Vision 请求并发
  - **三端一致**：返回结果含分类（VNClassifyImageRequest）/ 人脸数（VNDetectFaceRectanglesRequest）/ 矩形数（VNDetectRectanglesRequest）/ 文字（VNRecognizeTextRequest）/ 条码 payload（VNDetectBarcodesRequest）5 项并发执行结果
  - **操作步骤**：1. 准备一张含文字 / 人脸 / 二维码的 PNG 图片（建议 256×256 以上） 2. 在代码中调用 `engine.describe(image: cgImage, prompt: "描述这张图片")`
  - **失败排查**：检查 `NativeVisionEngine.describe` 中 `async let` 并发；查看 5 个 Vision 请求组合；`NativeVisionEngine.swift:21-98` 仅 `#if canImport(UIKit/AppKit)` 区分图像加载

- [ ] prompt 关键字聚焦「文字」
  - **三端一致**：返回 OCR 结果（VNRecognizeTextRequest），格式如「识别到 N 行文字：...」
  - **操作步骤**：1. 准备一张含中文文字的图片 2. 调用 `describe(image:, prompt: "识别文字")`
  - **失败排查**：检查 prompt 关键字判定（"文字" / "text" / "ocr"）

- [ ] prompt 关键字聚焦「人脸」
  - **三端一致**：返回人脸数（如「检测到 1 个人脸」或「未检测到人脸」）
  - **操作步骤**：1. 准备一张含人脸的图片 2. 调用 `describe(image:, prompt: "检测人脸")`
  - **失败排查**：检查 prompt 关键字「人脸」/「face」分支

- [ ] prompt 关键字聚焦「条码」
  - **三端一致**：返回条码 payload 字符串
  - **操作步骤**：1. 准备一张含二维码的图片 2. 调用 `describe(image:, prompt: "扫描二维码")`
  - **失败排查**：检查 prompt 关键字「条码」/「二维码」/「barcode」分支

- [ ] describe_image LLM 工具真实调用
  - **iOS**：文件路径必须来自 `.fileImporter` 用户选择，不能直接传 `/tmp/photo.png`
  - **iPad**：同 iOS
  - **macOS**：sandbox 禁用，可直接传 `/tmp/photo.png` 等任意路径
  - **操作步骤**：1. 开启工具开关 2. 准备一张含文字 / 二维码的 PNG 图片 3. iOS / iPad 通过 `.fileImporter` 选图；macOS 直接传路径 4. 发送「分析这张图片，识别其中的文字」
  - **预期结果**：LLM 调用 `describe_image` 工具，底层走 NativeVisionEngine，返回真实 OCR 文字与条码 payload，StepCard 展示工具调用与结果
  - **失败排查**：检查 `DescribeImageTool.execute` 调用链；查看 `MultimodalFacade.describeImage`；iOS 端检查 `DocumentPickerView.swift:13` 的 `.fileImporter`；macOS 端检查 `Aether-macOS.entitlements:15`（sandbox=false）

### 37.2 NativeASREngine（基于 SFSpeech 文件识别）

- [ ] 默认使用 NativeASREngine
  - **三端一致**：name 含 `NativeASR` / `SFSpeech`，`requiresNetwork = true`；无平台条件编译
  - **操作步骤**：1. 创建 `MultimodalFacade()` 2. 查询 `asrEngineName` 与 `requiresNetwork`
  - **失败排查**：检查 `MultimodalFacade.init()` 默认 ASR 引擎；`NativeASREngine.swift:14-82`

- [ ] 首次调用请求语音识别权限
  - **三端一致**：系统弹出「请求语音识别权限」对话框，点击允许后继续识别；三端都需要授权 `NSSpeechRecognitionUsageDescription` + `NSMicrophoneUsageDescription`
  - **操作步骤**：1. iOS / macOS 真机，未授权语音识别 2. 调用 `engine.transcribe(audioPath: URL, language: "zh")` 3. 观察系统弹窗
  - **失败排查**：检查 `SFSpeechRecognizer.requestAuthorization` 调用；查看 Info.plist `NSSpeechRecognitionUsageDescription` 与 `NSMicrophoneUsageDescription`

- [ ] 支持的音频格式
  - **三端一致**：wav / caf / m4a / mp3 / aac 5 种格式均能正确识别中文文字
  - **操作步骤**：1. 准备 wav / caf / m4a / mp3 / aac 各一份含中文语音 2. 依次调用 `engine.transcribe(audioPath: url, language: "zh")`
  - **失败排查**：检查 `NativeASREngine` 中扩展名白名单

- [ ] 不存在的文件抛错
  - **三端一致**：抛 `MultimodalError.emptyInput`
  - **操作步骤**：1. 传入不存在的文件路径 2. 调用 `transcribe(audioPath: URL(fileURLWithPath: "/tmp/nonexistent.wav"), language: "zh")`
  - **失败排查**：检查 `FileManager.fileExists` 校验

- [ ] 不支持的格式抛错
  - **三端一致**：抛 `MultimodalError.unsupportedAudioFormat`
  - **操作步骤**：1. 准备一个 .txt 文件 2. 调用 `transcribe(audioPath: txtURL, language: "zh")`
  - **失败排查**：检查扩展名校验

- [ ] CI 环境识别器不可用抛错
  - **三端一致**：`recognizer.isAvailable == false`，抛 `MultimodalError.asrRecognitionFailed`
  - **操作步骤**：1. CI 环境下（`CI=true`） 2. 调用 `transcribe(audioPath: wavURL, language: "zh")`
  - **失败排查**：检查 `recognizer.isAvailable` 判定

- [ ] transcribe_audio LLM 工具真实调用
  - **iOS**：文件路径必须来自 `.fileImporter` 用户选择，不能直接传 `/tmp/recording.wav`
  - **iPad**：同 iOS
  - **macOS**：可直接传 `/tmp/recording.wav` 等任意路径
  - **操作步骤**：1. 开启工具开关 2. 准备一段 ≥3 秒中文录音（wav） 3. iOS / iPad 通过 `.fileImporter` 选音频；macOS 直接传路径 4. 发送「转写音频」
  - **预期结果**：LLM 调用 `transcribe_audio` 工具，底层走 NativeASREngine，返回识别文字，StepCard 展示结果
  - **失败排查**：检查 `TranscribeAudioTool.execute`；查看权限授权状态；iOS 端检查文件路径来源

### 37.3 NativeTTSEngine（基于 AVSpeechSynthesizer.write）

- [ ] 默认使用 NativeTTSEngine
  - **三端一致**：name 含 `NativeTTS` / `AVSpeech`；代码三端一致
  - **操作步骤**：1. 创建 `MultimodalFacade()` 2. 查询 `ttsEngineName`
  - **失败排查**：检查 `MultimodalFacade.init()` 默认 TTS 引擎；`NativeTTSEngine.swift:13-113`

- [ ] 空文本抛 emptyInput
  - **三端一致**：抛 `MultimodalError.emptyInput`
  - **操作步骤**：1. 创建 NativeTTSEngine 2. 调用 `synthesize(text: "", voiceId: nil)`
  - **失败排查**：检查 `text.isEmpty` 校验

- [ ] 合成返回非空 WAV Data
  - **三端一致**：返回非空 `Data`，长度 ≥44 字节，前 4 字节为 ASCII `RIFF`，8-12 字节为 ASCII `WAVE`
  - **操作步骤**：1. iOS / macOS 真机（非 CI） 2. 调用 `synthesize(text: "你好，世界", voiceId: nil)` 3. 检查返回的 `Data`
  - **失败排查**：检查 `AVSpeechSynthesizer.write(_:toBufferCallback:)` 回调；查看 PCM Buffer 收集与 WAV 编码

- [ ] voiceId 无效回退默认中文
  - **三端一致**：回退到 `AVSpeechSynthesisVoice(language: "zh-CN")`，不抛错，返回合成数据
  - **操作步骤**：1. 传入不存在的 voiceId 2. 调用 `synthesize(text: "测试", voiceId: "non-existent-voice-id")`
  - **失败排查**：检查 `resolveVoice(voiceId:)` 中 `speechVoices()` 查找逻辑

- [ ] 音色库三端差异
  - **iOS**：默认音色 `AVSpeechSynthesisVoice(language: "zh-CN")`，可用音色依赖系统安装
  - **iPad**：同 iOS
  - **macOS**：系统音色库更丰富（包含高品质下载音色），可通过 `AVSpeechSynthesisVoice.speechVoices()` 列举更多音色
  - **操作步骤**：1. 调用 `AVSpeechSynthesisVoice.speechVoices()` 列举可用音色 2. macOS 观察音色数量是否显著多于 iOS 3. 尝试用不同 voiceId 合成
  - **失败排查**：检查 `NativeTTSEngine.swift:13-113` 中音色解析；查看系统已下载音色

- [ ] 长文本合成稳定
  - **三端一致**：返回完整 WAV Data，不卡死（30s 超时保护兜底）
  - **操作步骤**：1. 准备一段 ≥500 字的中文文本 2. 调用 `synthesize(text: longText, voiceId: nil)`
  - **失败排查**：检查超时保护 Task；查看 `finishOnce` 锁

- [ ] 30s 超时保护
  - **三端一致**：30s 后强制返回空 WAV 头（44 字节），不卡死
  - **操作步骤**：1. 模拟合成器无响应 2. 调用 synthesize 后等待 30s
  - **失败排查**：检查 `Task.sleep(nanoseconds: 30_000_000_000)` 超时分支

- [ ] CI 环境返回最小 WAV 头
  - **三端一致**：返回 44 字节最小空 WAV 头（RIFF + WAVE + fmt + data 长度 0），不卡住测试
  - **操作步骤**：1. CI 环境（`CI=true`） 2. 调用 `synthesize(text: "test", voiceId: nil)`
  - **失败排查**：检查 `ProcessInfo.processInfo.environment["CI"]` 判定

- [ ] synthesizeSpeech LLM 工具真实调用
  - **三端一致**：返回 WAV Data，可在消息气泡中播放或保存到文件
  - **操作步骤**：1. iOS / macOS 真机，已配置 API Key 2. 在主对话界面发送「请用语音合成说一段话」（如 LLM 触发 synthesize 工具或编程式调用 `MultimodalFacade.shared.synthesizeSpeech(text:voiceId:)`）
  - **失败排查**：检查 `MultimodalFacade.synthesizeSpeech` 调用链

### 37.4 引擎切换与向后兼容

- [ ] 切换回 PlaceholderVisionEngine
  - **三端一致**：name 含 `PlaceholderVisionEngine`
  - **操作步骤**：1. 创建 Facade 2. 调用 `facade.setVisionEngine(PlaceholderVisionEngine())` 3. 查询 `visionEngineName`
  - **失败排查**：检查 `setVisionEngine(_:)` actor 方法

- [ ] 切换回 PlaceholderASREngine
  - **三端一致**：name 为 `PlaceholderASR`
  - **操作步骤**：1. 创建 Facade 2. 调用 `facade.setASREngine(PlaceholderASREngine())` 3. 查询 `asrEngineName`
  - **失败排查**：检查 `setASREngine(_:)`

- [ ] 切换回 PlaceholderTTSEngine
  - **三端一致**：name 为 `PlaceholderTTS`
  - **操作步骤**：1. 创建 Facade 2. 调用 `facade.setTTSEngine(PlaceholderTTSEngine())` 3. 查询 `ttsEngineName`
  - **失败排查**：检查 `setTTSEngine(_:)`

### 37.5 NativeEnginesTests 单测执行

- [ ] 24 个测试用例全部通过
  - **iOS**：✅ 在 iOS 模拟器（iPhone 17）执行 `xcodebuild test -project Aether.xcodeproj -scheme Aether-iOS -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AetherTests/NativeEnginesTests CODE_SIGNING_ALLOWED=NO`
  - **iPad**：同 iOS，可指定 iPad 模拟器 destination
  - **macOS**：三端代码一致，可在 macOS scheme 下执行（若有 macOS 测试 target）
  - **操作步骤**：1. 执行上述 xcodebuild test 命令 2. 查看测试输出
  - **预期结果**：24 个用例全部通过（0 failures，0 skipped，CI 环境下跳过的用例不算）
  - **失败排查**：查看测试输出；检查 NativeVisionEngine / NativeASREngine / NativeTTSEngine 实现

## 38. Windows 端手测项（WPF .NET 8 thin client）

### 38.1 环境与构建

- [ ] .NET 8 SDK 安装验证
  - **前置条件**：Windows 10+ 开发机
  - **操作步骤**：1. 执行 `dotnet --version` 2. 执行 `dotnet --list-sdks`
  - **预期结果**：SDK 版本 ≥ 8.0.x，列表中包含 `8.0.xxx` SDK
  - **失败排查**：安装 .NET 8 SDK；检查 PATH 环境变量；查看 `global.json` 是否指定了不存在的 SDK 版本（`windows/Aether.Windows/global.json`）

- [ ] Windows 10+ 系统验证
  - **前置条件**：Windows 开发机
  - **操作步骤**：1. 执行 `winver` 2. 确认版本号 ≥ 10.0.19041
  - **预期结果**：系统为 Windows 10 2004+ 或 Windows 11
  - **失败排查**：升级系统；WPF .NET 8 不支持 Windows 7/8

- [ ] PowerShell 7+ 验证
  - **前置条件**：Windows 开发机
  - **操作步骤**：1. 执行 `pwsh -v` 2. 确认版本 ≥ 7.0
  - **预期结果**：PowerShell 7+ 已安装
  - **失败排查**：安装 PowerShell 7；或回退使用 Windows PowerShell 5.1（脚本兼容但建议 7+）

- [ ] 构建命令验证（make build-windows）
  - **前置条件**：仓库根目录，已安装 make 工具
  - **操作步骤**：1. 执行 `make build-windows`
  - **预期结果**：构建成功，输出 BUILD SUCCESS
  - **失败排查**：检查 `Makefile` 中 `build-windows` target；查看 `scripts/build-windows.ps1` 脚本

- [ ] 构建命令验证（pwsh scripts/build-windows.ps1 -Command build）
  - **前置条件**：仓库根目录
  - **操作步骤**：1. 执行 `pwsh scripts/build-windows.ps1 -Command build`
  - **预期结果**：构建成功，打印构建产物路径
  - **失败排查**：检查 `scripts/build-windows.ps1` 4 个子命令 build/publish/test/clean；查看 dotnet build 输出

- [ ] 构建命令验证（dotnet build）
  - **前置条件**：`windows/Aether.Windows/` 目录
  - **操作步骤**：1. `cd windows/Aether.Windows` 2. 执行 `dotnet build -c Debug`
  - **预期结果**：Build succeeded，0 errors
  - **失败排查**：检查 `windows/Aether.Windows/Aether.Windows.csproj`；查看 NuGet 还原是否成功

- [ ] 构建产物验证（bin/Debug/）
  - **前置条件**：Debug 构建已成功
  - **操作步骤**：1. 查看 `windows/Aether.Windows/bin/Debug/net8.0-windows/` 2. 确认 `Aether.Windows.exe` 存在
  - **预期结果**：可执行文件存在且可双击启动
  - **失败排查**：重新执行 `dotnet build`；检查 OutputType 是否为 WinExe

- [ ] Rust DLL 集成验证（Native/aether_core_ffi.dll 存在性）
  - **前置条件**：Rust 工具链已安装，CI 中由 rust job 构建 DLL
  - **操作步骤**：1. 查看 `windows/Aether.Windows/Native/aether_core_ffi.dll` 是否存在 2. 若不存在执行 `make build-rust-windows`
  - **预期结果**：DLL 存在；若不存在应用仍可启动（安全降级）
  - **失败排查**：检查 `rust/ffi/` FFI 导出；查看 `scripts/build-rust.ps1`；确认 `windows/Aether.Windows/Native/AetherNativeBridge.cs` 中 DLL 名 `aether_core_ffi.dll` 与实际一致

- [ ] Rust DLL 安全降级验证
  - **前置条件**：移除或重命名 `Native/aether_core_ffi.dll`
  - **操作步骤**：1. 启动应用 2. 发送一条消息
  - **预期结果**：应用不崩溃，自动走托管 SSE 解析路径（`UseRustSse=false`）
  - **失败排查**：检查 `windows/Aether.Windows/Native/AetherNativeBridge.cs` 中 `try/catch DllNotFoundException` 逻辑；查看日志中是否有降级提示

### 38.2 基础对话功能

- [ ] 应用启动（MainWindow 1000×700 + ChatPage 加载）
  - **前置条件**：Debug 构建产物已就绪
  - **操作步骤**：1. 双击 `Aether.Windows.exe` 或执行 `dotnet run --project windows/Aether.Windows`
  - **预期结果**：窗口尺寸 1000×700，标题栏显示「以太」，Frame 导航到 ChatPage
  - **失败排查**：检查 `windows/Aether.Windows/MainWindow.xaml` 中 Width=1000 Height=700；查看 `App.xaml.cs` 启动导航逻辑

- [ ] BFF Token 配置（硬编码 baseUrl）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `windows/Aether.Windows/ChatPage.xaml.cs:16` 2. 确认 `baseUrl` 已配置为可用 BFF 地址
  - **预期结果**：baseUrl 指向可达的 BFF 服务（TODO 待配置化）
  - **失败排查**：手动修改硬编码 baseUrl；追踪 TODO 待设置页实现后迁移

- [ ] 发送消息 + SSE 流式响应（StreamChatAsync）
  - **前置条件**：BFF 服务可达，Token 有效
  - **操作步骤**：1. 在输入框输入「你好」 2. 点击发送 Button
  - **预期结果**：调用 `AetherApiClient.StreamChatAsync`，SSE 流式响应逐步到达
  - **失败排查**：检查 `windows/Aether.Windows/Services/AetherApiClient.cs` 中 StreamChatAsync 实现；查看 HttpClient 是否设置 X-BFF-Token header

- [ ] 流式文本累加（StreamingText 实时更新）
  - **前置条件**：SSE 流已建立
  - **操作步骤**：1. 发送消息 2. 观察 StreamingText TextBlock 实时更新
  - **预期结果**：文本逐字累加显示在流式 TextBlock 中
  - **失败排查**：检查 `windows/Aether.Windows/ViewModels/ChatViewModel.cs` 中 StreamingText 属性绑定的 `OnPropertyChanged` 通知；确认 UI 线程调度 `Dispatcher.Invoke`

- [ ] 错误处理（ErrorMessage 显示）
  - **前置条件**：BFF 服务不可达或 Token 无效
  - **操作步骤**：1. 关闭 BFF 服务或修改 Token 为无效值 2. 发送消息
  - **预期结果**：错误 TextBlock 显示 ErrorMessage，应用不崩溃
  - **失败排查**：检查 `ChatViewModel.cs` 中 SendCommand 的 try/catch；查看 ErrorMessage 是否触发 OnPropertyChanged

- [ ] 回车发送（SendCommand）
  - **前置条件**：输入框已聚焦
  - **操作步骤**：1. 输入消息 2. 按下回车键
  - **预期结果**：触发 SendCommand，等价于点击发送 Button
  - **失败排查**：检查 `windows/Aether.Windows/ChatPage.xaml` 中 TextBox 的 KeyDown / InputBindings 绑定；确认 SendCommand 的 CanExecute

### 38.3 API 客户端

- [ ] GetConversationsAsync（会话列表，仅 API 无 UI）
  - **前置条件**：BFF 服务可达，已有至少 1 个会话
  - **操作步骤**：1. 在测试代码或调试器中调用 `AetherApiClient.GetConversationsAsync` 2. 检查返回的 `List<Conversation>`
  - **预期结果**：返回会话列表，包含 id / title / updatedAt 等字段
  - **失败排查**：检查 `windows/Aether.Windows/Services/AetherApiClient.cs:53-107` 中 GET `/api/conversations` 实现；查看 X-BFF-Token header

- [ ] CreateConversationAsync
  - **前置条件**：BFF 服务可达
  - **操作步骤**：1. 调用 `CreateConversationAsync(title)` 2. 检查返回的 Conversation
  - **预期结果**：BFF 创建会话并返回新会话对象，包含服务端生成的 id
  - **失败排查**：检查 POST `/api/conversations` 实现；查看请求 body 序列化

- [ ] DeleteConversationAsync
  - **前置条件**：已存在至少 1 个会话
  - **操作步骤**：1. 调用 `DeleteConversationAsync(conversationId)` 2. 再次调用 GetConversationsAsync
  - **预期结果**：被删除的会话不再出现在列表中
  - **失败排查**：检查 DELETE `/api/conversations/{id}` 实现；查看 HTTP 状态码 204

- [ ] GetMessagesAsync
  - **前置条件**：会话中已有消息
  - **操作步骤**：1. 调用 `GetMessagesAsync(conversationId)`
  - **预期结果**：返回该会话的消息列表，按时间升序
  - **失败排查**：检查 GET `/api/conversations/{id}/messages` 实现

- [ ] StreamChatAsync（托管路径 + Rust 路径切换 UseRustSse）
  - **前置条件**：会话已创建
  - **操作步骤**：1. 设置 `UseRustSse=false` 调用 StreamChatAsync 2. 设置 `UseRustSse=true` 再次调用
  - **预期结果**：两条路径均能正确返回 SSE 流；Rust 路径使用 `aether_sse_parse_chunk` 解析
  - **失败排查**：检查 `AetherNativeBridge.ParseSseChunk` 调用；对比托管路径与 Rust 路径输出是否一致

- [ ] 记忆 CRUD（ListMemoryAsync / CreateMemoryAsync / SearchMemoryAsync / DeleteMemoryAsync）
  - **前置条件**：BFF 记忆端点已部署
  - **操作步骤**：1. 调用 CreateMemoryAsync 2. 调用 ListMemoryAsync 3. 调用 SearchMemoryAsync 4. 调用 DeleteMemoryAsync
  - **预期结果**：4 个操作均成功，列表中能查到新建记忆，搜索能命中，删除后不再出现
  - **失败排查**：检查 `AetherApiClient.cs` 中记忆端点 `/api/memory` 实现序列

### 38.4 Rust P/Invoke 集成

- [ ] ParseSseChunk（aether_sse_parse_chunk）
  - **前置条件**：`aether_core_ffi.dll` 已就位
  - **操作步骤**：1. 准备一段 SSE chunk 字节 2. 调用 `AetherNativeBridge.ParseSseChunk`
  - **预期结果**：返回解析后的 content / toolCalls 结构，与托管路径一致
  - **失败排查**：检查 `windows/Aether.Windows/Native/AetherNativeBridge.cs` 中 `[DllImport("aether_core_ffi.dll")]` 签名；查看 `rust/ffi/` 中 `aether_sse_parse_chunk` 导出

- [ ] CosineF32（aether_cosine_f32）
  - **前置条件**：DLL 已就位
  - **操作步骤**：1. 准备两个等长 float 数组 2. 调用 `AetherNativeBridge.CosineF32`
  - **预期结果**：返回余弦相似度值 ∈ [-1, 1]
  - **失败排查**：检查数组长度一致性；查看 `aether_cosine_f32` 实现

- [ ] Redact（aether_redact）
  - **前置条件**：DLL 已就位
  - **操作步骤**：1. 准备含敏感信息（手机号/邮箱）的文本 2. 调用 `AetherNativeBridge.Redact`
  - **预期结果**：返回脱敏后文本，敏感信息被替换为 `***`
  - **失败排查**：检查 `aether_redact` 实现的正则规则；查看内存分配与字符串释放

- [ ] DLL 不存在时安全降级（try/catch DllNotFoundException）
  - **前置条件**：移除 `Native/aether_core_ffi.dll`
  - **操作步骤**：1. 启动应用 2. 调用任一 native 方法
  - **预期结果**：抛出 `DllNotFoundException` 被 catch，应用回退到托管实现，不崩溃
  - **失败排查**：检查 `AetherNativeBridge.cs` 中 try/catch 块；确认降级日志输出

### 38.5 设计令牌与 UI

- [ ] AetherColors 7 色应用
  - **前置条件**：应用已启动
  - **操作步骤**：1. 观察顶部栏背景色（LiquidGlass）2. 观察消息气泡色（AetherPurple）3. 观察窗口背景（DeepSpace）4. 观察标题文字（Starlight）
  - **预期结果**：7 色 AetherColors 与 Apple 端一致
  - **失败排查**：检查 `windows/Aether.Windows/DesignTokens.cs` 中 AetherColors 定义；对比 Apple 端 `DesignSystem.swift`

- [ ] AetherCornerRadius（12/16/24/999）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 检查 ChatPage.xaml 中各控件的 CornerRadius
  - **预期结果**：12/16/24/999 四档圆角被正确应用
  - **失败排查**：检查 `DesignTokens.cs` 中 AetherCornerRadius 常量；查看 XAML 绑定

- [ ] 已知 UI 限制确认
  - **前置条件**：应用已启动并完成一次对话
  - **操作步骤**：1. 观察用户/AI 消息气泡 2. 检查是否有 Markdown 渲染 3. 检查是否有 TypingIndicator 4. 检查是否有会话列表 UI 5. 检查是否有设置页
  - **预期结果**：用户/AI 消息同色左对齐无区分；无 Markdown 渲染（纯 TextBlock）；无 TypingIndicator；无会话列表 UI；无设置页
  - **失败排查**：以上限制属预期行为，无需修复；若误出现新功能需回归测试

### 38.6 单元测试

- [ ] AetherApiClientTest.cs 执行
  - **前置条件**：`windows/Aether.Windows.Tests/` 项目已编译
  - **操作步骤**：1. 执行 `dotnet test windows/Aether.Windows.Tests` 2. 查看 `AetherApiClientTest.cs`（206 行）覆盖 GetConversationsAsync + StreamChatAsync 托管路径
  - **预期结果**：所有用例通过，stub HttpClient 返回预期数据
  - **失败排查**：检查 `windows/Aether.Windows.Tests/AetherApiClientTest.cs` 中 stub HttpClient 实现；查看测试覆盖的端点路径

- [ ] ModelsTest.cs 执行
  - **前置条件**：测试项目已编译
  - **操作步骤**：1. 执行 `dotnet test` 2. 查看 `ModelsTest.cs`（189 行）覆盖 4 个 POCO 默认值与 JSON 往返
  - **预期结果**：4 个 POCO（Conversation / Message / Memory 等）默认值与 JSON 序列化/反序列化往返一致
  - **失败排查**：检查 `windows/Aether.Windows.Tests/ModelsTest.cs` 中 JsonSerializerOptions 配置；查看 POCO 属性默认值

- [ ] 单元测试命令验证
  - **前置条件**：测试项目已编译
  - **操作步骤**：1. 执行 `dotnet test`
  - **预期结果**：所有测试通过，输出 Passed: N Failed: 0
  - **失败排查**：查看 `pwsh scripts/build-windows.ps1 -Command test` 是否等价；检查 xUnit 版本兼容性

### 38.7 已知限制与未开放功能

- [ ] 限制清单确认
  - **前置条件**：N/A
  - **操作步骤**：1. 逐项确认以下功能未在 Windows 端实现
  - **预期结果**：以下功能均未开放（属预期行为，非 Bug）
  - **失败排查**：若某项意外出现，需回归对应实现
  - ❌ RAG 知识库（API 已提供 `searchDocuments`，客户端无 UI）
  - ❌ 工具调用（BFF 端执行，客户端无 UI）
  - ❌ 多模态（NativeVision / ASR / TTS）
  - ❌ HealthKit（Windows 平台无 HealthKit 等价 API）
  - ❌ 端侧 MLX 推理（Rust FFI `#[cfg]` 排除 Windows）
  - ❌ 离线模式（依赖 BFF 在线服务）
  - ❌ 本地数据库（无 SQLite / EF Core，仅 BffConfigStore）
  - ❌ MSIX 打包（仅 zip 自包含发布）
  - ❌ watchOS / Widget

### 38.8 会话列表 UI（新增 v1.5）

- [ ] ConversationListPage 加载
  - **前置条件**：BFF 服务可达，已存在至少 1 个会话
  - **操作步骤**：1. 启动应用 2. 导航到 ConversationListPage
  - **预期结果**：会话列表加载并展示，每行显示标题 / 最后消息预览 / 时间戳
  - **失败排查**：检查 `windows/Aether.Windows/Pages/ConversationListPage.xaml` 数据绑定；查看 ConversationListViewModel.LoadCommand 调用

- [ ] 创建新会话（ExtendedFAB）
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 点击 ExtendedFAB「新会话」按钮
  - **预期结果**：调用 BFF 创建会话，列表头部出现新会话项并自动导航到 ChatPage
  - **失败排查**：检查 ConversationListViewModel.CreateCommand；查看 AetherApiClient.CreateConversationAsync 实现

- [ ] 置顶 / 取消置顶
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 右键会话项 → 置顶 2. 再次右键 → 取消置顶
  - **预期结果**：置顶后会话移到列表顶部并显示置顶图标；取消后回到原位置
  - **失败排查**：检查 PinCommand 实现；查看 BFF PATCH `/conversations/{id}/pin` 调用

- [ ] 删除会话
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 右键会话项 → 删除 2. 确认弹窗中点击「确认」
  - **预期结果**：会话从列表移除，BFF 调用 DELETE `/conversations/{id}` 成功
  - **失败排查**：检查 DeleteCommand；查看确认弹窗绑定

- [ ] 点击会话导航到 ChatPage
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 点击任一会话项
  - **预期结果**：Frame 导航到 ChatPage 并传递 conversationId 参数
  - **失败排查**：检查 ListView SelectionChanged 事件；查看 Frame.Navigate 调用

- [ ] 错误 Banner 显示
  - **前置条件**：BFF 服务不可达
  - **操作步骤**：1. 启动应用进入会话列表 2. 观察错误状态
  - **预期结果**：顶部显示红色错误 Banner「加载会话失败」，并提供重试按钮
  - **失败排查**：检查 ErrorBanner Visibility 绑定；查看 LoadCommand 异常处理

### 38.9 设置页（新增 v1.5）

- [ ] BFF BaseUrl 输入
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 在 BFF BaseUrl TextBox 中输入新地址（如 `https://aether-bff.example.com`）
  - **预期结果**：输入生效，保存时持久化到 BffConfigStore
  - **失败排查**：检查 `windows/Aether.Windows/Pages/SettingsPage.xaml` TextBox 绑定；查看 SettingsViewModel 中的双向绑定模式

- [ ] BFF Token PasswordBox + 显示/隐藏切换
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 在 Token PasswordBox 中输入 token 2. 点击眼睛图标切换显示
  - **预期结果**：默认隐藏为圆点；切换后明文显示；保存时通过 DPAPI 加密后写入 BffConfigStore
  - **失败排查**：检查 PasswordBox 与 ToggleButton 绑定；查看 BffConfigStore 中 ProtectedData.Protect 调用

- [ ] 默认模型 ComboBox
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 点击默认模型 ComboBox 2. 选择不同模型（如 deepseek-chat / qwen-plus）
  - **预期结果**：下拉列表展示可选模型，选择后保存到 BffConfigStore
  - **失败排查**：检查 ComboBox ItemsSource 绑定；查看模型列表初始化逻辑

- [ ] 语言选择器（8 种语言）
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 点击语言选择器 2. 选择不同语言（zh-Hans / en / ja / ko / fr / de / es / zh-Hant）
  - **预期结果**：8 种语言可选；选择后调用 LanguageService.ApplyLanguage 立即切换 UI 文本
  - **失败排查**：检查 LanguageService 实现；查看 .resx 文件 Resources.Designer.cs

- [ ] 保存按钮（DPAPI 加密持久化）
  - **前置条件**：修改任一配置项
  - **操作步骤**：1. 点击「保存」按钮 2. 重启应用 3. 重新进入设置页
  - **预期结果**：BffConfigStore.SaveAsync 调用 ProtectedData.Protect 加密 Token；重启后配置仍存在
  - **失败排查**：检查 BffConfigStore 文件路径（`%AppData%/Aether/bff-config.json`）；查看 DPAPI 调用是否抛异常

- [ ] 返回按钮
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 点击左上角返回按钮
  - **预期结果**：Frame 导航回上一页（会话列表或 ChatPage）
  - **失败排查**：检查 Frame.GoBack 调用；查看 CanGoBack 判断

### 38.10 Markdown 渲染（新增 v1.5）

- [ ] 标题渲染（H1-H6）
  - **前置条件**：与 AI 进行一轮对话，AI 回复包含 `#` / `##` / `###` / `####` / `#####` / `######` 标题
  - **操作步骤**：1. 发送「请用 6 级标题示例回答」 2. 观察 AI 消息气泡
  - **预期结果**：H1-H6 字号递减、加粗显示，FlowDocument 中显示为 Paragraph
  - **失败排查**：检查 `windows/Aether.Windows/Services/MarkdownRenderer.cs` 中标题转换；查看 Markdig AST 解析

- [ ] 代码块渲染（语法高亮）
  - **前置条件**：AI 回复包含 ` ```language ... ``` ` 围栏代码块
  - **操作步骤**：1. 发送「请用 Python 写一段冒泡排序」 2. 观察代码块
  - **预期结果**：代码块以等宽字体渲染，背景深色，保留缩进与换行
  - **失败排查**：检查 FencedCodeBlock 渲染逻辑；查看 RichTextBox 中 FontFamily=Consolas 绑定

- [ ] 表格渲染
  - **前置条件**：AI 回复包含 GFM 表格
  - **操作步骤**：1. 发送「请用表格对比 React / Vue / Angular」 2. 观察表格
  - **预期结果**：表格以 Table 控件渲染，含表头 / 表体，列对齐正确
  - **失败排查**：检查 Markdig 表格扩展启用；查看 FlowDocument 中 Table 控件生成

- [ ] 任务列表渲染（CheckBox）
  - **前置条件**：AI 回复包含 `- [ ]` / `- [x]` 任务列表
  - **操作步骤**：1. 发送「请列出 3 个待办事项，前 2 个完成」 2. 观察任务列表
  - **预期结果**：每项前显示 CheckBox，已完成项勾选状态正确
  - **失败排查**：检查 Markdig task list 扩展；查看 CheckBox 控件渲染

- [ ] 链接渲染（Hyperlink）
  - **前置条件**：AI 回复包含 `[text](url)` 链接
  - **操作步骤**：1. 发送「请给出 GitHub 仓库链接」 2. 点击链接
  - **预期结果**：链接以 Hyperlink 显示，点击后在默认浏览器中打开
  - **失败排查**：检查 Hyperlink.Click 事件；查看 Process.Start 调用

- [ ] 加粗 / 斜体 / 删除线
  - **前置条件**：AI 回复包含 `**bold**` / `*italic*` / `~~strike~~`
  - **操作步骤**：1. 发送「请用加粗、斜体、删除线各写一个词」 2. 观察 Inline 渲染
  - **预期结果**：加粗显示为 Bold，斜体为 Italic，删除线带横线
  - **失败排查**：检查 Markdig 内联解析；查看 FlowDocument Inline 集合生成

### 38.11 i18n 国际化（新增 v1.5）

- [ ] 默认语言 zh-Hans
  - **前置条件**：首次启动应用
  - **操作步骤**：1. 启动应用 2. 观察所有 UI 文本
  - **预期结果**：默认显示简体中文（如「新会话」「设置」「发送」）
  - **失败排查**：检查 LanguageService 默认值；查看 Resources.Designer.cs 默认 Culture

- [ ] 切换到 English
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 语言选择器选「English」 2. 观察所有 UI 文本
  - **预期结果**：所有文本立即切换为英文（如「New Conversation」「Settings」「Send」）
  - **失败排查**：检查 Resources.en.resx 是否存在；查看 LanguageService.ApplyLanguage 调用

- [ ] 切换到 日本語
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 语言选择器选「日本語」 2. 观察 UI 文本
  - **预期结果**：所有文本切换为日文（如「新規会話」「設定」「送信」）
  - **失败排查**：检查 Resources.ja.resx；查看 Culture 切换是否生效

- [ ] 切换到 繁體中文
  - **前置条件**：进入 SettingsPage
  - **操作步骤**：1. 语言选择器选「繁體中文」 2. 观察 UI 文本
  - **预期结果**：所有文本切换为繁体中文（如「新會話」「設定」「傳送」）
  - **失败排查**：检查 Resources.zh-Hant.resx；查看 Culture 名称为 zh-Hant

- [ ] 切换后所有 UI 文本立即更新
  - **前置条件**：应用启动并完成一轮对话
  - **操作步骤**：1. 切换语言 2. 检查会话列表 / ChatPage / SettingsPage / 错误 Banner 文本
  - **预期结果**：所有页面 UI 文本立即更新为新语言，无需重启应用
  - **失败排查**：检查 LanguageService 是否通知所有 ViewModel 刷新；查看 INotifyPropertyChanged 触发

### 38.12 消息气泡 + TypingIndicator（新增 v1.5）

- [ ] 用户消息右对齐 AetherPurple
  - **前置条件**：发送一条用户消息
  - **操作步骤**：1. 输入「你好」并点击发送
  - **预期结果**：用户消息气泡右对齐，背景色为 AetherPurple，文字白色
  - **失败排查**：检查 ChatPage.xaml 中 ItemsControl ItemTemplate 的 HorizontalAlignment；查看 AetherColors.Purple 绑定

- [ ] AI 消息左对齐 LiquidGlass
  - **前置条件**：AI 回复一条消息
  - **操作步骤**：1. 等待 AI 流式响应完成
  - **预期结果**：AI 消息气泡左对齐，背景色为 LiquidGlass，文字 Starlight
  - **失败排查**：检查 ItemTemplate 中 IsMine 判断逻辑；查看 BooleanToValueConverter

- [ ] 流式响应时三圆点闪烁
  - **前置条件**：发起一轮对话
  - **操作步骤**：1. 发送消息 2. 观察 AI 气泡在首个 token 到达前的状态
  - **预期结果**：AI 气泡显示三个圆点闪烁动画（TypingIndicator），首个 token 到达后切换为流式文本
  - **失败排查**：检查 TypingIndicator UserControl 动画 Storyboard；查看 IsStreaming 状态绑定

- [ ] 消息时间戳显示
  - **前置条件**：发送并接收一条消息
  - **操作步骤**：1. 观察消息气泡底部
  - **预期结果**：每条消息底部显示时间戳（格式 HH:mm），用户与 AI 消息均显示
  - **失败排查**：检查 ItemTemplate 中 Timestamp TextBlock 绑定；查看 Message.CreatedAt 格式化

## 39. Android 端手测项（Kotlin + Jetpack Compose thin client）

### 39.1 环境与构建

- [ ] JDK 17 验证
  - **前置条件**：开发机已安装 JDK
  - **操作步骤**：1. 执行 `java -version` 2. 执行 `echo $JAVA_HOME`
  - **预期结果**：openjdk version "17.x.x"，JAVA_HOME 已设置
  - **失败排查**：安装 JDK 17（Android Studio 自带）；检查 `~/.zshrc` 或 `~/.bashrc` 中 JAVA_HOME

- [ ] Android SDK 35 验证
  - **前置条件**：Android Studio 已安装
  - **操作步骤**：1. 执行 `echo $ANDROID_HOME` 2. 执行 `echo $ANDROID_SDK_ROOT` 3. 查看 `sdkmanager --list_installed`
  - **预期结果**：环境变量已设置，安装了 platforms;android-35 与 build-tools;35.0.0
  - **失败排查**：通过 Android Studio → SDK Manager 安装 SDK 35；检查 `android/local.properties` 自动生成

- [ ] Gradle 8.7 + Wrapper 验证
  - **前置条件**：仓库已 clone
  - **操作步骤**：1. 查看 `android/gradle/wrapper/gradle-wrapper.properties` 中 `distributionUrl` 2. 执行 `./gradlew --version`
  - **预期结果**：Gradle 8.7，Wrapper 已提交到仓库
  - **失败排查**：检查 `android/gradlew` 是否有可执行权限 `chmod +x gradlew`；查看 wrapper properties

- [ ] 构建命令验证（make build-android）
  - **前置条件**：仓库根目录
  - **操作步骤**：1. 执行 `make build-android`
  - **预期结果**：Debug APK 构建成功
  - **失败排查**：检查 `Makefile` 中 `build-android` target；查看 `scripts/build-android.sh` 输出

- [ ] 构建命令验证（./scripts/build-android.sh build-android）
  - **前置条件**：仓库根目录
  - **操作步骤**：1. 执行 `./scripts/build-android.sh build-android`
  - **预期结果**：构建成功，输出 APK 路径
  - **失败排查**：检查 `scripts/build-android.sh` 4 个子命令 build-android/build-android-release/test-android/clean

- [ ] 构建命令验证（./gradlew assembleDebug）
  - **前置条件**：`android/` 目录
  - **操作步骤**：1. `cd android` 2. 执行 `./gradlew assembleDebug`
  - **预期结果**：BUILD SUCCESSFUL
  - **失败排查**：查看 `android/app/build.gradle` 中 compileSdk=35；检查 Kotlin 1.9.24 + Compose BOM 2024.09.00 依赖

- [ ] 构建产物验证（app-debug.apk）
  - **前置条件**：Debug 构建已成功
  - **操作步骤**：1. 查看 `android/app/build/outputs/apk/debug/app-debug.apk` 2. 执行 `adb install app-debug.apk`
  - **预期结果**：APK 文件存在，可安装到设备
  - **失败排查**：检查 `android/app/build.gradle` 中 applicationId；查看 minSdk=29 是否与设备匹配

- [ ] Rust JNI 集成验证（libaether_core_ffi.so）
  - **前置条件**：CI 中由 rust job 构建 .so
  - **操作步骤**：1. 查看 `android/app/src/main/jniLibs/arm64-v8a/libaether_core_ffi.so` 2. 查看 `android/app/src/main/jniLibs/x86_64/libaether_core_ffi.so`
  - **预期结果**：两个 ABI 的 .so 文件均存在
  - **失败排查**：执行 `make build-rust-android`；查看 `scripts/build-rust-android.sh`；检查 `rust/ffi/` 中 `#[cfg(target_os = "android")]` 导出

- [ ] local.properties 自动生成
  - **前置条件**：首次构建
  - **操作步骤**：1. 删除 `android/local.properties` 2. 执行 `./gradlew assembleDebug`
  - **预期结果**：构建脚本自动生成 `local.properties`，写入 sdk.dir
  - **失败排查**：检查 `scripts/build-android.sh` 中 local.properties 生成逻辑；确认 ANDROID_HOME 已设置

### 39.2 应用启动与导航

- [ ] MainActivity 启动（enableEdgeToEdge + AetherTheme）
  - **前置条件**：APK 已安装到设备/模拟器
  - **操作步骤**：1. 点击应用图标启动
  - **预期结果**：应用启动，EdgeToEdge 沉浸式状态栏，AetherTheme 强制深色模式
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/MainActivity.kt` 中 `enableEdgeToEdge()` + `setContent { AetherTheme { AetherApp() } }`

- [ ] ServiceLocator 初始化（DataStore + BFF 配置流）
  - **前置条件**：应用首次启动
  - **操作步骤**：1. 启动应用 2. 观察日志中 ServiceLocator 初始化
  - **预期结果**：DataStore Preferences 与 BFF 配置流初始化完成，无异常
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/AetherApp.kt` 中 ServiceLocator 调用；查看 BffConfigStore 初始化

- [ ] 三路由导航（conversations / chat/{conversationId}/{title} / settings）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 启动后默认进入 conversations 2. 点击某会话进入 chat 3. 点击 TopAppBar 设置图标进入 settings 4. 返回
  - **预期结果**：三路由切换正常，NavHost 路由配置正确
  - **失败排查**：检查 `AetherApp.kt` 中 `NavHost(startDestination = "conversations")` 与 composable 路由声明

- [ ] 路由参数传递（URL 编码 title）
  - **前置条件**：会话标题包含特殊字符（如空格 / 中文 / &）
  - **操作步骤**：1. 创建标题为「测试 会话 & 你好」的会话 2. 进入该会话
  - **预期结果**：TopAppBar 显示正确解码后的标题
  - **失败排查**：检查 `AetherApp.kt` 中 `Uri.encode(title)` / `Uri.decode(title)` 调用

### 39.3 会话列表 UI

- [ ] ConversationListScreen 加载（Scaffold + TopAppBar + ExtendedFAB「新会话」）
  - **前置条件**：应用启动后进入会话列表
  - **操作步骤**：1. 观察页面结构
  - **预期结果**：顶部 TopAppBar + 右下 ExtendedFAB「新会话」+ LazyColumn
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/conversations/ConversationListScreen.kt` 中 Scaffold 结构

- [ ] LazyColumn 会话 Card 渲染（置顶图标 + 标题 + 预览 + 时间）
  - **前置条件**：已有至少 2 个会话
  - **操作步骤**：1. 查看会话列表
  - **预期结果**：每个 Card 显示置顶图标（若已置顶）、标题、最后一条消息预览、相对时间
  - **失败排查**：检查 `ConversationListScreen.kt` 中 ConversationCard 组合；查看时间格式化

- [ ] 创建会话（ExtendedFAB → onCreated 回调）
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 点击 ExtendedFAB「新会话」
  - **预期结果**：调用 onCreateConversation 回调，创建新会话并跳转到 chat 路由
  - **失败排查**：检查 `ConversationListScreen.kt` 中 ExtendedFAB onClick；查看 ViewModel createConversation 调用

- [ ] 置顶/取消置顶（IconButton）
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 点击某会话 Card 上的置顶 IconButton 2. 再次点击取消置顶
  - **预期结果**：置顶图标切换状态，置顶会话上移到列表顶部
  - **失败排查**：检查 `ConversationListScreen.kt` 中 IconButton onClick；查看 ViewModel togglePin 调用与排序逻辑

- [ ] 删除会话（IconButton）
  - **前置条件**：已有至少 1 个会话
  - **操作步骤**：1. 点击某会话 Card 上的删除 IconButton 2. 确认删除
  - **预期结果**：会话从列表中移除
  - **失败排查**：检查 `ConversationListScreen.kt` 中删除 IconButton；查看 ViewModel deleteConversation 调用

- [ ] 错误 Banner 显示
  - **前置条件**：BFF 服务不可达
  - **操作步骤**：1. 关闭 BFF 服务 2. 下拉刷新会话列表
  - **预期结果**：顶部显示错误 Banner，包含错误信息
  - **失败排查**：检查 `ConversationListScreen.kt` 中 uiState.error 渲染分支

- [ ] 下拉刷新
  - **前置条件**：会话列表已加载
  - **操作步骤**：1. 在列表顶部下拉
  - **预期结果**：触发刷新指示器，重新拉取会话列表
  - **失败排查**：检查 `ConversationListScreen.kt` 中 `pullToRefresh` 修饰符；查看 ViewModel refresh 调用

### 39.4 聊天 UI

- [ ] ChatScreen 加载（Scaffold + TopAppBar 返回/设置）
  - **前置条件**：从会话列表进入某会话
  - **操作步骤**：1. 观察页面结构
  - **预期结果**：TopAppBar 左侧返回箭头 + 右侧设置图标，下方 LazyColumn 消息列表 + 底部 ChatInputBar
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/chat/ChatScreen.kt` 中 Scaffold 结构

- [ ] MessageBubble 左右区分（用户 aetherPurple 右对齐 / AI liquidGlass 左对齐）
  - **前置条件**：已发送至少 2 条消息
  - **操作步骤**：1. 观察消息气泡布局
  - **预期结果**：用户消息靠右、aetherPurple 背景；AI 消息靠左、liquidGlass 背景
  - **失败排查**：检查 `ChatScreen.kt` 中 MessageBubble 的 `Arrangement.End` / `Arrangement.Start`；查看背景色绑定

- [ ] StreamingBubble 流式光标 `▌`
  - **前置条件**：SSE 流式响应进行中
  - **操作步骤**：1. 发送消息 2. 观察流式气泡
  - **预期结果**：流式文本末尾出现 `▌` 光标闪烁
  - **失败排查**：检查 `ChatScreen.kt` 中 StreamingBubble 的光标组合；查看动画 spec

- [ ] TypingIndicator「思考中…」
  - **前置条件**：等待 AI 响应阶段
  - **操作步骤**：1. 发送消息 2. 观察首字节到达前
  - **预期结果**：显示「思考中…」提示
  - **失败排查**：检查 `ChatScreen.kt` 中 TypingIndicator 组合；查看 uiState.isLoading 状态

- [ ] ChatInputBar（OutlinedTextField + FilledIconButton 发送）
  - **前置条件**：聊天页已加载
  - **操作步骤**：1. 在 OutlinedTextField 输入文本 2. 点击 FilledIconButton 发送
  - **预期结果**：消息发送成功，输入框清空
  - **失败排查**：检查 `ChatScreen.kt` 中 ChatInputBar 组合；查看 FilledIconButton onClick

- [ ] 错误 Banner 显示
  - **前置条件**：发送消息时网络异常
  - **操作步骤**：1. 关闭网络 2. 发送消息
  - **预期结果**：聊天页顶部显示错误 Banner
  - **失败排查**：检查 `ChatScreen.kt` 中 uiState.error 渲染分支

- [ ] 回车发送（仅 FilledIconButton 触发）
  - **前置条件**：输入框已聚焦
  - **操作步骤**：1. 输入消息 2. 按下软键盘回车键
  - **预期结果**：默认不触发发送（仅 FilledIconButton 触发），需手动点击发送按钮
  - **失败排查**：检查 `ChatScreen.kt` 中 OutlinedTextField 的 keyboardOptions 是否设置 IMEAction.Default；若意外支持回车发送需确认是否新增了 keyboardActions

### 39.5 设置 UI

- [ ] SettingsScreen 加载
  - **前置条件**：从聊天页 TopAppBar 点击设置图标
  - **操作步骤**：1. 进入设置页
  - **预期结果**：显示 4 个配置项（BFF URL / Token / 默认模型 / 主题色）+ 保存按钮
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/settings/SettingsScreen.kt` 中表单组合

- [ ] BFF URL 输入
  - **前置条件**：设置页已加载
  - **操作步骤**：1. 修改 BFF URL 文本框 2. 点击保存
  - **预期结果**：URL 写入 DataStore，重启应用后保留
  - **失败排查**：检查 `BffConfigStore.setBaseUrl` 调用；查看 DataStore Preferences 写入

- [ ] Token 密码可视切换
  - **前置条件**：Token 输入框已填入内容
  - **操作步骤**：1. 点击密码可视切换图标 2. 切换明文/密文显示
  - **预期结果**：Token 默认密文显示，切换后明文可见
  - **失败排查**：检查 `SettingsScreen.kt` 中 `visualTransformation` 切换逻辑

- [ ] 默认模型选择器（deepseek-chat / deepseek-reasoner / qwen-plus / qwen-turbo）
  - **前置条件**：设置页已加载
  - **操作步骤**：1. 点击默认模型下拉 2. 选择 qwen-plus
  - **预期结果**：4 个选项可选，选择后保存到 DataStore
  - **失败排查**：检查 `SettingsScreen.kt` 中模型选择器组件；查看 `BffConfigStore.setDefaultModel` 调用

- [ ] 主题色选择（purple / blue / glow）
  - **前置条件**：设置页已加载
  - **操作步骤**：1. 点击主题色选项中的 blue 2. 保存
  - **预期结果**：主题色切换为 blue，重启后保留
  - **失败排查**：检查 `SettingsScreen.kt` 中主题色选择器；查看 `BffConfigStore.setAccentColor` 调用

- [ ] 保存按钮（DataStore + EncryptedSharedPreferences 持久化）
  - **前置条件**：修改任意配置项
  - **操作步骤**：1. 点击保存按钮 2. 重启应用 3. 重新进入设置页
  - **预期结果**：配置项持久化保留；user_token 经 EncryptedSharedPreferences AES256-GCM 加密存储
  - **失败排查**：检查 `BffConfigStore` 双存储写入逻辑；查看 AndroidKeyStore 是否可用

### 39.6 API 客户端

- [ ] 会话 CRUD（AetherApi）
  - **前置条件**：BFF 服务可达
  - **操作步骤**：1. 调用 listConversations 2. createConversation 3. deleteConversation
  - **预期结果**：3 个操作均成功，X-BFF-Token 鉴权通过
  - **失败排查**：检查 `android/app/src/main/java/com/aether/data/api/AetherApi.kt` 中 Ktor HttpClient 配置

- [ ] 消息 CRUD（含 submitFeedback）
  - **前置条件**：会话已创建
  - **操作步骤**：1. 调用 listMessages 2. send message 3. submitFeedback（like/dislike）
  - **预期结果**：消息列表返回正确，feedback 提交成功
  - **失败排查**：检查 `AetherApi.kt` 中消息端点定义；查看 submitFeedback 请求体

- [ ] 记忆 CRUD
  - **前置条件**：BFF 记忆端点已部署
  - **操作步骤**：1. createMemory 2. listMemory 3. searchMemory 4. deleteMemory
  - **预期结果**：4 个操作均成功
  - **失败排查**：检查 `AetherApi.kt` 中 `/api/memory` 端点序列

- [ ] RAG searchDocuments(query, limit=3)（仅 API 无 UI）
  - **前置条件**：BFF RAG 端点已部署
  - **操作步骤**：1. 在测试代码中调用 `AetherApi.searchDocuments("测试", 3)`
  - **预期结果**：返回最多 3 条相关文档片段
  - **失败排查**：检查 `AetherApi.kt` 中 searchDocuments 函数定义；查看 limit 默认值 3

- [ ] Health uploadHealthSummary / getHealthSummary（仅 API 无 UI）
  - **前置条件**：BFF Health 端点已部署
  - **操作步骤**：1. 调用 uploadHealthSummary(payload) 2. 调用 getHealthSummary()
  - **预期结果**：上传成功，查询能返回刚上传的数据
  - **失败排查**：检查 `AetherApi.kt` 中 Health 端点定义；查看 payload 序列化

- [ ] SSE 流式（ChatStreamClient.streamChat: Flow<String>）
  - **前置条件**：会话已创建
  - **操作步骤**：1. 调用 `ChatStreamClient.streamChat` 收集 Flow
  - **预期结果**：返回 `Flow<String>`，按 SSE chunk 顺序发射
  - **失败排查**：检查 `android/app/src/main/java/com/aether/data/api/ChatStreamClient.kt` 中 Ktor SSE 实现；查看 Flow 收集线程

### 39.7 Rust JNI 集成

- [ ] SseBridge.parseWithTools（返回 content + toolCalls JSON）
  - **前置条件**：libaether_core_ffi.so 已加载
  - **操作步骤**：1. 准备 SSE chunk 字符串 2. 调用 `SseBridge.parseWithTools(chunk)`
  - **预期结果**：返回包含 content 与 toolCalls JSON 的结构
  - **失败排查**：检查 `android/app/src/main/java/com/aether/rust/SseBridge.kt` 中 JNI extern 声明；查看 `rust/ffi/` 中 `aether_sse_parse_with_tools` 导出

- [ ] SseBridge.reset（清空累积器）
  - **前置条件**：已调用 parseWithTools 至少一次
  - **操作步骤**：1. 调用 `SseBridge.reset()` 2. 再次调用 parseWithTools
  - **预期结果**：累积器已清空，下次解析从初始状态开始
  - **失败排查**：检查 `SseBridge.kt` 中 reset 实现；查看 native 侧状态管理

- [ ] VectorMath.cosineF64
  - **前置条件**：.so 已加载
  - **操作步骤**：1. 准备两个等长 DoubleArray 2. 调用 `VectorMath.cosineF64(a, b)`
  - **预期结果**：返回余弦相似度 ∈ [-1, 1]
  - **失败排查**：检查 `android/app/src/main/java/com/aether/rust/VectorMath.kt` 中 JNI 签名

- [ ] VectorMath.cosineF64Safe（JNI 不可用回退 0.0）
  - **前置条件**：模拟 JNI 不可用场景（如移除 .so）
  - **操作步骤**：1. 调用 `VectorMath.cosineF64Safe(a, b)`
  - **预期结果**：捕获 `UnsatisfiedLinkError`，返回 0.0，不崩溃
  - **失败排查**：检查 `VectorMath.kt` 中 try/catch 块；查看回退日志

- [ ] BuildConfig.USE_RUST_SSE=true 默认启用
  - **前置条件**：构建配置已加载
  - **操作步骤**：1. 查看 `android/app/build.gradle` 中 buildConfigField 2. 检查运行时 `BuildConfig.USE_RUST_SSE`
  - **预期结果**：USE_RUST_SSE = true
  - **失败排查**：检查 `build.gradle` 中 buildConfigField 配置；查看 BuildConfig 生成

- [ ] .so 不存在时安全降级（UnsatisfiedLinkError 捕获）
  - **前置条件**：移除 jniLibs 下 .so 文件
  - **操作步骤**：1. 启动应用 2. 发送消息触发 SSE 解析
  - **预期结果**：UnsatisfiedLinkError 被 catch，回退到 Kotlin SSE 解析路径，应用不崩溃
  - **失败排查**：检查 `SseBridge.kt` 中 try/catch；查看 Kotlin 回退解析实现

### 39.8 Room 数据库

- [ ] AetherDatabase v=1 实体（ConversationEntity + MessageEntity 外键 CASCADE）
  - **前置条件**：应用已编译
  - **操作步骤**：1. 查看 `android/app/src/main/java/com/aether/data/local/AetherDatabase.kt` 2. 确认 entities 与 version=1
  - **预期结果**：包含 ConversationEntity 与 MessageEntity，外键定义 + onDelete = CASCADE
  - **失败排查**：检查 `AetherDatabase.kt` 中 `@Database(entities = [...], version = 1)`；查看外键索引

- [ ] ConversationDao（observeAll Flow / getById / upsert / upsertAll / deleteById）
  - **前置条件**：测试已编译
  - **操作步骤**：1. 查看 `ConversationDao.kt` 2. 执行 ConversationRepositoryTest 验证各方法
  - **预期结果**：5 个方法均按预期工作
  - **失败排查**：检查 `ConversationDao.kt` 中 `@Query` / `@Upsert` 注解

- [ ] MessageDao（observeByConversation Flow / upsert / deleteById / deleteByConversation）
  - **前置条件**：测试已编译
  - **操作步骤**：1. 查看 `MessageDao.kt` 2. 执行 ConversationRepositoryTest 中的级联删除用例
  - **预期结果**：4 个方法均按预期工作，级联删除生效
  - **失败排查**：检查 `MessageDao.kt` 中 `@Query` 注解；查看外键 CASCADE 配置

- [ ] 注意：生产路径未使用
  - **前置条件**：N/A
  - **操作步骤**：1. 确认 Repository 走网络而非 Room
  - **预期结果**：Room 已建表但生产 Repository 不读写本地数据库
  - **失败排查**：检查 `android/app/src/main/java/com/aether/data/repository/ConversationRepository.kt` 是否调用 DAO；当前实现仅走网络

### 39.9 BFF 配置存储

- [ ] BffConfigStore 双存储（DataStore Preferences + EncryptedSharedPreferences）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `android/app/src/main/java/com/aether/data/api/BffConfigStore.kt` 2. 调用 setBaseUrl / setUserToken
  - **预期结果**：非敏感配置写入 DataStore；user_token 写入 EncryptedSharedPreferences
  - **失败排查**：检查 `BffConfigStore.kt` 中双存储写入逻辑

- [ ] setBaseUrl / setUserToken / setDefaultModel / setAccentColor
  - **前置条件**：BffConfigStore 已初始化
  - **操作步骤**：1. 依次调用 4 个 setter
  - **预期结果**：4 个配置项均可写入并读取
  - **失败排查**：检查 `BffConfigStore.kt` 中各 setter 实现；查看 Flow 发射

- [ ] EncryptedSharedPreferences AES256-GCM 加密 user_token
  - **前置条件**：AndroidKeyStore 可用
  - **操作步骤**：1. 设置 user_token 2. 通过 `adb shell run-as com.aether.app cat /data/data/com.aether.app/shared_prefs/*.xml` 查看存储
  - **预期结果**：user_token 在 xml 中以密文形式存储
  - **失败排查**：检查 `BffConfigStore.kt` 中 `MasterKey.Builder` + `EncryptedSharedPreferences.create` 调用

- [ ] AndroidKeyStore 不可用时跳过 Encrypted 路径
  - **前置条件**：模拟 AndroidKeyStore 不可用（如某些定制 ROM）
  - **操作步骤**：1. 设置 user_token 2. 查看日志
  - **预期结果**：捕获 KeyStore 异常，回退到普通 SharedPreferences（明文），应用不崩溃
  - **失败排查**：检查 `BffConfigStore.kt` 中 try/catch 块；查看回退日志

### 39.10 设计令牌与主题

- [ ] AetherColors 7 色（与 Apple 端一致）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `android/app/src/main/java/com/aether/ui/theme/AetherColors.kt` 2. 对比 Apple 端 7 色
  - **预期结果**：DeepSpace / AetherPurple / LiquidGlass / Starlight 等 7 色与 Apple 端一致
  - **失败排查**：检查 `AetherColors.kt` 中色值定义；对比 `apple/Aether/Sources/DesignSystem/DesignSystem.swift`

- [ ] AetherTypography（title=28.sp / display=48.sp / body=16.sp）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `AetherTypography.kt`
  - **预期结果**：title=28.sp / display=48.sp / body=16.sp 等字号定义正确
  - **失败排查**：检查 `AetherTypography.kt` 中 TextUnit 定义

- [ ] AetherSpacing（xs=2.dp ~ xxxl=32.dp）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `AetherSpacing.kt`
  - **预期结果**：xs=2.dp / sm=4.dp / md=8.dp / lg=12.dp / xl=16.dp / xxl=24.dp / xxxl=32.dp
  - **失败排查**：检查 `AetherSpacing.kt` 中 Dp 常量

- [ ] AetherCornerRadius（small=12.dp / medium=16.dp / large=24.dp / pill=999.dp）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `AetherCornerRadius.kt` 2. 检查 MessageBubble 圆角
  - **预期结果**：4 档圆角被正确应用
  - **失败排查**：检查 `AetherCornerRadius.kt` 中 Dp 常量；查看 `RoundedCornerShape` 绑定

- [ ] AetherAnimation（transitionMs=250 / messageAppearMs=200 / buttonPressMs=100）
  - **前置条件**：应用已启动
  - **操作步骤**：1. 查看 `AetherAnimation.kt` 2. 触发消息出现动画
  - **预期结果**：动画时长符合定义
  - **失败排查**：检查 `AetherAnimation.kt` 中 Int 常量；查看 `tween<Int>` 使用

- [ ] AetherTheme 强制深色模式（darkColorScheme，无浅色变体）
  - **前置条件**：系统切换为浅色模式
  - **操作步骤**：1. 启动应用 2. 观察界面颜色
  - **预期结果**：应用保持深色模式，不随系统切换
  - **失败排查**：检查 `AetherTheme.kt` 中 `darkColorScheme()` 强制使用；确认无 `isSystemInDarkTheme()` 判断

### 39.11 单元测试

- [ ] VectorMathTest.kt（3 用例，JNI 不可用回退）
  - **前置条件**：测试已编译
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest --tests "*.VectorMathTest"`
  - **预期结果**：3 个用例通过，覆盖 cosineF64Safe 回退路径
  - **失败排查**：检查 `android/app/src/test/java/com/aether/rust/VectorMathTest.kt`

- [ ] SseBridgeTest.kt（5 用例，Kotlin 回退路径）
  - **前置条件**：测试已编译
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest --tests "*.SseBridgeTest"`
  - **预期结果**：5 个用例通过，覆盖 Kotlin SSE 解析回退路径
  - **失败排查**：检查 `android/app/src/test/java/com/aether/rust/SseBridgeTest.kt`；注意 JNI 在纯 JVM 测试中不可用

- [ ] ModelsTest.kt（7 用例，序列化与默认值）
  - **前置条件**：测试已编译
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest --tests "*.ModelsTest"`
  - **预期结果**：7 个用例通过
  - **失败排查**：检查 `android/app/src/test/java/com/aether/data/model/ModelsTest.kt`

- [ ] BffConfigTest.kt（7 用例，Robolectric，DataStore 读写）
  - **前置条件**：测试已编译，Robolectric 已配置
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest --tests "*.BffConfigTest"`
  - **预期结果**：7 个用例通过
  - **失败排查**：检查 `android/app/src/test/java/com/aether/data/api/BffConfigTest.kt`；查看 `@RunWith(RobolectricTestRunner::class)`

- [ ] ConversationRepositoryTest.kt（8 用例，Room in-memory，DAO CRUD + 排序 + 级联删除）
  - **前置条件**：测试已编译
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest --tests "*.ConversationRepositoryTest"`
  - **预期结果**：8 个用例通过，覆盖 DAO CRUD、排序、级联删除
  - **失败排查**：检查 `android/app/src/test/java/com/aether/data/repository/ConversationRepositoryTest.kt`；查看 Room in-memory database 构建

- [ ] 单元测试命令验证
  - **前置条件**：测试已编译
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest`
  - **预期结果**：所有测试通过
  - **失败排查**：查看 `./scripts/build-android.sh test-android` 是否等价；检查测试覆盖率说明（仅回退路径，未测试 native 路径）

### 39.12 AndroidManifest 权限

- [ ] INTERNET 权限（必需）
  - **前置条件**：APK 已构建
  - **操作步骤**：1. 查看 `android/app/src/main/AndroidManifest.xml` 2. 确认 `<uses-permission android:name="android.permission.INTERNET" />`
  - **预期结果**：INTERNET 权限已声明
  - **失败排查**：检查 `AndroidManifest.xml`；网络请求失败时确认权限已授予

- [ ] RECORD_AUDIO 权限（声明但未实现使用）
  - **前置条件**：APK 已构建
  - **操作步骤**：1. 查看 `AndroidManifest.xml` 中 RECORD_AUDIO 声明 2. 全局搜索 `AudioRecord` / `MediaRecorder` 使用
  - **预期结果**：权限已声明但代码中无语音录制功能实现
  - **失败排查**：声明属预期行为；若发现实际调用语音 API 需回归测试

### 39.13 已知限制与未开放功能

- [ ] 限制清单确认
  - **前置条件**：N/A
  - **操作步骤**：1. 逐项确认以下功能未在 Android 端实现
  - **预期结果**：以下功能均未开放（属预期行为，非 Bug）
  - **失败排查**：若某项意外出现，需回归对应实现
  - ❌ 工具调用（BFF 端执行，客户端无 UI）
  - ❌ 多模态（NativeVision / ASR / TTS）
  - ❌ Health Connect 集成（HealthScreen UI 已实现，但未对接 Android Health Connect 平台 API）
  - ❌ 端侧 MLX 推理（Rust FFI `#[cfg]` 排除 Android）
  - ❌ 离线模式（依赖 BFF 在线服务，Room 仅缓存会话列表）
  - ❌ watchOS / Widget
  - ❌ UI 自动化测试（无 Espresso / Compose UI Test）
  - ❌ RECORD_AUDIO 实际使用（声明但无实现）

### 39.14 RAG 知识库 UI（新增 v1.5）

- [ ] KnowledgeBaseScreen 加载
  - **前置条件**：BFF 服务可达，知识库已上传至少 1 个文档
  - **操作步骤**：1. 启动应用 2. 导航到 KnowledgeBaseScreen
  - **预期结果**：页面显示搜索框 + 搜索按钮，初始为空状态提示「输入关键词搜索」
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/kb/KnowledgeBaseScreen.kt`；查看 KnowledgeBaseViewModel 初始化

- [ ] 搜索框输入 + 搜索按钮
  - **前置条件**：进入 KnowledgeBaseScreen
  - **操作步骤**：1. 在搜索框输入「Aether」 2. 点击搜索按钮
  - **预期结果**：调用 BFF `searchDocuments` 端点，请求中带 query 参数
  - **失败排查**：检查 ViewModel.search() 调用；查看 AetherApiClient.searchDocuments 实现

- [ ] 搜索结果 LazyColumn（DocumentChunk Card）
  - **前置条件**：搜索返回至少 1 条结果
  - **操作步骤**：1. 等待搜索完成 2. 观察 LazyColumn
  - **预期结果**：每条 DocumentChunk 显示为 Card，含文档标题 / 片段内容 / 相似度分数
  - **失败排查**：检查 LazyColumn items 绑定；查看 DocumentChunk 数据类

- [ ] 空状态 / 加载状态 / 错误状态
  - **前置条件**：分别测试 3 种状态
  - **操作步骤**：1. 输入不存在的关键词 → 空状态 2. 搜索过程中 → 加载 CircularProgressIndicator 3. 关闭 BFF → 错误状态
  - **预期结果**：3 种状态正确显示，错误状态可重试
  - **失败排查**：检查 UiState sealed class；查看 when 表达式分支

### 39.15 Health UI（新增 v1.5）

- [ ] HealthScreen 加载
  - **前置条件**：BFF 服务可达，已上传至少 1 天的健康数据
  - **操作步骤**：1. 启动应用 2. 导航到 HealthScreen
  - **预期结果**：页面显示日期选择器 + 健康数据卡片
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/health/HealthScreen.kt`；查看 HealthViewModel 初始化

- [ ] 日期选择
  - **前置条件**：进入 HealthScreen
  - **操作步骤**：1. 点击日期选择器 2. 选择不同日期
  - **预期结果**：DatePickerDialog 弹出，选择后调用 `getHealthSummary` 加载该日数据
  - **失败排查**：检查 DatePickerDialog 显示；查看 onDateSelected 回调

- [ ] 健康数据卡片（步数 / 睡眠 / 心率）
  - **前置条件**：所选日期有健康数据
  - **操作步骤**：1. 选择有数据的日期 2. 观察数据卡片
  - **预期结果**：显示步数 Card（如「8,432 步」）/ 睡眠 Card（如「7h 23m」）/ 心率 Card（如「72 bpm」）
  - **失败排查**：检查 HealthSummary 数据类；查看 Card Composable 绑定

- [ ] 上传今日健康数据按钮
  - **前置条件**：进入 HealthScreen
  - **操作步骤**：1. 点击「上传今日健康数据」按钮
  - **预期结果**：调用 BFF `uploadHealthSummary` 端点，上传成功后显示 Snackbar 提示
  - **失败排查**：检查 uploadHealthSummary 调用；查看 SnackbarHost 状态

- [ ] 加载 / 错误状态
  - **前置条件**：分别测试 2 种状态
  - **操作步骤**：1. 数据加载中 → CircularProgressIndicator 2. 关闭 BFF → 错误状态
  - **预期结果**：加载中显示进度，错误状态显示错误信息 + 重试按钮
  - **失败排查**：检查 UiState 状态切换；查看 ViewModel 异常处理

### 39.16 Rust Redact JNI（新增 v1.5）

- [ ] Redact.redactSafe 调用
  - **前置条件**：App 已安装到设备 / 模拟器（含 `libaether_core_ffi.so`）
  - **操作步骤**：1. 在 ChatScreen 发送含敏感信息的消息（如「我的手机号 13800138000」） 2. 观察发送前的脱敏日志
  - **预期结果**：`Redact.redactSafe` 通过 JNI 调用 `aether_redact`，返回脱敏后文本（如「我的手机号 [PHONE]」）
  - **失败排查**：检查 `android/app/src/main/java/com/aether/rust/Redact.kt` 中 external fun 声明；查看 `rust/ffi/src/jni.rs` 中 `Java_com_aether_rust_Redact_redactSafe` 实现

- [ ] JNI 不可用时返回原文
  - **前置条件**：在纯 JVM 单元测试中（无 `.so`）
  - **操作步骤**：1. 执行 `./gradlew testDebugUnitTest` 2. 查看 RedactTest 测试结果
  - **预期结果**：JNI 不可用时 `redactSafe` 回退返回原文，不抛异常
  - **失败排查**：检查 `Redact.kt` 中 try/catch UnsatisfiedLinkError；查看回退路径测试覆盖

### 39.17 消息长按菜单（新增 v1.5）

- [ ] 长按消息弹出 DropdownMenu
  - **前置条件**：进入 ChatScreen 并存在至少 1 条消息
  - **操作步骤**：1. 长按任一消息气泡
  - **预期结果**：弹出 DropdownMenu 含「复制」「重发」（仅用户消息）/「删除」3 项
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/chat/ChatScreen.kt` 中 combinedClickable onLongClick；查看 DropdownMenu expanded 状态

- [ ] 复制（ClipboardManager）
  - **前置条件**：长按菜单已弹出
  - **操作步骤**：1. 点击「复制」
  - **预期结果**：消息文本写入 ClipboardManager，显示「已复制」Snackbar 提示
  - **失败排查**：检查 ClipboardManager.setPrimaryClip 调用；查看 ClipDescription MIMETYPE_TEXT_PLAIN

- [ ] 重发（仅用户消息）
  - **前置条件**：长按用户消息
  - **操作步骤**：1. 长按用户消息 2. 点击「重发」
  - **预期结果**：重新调用 BFF 发送该消息，AI 重新生成回复；AI 消息不显示「重发」选项
  - **失败排查**：检查 isUser 判断逻辑；查看 ViewModel.resend() 调用

- [ ] 删除
  - **前置条件**：长按任一消息
  - **操作步骤**：1. 长按消息 2. 点击「删除」
  - **预期结果**：消息从列表移除（如启用 Room 则同步删除本地记录）
  - **失败排查**：检查 ViewModel.deleteMessage() 调用；查看 List 更新

### 39.18 Markdown 渲染（新增 v1.5）

- [ ] AI 消息 MarkdownText 渲染
  - **前置条件**：与 AI 进行一轮对话
  - **操作步骤**：1. 发送消息 2. 观察 AI 消息渲染
  - **预期结果**：AI 消息以 MarkdownText Composable 渲染，纯 Text 已替换
  - **失败排查**：检查 `android/app/src/main/java/com/aether/app/ui/chat/MarkdownText.kt`；查看 Markwon markwon 实例创建

- [ ] 标题 / 代码块 / 表格 / 任务列表 / 链接
  - **前置条件**：AI 回复包含多种 Markdown 元素
  - **操作步骤**：1. 发送「请用标题、代码块、表格、任务列表、链接各举一例」
  - **预期结果**：
    - 标题 H1-H6 字号递减、加粗
    - 代码块等宽字体 + 深色背景 + 语法高亮
    - 表格以 Table 排列，列对齐
    - 任务列表前显示 CheckBox
    - 链接可点击跳转浏览器
  - **失败排查**：检查 Markwon 插件注册（core + tables + tasklist + strikethrough + linkify + syntax-highlight）；查看 Plugin 配置

### 39.19 i18n 国际化（新增 v1.5）

- [ ] 默认语言 zh-Hans
  - **前置条件**：首次启动应用
  - **操作步骤**：1. 启动应用 2. 观察所有 UI 文本
  - **预期结果**：默认显示简体中文（如「新会话」「设置」「发送」）
  - **失败排查**：检查 `android/app/src/main/res/values/strings.xml` 默认资源；查看 Locale 默认值

- [ ] 切换到 English / 日本語 / 繁體中文
  - **前置条件**：进入设置页
  - **操作步骤**：1. 选择不同语言（en / ja / zh-rTW）
  - **预期结果**：每种语言切换后界面文本立即更新为对应语言
  - **失败排查**：检查 `values-en/strings.xml` / `values-ja/strings.xml` / `values-zh-rTW/strings.xml` 是否存在；查看 Locale 持久化

- [ ] 切换后 recreate Activity
  - **前置条件**：选择新语言
  - **操作步骤**：1. 选择语言 2. 观察 Activity 重建
  - **预期结果**：调用 `activity.recreate()` 重建 Activity，所有 Composable 重新读取 stringResource
  - **失败排查**：检查 LanguageService.recreate 调用；查看 Activity 生命周期

- [ ] stringResource 所有 UI 文本
  - **前置条件**：切换到不同语言
  - **操作步骤**：1. 检查会话列表 / 聊天 / 设置 / RAG / Health 各页面文本
  - **预期结果**：所有 UI 文本通过 `stringResource(R.string.xxx)` 读取，无硬编码字符串
  - **失败排查**：检查 Composable 中是否仍有 hardcoded 字面量；使用 `./gradlew lint` 检查 HardcodedText 警告

### 39.20 Room 生产使用（新增 v1.5）

- [ ] 离线打开 App 显示本地缓存会话
  - **前置条件**：联网时已加载过会话列表
  - **操作步骤**：1. 关闭网络 2. 启动 App
  - **预期结果**：会话列表从 Room 数据库加载，显示本地缓存的会话
  - **失败排查**：检查 `ConversationRepository.getAllConversations()` 先 Room 后网络逻辑；查看 ConversationDao.getAll() 调用

- [ ] 网络恢复后自动同步
  - **前置条件**：离线状态下查看过会话列表
  - **操作步骤**：1. 恢复网络 2. 下拉刷新会话列表
  - **预期结果**：调用 BFF 拉取最新会话，更新 Room 数据库，UI 自动刷新
  - **失败排查**：检查 Repository 中网络请求成功后写入 Room 的逻辑；查看 Flow 合并策略

- [ ] 创建会话先写 Room 再调 API
  - **前置条件**：联网状态
  - **操作步骤**：1. 创建新会话 2. 观察日志
  - **预期结果**：先 `ConversationDao.insert(conversation)` 写入本地，再调 BFF `createConversation`，UI 立即显示新会话
  - **失败排查**：检查 `ConversationRepository.createConversation()` 顺序；查看 Room 事务

- [ ] 删除会话先删 Room 再调 API
  - **前置条件**：联网状态，已有会话
  - **操作步骤**：1. 删除任一会话 2. 观察日志
  - **预期结果**：先 `ConversationDao.delete(id)` 删除本地，再调 BFF `deleteConversation`，UI 立即移除
  - **失败排查**：检查 `ConversationRepository.deleteConversation()` 顺序；查看网络失败时 Room 数据回滚策略

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
| v1.2 设计升级（35） | iOS / iPad / macOS 真机或模拟器 | AnimationTokens / AetherIcons / Starfield 呼吸 / 响应式布局，三端均需验证 |
| 端侧多模态 v1.3 Phase 1（36） | iOS / macOS 真机或模拟器 | 占位实现无需外部模型；OCR 需准备含文字图片 |
| NativeVisionEngine 5 并发请求（37.1） | iOS / macOS 真机或模拟器 | 需准备含文字 / 人脸 / 二维码的 PNG 图片，建议 256×256 以上 |
| NativeASREngine 语音识别（37.2） | iOS / macOS 真机（推荐）| 需授权语音识别权限；准备 wav/caf/m4a/mp3/aac 音频；CI 环境识别器不可用 |
| NativeTTSEngine 语音合成（37.3） | iOS / macOS 真机（推荐）| CI 环境返回最小空 WAV 头，真机正常合成 |
| NativeEnginesTests 单测（37.5） | iOS 模拟器（iPhone 17） | 24 用例 0 failures，CI 环境跳过的用例不算 |
| Windows 端构建（38.1） | Windows 10+ 真机或虚拟机 | .NET 8 SDK + PowerShell 7+，支持 win-x64 / win-arm64 |
| Windows 端基础对话（38.2） | Windows 10+ 真机或虚拟机 | 需部署 BFF 并配置 X-BFF-Token；v1.5 起 baseUrl 已迁移至 BffConfigStore（DPAPI 加密）|
| Windows 端 Rust P/Invoke（38.4） | Windows 10+ 真机或虚拟机 | 需 Native/aether_core_ffi.dll（CI 构建），DLL 不存在时验证安全降级 |
| Windows 端单测（38.6） | Windows 10+ 真机或虚拟机 | `dotnet test` xUnit 7 文件 72 用例，无需 BFF |
| Android 端构建（39.1） | Android 真机（API 29+）或模拟器 | JDK 17 + Android SDK 35 + Gradle 8.7（wrapper 已提交） |
| Android 端会话列表 UI（39.3） | Android 真机或模拟器 | 需部署 BFF 并配置 X-BFF-Token |
| Android 端聊天 UI（39.4） | Android 真机或模拟器 | 需部署 BFF；验证流式光标 `▌` 与 TypingIndicator |
| Android 端设置 UI（39.5） | Android 真机或模拟器 | 验证 BFF URL / Token 加密存储 / 模型选择 / 主题色 |
| Android 端 Rust JNI（39.7） | Android 真机或模拟器 | 需 jniLibs/{arm64-v8a,x86_64}/libaether_core_ffi.so（CI 构建） |
| Android 端 Room 数据库（39.8） | Android 真机或模拟器 | v1.5 起已生产使用，Repository 先 Room 后网络（详见 39.20） |
| Android 端单测（39.11） | 任意系统（JVM） | `./gradlew testDebugUnitTest`，12 文件 95 用例，JNI 在纯 JVM 不可用测试覆盖回退路径 |
| Windows 端 v1.5 新功能（38.8-38.12） | Windows 10+ 真机或虚拟机 | 会话列表 / 设置页 / Markdown / i18n / 消息气泡；i18n 切换无需重启，DPAPI 加密需 Windows 用户态 |
| Android 端 v1.5 新功能（39.14-39.20） | Android 真机或模拟器 | RAG / Health / Rust Redact / 消息长按 / Markdown / i18n / Room 生产；JNI 需真机或模拟器 |

## 手测执行优先级

**P0（核心路径，必须验证）**：1, 2, 3, 9, 10, 11, 16, 21（多平台适配，发布前必须验证三端启动与基础功能），23（macOS 设置导航修复，核心交互修复），27（国际化与无障碍，发布前必须验证 String Catalog 注册与 VoiceOver 基础朗读），35（v1.2 设计升级，三端视觉一致性，发布前必验证 Starfield 呼吸 / AetherIcons 渲染 / 响应式布局），37（v1.4 Native 引擎，端侧多模态真实功能，发布前必验证 describe_image / transcribe_audio 真实调用与权限授权），38.1（Windows 端构建与启动，发布前必验证 Windows 客户端可构建启动），39.1（Android 端构建与启动，发布前必验证 APK 可构建安装）
**P1（重要功能，应验证）**：4, 5, 6, 7, 8, 12, 14, 15, 17, 18, 19, 20, 22（工具能力增强，重要新增功能，建议每次发布前验证），24（macOS markdown 视觉修复），25（macOS 语音朗读 UI 修复），26（预设系统提示词），36（v1.3 端侧多模态 Phase 1，Facade 门面 + 占位工具 + 跨平台 OCR + MemoryBudget，作为 v1.4 Native 引擎的对照基线），38.2-38.6（Windows 端基础对话 + Rust P/Invoke + 设计令牌 + 单测，thin client 核心路径），38.8-38.12（Windows v1.5 新功能：会话列表 UI / 设置页 / Markdown / i18n / 消息气泡 + TypingIndicator），39.2-39.11（Android 端 3 屏 UI + Rust JNI + Room + BFF 配置 + 设计令牌 + 单测，thin client 完整功能路径），39.14-39.20（Android v1.5 新功能：RAG / Health / Rust Redact / 消息长按 / Markdown / i18n / Room 生产）
**P2（增强功能，可选验证）**：13（需 watchOS 硬件），14.3（需 iPhone + iPad），38.7（Windows 已知限制盘点，9 项 ❌），39.12-39.13（Android 权限与已知限制盘点，8 项 ❌）

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
| v1.2 设计升级（35） | P0 | AnimationTokens / AetherIcons / Starfield 呼吸 / 响应式布局 / SF Symbols 替换，三端视觉一致性，发布前必验证 |
| v1.3 端侧多模态 Phase 1（36） | P1 | MultimodalFacade 门面 + 4 个占位工具 + 跨平台 OCR + MemoryBudget，作为 v1.4 Native 引擎对照基线 |
| v1.4 Native 引擎（37） | P0 | NativeVisionEngine / NativeASREngine / NativeTTSEngine 真实功能 + 24 单测，发布前必验证 |
| Windows 端构建与启动（38.1） | P0 | WPF .NET 8 客户端可构建启动，发布前必验证（thin client 依赖 BFF） |
| Windows 端核心功能（38.2-38.6） | P1 | 基础对话 + Rust P/Invoke + 设计令牌 + 单测，thin client 核心路径 |
| Windows 端 v1.5 新功能（38.8-38.12） | P1 | 会话列表 UI + 设置页（DPAPI 加密）+ Markdown（Markdig 0.37.0）+ i18n（8 种语言 .resx）+ 消息气泡 + TypingIndicator |
| Windows 端已知限制盘点（38.7） | P2 | 9 项 ❌ 未开放功能盘点（RAG / 工具 / 多模态 / HealthKit / 端侧 MLX 推理 / 离线模式 / 本地数据库 / MSIX 打包 / watchOS-Widget） |
| Android 端构建与启动（39.1） | P0 | Kotlin + Compose APK 可构建安装，发布前必验证（thin client 依赖 BFF） |
| Android 端核心功能（39.2-39.11） | P1 | 3 屏 UI（会话列表 / 聊天 / 设置）+ Rust JNI + Room + BFF 配置 + 设计令牌 + 单测，thin client 完整功能路径 |
| Android 端 v1.5 新功能（39.14-39.20） | P1 | RAG UI + Health UI + Rust Redact JNI + 消息长按菜单 + Markdown（Markwon 4.6.2）+ i18n（8 种语言 strings.xml）+ Room 生产使用 |
| Android 端已知限制盘点（39.12-39.13） | P2 | 8 项 ❌ 未开放功能盘点（工具 / 多模态 / Health Connect / 端侧 MLX 推理 / 离线模式 / watchOS-Widget / UI 自动化测试 / RECORD_AUDIO） |
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
- **平台**：iOS / iPad / macOS / watchOS / Windows / Android
- **模块**：对应本文档章节号（如 1、21.1、22.2）
- **测试项**：测试项名称
- **结果**：PASS / FAIL / BLOCK
- **备注**：失败原因、阻塞说明或回归记录
