# AIBuilder 路线图

> 本文档描述 AIBuilder 在 Day 20 之后的演进方向与里程碑。优先级：P0（必须） / P1（重要） / P2（增强）。

---

## 当前基线（Day 1-20）

- iOS / iPad / macOS 三端原生 SwiftUI 渲染
- 13 / 24 个工具（iOS / macOS）
- 385 keys 完整 i18n（en / zh-Hans / zh-Hant）
- 248 UT + 13 UIT，0 failures / 0 skips
- 多 Provider（DeepSeek / Qwen / MLX）+ SmartRouter + Fallback

---

## Phase F：工程质量与上架准备（P0）

- [ ] App Store 元数据与截图最终确认
- [ ] PrivacyInfo.xcprivacy 与隐私问卷对齐
- [ ] 真机测试（iPhone / iPad / Mac）
- [ ] TestFlight 内测与崩溃监控验证
- [ ] CI 构建时长优化与缓存策略

## Phase G：智能体能力增强（P1）

- [ ] MCP（Model Context Protocol）客户端接入
- [ ] 长期记忆向量库（跨会话 remember / recall）
- [ ] Agent 任务规划（多步目标分解与执行）
- [ ] 插件化工具市场（外部工具动态注册）

## Phase H：体验与设计升级（P1）

- [ ] 全新 Design System（颜色 / 字体 / 间距 Token）
- [ ] 深色模式全面适配
- [ ] 动画与过渡效果统一
- [ ] macOS 多窗口与拖拽支持

## Phase I：云端与协作（P2）

- [ ] 对话历史 iCloud 同步
- [ ] 跨设备连续对话（Handoff）
- [ ] 团队知识库共享
- [ ] Web / Android 伴侣应用

---

## 里程碑时间表（建议）

| 里程碑 | 目标 | 关键交付 |
|--------|------|----------|
| v1.0 | App Store 首发 | 工程化完善、审核通过、首版上架 |
| v1.1 | 智能体增强 | MCP、长期记忆、Agent 规划 |
| v1.2 | 设计升级 | Design System、深色模式、动画 |
| v2.0 | 跨端协作 | iCloud 同步、Web 伴侣、团队协作 |
