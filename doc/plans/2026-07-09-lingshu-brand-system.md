# 灵枢品牌视觉系统实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 App 从 "AIBuilder" 品牌化为「灵枢」，建立东方美学与现代 SwiftUI 融合的视觉系统：生成品牌图标、创建开屏展示、定义内部 UI 色彩与字体风格。

**Architecture:** 以「灵枢」意境为核心——墨黑、朱砂、宣纸、青翠四色为骨架，楷书/宋体为字体，生成 1024px 主图标并自动派生 macOS 全尺寸，创建 SwiftUI LaunchScreen 与品牌 Splash 动画，最后将 ColorTokens / TypographyTokens 切换为灵枢品牌色系。

**Tech Stack:** SwiftUI, SwiftData, Xcode 16, text_to_image API（图标生成）

---

## 品牌设计语言

### 色彩体系

| Token | 色值 | 含义 |
|-------|------|------|
| `inkBlack` | #1A1A2E | 墨黑——主文字、深色背景 |
| `vermillion` | #C53D43 | 朱砂——强调色、用户气泡 |
| `ricePaper` | #F5F0E8 | 宣纸——浅色背景 |
| `jadeGreen` | #4A7C59 | 青翠——成功、健康 |
| `antiqueGold` | #B8860B | 古金——装饰、高亮 |
| `inkGray` | #4A4A5A | 淡墨——次要文字 |

### 字体体系

- 标题：`Songti SC` / `serif`（宋体，古典感）
- 正文：系统默认（PingFang SC，现代感）
- 装饰：`Kaiti SC`（楷体，仅用于 Logo / 开屏）

### 图标设计

- **主体**：「灵」字篆刻风格，朱砂红印泥效果
- **背景**：宣纸米白，带细微纸纹
- **边框**：圆角方形（iOS 风格），无描边
- **意境**：传统印章与现代 App Icon 的融合

---

## File Structure

| File | Responsibility |
|------|----------------|
| `AIBuilder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | iOS 1024 主图标（生成替换） |
| `AIBuilder/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png` | macOS 全尺寸（从 1024 派生） |
| `AIBuilder/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | 朱砂强调色 |
| `AIBuilder/Resources/Assets.xcassets/BrandColor.colorset/Contents.json` | 新增品牌色集 |
| `AIBuilder/DesignSystem/ColorTokens.swift` | 切换为灵枢色彩 |
| `AIBuilder/DesignSystem/TypographyTokens.swift` | 添加宋体标题 token |
| `AIBuilder/Views/Components/LaunchScreen.swift` | 开屏展示视图 |
| `AIBuilder/Views/Components/BrandSplash.swift` | 品牌动画 Splash |
| `AIBuilder/App/AIBuilderApp.swift` | 接入 Splash |
| `AIBuilder/Resources/Info.plist` | 更新 App 名称 |
| `AIBuilder.xcodeproj/project.pbxproj` | PRODUCT_NAME / DISPLAY_NAME |
| `screenshots/` | 更新截图（新品牌） |

---

## Task 1: 更新 App 名称为「灵枢」

**Files:**
- Modify: `AIBuilder/Resources/Info.plist`
- Modify: `AIBuilder.xcodeproj/project.pbxproj`

- [ ] **Step 1: 在 Info.plist 添加 CFBundleDisplayName**

Open `AIBuilder/Resources/Info.plist`, add after `CFBundleName`:

```xml
<key>CFBundleDisplayName</key>
<string>灵枢</string>
```

- [ ] **Step 2: 在 pbxproj 添加 INFOPLIST_KEY_CFBundleDisplayName**

Open `AIBuilder.xcodeproj/project.pbxproj`, for the AIBuilder target Debug & Release configurations, add:

```
INFOPLIST_KEY_CFBundleDisplayName = "灵枢";
```

- [ ] **Step 3: 更新窗口标题**

In `AIBuilder/App/AIBuilderApp.swift`, the macOS window title comes from the root view. Ensure ChatView's navigation title shows 「灵枢」.

- [ ] **Step 4: Build verification**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Resources/Info.plist AIBuilder.xcodeproj/project.pbxproj
git commit -m "feat(brand): rename app to 灵枢 (LingShu)"
```

---

## Task 2: 生成灵枢 App 图标

**Files:**
- Create: `AIBuilder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Create: macOS icon sizes derived from 1024

- [ ] **Step 1: 生成 1024×1024 主图标**

使用 text_to_image API 生成图标：

```
https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=A%20minimalist%20iOS%20app%20icon%20featuring%20the%20Chinese%20character%20%E7%81%B5%20(ling%2C%20spirit)%20in%20ancient%20seal%20script%20style%2C%20vermillion%20red%20cinnabar%20ink%20on%20rice%20paper%20white%20background%2C%20subtle%20paper%20texture%2C%20centered%20composition%2C%20no%20border%2C%20flat%20design%2C%20modern%20minimalist%20Chinese%20aesthetic%2C%20soft%20shadows%20resembling%20ink%20seal%20impression&image_size=square
```

下载图片并保存为 `AppIcon-1024.png`。

- [ ] **Step 2: 派生 macOS 尺寸**

使用 `sips` 命令从 1024×1024 派生 macOS 所需尺寸：

```bash
cd AIBuilder/Resources/Assets.xcassets/AppIcon.appiconset
for size in 16 32 128 256 512; do
    sips -z $size $size AppIcon-1024.png --out icon_${size}x${size}.png
    sips -z $((size*2)) $((size*2)) AppIcon-1024.png --out icon_${size}x${size}@2x.png
done
```

- [ ] **Step 3: 验证图标文件**

```bash
ls -la AIBuilder/Resources/Assets.xcassets/AppIcon.appiconset/*.png | wc -l
```
Expected: 11 files (1 iOS + 10 macOS)

- [ ] **Step 4: Build verification**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**, 0 warnings about app icon

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Resources/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat(brand): generate 灵枢 app icon with seal script aesthetic"
```

---

## Task 3: 定义灵枢品牌色彩 AccentColor

**Files:**
- Modify: `AIBuilder/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `AIBuilder/Resources/Assets.xcassets/InkBlack.colorset/Contents.json`
- Create: `AIBuilder/Resources/Assets.xcassets/RicePaper.colorset/Contents.json`
- Create: `AIBuilder/Resources/Assets.xcassets/Vermillion.colorset/Contents.json`
- Create: `AIBuilder/Resources/Assets.xcassets/JadeGreen.colorset/Contents.json`
- Create: `AIBuilder/Resources/Assets.xcassets/AntiqueGold.colorset/Contents.json`

- [ ] **Step 1: 设置 AccentColor 为朱砂红**

Replace `AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x43",
          "green" : "0x3D",
          "red" : "0xC5"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: 创建 InkBlack 色集**

Create `InkBlack.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x2E",
          "green" : "0x1A",
          "red" : "0x1A"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 3: 创建 RicePaper 色集**

Create `RicePaper.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xE8",
          "green" : "0xF0",
          "red" : "0xF5"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 4: 创建 Vermillion / JadeGreen / AntiqueGold 色集**

Create `Vermillion.colorset/Contents.json` (same as AccentColor), `JadeGreen.colorset/Contents.json` (RGB 0x59,0x7C,0x4A), `AntiqueGold.colorset/Contents.json` (RGB 0x0B,0x86,0xB8).

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Resources/Assets.xcassets/
git commit -m "feat(brand): define LingShu color palette (vermillion, ink, rice paper, jade, gold)"
```

---

## Task 4: 更新 ColorTokens 为灵枢品牌色

**Files:**
- Modify: `AIBuilder/DesignSystem/ColorTokens.swift`

- [ ] **Step 1: 重写 ColorTokens 使用品牌色**

Replace the content of `ColorTokens.swift`:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 灵枢品牌色彩系统
extension Color {
    // MARK: - 品牌色
    /// 朱砂红——强调色
    static let vermillion = Color(red: 0.77, green: 0.24, blue: 0.27)
    /// 墨黑
    static let inkBlack = Color(red: 0.10, green: 0.10, blue: 0.18)
    /// 宣纸白
    static let ricePaper = Color(red: 0.96, green: 0.94, blue: 0.91)
    /// 青翠
    static let jadeGreen = Color(red: 0.29, green: 0.49, blue: 0.35)
    /// 古金
    static let antiqueGold = Color(red: 0.72, green: 0.53, blue: 0.04)
    /// 淡墨
    static let inkGray = Color(red: 0.29, green: 0.29, blue: 0.35)

    // MARK: - 语义映射
    static var backgroundPrimary: Color {
        #if canImport(UIKit)
        return Color(.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    static var backgroundSecondary: Color {
        #if canImport(UIKit)
        return Color(.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    static var backgroundTertiary: Color {
        #if canImport(UIKit)
        return Color(.tertiarySystemBackground)
        #else
        return Color(NSColor.underPageBackgroundColor)
        #endif
    }

    // MARK: - 气泡（灵枢品牌）
    static let bubbleUser = vermillion
    static var bubbleAssistant: Color {
        #if canImport(UIKit)
        return Color(.systemGray6)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    // MARK: - 文字
    static var textPrimary: Color {
        #if canImport(UIKit)
        return Color(.label)
        #else
        return Color(NSColor.labelColor)
        #endif
    }
    static var textSecondary: Color {
        #if canImport(UIKit)
        return Color(.secondaryLabel)
        #else
        return Color(NSColor.secondaryLabelColor)
        #endif
    }
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

    // MARK: - 代码块
    static let codeBackgroundLight = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let codeBackgroundDark = Color(red: 0.16, green: 0.17, blue: 0.19)
    static var codeBorder: Color {
        #if canImport(UIKit)
        return Color(.systemGray5)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
}
```

- [ ] **Step 2: Build verification**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIBuilderTests/DesignTokensTests -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/DesignSystem/ColorTokens.swift
git commit -m "feat(brand): update ColorTokens with LingShu vermillion brand color"
```

---

## Task 5: 更新 TypographyTokens 添加宋体标题

**Files:**
- Modify: `AIBuilder/DesignSystem/TypographyTokens.swift`

- [ ] **Step 1: 添加品牌字体 token**

Add to `TypographyTokens.swift`:

```swift
/// 灵枢品牌标题（宋体）
static let brandTitle = Font.custom("Songti SC", size: 28, relativeTo: .title2)
/// 灵枢开屏 Logo 字体（楷体）
static let brandLogo = Font.custom("Kaiti SC", size: 48, relativeTo: .largeTitle)
/// 灵枢装饰文字
static let brandDecorative = Font.custom("Songti SC", size: 16, relativeTo: .subheadline)
```

- [ ] **Step 2: Build verification**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add AIBuilder/DesignSystem/TypographyTokens.swift
git commit -m "feat(brand): add Songti and Kaiti brand typography tokens"
```

---

## Task 6: 创建开屏展示 LaunchScreen

**Files:**
- Create: `AIBuilder/Views/Components/LaunchScreen.swift`
- Modify: `AIBuilder/Resources/Info.plist`

- [ ] **Step 1: 创建 LaunchScreen SwiftUI 视图**

Create `AIBuilder/Views/Components/LaunchScreen.swift`:

```swift
import SwiftUI

/// 灵枢开屏展示：宣纸背景 + 朱砂印章 + 品牌名
struct LaunchScreen: View {
    @State private var fadeIn = false

    var body: some View {
        ZStack {
            // 宣纸背景
            Color.ricePaper
                .ignoresSafeArea()

            VStack(spacing: Spacing.xxl) {
                Spacer()

                // 朱砂印章
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(Color.vermillion)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.vermillion.opacity(0.3), radius: 10, y: 4)

                    Text("灵")
                        .font(.custom("Kaiti SC", size: 56))
                        .foregroundStyle(Color.ricePaper)
                }
                .scaleEffect(fadeIn ? 1.0 : 0.8)
                .opacity(fadeIn ? 1.0 : 0)

                VStack(spacing: Spacing.sm) {
                    Text("灵枢")
                        .font(.brandTitle)
                        .foregroundStyle(Color.inkBlack)

                    Text("LingShu · AI 对话助手")
                        .font(.brandDecorative)
                        .foregroundStyle(Color.inkGray)
                }
                .opacity(fadeIn ? 1.0 : 0)
                .offset(y: fadeIn ? 0 : 10)

                Spacer()

                Text("古之智者，枢机通灵")
                    .font(.brandDecorative)
                    .foregroundStyle(Color.inkGray.opacity(0.6))
                    .padding(.bottom, Spacing.xxl)
                    .opacity(fadeIn ? 1.0 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                fadeIn = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("灵枢，AI 对话助手")
    }
}

#Preview {
    LaunchScreen()
}
```

- [ ] **Step 2: 在 Info.plist 配置 LaunchScreen**

Update `UILaunchScreen` in Info.plist:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIColorName</key>
    <string>RicePaper</string>
</dict>
```

This sets the launch screen background to rice paper color. The animated splash is handled by `BrandSplash` in the next task.

- [ ] **Step 3: Register file & build**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/Views/Components/LaunchScreen.swift AIBuilder/Resources/Info.plist AIBuilder.xcodeproj/project.pbxproj
git commit -m "feat(brand): create LaunchScreen with rice paper and vermillion seal"
```

---

## Task 7: 创建品牌 Splash 动画

**Files:**
- Create: `AIBuilder/Views/Components/BrandSplash.swift`
- Modify: `AIBuilder/App/AIBuilderApp.swift`
- Modify: `AIBuilder/Views/Chat/ChatView.swift` (or AIBuilderApp root)

- [ ] **Step 1: 创建 BrandSplash 组件**

Create `AIBuilder/Views/Components/BrandSplash.swift`:

```swift
import SwiftUI

/// 灵枢品牌 Splash 动画：开屏展示 1.5 秒后淡出
struct BrandSplash: View {
    @Binding var isVisible: Bool
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            if isVisible {
                LaunchScreen()
                    .opacity(fadeOut ? 0 : 1)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                fadeOut = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                isVisible = false
                            }
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(AnimationTokens.transition, value: isVisible)
    }
}
```

- [ ] **Step 2: 在 AIBuilderApp 接入 Splash**

In `AIBuilderApp.swift`, wrap `ChatView()` with splash:

```swift
WindowGroup {
    ChatView()
        .overlay {
            BrandSplash(isVisible: $showSplash)
        }
        .onAppear {
            showSplash = true
        }
        // ... existing modifiers
}
```

Add `@State private var showSplash = false` to the App struct (or pass via environment).

Since `AIBuilderApp` is a `struct App`, use a wrapper view:

```swift
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ChatView()
            .overlay {
                if showSplash {
                    BrandSplash(isVisible: $showSplash)
                }
            }
    }
}
```

Then in `WindowGroup { RootView() }`.

- [ ] **Step 3: Build verification**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add AIBuilder/Views/Components/BrandSplash.swift AIBuilder/App/AIBuilderApp.swift
git commit -m "feat(brand): add BrandSplash animation with 1.5s launch transition"
```

---

## Task 8: 更新 UI 内部风格元素

**Files:**
- Modify: `AIBuilder/Views/Chat/ChatView.swift` — 标题栏品牌名
- Modify: `AIBuilder/Views/Conversation/ConversationList.swift` — 空状态品牌名
- Modify: `AIBuilder/Views/Components/EmptyStateView.swift` — 默认图标风格

- [ ] **Step 1: 更新 ChatView 空状态标题**

In `ChatView.swift`, find the empty state title "AI Builder" and replace with:

```swift
Text("灵枢")
    .font(.brandTitle)
    .foregroundStyle(Color.inkBlack)
```

And subtitle:
```swift
Text("AI 对话助手")
    .font(.brandDecorative)
    .foregroundStyle(Color.inkGray)
```

- [ ] **Step 2: 更新 EmptyStateView 默认图标**

In `EmptyStateView.swift`, for conversation empty state, use a more branded icon:

```swift
// 替换 bubble.left.and.bubble.right 为更具东方意境的图标
Image(systemName: "scroll")  // 或 "character.book.closed"
```

- [ ] **Step 3: 更新 ConversationList 标题**

In `ConversationList.swift`, ensure the navigation title shows 「灵枢」 or 「对话」 with brand styling.

- [ ] **Step 4: Build verification**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add AIBuilder/Views/
git commit -m "feat(brand): update UI with LingShu brand titles and styling"
```

---

## Task 9: 更新 AvatarView 为灵枢风格

**Files:**
- Modify: `AIBuilder/Views/Components/AvatarView.swift`

- [ ] **Step 1: 更新头像配色**

Update `AvatarView.swift`:

```swift
private var backgroundColor: Color {
    switch role {
    case .user: return Color.vermillion.opacity(0.15)
    case .assistant: return Color.jadeGreen.opacity(0.15)
    }
}

private var iconColor: Color {
    switch role {
    case .user: return Color.vermillion
    case .assistant: return Color.jadeGreen
    }
}

private var iconName: String {
    switch role {
    case .user: return "person.fill"
    case .assistant: return "sparkles"  // 或 "scroll" 更东方
    }
}
```

- [ ] **Step 2: Build verification & commit**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
git add AIBuilder/Views/Components/AvatarView.swift
git commit -m "feat(brand): update AvatarView with vermillion/jade brand colors"
```

---

## Task 10: 全量验证与推送

- [ ] **Step 1: iOS build**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 2: macOS build**

```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=macOS,arch=arm64' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 3: UT + UIT**

```bash
xcodebuild test -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: 0 failures, 0 skipped

- [ ] **Step 4: Push**

```bash
git push
```

---

## Self-Review

- **Spec coverage:** App 名称、图标、开屏、UI 风格四项全部覆盖。
- **Placeholder scan:** 所有代码均为可执行内容。
- **Type consistency:** `Color.vermillion` / `Color.inkBlack` / `Color.ricePaper` / `Font.brandTitle` / `Font.brandLogo` 定义一致。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-09-lingshu-brand-system.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** — 每个 Task 派发独立子代理。
2. **Inline Execution** — 当前会话顺序执行。

**Which approach?**
