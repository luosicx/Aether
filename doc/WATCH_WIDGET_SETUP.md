# Watch/Widget 构建调试指南

本指南说明 Aether 的 watchOS App（`AetherWatch`）与 Widget Extension（`AetherWidgets`）的构建、调试与已知限制。

> **重要**：Watch App 与 Widget Extension 的 target 已存在于 `Aether.xcodeproj/project.pbxproj` 中，对应的 scheme（`AetherWatch` / `AetherWidgets`）也已生成，**无需在 Xcode 中手动创建 target**。本指南仅关注构建与调试。

---

## 1. 概述

| Target | Scheme | 平台 | 说明 |
|--------|--------|------|------|
| `AetherWatch` | `AetherWatch` | watchOS 10+ | Watch 快速对话 + 健康洞察，源码位于 `AetherWatch/` |
| `AetherWidgets` | `AetherWidgets` | iOS 17+ | 三个 Widget（QuickChat / HealthInsight / RecentConversations），源码位于 `AetherWidgets/` |

两个 target 均已配置好 App Group entitlements 与源文件 membership，开箱即可构建。

---

## 2. 构建方法

### 2.1 命令行（推荐）

项目根目录执行：

```bash
# 构建 Watch App
make build-watch

# 构建 Widget Extension
make build-widget
```

底层等价命令（`make` 目标内部调用）：

```bash
# Watch
xcodebuild build \
  -project Aether.xcodeproj \
  -scheme AetherWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  -configuration Debug

# Widget
xcodebuild build \
  -project Aether.xcodeproj \
  -scheme AetherWidgets \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug
```

### 2.2 Xcode

1. 打开 `Aether.xcodeproj`
2. 在顶部 **scheme 选择器**中选择 `AetherWatch` 或 `AetherWidgets`
3. 选择对应的目标设备（Watch 模拟器 / iPhone 模拟器）
4. `Cmd + R` 运行，或 `Cmd + B` 仅构建

---

## 3. App Group 配置

Watch App、Widget Extension 与主 App 通过 App Group 共享 SwiftData 存储：

- **App Group Identifier**：`group.com.aether.app`
- **共享内容**：`Conversation` / `ChatMessage` / `HealthInsight` 等 SwiftData 模型
- **容器路径**：`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aether.app")`

各 target 的 entitlements 文件已配置 `com.apple.security.application-groups`：

- `Aether/Aether.entitlements`（iOS/macOS 主 App）
- `AetherWatch/AetherWatch.entitlements`（watchOS App）
- `AetherWidgets/AetherWidgets.entitlements`（Widget Extension）

> Widget 与 Watch 为只读访问主 App 数据，不可通过 Widget/Watch 修改 SwiftData。

---

## 4. 已知限制

### 4.1 Xcode beta SwiftData macro plugin server bug

在某些 Xcode beta 版本中，SwiftData `@Model` 宏的 macro plugin server 存在 bug，可能导致 Watch / Widget 作为独立 target 单独构建时失败（表现为主 App 构建正常，但 Watch/Widget standalone build 报 macro 相关错误）。

**规避方式**：
- 优先使用正式版 Xcode 16+
- 或先构建主 App（`make build-ios`），再构建 Watch/Widget
- 或在 Xcode 中以主 App scheme 运行（Watch/Widget 作为依赖被一起编译）

### 4.2 独立 target，不嵌入主 App

Watch App 与 Widget Extension 作为**独立 target** 存在于工程中，**未嵌入主 App** 的 Embed 阶段。这意味着：

- 构建产物独立输出，不会自动打包进 `Aether.app`
- 调试时需单独选择对应 scheme 运行
- 发布前若需将 Widget 打入主 App，需在主 App target 的 Build Phases → Embed App Extensions 中补充配置

### 4.3 未在 CI 中构建

当前 CI（`.github/workflows/ci.yml`）仅构建并测试主 App（`Aether-iOS` scheme），**Watch 与 Widget 不在 CI 构建矩阵中**。因此：

- Watch/Widget 的构建回归需在本地手动验证
- 提交涉及 `AetherWatch/` 或 `AetherWidgets/` 的改动时，请本地执行 `make build-watch` / `make build-widget` 确认通过
