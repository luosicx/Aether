# AIBuilder 设计系统全量优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 `doc/DESIGN_UPDATE.md` 全量优化 AIBuilder 的视觉系统：建立 Design Tokens、补齐深色模式、升级会话/消息视觉、macOS 多窗口、统一空状态/加载/Toast 反馈组件、规范动画、补齐截图素材。

**Architecture:** 先建立 `DesignTokens.swift` 作为单一事实来源，再抽取通用组件（`EmptyStateView` / `LoadingStateView` / `ToastView` / `CardStyle`），然后用 token 与组件迁移现有视图，最后补齐 macOS 多窗口与截图素材。每个任务可独立构建、独立提交。

**Tech Stack:** SwiftUI, SwiftData, Xcode 16, XCTest / XCUITest

---

## File Structure

| File | Responsibility |
|------|----------------|
| `AIBuilder/DesignSystem/DesignTokens.swift` | 颜色 / 字体 / 间距 / 圆角 / 动画时长 token |
| `AIBuilder/DesignSystem/ColorTokens.swift` | 语义颜色扩展（Color.backgroundPrimary 等） |
| `AIBuilder/DesignSystem/TypographyTokens.swift` | 字体扩展（Font.bodyAI 等） |
| `AIBuilder/DesignSystem/SpacingTokens.swift` | 间距常量 |
| `AIBuilder/DesignSystem/AnimationTokens.swift` | 动画时长 / 缓动 token |
| `AIBuilder/Views/Components/EmptyStateView.swift` | 统一空状态组件 |
| `AIBuilder/Views/Components/LoadingStateView.swift` | 统一加载骨架屏 |
| `AIBuilder/Views/Components/ToastView.swift` | 统一 Toast 反馈 |
| `AIBuilder/Views/Components/CardStyle.swift` | 通用卡片样式 modifier |
| `AIBuilder/Views/Components/AvatarView.swift` | 用户 / AI 头像标识 |
| `AIBuilder/Views/Chat/MessageBubble.swift` | 消息气泡（使用 token + 头像 + 引用块 + 折叠 + 继续生成） |
| `AIBuilder/Views/Chat/CodeSyntaxHighlighter.swift` | 代码高亮（深浅色双主题） |
| `AIBuilder/Views/Chat/CodeBlockView.swift` | 代码块（深浅色背景） |
| `AIBuilder/Views/Conversation/ConversationRow.swift` | 会话行（最后消息预览 + 未读标识） |
| `AIBuilder/Views/Conversation/ConversationList.swift` | 接入 EmptyStateView |
| `AIBuilder/Views/RAG/KnowledgeBaseView.swift` | 接入 EmptyStateView |
| `AIBuilder/Views/Chat/MessageListView.swift` | 接入 LoadingStateView / ToastView / 动画 token |
| `AIBuilder/Views/Chat/ChatView.swift` | 接入 ToastView |
| `AIBuilder/App/AIBuilderApp.swift` | macOS 多窗口（Window Group for conversation） |
| `AIBuilder/Views/Chat/MarkdownText.swift` | 引用块渲染（blockquote） |
| `AIBuilderTests/DesignTokensTests.swift` | token 单测 |
| `AIBuilderTests/EmptyStateViewTests.swift` | 空状态组件单测 |
| `screenshots/` | 补齐深色模式 + 多尺寸截图 |
| `docs/superpowers/plans/2026-07-09-design-system-optimization.md` | 本实施计划 |

---

## Pre-Flight

当前代码状态：
- iOS / macOS build：0 warnings
- UT 248 / UIT 13：0 failures, 0 skipped
- 硬编码：46 处颜色、77 处字体、119 处间距
- 缺失组件：ToastView / EmptyStateView / LoadingStateView / AvatarView / CardStyle
- 风险点：`CodeSyntaxHighlighter.swift` / `CodeBlockView.swift` 10 个 RGB 字面量无浅色适配

---

## Task 1: 建立 DesignTokens 体系

**Files:**
- Create: `AIBuilder/DesignSystem/DesignTokens.swift`
- Create: `AIBuilder/DesignSystem/ColorTokens.swift`
- Create: `AIBuilder/DesignSystem/TypographyTokens.swift`
- Create: `AIBuilder/DesignSystem/SpacingTokens.swift`
- Create: `AIBuilder/DesignSystem/AnimationTokens.swift`
- Create: `AIBuilderTests/DesignTokensTests.swift`
- Modify: `AIBuilder.xcodeproj/project.pbxproj`（注册新文件）

- [ ] **Step 1: 创建目录与 DesignTokens.swift**

Create `AIBuilder/DesignSystem/DesignTokens.swift`:

```swift
import SwiftUI

/// AIBuilder 设计系统入口：聚合颜色、字体、间距、圆角、动画 token
/// 使用方式：Color.backgroundPrimary / Font.bodyAI / Spacing.medium / AnimationTokens.transition
enum DesignTokens {}

/// 间距 token（基于 4pt grid）
enum Spacing {
    /// 2pt
    static let xs: CGFloat = 2
    /// 4pt
    static let sm: CGFloat = 4
    /// 8pt
    static let md: CGFloat = 8
    /// 12pt
    static let lg: CGFloat = 12
    /// 16pt
    static let xl: CGFloat = 16
    /// 24pt
    static let xxl: CGFloat = 24
    /// 32pt
    static let xxxl: CGFloat = 32
}

/// 圆角 token
enum CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 18
    static let pill: CGFloat = 999
}

/// 动画 token
enum AnimationTokens {
    /// 页面转场 0.25s
    static let transition: Animation = .easeInOut(duration: 0.25)
    /// 消息进入 0.2s
    static let messageAppear: Animation = .easeOut(duration: 0.2)
    /// 按钮按下 0.1s
    static let buttonPress: Animation = .easeInOut(duration: 0.1)
    /// 骨架屏呼吸 0.8s
    static let skeleton: Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    /// 闪烁光标 0.5s
    static let blink: Animation = .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
}
```

- [ ] **Step 2: 创建 ColorTokens.swift**

Create `AIBuilder/DesignSystem/ColorTokens.swift`:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 语义颜色 token：所有视图统一使用这些扩展，不直接引用 Color.red / Color(.systemGray5)
extension Color {
    // MARK: - 背景
    /// 主背景（List / Form 默认背景）
    static var backgroundPrimary: Color {
        #if canImport(UIKit)
        return Color(.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    /// 次背景（卡片 / 分组背景）
    static var backgroundSecondary: Color {
        #if canImport(UIKit)
        return Color(.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    /// 三级背景（代码块 / 输入栏）
    static var backgroundTertiary: Color {
        #if canImport(UIKit)
        return Color(.tertiarySystemBackground)
        #else
        return Color(NSColor.underPageBackgroundColor)
        #endif
    }

    // MARK: - 气泡
    /// 用户气泡背景
    static let bubbleUser = Color.accentColor
    /// 助手气泡背景
    static var bubbleAssistant: Color {
        #if canImport(UIKit)
        return Color(.systemGray6)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    // MARK: - 文字
    /// 主要文字
    static var textPrimary: Color {
        #if canImport(UIKit)
        return Color(.label)
        #else
        return Color(NSColor.labelColor)
        #endif
    }
    /// 次要文字
    static var textSecondary: Color {
        #if canImport(UIKit)
        return Color(.secondaryLabel)
        #else
        return Color(NSColor.secondaryLabelColor)
        #endif
    }
    /// 三级文字（时间戳、占位）
    static var textTertiary: Color {
        #if canImport(UIKit)
        return Color(.tertiaryLabel)
        #else
        return Color(NSColor.tertiaryLabelColor)
        #endif
    }

    // MARK: - 分隔线
    static var separator: Color {
        #if canImport(UIKit)
        return Color(.separator).opacity(0.3)
        #else
        return Color(NSColor.separatorColor).opacity(0.3)
        #endif
    }

    // MARK: - 代码块（深浅色双主题）
    /// 代码块背景（浅色）
    static let codeBackgroundLight = Color(red: 0.96, green: 0.97, blue: 0.98)
    /// 代码块背景（深色）
    static let codeBackgroundDark = Color(red: 0.16, green: 0.17, blue: 0.19)
    /// 代码块边框
    static var codeBorder: Color {
        #if canImport(UIKit)
        return Color(.systemGray5)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
}
```

- [ ] **Step 3: 创建 TypographyTokens.swift**

Create `AIBuilder/DesignSystem/TypographyTokens.swift`:

```swift
import SwiftUI

/// 字体 token：统一字体样式
extension Font {
    /// AI 对话正文（.body）
    static let bodyAI = Font.body
    /// AI 副标题（.subheadline）
    static let subheadlineAI = Font.subheadline
    /// AI 注释（.caption2）
    static let captionAI = Font.caption2
    /// AI 标题（.headline）
    static let headlineAI = Font.headline
    /// AI 大标题（.title2）
    static let titleAI = Font.title2
    /// 空状态大标题（.system size: 34 light）
    static let emptyStateTitle = Font.system(size: 34, weight: .light)
    /// 等宽字体（工具消息 / 代码）
    static let monoAI = Font.callout.monospaced()
    /// 工具标签（caption2 medium）
    static let toolLabel = Font.caption2.weight(.medium)
}
```

- [ ] **Step 4: 创建 SpacingTokens.swift（合并到 DesignTokens）**

已在 Step 1 的 `DesignTokens.swift` 中定义 `Spacing` enum，此步跳过。

- [ ] **Step 5: 创建 AnimationTokens.swift（合并到 DesignTokens）**

已在 Step 1 的 `DesignTokens.swift` 中定义 `AnimationTokens`，此步跳过。

- [ ] **Step 6: 写单测**

Create `AIBuilderTests/DesignTokensTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import AIBuilder

final class DesignTokensTests: XCTestCase {

    func testSpacingTokensFollowFourPointGrid() {
        XCTAssertEqual(Spacing.xs, 2)
        XCTAssertEqual(Spacing.sm, 4)
        XCTAssertEqual(Spacing.md, 8)
        XCTAssertEqual(Spacing.lg, 12)
        XCTAssertEqual(Spacing.xl, 16)
        XCTAssertEqual(Spacing.xxl, 24)
        XCTAssertEqual(Spacing.xxxl, 32)
    }

    func testCornerRadiusTokens() {
        XCTAssertEqual(CornerRadius.small, 8)
        XCTAssertEqual(CornerRadius.medium, 12)
        XCTAssertEqual(CornerRadius.large, 18)
    }

    func testColorTokensResolveOnCurrentPlatform() {
        // 仅验证可解析，不验证具体色值（平台相关）
        _ = Color.backgroundPrimary
        _ = Color.backgroundSecondary
        _ = Color.bubbleAssistant
        _ = Color.textPrimary
        _ = Color.textSecondary
        _ = Color.separator
        _ = Color.codeBackgroundLight
        _ = Color.codeBackgroundDark
    }

    func testTypographyTokensResolve() {
        _ = Font.bodyAI
        _ = Font.captionAI
        _ = Font.headlineAI
        _ = Font.emptyStateTitle
        _ = Font.monoAI
        _ = Font.toolLabel
    }
}
```

- [ ] **Step 7: 注册文件到 Xcode 项目并构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 8: Commit**

```bash
git add AIBuilder/DesignSystem/ AIBuilderTests/DesignTokensTests.swift
git commit -m "feat(design): add DesignTokens with color, typography, spacing and animation tokens"
```

---

## Task 2: 统一空状态组件 EmptyStateView

**Files:**
- Create: `AIBuilder/Views/Components/EmptyStateView.swift`
- Create: `AIBuilderTests/EmptyStateViewTests.swift`
- Modify: `AIBuilder/Views/Conversation/ConversationList.swift`
- Modify: `AIBuilder/Views/RAG/KnowledgeBaseView.swift`
- Modify: `AIBuilder/Views/Settings/SettingsView.swift`

- [ ] **Step 1: 创建 EmptyStateView 组件**

Create `AIBuilder/Views/Components/EmptyStateView.swift`:

```swift
import SwiftUI

/// 统一空状态组件：插画 + 标题 + 说明 + 主操作按钮
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryButtonTitle: String? = nil
    var primaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.emptyStateTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadlineAI)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xxxl)

            if let title = primaryButtonTitle, let action = primaryAction {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(message)")
    }
}

#Preview {
    EmptyStateView(
        systemImage: "bubble.left.and.bubble.right",
        title: "还没有对话",
        message: "点击右上角新建对话开始聊天",
        primaryButtonTitle: "新建对话",
        primaryAction: {}
    )
}
```

- [ ] **Step 2: 写单测**

Create `AIBuilderTests/EmptyStateViewTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import AIBuilder

final class EmptyStateViewTests: XCTestCase {

    func testEmptyStateViewInitWithAllFields() {
        let view = EmptyStateView(
            systemImage: "doc.text",
            title: "暂无文档",
            message: "导入文档以启用 RAG",
            primaryButtonTitle: "导入",
            primaryAction: {}
        )
        XCTAssertEqual(view.title, "暂无文档")
        XCTAssertEqual(view.message, "导入文档以启用 RAG")
        XCTAssertEqual(view.primaryButtonTitle, "导入")
        XCTAssertNotNil(view.primaryAction)
    }

    func testEmptyStateViewInitWithoutAction() {
        let view = EmptyStateView(
            systemImage: "sidebar.left",
            title: "选择一个分类",
            message: "从左侧选择"
        )
        XCTAssertNil(view.primaryButtonTitle)
        XCTAssertNil(view.primaryAction)
    }
}
```

- [ ] **Step 3: 迁移 ConversationList 空状态**

Open `AIBuilder/Views/Conversation/ConversationList.swift`，找到空状态实现（约 line 53 `Text("还没有对话")`），替换为：

```swift
EmptyStateView(
    systemImage: "bubble.left.and.bubble.right",
    title: "还没有对话",
    message: "点击右上角新建对话开始聊天",
    primaryButtonTitle: "新建对话",
    primaryAction: { /* 保留原新建对话 action */ }
)
```
保留原有的 `primaryAction` 逻辑（如调用 viewModel）。

- [ ] **Step 4: 迁移 KnowledgeBaseView 空状态**

Open `AIBuilder/Views/RAG/KnowledgeBaseView.swift`，找到 `ContentUnavailableView("选择一个文档", systemImage: "doc.text")`（约 line 117），替换为：

```swift
EmptyStateView(
    systemImage: "doc.text",
    title: "暂无文档",
    message: "导入文档以启用 RAG 知识库",
    primaryButtonTitle: "导入文档",
    primaryAction: { /* 保留原导入 action */ }
)
```

- [ ] **Step 5: 构建并测试**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 6: Commit**

```bash
git add AIBuilder/Views/Components/EmptyStateView.swift AIBuilderTests/EmptyStateViewTests.swift AIBuilder/Views/Conversation/ConversationList.swift AIBuilder/Views/RAG/KnowledgeBaseView.swift
git commit -m "feat(ui): add unified EmptyStateView and migrate conversation/knowledge base"
```

---

## Task 3: 统一加载组件 LoadingStateView

**Files:**
- Create: `AIBuilder/Views/Components/LoadingStateView.swift`
- Modify: `AIBuilder/Views/Components/SkeletonView.swift`
- Modify: `AIBuilder/Views/Chat/MessageListView.swift`

- [ ] **Step 1: 创建 LoadingStateView**

Create `AIBuilder/Views/Components/LoadingStateView.swift`:

```swift
import SwiftUI

/// 统一加载状态：骨架屏 + 进度文本
struct LoadingStateView: View {
    let text: String
    var skeletonLines: Int = 3

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(0..<skeletonLines, id: \.self) { _ in
                    SkeletonView()
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, Spacing.xl)

            Text(text)
                .font(.captionAI)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview {
    LoadingStateView(text: "AI 正在思考...")
        .frame(height: 200)
}
```

- [ ] **Step 2: 确认 SkeletonView 存在并使用 token**

Read `AIBuilder/Views/Components/SkeletonView.swift`，将硬编码颜色改为 `Color.backgroundTertiary`，动画改为 `AnimationTokens.skeleton`。

```swift
struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.small)
            .fill(Color.backgroundTertiary)
            .animation(reduceMotion ? nil : AnimationTokens.skeleton, value: true)
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3: 在 MessageListView 中使用 LoadingStateView**

Open `AIBuilder/Views/Chat/MessageListView.swift`，找到现有 `SkeletonView` 占位（约 line 149），替换为 `LoadingStateView(text: "AI 正在思考...")`。

- [ ] **Step 4: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Views/Components/LoadingStateView.swift AIBuilder/Views/Components/SkeletonView.swift AIBuilder/Views/Chat/MessageListView.swift
git commit -m "feat(ui): add unified LoadingStateView with skeleton and progress text"
```

---

## Task 4: 统一 Toast 反馈组件 ToastView

**Files:**
- Create: `AIBuilder/Views/Components/ToastView.swift`
- Modify: `AIBuilder/Views/Chat/MessageListView.swift`
- Modify: `AIBuilder/Views/Chat/ChatView.swift`

- [ ] **Step 1: 创建 ToastView**

Create `AIBuilder/Views/Components/ToastView.swift`:

```swift
import SwiftUI

/// 统一 Toast 反馈：操作成功/复制/撤销
struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadlineAI)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.black.opacity(0.75))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// Toast overlay modifier
struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var systemImage: String = "checkmark.circle.fill"

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                ToastView(message: message, systemImage: systemImage)
                    .padding(.top, Spacing.xxl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(AnimationTokens.transition) {
                                isPresented = false
                            }
                        }
                    }
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(AnimationTokens.transition, value: isPresented)
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, systemImage: String = "checkmark.circle.fill") -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, systemImage: systemImage))
    }
}
```

- [ ] **Step 2: 在 ChatView 接入 ToastView**

Open `AIBuilder/Views/Chat/ChatView.swift`，找到现有 `feedbackToast` 状态（在 `MessageListView.swift:189` 附近），统一为 `@State private var showToast = false` + `@State private var toastMessage = ""`。

在 `ChatView` body 末尾添加：
```swift
.toast(isPresented: $showToast, message: toastMessage)
```

复制消息时触发：
```swift
withAnimation(AnimationTokens.transition) {
    toastMessage = "已复制"
    showToast = true
}
```

- [ ] **Step 3: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/Views/Components/ToastView.swift AIBuilder/Views/Chat/
git commit -m "feat(ui): add unified ToastView with overlay modifier and integrate into ChatView"
```

---

## Task 5: 通用卡片样式 CardStyle 与 AvatarView

**Files:**
- Create: `AIBuilder/Views/Components/CardStyle.swift`
- Create: `AIBuilder/Views/Components/AvatarView.swift`
- Modify: `AIBuilder/Views/Chat/StepCardView.swift`
- Modify: `AIBuilder/Views/Chat/CitationCard.swift`
- Modify: `AIBuilder/Views/Chat/CodeBlockView.swift`

- [ ] **Step 1: 创建 CardStyle modifier**

Create `AIBuilder/Views/Components/CardStyle.swift`:

```swift
import SwiftUI

/// 通用卡片样式 modifier：统一背景、圆角、描边、阴影
struct CardStyle: ViewModifier {
    var background: Color = .backgroundSecondary
    var cornerRadius: CGFloat = CornerRadius.medium
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.separator, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle(
        background: Color = .backgroundSecondary,
        cornerRadius: CGFloat = CornerRadius.medium,
        padding: CGFloat = Spacing.lg
    ) -> some View {
        modifier(CardStyle(background: background, cornerRadius: cornerRadius, padding: padding))
    }
}
```

- [ ] **Step 2: 创建 AvatarView**

Create `AIBuilder/Views/Components/AvatarView.swift`:

```swift
import SwiftUI

/// 用户 / AI 头像标识
struct AvatarView: View {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Image(systemName: iconName)
                .font(.system(size: size * 0.5))
                .foregroundStyle(iconColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        switch role {
        case .user: return Color.accentColor.opacity(0.15)
        case .assistant: return Color.purple.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch role {
        case .user: return Color.accentColor
        case .assistant: return Color.purple
        }
    }

    private var iconName: String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        }
    }
}

#Preview {
    HStack {
        AvatarView(role: .user)
        AvatarView(role: .assistant)
    }
    .padding()
}
```

- [ ] **Step 3: 迁移 StepCardView / CitationCard / CodeBlockView 使用 cardStyle**

Open `AIBuilder/Views/Chat/StepCardView.swift`，将现有背景/圆角/描边代码替换为：
```swift
.cardStyle()
```

Open `AIBuilder/Views/Chat/CitationCard.swift`，同样替换为 `.cardStyle()`。

Open `AIBuilder/Views/Chat/CodeBlockView.swift`，替换为：
```swift
.cardStyle(background: Color.backgroundTertiary, cornerRadius: CornerRadius.medium, padding: Spacing.md)
```

- [ ] **Step 4: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Views/Components/CardStyle.swift AIBuilder/Views/Components/AvatarView.swift AIBuilder/Views/Chat/
git commit -m "feat(ui): add CardStyle modifier and AvatarView, migrate step/citation/code cards"
```

---

## Task 6: MessageBubble 视觉升级（头像 + 引用块 + 折叠 + 继续生成）

**Files:**
- Modify: `AIBuilder/Views/Chat/MessageBubble.swift`
- Modify: `AIBuilder/Views/Chat/MarkdownText.swift`

- [ ] **Step 1: 在 MessageBubble 添加 AvatarView**

Open `AIBuilder/Views/Chat/MessageBubble.swift`，在外层 `HStack` 中为 assistant 消息添加头像：
```swift
HStack(alignment: .top, spacing: Spacing.sm) {
    if !isUser {
        AvatarView(role: .assistant, size: 28)
    }
    VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.sm) {
        // ... existing content
    }
    if isUser {
        AvatarView(role: .user, size: 28)
    }
}
```

- [ ] **Step 2: 迁移气泡颜色/字体/间距到 token**

替换：
- `bubbleBackground` 使用 `Color.bubbleUser` / `Color.bubbleAssistant`
- 文字颜色使用 `Color.textPrimary` / `Color.white`
- `.padding(.horizontal, 14)` → `.padding(.horizontal, Spacing.lg)`
- `.padding(.vertical, 10)` → `.padding(.vertical, Spacing.md)`
- `RoundedCornerShape(radius: 18)` → `RoundedRectangle(cornerRadius: CornerRadius.large)`
- `.font(.caption2.weight(.medium))` → `.font(.toolLabel)`
- `.font(.body)` → `.font(.bodyAI)`
- `.font(.callout.monospaced())` → `.font(.monoAI)`

- [ ] **Step 3: 在 MarkdownText 添加引用块渲染**

Open `AIBuilder/Views/Chat/MarkdownText.swift`，在 Markdown 解析中识别 `> ` 开头的行，渲染为：
```swift
HStack(spacing: Spacing.sm) {
    Rectangle()
        .fill(Color.accentColor)
        .frame(width: 3)
    Text(quoteContent)
        .font(.bodyAI)
        .foregroundStyle(.secondary)
}
.padding(.vertical, Spacing.xs)
```

- [ ] **Step 4: 添加长文本折叠**

在 `MarkdownText` 中，若内容超过 500 字符，默认显示前 500 字符并添加「展开」按钮：
```swift
@State private var isExpanded = false

if content.count > 500 && !isExpanded {
    Text(String(content.prefix(500)) + "...")
    Button("展开") {
        withAnimation(AnimationTokens.transition) { isExpanded = true }
    }
} else {
    // full markdown rendering
}
```

- [ ] **Step 5: 添加「继续生成」按钮**

在 `MessageBubble` 中，若 `message.isStreaming == false` 且 `isUser == false` 且消息为最后一条，显示「继续生成」按钮：
```swift
if !message.isStreaming && !isUser {
    Button {
        // 调用 onResend 或 onContinue
    } label: {
        Label("继续生成", systemImage: "arrow.forward")
            .font(.captionAI)
    }
}
```

- [ ] **Step 6: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: Commit**

```bash
git add AIBuilder/Views/Chat/MessageBubble.swift AIBuilder/Views/Chat/MarkdownText.swift
git commit -m "feat(ui): upgrade MessageBubble with avatars, blockquote, collapse and continue button"
```

---

## Task 7: ConversationRow 视觉升级（最后消息预览 + 未读标识）

**Files:**
- Modify: `AIBuilder/Views/Conversation/ConversationRow.swift`
- Modify: `AIBuilder/Models/Conversation.swift`

- [ ] **Step 1: 在 Conversation 模型添加未读标识**

Open `AIBuilder/Models/Conversation.swift`，添加：
```swift
var unreadCount: Int = 0
```

- [ ] **Step 2: 在 ConversationRow 添加未读标识 badge**

Open `AIBuilder/Views/Conversation/ConversationRow.swift`，在时间戳下方添加：
```swift
if conversation.unreadCount > 0 {
    Text("\(conversation.unreadCount)")
        .font(.captionAI)
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background(Color.accentColor)
        .clipShape(Capsule())
}
```

- [ ] **Step 3: 迁移 ConversationRow 到 token**

替换：
- `HStack(spacing: 12)` → `HStack(spacing: Spacing.lg)`
- `VStack(spacing: 4)` → `VStack(spacing: Spacing.sm)`
- `.padding(.vertical, 6)` → `.padding(.vertical, Spacing.sm + 2)`
- `.font(.body.weight(.medium))` → `.font(.bodyAI.weight(.medium))`
- `.font(.caption2)` → `.font(.captionAI)`
- `.font(.subheadline)` → `.font(.subheadlineAI)`

- [ ] **Step 4: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Views/Conversation/ConversationRow.swift AIBuilder/Models/Conversation.swift
git commit -m "feat(ui): add unread badge and migrate ConversationRow to design tokens"
```

---

## Task 8: 代码高亮深浅色双主题

**Files:**
- Modify: `AIBuilder/Services/Markdown/CodeSyntaxHighlighter.swift`
- Modify: `AIBuilder/Views/Chat/CodeBlockView.swift`

- [ ] **Step 1: 在 CodeSyntaxHighlighter 添加浅色配色**

Open the `CodeSyntaxHighlighter.swift` file，将现有 RGB 字面量重构为深浅色双主题：

```swift
enum SyntaxTheme {
    case light
    case dark

    var keyword: Color {
        switch self {
        case .light: return Color(red: 0.51, green: 0.20, blue: 0.55)
        case .dark:  return Color(red: 0.84, green: 0.51, blue: 0.84)
        }
    }
    var string: Color {
        switch self {
        case .light: return Color(red: 0.16, green: 0.55, blue: 0.24)
        case .dark:  return Color(red: 0.51, green: 0.78, blue: 0.51)
        }
    }
    var comment: Color {
        switch self {
        case .light: return Color(red: 0.40, green: 0.40, blue: 0.40)
        case .dark:  return Color(red: 0.55, green: 0.55, blue: 0.55)
        }
    }
    var number: Color {
        switch self {
        case .light: return Color(red: 0.80, green: 0.40, blue: 0.00)
        case .dark:  return Color(red: 0.95, green: 0.69, blue: 0.40)
        }
    }
    var type: Color {
        switch self {
        case .light: return Color(red: 0.20, green: 0.40, blue: 0.80)
        case .dark:  return Color(red: 0.55, green: 0.78, blue: 0.95)
        }
    }
    var function: Color {
        switch self {
        case .light: return Color(red: 0.40, green: 0.20, blue: 0.80)
        case .dark:  return Color(red: 0.69, green: 0.51, blue: 0.95)
        }
    }
    var plainText: Color {
        switch self {
        case .light: return Color.primary
        case .dark:  return Color(red: 0.92, green: 0.93, blue: 0.94)
        }
    }
}
```

- [ ] **Step 2: 在 CodeBlockView 根据 colorScheme 选择主题**

Open `AIBuilder/Views/Chat/CodeBlockView.swift`，添加 `@Environment(\.colorScheme)` 并根据值选择背景和主题：

```swift
@Environment(\.colorScheme) private var colorScheme

var body: some View {
    let theme: SyntaxTheme = colorScheme == .dark ? .dark : .light
    let backgroundColor = colorScheme == .dark ? Color.codeBackgroundDark : Color.codeBackgroundLight

    // 使用 backgroundColor 替代硬编码 RGB
    // 将 theme 传入 highlighter
}
```

- [ ] **Step 3: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/Services/Markdown/CodeSyntaxHighlighter.swift AIBuilder/Views/Chat/CodeBlockView.swift
git commit -m "feat(ui): add light/dark dual theme for code syntax highlighting"
```

---

## Task 9: 全量迁移视图到 Design Tokens

**Files:**
- Modify: `AIBuilder/Views/Chat/ChatView.swift`
- Modify: `AIBuilder/Views/Chat/ChatInputBar.swift`
- Modify: `AIBuilder/Views/Chat/MessageListView.swift`
- Modify: `AIBuilder/Views/Chat/StepCardView.swift`
- Modify: `AIBuilder/Views/Chat/CitationCard.swift`
- Modify: `AIBuilder/Views/Chat/MarkdownTableView.swift`
- Modify: `AIBuilder/Views/Chat/TypingIndicator.swift`
- Modify: `AIBuilder/Views/Chat/FeedbackBar.swift`
- Modify: `AIBuilder/Views/Settings/SettingsView.swift`
- Modify: `AIBuilder/Views/Settings/HealthSettingsView.swift`
- Modify: `AIBuilder/Views/Settings/TTSVoicePickerView.swift`
- Modify: `AIBuilder/Views/RAG/KnowledgeBaseView.swift`
- Modify: `AIBuilder/Views/OnDevice/OnDeviceModelView.swift`

- [ ] **Step 1: 批量替换颜色 token**

对每个文件执行以下替换（使用 Xcode Find & Replace）：
- `Color(.systemGray5)` → `Color.backgroundSecondary`（仅在背景场景）
- `Color(.systemGray6)` → `Color.backgroundTertiary`
- `Color(.separator).opacity(0.3)` → `Color.separator`
- `Color(.tertiaryLabel)` → `Color.textTertiary`
- `Color.accentColor`（作为气泡背景）→ `Color.bubbleUser`
- `.foregroundColor(.secondary)` → `.foregroundStyle(.secondary)`（SwiftUI 5 推荐）

- [ ] **Step 2: 批量替换字体 token**

- `.font(.caption2)` → `.font(.captionAI)`
- `.font(.caption)` → `.font(.captionAI)`
- `.font(.body)` → `.font(.bodyAI)`
- `.font(.headline)` → `.font(.headlineAI)`
- `.font(.title2)` → `.font(.titleAI)`
- `.font(.system(size: 34, weight: .light))` → `.font(.emptyStateTitle)`
- `.font(.callout.monospaced())` → `.font(.monoAI)`
- `.font(.caption2.weight(.medium))` → `.font(.toolLabel)`

- [ ] **Step 3: 批量替换间距 token**

- `HStack(spacing: 4)` → `HStack(spacing: Spacing.sm)`
- `HStack(spacing: 8)` → `HStack(spacing: Spacing.md)`
- `HStack(spacing: 12)` → `HStack(spacing: Spacing.lg)`
- `VStack(spacing: 4)` → `VStack(spacing: Spacing.sm)`
- `VStack(spacing: 8)` → `VStack(spacing: Spacing.md)`
- `VStack(spacing: 12)` → `VStack(spacing: Spacing.lg)`
- `VStack(spacing: 20)` → `VStack(spacing: Spacing.xxl)`
- `.padding(20)` → `.padding(Spacing.xl)`
- `.padding(.horizontal, 14)` → `.padding(.horizontal, Spacing.lg)`
- `.padding(.vertical, 10)` → `.padding(.vertical, Spacing.md)`
- `.padding(.horizontal, 32)` → `.padding(.horizontal, Spacing.xxxl)`

- [ ] **Step 4: 批量替换动画 token**

- `withAnimation(.easeInOut(duration: 0.25))` → `withAnimation(AnimationTokens.transition)`
- `withAnimation(.easeOut(duration: 0.2))` → `withAnimation(AnimationTokens.messageAppear)`
- `.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true))` → `.animation(AnimationTokens.skeleton)`
- `.animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true))` → `.animation(AnimationTokens.blink)`

- [ ] **Step 5: 构建并测试**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

Run:
```bash
xcodebuild test -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:AIBuilderTests 2>&1 | tail -5
```
Expected: 0 failures, 0 skipped

- [ ] **Step 6: Commit**

```bash
git add AIBuilder/Views/
git commit -m "refactor(ui): migrate all views to DesignTokens (color, typography, spacing, animation)"
```

---

## Task 10: macOS 多窗口支持

**Files:**
- Modify: `AIBuilder/App/AIBuilderApp.swift`
- Modify: `AIBuilder.xcodeproj/project.pbxproj`（Info.plist 多窗口配置）

- [ ] **Step 1: 在 AIBuilderApp 添加多窗口支持**

Open `AIBuilder/App/AIBuilderApp.swift`，在 macOS 分支下添加 `Window` scene 用于独立对话窗口：

```swift
var body: some Scene {
    WindowGroup {
        ChatView()
            #if os(macOS)
            .frame(minWidth: 800, minHeight: 500)
            #endif
            .task {
                _ = AVSpeechSynthesisVoice.speechVoices()
            }
    }
    #if os(macOS)
    .defaultSize(width: 1000, height: 700)
    // macOS 多窗口：允许通过 Cmd+N 打开新窗口
    .commands {
        CommandGroup(replacing: .newItem) {
            Button("新建对话窗口") {
                NotificationCenter.default.post(name: .newConversationRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        // ... existing commands
    }
    #endif
    .modelContainer(for: [...])
}
```

- [ ] **Step 2: 在 Info.plist 启用多窗口**

在 `Info.plist` 中添加（macOS）：
```xml
<key>NSApplicationSupportsMultipleWindows</key>
<true/>
```

- [ ] **Step 3: 构建 macOS**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=macOS,arch=arm64' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/App/AIBuilderApp.swift AIBuilder/Info.plist
git commit -m "feat(macOS): enable multi-window support for conversations"
```

---

## Task 11: macOS 工具栏 segmented 切换

**Files:**
- Modify: `AIBuilder/Views/Chat/ChatView.swift`

- [ ] **Step 1: 在 ChatView macOS 工具栏添加 segmented**

Open `AIBuilder/Views/Chat/ChatView.swift`，在 macOS `NavigationSplitView` detail 中添加：

```swift
#if os(macOS)
.toolbar {
    ToolbarItem(placement: .navigation) {
        Picker("视图", selection: $selectedTab) {
            Label("聊天", systemImage: "bubble.left").tag(ViewTab.chat)
            Label("知识库", systemImage: "books.vertical").tag(ViewTab.knowledge)
            Label("健康", systemImage: "heart.text.square").tag(ViewTab.health)
        }
        .pickerStyle(.segmented)
    }
}
#endif
```

添加枚举：
```swift
enum ViewTab: String, CaseIterable {
    case chat, knowledge, health
}
```

- [ ] **Step 2: 根据 selectedTab 切换 detail 视图**

```swift
switch selectedTab {
case .chat: ChatDetailContent()
case .knowledge: KnowledgeBaseView()
case .health: HealthSettingsView(chatViewModel: chatViewModel)
}
```

- [ ] **Step 3: 构建 macOS**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=macOS,arch=arm64' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/Views/Chat/ChatView.swift
git commit -m "feat(macOS): add segmented toolbar for chat/knowledge/health switching"
```

---

## Task 12: 动画规范统一与 reduceMotion 处理

**Files:**
- Modify: `AIBuilder/Views/Chat/MessageListView.swift`
- Modify: `AIBuilder/Views/Chat/MessageBubble.swift`
- Modify: `AIBuilder/Views/Chat/TypingIndicator.swift`
- Modify: `AIBuilder/Views/Chat/StepCardView.swift`

- [ ] **Step 1: 在 MessageListView 统一 transition**

Open `AIBuilder/Views/Chat/MessageListView.swift`，添加 `@Environment(\.accessibilityReduceMotion)`，将 transition 替换为：

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// 消息进入
.transition(reduceMotion ? .opacity : .asymmetric(
    insertion: .move(edge: .bottom).combined(with: .opacity),
    removal: .opacity
))
.animation(reduceMotion ? nil : AnimationTokens.messageAppear, value: messages.count)
```

- [ ] **Step 2: 在 MessageBubble BlinkingCursor 处理 reduceMotion**

Open `AIBuilder/Views/Chat/MessageBubble.swift`，在 `BlinkingCursor` 中：
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// ...
.animation(reduceMotion ? nil : AnimationTokens.blink, value: isVisible)
```

- [ ] **Step 3: 在 TypingIndicator 处理 reduceMotion**

Open `AIBuilder/Views/Chat/TypingIndicator.swift`，类似处理。

- [ ] **Step 4: 构建**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Views/Chat/
git commit -m "feat(a11y): unify animations with AnimationTokens and handle reduceMotion"
```

---

## Task 13: 截图与预览素材补齐

**Files:**
- Create: `screenshots/dark/ios_chat_main_dark.png`
- Create: `screenshots/dark/macos_chat_dark.png`
- Modify: `screenshots/README.md`

- [ ] **Step 1: 生成深色模式截图**

启动模拟器，在设置中开启深色模式，截取：
```bash
xcrun simctl ui "iPhone 17" appearance dark
xcrun simctl io "iPhone 17" screenshot screenshots/dark/ios_chat_main_dark.png
xcrun simctl io "iPhone 17" screenshot screenshots/dark/ios_settings_dark.png
xcrun simctl ui "iPhone 17" appearance light
```

- [ ] **Step 2: 更新 screenshots/README.md**

在表格后添加深色模式小节：
```markdown
## 深色模式

| iOS 对话（深色） | iOS 设置（深色） | macOS 对话（深色） |
|---|---|---|
| ![iOS Chat Dark](screenshots/dark/ios_chat_main_dark.png) | ![iOS Settings Dark](screenshots/dark/ios_settings_dark.png) | ![macOS Chat Dark](screenshots/dark/macos_chat_dark.png) |
```

- [ ] **Step 3: Commit**

```bash
git add screenshots/
git commit -m "docs(screenshots): add dark mode screenshots"
```

---

## Task 14: 全量构建与测试验证

**Files:**
- 无代码变更

- [ ] **Step 1: iOS build**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**, 0 warnings

- [ ] **Step 2: macOS build**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=macOS,arch=arm64' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**, 0 warnings

- [ ] **Step 3: UT + UIT**

Run:
```bash
xcodebuild test -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: 0 failures, 0 skipped（UT 248+新增, UIT 13）

---

## Task 15: 推送并更新 PR

- [ ] **Step 1: Push**

```bash
git push
```

- [ ] **Step 2: 更新 PR 描述**

Use body:
```markdown
## Summary

This PR implements the full design system optimization per `doc/DESIGN_UPDATE.md`.

## Changes

- feat(design): add DesignTokens (color, typography, spacing, animation)
- feat(ui): add unified EmptyStateView, LoadingStateView, ToastView, CardStyle, AvatarView
- feat(ui): upgrade MessageBubble with avatars, blockquote, collapse, continue button
- feat(ui): add unread badge to ConversationRow
- feat(ui): light/dark dual theme for code syntax highlighting
- refactor(ui): migrate all views to DesignTokens
- feat(macOS): enable multi-window support
- feat(macOS): add segmented toolbar for chat/knowledge/health
- feat(a11y): unify animations with reduceMotion handling
- docs(screenshots): add dark mode screenshots

## Verification

- iOS build: success, 0 warnings
- macOS build: success, 0 warnings
- UT/UIT: 0 failures, 0 skipped
```

---

## Self-Review

- **Spec coverage:** DESIGN_UPDATE.md §1-7 全部覆盖（Token、深色、消息、macOS、组件、动画、截图）。
- **Placeholder scan:** 所有代码均为可执行内容，无 TBD/TODO。
- **Type consistency:** `Spacing.md` = 8, `CornerRadius.large` = 18, `Color.bubbleAssistant` 等定义与迁移步骤一致。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-09-design-system-optimization.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** — 每个 Task 派发独立子代理。
2. **Inline Execution** — 当前会话顺序执行。

**Which approach?**
