# Aether 实战计划

文档说明

· 适用对象：中国大陆 iOS / AI 应用开发者
· 目标：在合规前提下，构建具备流式对话、RAG、Agent、多模态、端侧推理等能力的 AI 原生 App
· 前置条件：已掌握 SwiftUI、Combine、SwiftData 等 iOS 开发基础

一、背景与战略原则

截至 2026 年 7 月，部分海外 AI 服务在国内不可直接使用，需进行技术选型调整。核心战略原则：

1. 合规优先：所有云端服务及数据存储均需符合国内法律法规要求
2. 端侧增强：利用设备端算力降低对云端服务的依赖，既符合隐私合规要求，也能在弱网环境下保持可用
3. 生态适配：充分利用国内成熟的云服务生态和 AI 平台

当前国内 AI 生态已趋成熟——DeepSeek、通义千问等国产模型能力对齐海外主流水平，阿里云/腾讯云提供稳定的 BaaS 基础设施。将技术栈国内化，不代表妥协，而是更务实的选择。

二、能力替代方案总览

原方案 国内替代方案 调整说明
OpenAI / Claude API DeepSeek API、阿里云百炼 协议高度兼容，修改 base_url + model 名即可
Google Cloud / Firebase 阿里云、腾讯云、LeanCloud 全套 BaaS 服务替代
Apple Intelligence / PCC 国内大模型 API + 端侧 MLX 模型 云端逻辑改用国产模型，端侧保持不变
Siri AI 新功能 SiriKit + Shortcuts + 本地语音识别 保留基础系统集成，等待官方更新
Vision Pro 空间 AI 国产大模型 API + ARKit 原生能力 视觉理解改用国内 API
Cloudflare Workers Workers + 绑定自定义域名 技术方案不变，仅需域名配置
灵动岛（Live Activities） 保留，完全可用 系统级能力不受影响

三、分阶段实施路线图

准备阶段：环境与账号配置（第 0 周）

· 注册阿里云/腾讯云账号，开通大模型服务
· 获取 DeepSeek API Key，熟悉国内模型 API 文档
· 准备自有域名，用于 Cloudflare Workers 代理
· 配置 Xcode 开发环境，确保 iOS 17+ SDK 就绪

第一阶段：核心对话与 RAG（第 1-3 天）

Day 1：API 接入与流式对话

· 调用 DeepSeek API 实现基础对话
· 完成流式响应的解析（SSE 协议）
· 实现 Combine 驱动的打字机效果

```swift
// 关键改动：仅需替换 base_url 和 model 名
URL(string: "https://api.deepseek.com/chat/completions")
"model": "deepseek-v4-flash"
```

Day 2：多轮对话与上下文记忆

· SwiftData 持久化聊天记录
· 支持 system prompt 设定
· 会话管理（新建/切换/删除）

Day 3：RAG 本地知识库

· 本地文档导入与分块
· 调用 DeepSeek Embedding API 向量化
· 余弦相似度检索 + 上下文注入

第二阶段：多模态与系统能力（第 4-6 天）

Day 4：工具调用

· 定义 Function Calling Schema
· 实现闹钟、提醒等 iOS 系统功能调用
· ReAct 循环初步

Day 5：视觉与语音

· PhotosPicker 选图，DeepSeek Vision API 识别
· SFSpeechRecognizer 语音输入
· AVSpeechSynthesizer 语音朗读

Day 6：工程优化

· 语义缓存（基于向量相似度）
· Token 估算与滑动窗口压缩
· Actor 并发隔离

第三阶段：生产级架构（第 7-10 天）

Day 7：产品化打磨

· 设置面板（人设/开关集中管理）
· 错误处理与骨架屏
· README 与作品集准备

Day 8：Multi-Agent 自主规划

· ReAct 循环增强
· 多工具串联执行
· 步骤卡片 UI 可视化

Day 9：长期记忆与可插拔工具

· 用户偏好记忆存储
· ToolProtocol 插件体系
· 调试面板

Day 10：质量保障与分发

· XCTest 单元测试
· TestFlight 内测分发
· 对话导出为 Markdown

第四阶段：国内云服务集成（第 11-14 天）

Day 11：主动智能

· Live Activities 灵动岛（完全可用）
· BGTaskScheduler 后台触发
· 本地通知主动提醒

Day 12：智能路由与反馈闭环

· 根据复杂度动态选择模型
· 用户点赞/踩反馈调整 RAG 权重
· Swift 6 并发适配

Day 13：国产大模型深度适配

· 接入通义千问/Qwen 系列
· 多模型统一抽象层
· 模型对比与自动降级

Day 14：远程配置与遥测

· 远程热更新（System Prompt/模型切换）
· 性能埋点与统计看板
· 国内云存储日志上报

第五阶段：系统级融合（第 15-18 天）

Day 15：BFF 代理层

· Cloudflare Workers + 自定义域名部署国内可访问
· API Key 服务端保护
· 设备级限流

Day 16：端侧模型落地

· MLX Swift + GGUF 量化模型
· 断网环境下本地推理
· Shortcuts 深度集成

Day 17：watchOS 扩展（可选）

· HealthKit 健康数据接入
· 端侧推理 + 跨设备接力
· 主动健康提醒

Day 18：App Intents 国内可用能力

· Shortcuts 动作暴露
· NSUserActivity Handoff
· Spotlight 搜索集成
· SiriKit 基础功能

四、已剔除/暂缓的能力清单

以下能力因国内政策或基础设施限制，建议暂缓或跳过：

能力 原因 状态
Apple Intelligence / PCC 国内未上线，等待官方进展 暂缓
Siri AI 新功能 (App Intents 进阶) 依赖 Apple Intelligence 暂缓
Vision Pro 空间 AI 能力 依赖云端 AI 功能未上线 暂缓
Firebase Realtime Database GCP 国内不可用 替换为国内云
OpenAI / Claude 直连 官方限制 + 网络不可达 替换为国产模型

注：上述能力在官方上线或政策明朗后，可无缝迁移——因为核心架构已通过协议抽象层隔离了具体实现。

五、国内技术栈推荐清单

类别 推荐方案 说明
大模型 API DeepSeek、阿里云百炼（通义千问）、腾讯云混元 兼容 OpenAI 协议
Embedding DeepSeek Embedding、通义千问 Embedding RAG 向量化
BaaS 后端 阿里云、腾讯云、LeanCloud 用户认证、数据存储
Serverless Cloudflare Workers + 自定义域名 代理层、限流
推送服务 极光推送、个推、阿里云推送 本地通知替代方案
日志分析 阿里云日志服务、腾讯云 CLS 遥测数据上报
崩溃监控 Bugly（腾讯）、友盟+ 线上稳定性监控
支付 StoreKit 2（苹果官方，完全可用） 订阅付费

六、里程碑与预计工期

阶段 核心交付物 预计工期
准备阶段 云账号配置、API Key 就绪 2-3 天
第一至三阶段 完整 AI 对话 + RAG + Agent 10 天
第四至五阶段 生产级架构 + 系统融合 8 天
总计 可上架的 AI Native App 约 18-20 天

七、风险与应对策略

风险 应对措施
国内大模型 API 能力差异 提前做模型对比测试，核心逻辑通过协议抽象层隔离具体模型实现，保持切换灵活性
用户隐私合规（《个人信息保护法》） 敏感数据端侧处理（MLX 本地推理），不上传云端；如需上传，使用国内合规云服务并完成数据分类分级
审核政策变化 设置页增加“投诉反馈”入口，AI 回复底部标注“内容由 AI 生成”
端侧模型在旧设备上运行缓慢 根据 os_proc_available_memory() 动态判断，内存不足时自动切换云端 API

八、文档版本

版本 日期 修改内容
v1.0 2026-07-05 初始版本，基于 Day 1-20 实战内容整理
