# Aether 设计更新计划

> 描述 Aether UI/UX 的下一阶段演进目标、设计原则与具体改动清单。

---

## 设计原则

1. **原生优先**：继续遵循 iOS / iPad / macOS Human Interface Guidelines，不引入跨平台 UI 框架。
2. **信息密度可调**：macOS 与 iPad 利用大屏展示更多上下文；iPhone 保持单任务聚焦。
3. **无障碍一贯**：所有新增控件必须同时提供 `accessibilityLabel` 与 `accessibilityHint`。
4. **动效服务交互**：过渡动画用于阐明层级关系，避免炫技式动效。

---

## 1. Design System Token 化（已落地）

> 已完成：颜色 / 字体 / 间距 / 圆角 / 动画 token 已统一收敛到 `Aether/DesignSystem/` 目录，所有视图直接引用语义 token，不硬编码原生颜色。

- `ColorTokens.swift`：定义 Aether 品牌色（`deepSpace` / `aetherPurple` / `electricBlue` / `liquidGlass` / `nebulaGlow` / `starlight` / `duskGray`）与 `aetherGradient` 渐变，气泡色 `bubbleUser` / `bubbleAI`，背景 `backgroundPrimary` / `backgroundSecondary` / `backgroundTertiary`，文字 `textPrimary` / `textSecondary` / `textTertiary`。
- `TypographyTokens.swift`：定义 Aether 品牌字体（`aetherTitle` 28pt / `aetherDisplay` 48pt / `aetherBody` 16pt）与对话字体（`bodyAI` / `subheadlineAI` / `captionAI` / `headlineAI` / `titleAI` / `monoAI` / `toolLabel`）。
- `DesignTokens.swift`：定义间距 `Spacing`（xs 2 / sm 4 / md 8 / lg 12 / xl 16 / xxl 24 / xxxl 32）、圆角 `CornerRadius`（small 12 / medium 16 / large 24 / pill 999）、动画 `AnimationTokens`（transition / messageAppear / buttonPress / skeleton / blink）。

## 2. 深色模式全面适配

- 为所有自定义视图添加 `.preferredColorScheme` 测试覆盖。
- Markdown 代码块、MessageBubble、Settings Form 在深色模式下对比度 ≥ 4.5:1。
- 截图补充深色模式版本。

## 3. 会话与消息列表视觉升级

- 引入头像/角色标识区分用户与 AI。
- 消息气泡支持引用块、折叠长文本、「继续生成」按钮。
- ConversationRow 增加最后一条消息预览与未读标识。

## 4. macOS 多窗口与侧边栏

- 支持同时打开多个对话窗口（NSWindowController 包装 ChatView）。
- Sidebar 增加拖拽排序会话组。
- 工具栏增加 segmented 切换「聊天 / 知识库 / 健康」。

## 5. 空状态与反馈组件

- 统一 `EmptyStateView`：插画 + 标题 + 说明 + 主操作按钮。
- 统一 `LoadingStateView`：骨架屏 + 进度文本。
- 统一 `ToastView`：操作成功/复制/撤销反馈。

## 6. 动画规范

- 页面转场：0.25s ease-in-out。
- 消息进入：从底部淡入 + 轻微上浮，0.2s。
- 按钮按下：0.95 scale，0.1s。
- 列表插入/删除：SwiftUI 默认 `.transition`。

## 7. 截图与预览素材

- 按 App Store 尺寸要求补充：
  - iPhone 6.7" / 6.1" / 5.5"
  - iPad 12.9" / 11"
  - Mac 1280×800 / 1440×900 / 2560×1600
- 生成 App 预览视频（30 秒展示流式对话 + 工具调用）。
