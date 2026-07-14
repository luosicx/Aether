# Watch App 与 Widget Extension 配置指南

本指南说明如何在 Xcode 中手动添加 watchOS App target 和 Widget Extension target，并配置共享 SwiftData store。

> **背景**：所有源代码文件已创建完毕，但由于 `project.pbxproj` 结构复杂，手动编辑风险较高，因此 target 的创建需在 Xcode UI 中完成。以下是详细步骤。

---

## 目录

1. [前置准备：App Group](#1-前置准备app-group)
2. [添加 watchOS App Target（Task 4）](#2-添加-watchos-app-targettask-4)
3. [添加 Widget Extension Target（Task 5）](#3-添加-widget-extension-targettask-5)
4. [共享文件配置](#4-共享文件配置)
5. [URL Scheme 配置](#5-url-scheme-配置)
6. [验证清单](#6-验证清单)

---

## 1. 前置准备：App Group

### 1.1 Apple Developer Portal

1. 登录 [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup)
2. 点击 **+** 创建新 App Group
   - Identifier: `group.com.aether.app`
   - Description: `Aether Shared Data`

### 1.2 App ID 配置

1. 在 [Identifiers](https://developer.apple.com/account/resources/identifiers/list) 页面找到 `com.aether.app`
2. 编辑 → 勾选 **App Groups** → 添加 `group.com.aether.app`
3. 为 Watch App ID (`com.aether.watch`) 和 Widget Extension ID (`com.aether.app.widgets`) 重复此步骤

### 1.3 已完成的 entitlements 文件

以下文件已创建/更新，包含 `com.apple.security.application-groups` → `group.com.aether.app`：

- `Aether/Aether.entitlements` — iOS/macOS 主 App（已添加 App Group）
- `AetherWatch/AetherWatch.entitlements` — watchOS App（已创建）
- Widget Extension 需创建 `AetherWidgets/AetherWidgets.entitlements`（步骤见下文）

---

## 2. 添加 watchOS App Target（Task 4）

### 2.1 创建 Target

1. 在 Xcode 中打开 `Aether.xcodeproj`
2. 菜单 **File → New → Target...**
3. 选择 **watchOS** 标签页 → **App**
4. 填写：
   - Product Name: `AetherWatch`
   - Bundle Identifier: `com.aether.watch`
   - Watch App: **Standalone Watch App**（独立 Watch App，非 Companion）
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Include Notification Scene: **取消勾选**
5. 点击 **Finish**
6. 如果 Xcode 弹出 "Activate scheme?" 对话框，点击 **Activate**

### 2.2 删除自动生成的文件

Xcode 会自动生成一些文件，需要删除或替换：

1. 删除 Xcode 自动生成的 `AetherWatchApp.swift`（因为 `AetherWatch/WatchApp.swift` 已存在且包含 `@main`）
2. 删除自动生成的 `ContentView.swift`、`Assets.xcassets`（如果有的话）

### 2.3 添加现有源文件到 Watch Target

1. 在 Project Navigator 中右键 `AetherWatch` 文件夹
2. **Add Files to "Aether"...**
3. 选择以下文件（勾选 **AetherWatch** target）：
   - `AetherWatch/WatchApp.swift`
   - `AetherWatch/Views/WatchQuickChatView.swift`
   - `AetherWatch/Views/WatchHealthInsightView.swift`
   - `AetherWatch/AetherWatch.entitlements`
   - `Shared/AppGroupContainer.swift`
4. 添加 SwiftData 模型文件（勾选 **AetherWatch** target）：
   - `Aether/Models/Conversation.swift`
   - `Aether/Models/ChatMessage.swift`
   - `Aether/Models/HealthInsight.swift`
   - `Aether/Models/DocumentChunk.swift`
   - `Aether/Models/MessageFeedback.swift`

### 2.4 配置 Build Settings

在 **AetherWatch** target 的 **Build Settings** 中：

| 设置 | 值 |
|---|---|
| WatchOS Deployment Target | `10.0` |
| Code Signing Entitlements | `AetherWatch/AetherWatch.entitlements` |
| Product Bundle Identifier | `com.aether.watch` |
| Development Team | `YZD665FDV5`（与主 App 一致） |
| Swift Version | `5.0` |

### 2.5 配置 Info.plist

在 AetherWatch target 的 Build Settings 中设置：
- `GENERATE_INFOPLIST_FILE = YES`（让 Xcode 自动生成）
- 或创建 `AetherWatch/Info.plist`，设置 `WKApplication=true`、`WKWatchOnly=true`

### 2.6 添加 Localizable.xcstrings（可选但推荐）

1. **Add Files to "Aether"...** → 选择 `Aether/Resources/Localizable.xcstrings`
2. 勾选 **AetherWatch** target
3. 确保 "Copy items if needed" **取消勾选**（共享同一文件）

---

## 3. 添加 Widget Extension Target（Task 5）

### 3.1 创建 Target

1. 菜单 **File → New → Target...**
2. 选择 **iOS** 标签页 → **Widget Extension**
3. 填写：
   - Product Name: `AetherWidgets`
   - Bundle Identifier: `com.aether.app.widgets`
   - Include Configuration App Intent: **勾选**
   - Embed in Application: **Aether**
4. 点击 **Finish**

### 3.2 删除自动生成的文件

1. 删除 Xcode 自动生成的 Widget 文件（如 `AetherWidgets.swift` 等）
2. 保留自动生成的 `Info.plist` 和 `Assets.xcassets`（如果有的话）

### 3.3 添加现有源文件到 Widget Target

1. **Add Files to "Aether"...** → 选择以下文件（勾选 **AetherWidgets** target）：
   - `AetherWidgets/AetherWidgetBundle.swift`
   - `AetherWidgets/QuickChatWidget.swift`
   - `AetherWidgets/HealthInsightWidget.swift`
   - `AetherWidgets/RecentConversationsWidget.swift`
   - `Shared/AppGroupContainer.swift`
2. 添加 SwiftData 模型文件（勾选 **AetherWidgets** target）：
   - `Aether/Models/Conversation.swift`
   - `Aether/Models/HealthInsight.swift`
   - `Aether/Models/ChatMessage.swift`（Conversation 的 @Relationship 依赖）
   - `Aether/Models/DocumentChunk.swift`
   - `Aether/Models/MessageFeedback.swift`

### 3.4 创建 Widget Entitlements

创建文件 `AetherWidgets/AetherWidgets.entitlements`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.aether.app</string>
    </array>
</dict>
</plist>
```

在 **AetherWidgets** target 的 Build Settings 中设置：
- `CODE_SIGN_ENTITLEMENTS = AetherWidgets/AetherWidgets.entitlements`

### 3.5 配置 Build Settings

| 设置 | 值 |
|---|---|
| iOS Deployment Target | `17.0` |
| Code Signing Entitlements | `AetherWidgets/AetherWidgets.entitlements` |
| Product Bundle Identifier | `com.aether.app.widgets` |
| Development Team | `YZD665FDV5` |
| Swift Version | `5.0` |

### 3.6 添加 Localizable.xcstrings

1. **Add Files to "Aether"...** → 选择 `Aether/Resources/Localizable.xcstrings`
2. 勾选 **AetherWidgets** target
3. "Copy items if needed" **取消勾选**

---

## 4. 共享文件配置

### 4.1 共享源文件 Target Membership

以下文件需添加到多个 target 的 Compile Sources：

| 文件 | Aether (iOS/macOS) | AetherWatch (watchOS) | AetherWidgets (Widget) |
|---|---|---|---|
| `Shared/AppGroupContainer.swift` | ✅ | ✅ | ✅ |
| `Aether/Models/Conversation.swift` | ✅ | ✅ | ✅ |
| `Aether/Models/ChatMessage.swift` | ✅ | ✅ | ✅ |
| `Aether/Models/HealthInsight.swift` | ✅ | ✅ | ✅ |
| `Aether/Models/DocumentChunk.swift` | ✅ | ✅ | ✅ |
| `Aether/Models/MessageFeedback.swift` | ✅ | ✅ | ✅ |
| `AetherWatch/WatchApp.swift` | ❌ | ✅ | ❌ |
| `AetherWatch/Views/*.swift` | ❌ | ✅ | ❌ |
| `AetherWidgets/*.swift` | ❌ | ❌ | ✅ |

### 4.2 共享 Assets.xcassets（可选）

如果 Widget/Watch 需要使用主 App 的自定义颜色（如 `AetherPurple`、`DeepSpace` 等）：

1. **Add Files to "Aether"...** → 选择 `Aether/Resources/Assets.xcassets`
2. 勾选 **AetherWidgets** 和/或 **AetherWatch** target
3. "Copy items if needed" **取消勾选**

> 注意：Watch 和 Widget 的 Assets.xcassets 可能与主 App 的冲突。建议为 Watch/Widget 创建独立的 Assets.xcassets，仅包含所需色板。

---

## 5. URL Scheme 配置

### 5.1 主 App URL Scheme（已完成）

`Aether/Resources/Info.plist` 已添加 `aether://` URL Scheme：

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.aether.app</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>aether</string>
        </array>
    </dict>
</array>
```

### 5.2 支持的 Deeplink 格式

| URL | 行为 |
|---|---|
| `aether://conversation/<uuid>` | 切换到指定会话 |
| `aether://ask?query=<encoded>` | 填入问题并发送（Widget 快速对话入口） |

---

## 6. 验证清单

### 6.1 Watch App 验证

- [ ] AetherWatch target 编译成功
- [ ] Watch 模拟器启动后显示 TabView（快速对话 + 健康洞察两个页面）
- [ ] 快速对话页可以发送消息（预设按钮 + 自定义输入）
- [ ] 健康洞察页显示最近一条 HealthInsight（或空状态）
- [ ] Watch 发送消息后，iOS App 前台时收到 `.wcQuickChatReceived` 通知并写入当前会话
- [ ] Watch 发送消息时 iOS App 不在前台，通过 `transferUserInfo` 后台投递，App 下次启动时收到

### 6.2 Widget 验证

- [ ] AetherWidgets target 编译成功
- [ ] 主屏幕可添加三种 Widget（快速对话、健康洞察、最近会话）
- [ ] 快速对话 Widget：Small 显示 1 个预设，Medium 显示 2x2 网格
- [ ] 快速对话 Widget 点击后打开 App 并自动发送问题
- [ ] 健康洞察 Widget：显示最新 HealthInsight 内容
- [ ] 最近会话 Widget：显示最近 3 条会话标题
- [ ] 最近会话 Widget 点击后打开 App 并切换到对应会话

### 6.3 共享数据验证

- [ ] iOS App 写入 HealthInsight 后，Watch 健康洞察页和 Widget 均可读取
- [ ] iOS App 创建会话后，最近会话 Widget 可显示
- [ ] App Group 容器中存在 `Aether.sqlite` 文件

---

## 文件清单

### 新建文件

| 路径 | 说明 |
|---|---|
| `AetherWatch/AetherWatch.entitlements` | Watch App 的 App Group entitlements |
| `Shared/AppGroupContainer.swift` | App Group 共享容器辅助工具 |
| `AetherWidgets/AetherWidgetBundle.swift` | Widget Bundle 入口 |
| `AetherWidgets/QuickChatWidget.swift` | 快速对话 Widget |
| `AetherWidgets/HealthInsightWidget.swift` | 健康洞察 Widget |
| `AetherWidgets/RecentConversationsWidget.swift` | 最近会话 Widget |

### 修改文件

| 路径 | 修改内容 |
|---|---|
| `Aether/Aether.entitlements` | 添加 `com.apple.security.application-groups` |
| `Aether/Resources/Info.plist` | 添加 `aether://` URL Scheme |
| `AetherWatch/WatchApp.swift` | 添加 TabView 连接 QuickChat + HealthInsight；使用 AppGroupContainer |
| `AetherWatch/Views/WatchQuickChatView.swift` | 本地化文案；添加 transferUserInfo 后台投递 |
| `AetherWatch/Views/WatchHealthInsightView.swift` | 本地化文案 |
| `Aether/Services/Connectivity/WatchConnectivityService.swift` | 添加 `didReceiveUserInfo` 后台消息处理 |
| `Aether/AppIntents/AskAetherIntent.swift` | 添加 `openAppWhenRun = true` |
| `Aether/ViewModels/ChatViewModel.swift` | 订阅 `.wcQuickChatReceived` 通知 |
| `Aether/Views/Chat/ChatView.swift` | 添加 `pendingWatchMessage` 观察处理；扩展 deeplink 支持 `aether://ask` |
