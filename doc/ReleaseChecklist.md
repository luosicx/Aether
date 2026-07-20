# Aether 上架前发布检查清单

> Day 20 上架准备：Archive / TestFlight / App Store 元数据 / 审核信息 / 提交审核前最终检查

## 1. Archive 检查

- [ ] Xcode 中 Scheme 选择 `Aether` → Destination 选 `Generic iOS Device`（Any iOS Simulator Device 亦可触发 Archive）
- [ ] Product → Archive，等待归档完成
- [ ] 验证 Archive 过程中无 warning（特别注意：隐私清单缺失 / Info.plist 引用错误 / unused import）
- [ ] 在 Xcode Organizer 中确认生成的 `.xcarchive` 文件有效

## 2. TestFlight 上传

- [ ] Xcode Organizer → 选择最新 Archive → Distribute App
- [ ] 分发方式选择 `TestFlight App Store`（内部测试）
- [ ] 上传选项：保持默认（Include bitcode for iOS content / Upload symbols）
- [ ] 等待 Apple 处理（通常 10-30 分钟）
- [ ] 在 App Store Connect → TestFlight 标签确认构建版本已出现
- [ ] 邀请内部测试员并完成首次安装验证

## 3. App Store 元数据

### 3.1 基本信息
- [ ] **名称**：以太（30 字符内，符合 App Store 命名规范）
- [ ] **副标题**：AI 对话助手（30 字符内，突出核心功能）
- [ ] **描述**：覆盖 SwiftUI + SwiftData + 流式对话 / RAG / 工具调用 / 健康洞察等核心特性
- [ ] **关键词**：AI / Chat / 对话 / 助手 / 健康（100 字符内，逗号分隔）
- [ ] **推广文本**：可选，用于临时公告（170 字符内）

### 3.2 截图与预览
- [ ] **6.7" 截图**（iPhone 14 Pro Max / 15 Pro Max）：至少 1 张，建议全部 5-10 张
  - 主对话页 / 设置页 / 健康洞察 / 知识库 / 端侧推理
- [ ] **6.1" 截图**（iPhone 15 Pro）：至少 1 张
- [ ] **App 预览视频**（可选）：30 秒内，展示流式对话核心交互

### 3.3 其他
- [ ] **App 分类**：Productivity 或 Utilities
- [ ] **版权**：© 2026 [开发者/公司名]
- [ ] **URL**：可选，指向产品官网
- [ ] **支持 URL**：指向 feedback@aether.app 或支持页面

## 4. 审核信息

- [ ] **年龄分级**：4+（无不适内容，需在 App Store Connect 中确认问卷）
- [ ] **隐私清单**：在 App Store Connect → App 隐私中如实填写
  - 收集数据类型：对话内容 / 健康数据 / 性能数据 / 崩溃数据
  - 用途：App 功能 / 分析
  - 与用户身份关联：是
  - 用于追踪：否
- [ ] **隐私政策 URL**：指向 App 内隐私政策或可访问的网页版本
- [ ] **权限说明**：Info.plist 中已声明 NSHealthShareUsageDescription / NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription / NSRemindersUsageDescription / NSCalendarsUsageDescription
- [ ] **第三方 SDK 声明**：Bugly / DeepSeek API / Qwen API（在隐私清单中如实披露）
- [ ] **新功能测试方式说明**（建议在审核备注中向 Apple 说明以下新功能的验证路径）：
  - **TTS 音色配置**：进入 设置 → 语音朗读，选择不同音色（系统内置 / AVSpeechSynthesisVoice），调节语速 / 音调 / 音量滑块，点击「试听」预览，发送一条助手回复并点击朗读，验证朗读使用所选音色与参数
  - **Markdown 渲染**：发送一条可触发包含代码块（```swift）、表格、任务列表（- [ ]）、多级标题（#/##/###）的助手回复，验证代码块语法高亮、表格对齐、任务列表勾选状态、标题层级缩进渲染正确
  - **端侧 MLX 模型下载**：进入 设置 → 端侧推理，选择模型（如 Qwen2.5-0.5B-Instruct）开始下载，验证下载进度条更新、中断后重启可断点续传、下载完成自动执行 SHA256 校验；关闭网络后发起对话，验证自动切换为端侧推理并在 UI 标识
  - **HealthKit 授权**：首次进入 设置 → 健康洞察，验证系统弹出 HealthKit 授权弹窗并请求心率 / 睡眠 / 步数读取权限；授权后下拉刷新健康洞察，验证数据读取成功；在对话中验证健康上下文已注入 system prompt（助手可引用近 7 天健康数据）

### 4.1 构建验证
- [ ] iOS 构建：`xcodebuild build -destination 'platform=iOS Simulator,name=iPhone 17'` 成功
- [ ] macOS 构建：`xcodebuild build -destination 'platform=macOS'` 成功
- [ ] 双端构建均无警告（或警告已审查）

### 4.2 工具数量审计
- [ ] iOS 工具数：14 个（14 个跨平台工具，无条件注册）
- [ ] macOS 工具数：25 个（14 跨平台 + 11 macOS 独有 AppleScriptTool/ScreenshotTool/OCRTool/TerminalCommandTool/WindowManagementTool/AppManagementTool/FileOperationTool/FinderTool/SafariControlTool/SystemControlTool/InputAutomationTool）
- [ ] ToolRegistry.swift 注册数验证：14 个跨平台工具无条件注册，11 个 macOS 独有工具用 `#if os(macOS)` 条件注册

### 4.3 测试规模
- [ ] UT 用例数：2771
- [ ] UIT 用例数：30
- [ ] iOS UT 运行：`xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` 全部通过（0 skipped，0 failures）
- [ ] UIT 运行全部通过（0 failures）

### 4.4 预设提示词功能验证
- [ ] 11 个预设角色可正常选择并填入 TextEditor
- [ ] 每个预设 prompt ≥ 150 字（默认助手除外）
- [ ] 预设填入后可编辑
- [ ] PresetPromptsTests 4 个用例通过

### 4.5 macOS 体验修复验证
- [ ] macOS 设置二级页有返回按钮可关闭
- [ ] macOS markdown 表格/气泡视觉层次正常
- [ ] macOS 语音朗读不卡顿、按钮状态正常
- [ ] iOS 端不受影响

### 4.6 工具项中文化验证
- [ ] Settings 偏好工具列表显示中文 description
- [ ] preferredTools 存储仍用英文 name

### 4.7 代码注释验证
- [ ] 18 个工具文件有文件级 `///` 注释
- [ ] ToolRegistry.swift 有注册逻辑注释

## 4.8 国际化与无障碍审计

- [ ] `Localizable.xcstrings` 包含 888 keys，8 种语言（zh-Hans / zh-Hant / en / ja / ko / fr / de / es）翻译完整
- [ ] 设置 → 语言切换（9 选项：跟随系统 + 8 种语言）后重启，各语言界面无残留中文
- [ ] VoiceOver 可朗读设置页所有 Toggle / Picker / Button
- [ ] 所有关键交互控件存在 `accessibilityIdentifier`（供 UITest 使用，当前覆盖 13 个元素）
- [ ] Dynamic Type XL 下设置页 Toggle / Picker 行不截断
- [ ] Watch App 与 LaunchScreen 含无障碍标签（accessibilityLabel）

## 4.9 截图与元数据审计

- [ ] `screenshots/` 目录包含 8 张核心页面截图
- [ ] README.md 截图表格渲染正常
- [ ] App Store Connect 已上传 6.7" / 6.1" / iPad / macOS 截图

## 4.10 多平台构建验证

### iOS 构建
- [ ] 执行命令构建 iOS Simulator 版本：
  ```bash
  xcodebuild build \
    -project Aether.xcodeproj \
    -scheme Aether-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO
  ```
- [ ] 预期输出：`** BUILD SUCCEEDED **`
- [ ] 无 warning（特别注意 unused import / deprecated API）

### macOS 构建
- [ ] 执行命令构建 macOS 版本：
  ```bash
  xcodebuild build \
    -project Aether.xcodeproj \
    -scheme Aether-macOS \
    -destination 'platform=macOS' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO
  ```
- [ ] 预期输出：`** BUILD SUCCEEDED **`
- [ ] macOS 独有工具用 `#if os(macOS)` 守卫，iOS 构建不报错
- [ ] iOS-only 框架（BGTaskScheduler / ActivityKit / HealthKit / WatchConnectivity）用 `#if os(iOS)` 守卫，macOS 构建不报错

## 4.11 工具数量审计

- [ ] iOS 工具数 = 14（14 个跨平台工具）
- [ ] macOS 工具数 = 25（14 跨平台 + 11 macOS 独有）
- [ ] 验证命令：
  ```bash
  # 在 Xcode 中运行 Debug Playground 或在 ChatViewModel 加日志：
  # print("Tools count: \(ToolRegistry.shared.allToolDefs.count)")
  ```
- [ ] 预期：iOS 14，macOS 25
- [ ] ToolRegistry 注册逻辑：14 个跨平台工具无条件注册 + 11 个 macOS 工具用 `#if os(macOS)` 条件注册

## 4.12 测试规模审计

### 单元测试（UT）
- [ ] UT 用例数 = 2771（2771 pass / 0 skip / 0 failures）
- [ ] UT 文件数 = 157
- [ ] 验证命令：
  ```bash
  xcodebuild test \
    -project Aether.xcodeproj \
    -scheme Aether-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:AetherTests \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  ```
- [ ] 预期输出包含：`Executed 2771 tests, with 0 failures, 0 skipped`

### UI 测试（UIT）
- [ ] UIT 用例数 = 30（30 pass / 0 skip / 0 failures）
- [ ] UIT 文件数 = 7
- [ ] 验证命令：
  ```bash
  xcodebuild test \
    -project Aether.xcodeproj \
    -scheme Aether-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:AetherUITests \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  ```
- [ ] 预期输出包含：`Executed 30 tests, with 0 failures, 0 skipped`

## 4.13 文档完整性审计

- [ ] `doc/ARCHITECTURE.md` 存在且章节完整（1-8）
- [ ] `doc/USAGE.md` 存在且章节完整（1-10）
- [ ] `doc/MANUAL_TEST_CHECKLIST.md` 存在且手测项完整
- [ ] `doc/ReleaseChecklist.md` 存在且 4.1-4.14 审计项完整
- [ ] `doc/BFF_DEPLOYMENT.md` 存在且部署步骤完整
- [ ] `doc/CONTRIBUTING.md` 存在（贡献指南）
- [ ] `doc/CHANGELOG.md` 存在（变更日志）
- [ ] `doc/API.md` 存在（API 契约文档）
- [ ] `README.md` 详细文档章节含 8 个文档链接
- [ ] 文档间交叉引用链接全部有效（点击不报 404）

## 4.14 国际化与无障碍审计

### 国际化
- [ ] `Localizable.xcstrings` 存在且已注册到 Resources build phase
- [ ] `developmentRegion = zh-Hans`，`knownRegions` 含 `zh-Hans` / `zh-Hant` / `en` / `ja` / `ko` / `fr` / `de` / `es` / `Base`
- [ ] SwiftUI `Text`/`Button`/`TextField` 字面量在构建后自动提取到 String Catalog
- [ ] 验证命令：
  ```bash
  # 构建后检查 .xcstrings 是否被编译为 .loctable
  ls ~/Library/Developer/Xcode/DerivedData/Aether-*/Build/Products/Debug-iphonesimulator/Aether.app/*.lproj/
  ```

### 无障碍
- [ ] 13 个视图含 `accessibilityLabel`（MarkdownText / CodeBlockView / MarkdownTableView / HeadingView / ErrorOverlay / CitationCard / ConversationRow / OnDeviceModelView / KnowledgeBaseView / HealthSettingsView / PrivacyPolicyView / DocumentPickerView / PresetPrompts）
- [ ] 13 个关键交互元素含 `accessibilityIdentifier`（sendButton / messageInputField / voiceInputButton / knowledgeBaseButton / settingsButton / conversationListButton / newConversationButton / importDocumentButton / downloadModelButton / deleteModelButton / requestHealthAuthButton / thumbsUpButton / thumbsDownButton）
- [ ] VoiceOver 开启后能正确朗读各视图标签与提示

## 4.15 SwiftLint 静态分析

- [ ] SwiftLint 已安装（`brew install swiftlint` 或通过 SPM 集成）
- [ ] `.swiftlint.yml` 配置文件存在于项目根目录
- [ ] 执行 SwiftLint 检查：
  ```bash
  swiftlint lint --path Aether --reporter emoji
  ```
- [ ] 预期输出：0 serious / 0 violations（或所有 warning 已审查并标记 `// swiftlint:disable`）
- [ ] Xcode Build Phase 中 SwiftLint Run Script 已配置（构建时自动触发）
- [ ] 提交前确认无新增 SwiftLint violation

## 4.16 Watch App 构建验证

> ⚠️ Watch App target 需在 Xcode 中手动创建并关联 `AetherWatch/` 源文件。

- [ ] Watch target 已创建，Bundle ID 为 `<主 App Bundle ID>.watchkitapp`
- [ ] `AetherWatch/` 目录下 3 个源文件已添加到 Watch target
- [ ] Watch target Signing & Capabilities 已添加 App Group `group.com.aether.app`
- [ ] Watch target Deployment Target 设为 watchOS 10+
- [ ] Watch App 构建成功：
  ```bash
  xcodebuild build \
    -project Aether.xcodeproj \
    -scheme AetherWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
    -configuration Debug
  ```
- [ ] 预期输出：`** BUILD SUCCEEDED **`
- [ ] Watch App 在 Apple Watch 模拟器中启动，TabView 三标签正常显示
- [ ] WatchConnectivity 与 iPhone 主 App 配对通信正常

## 4.17 Widget Extension 构建验证

> ⚠️ Widget Extension target 需在 Xcode 中手动创建并关联 `AetherWidgets/` 源文件。

- [ ] Widget target 已创建，Bundle ID 为 `<主 App Bundle ID>.widgets`
- [ ] `AetherWidgets/` 目录下 4 个源文件已添加到 Widget target
- [ ] Widget target Signing & Capabilities 已添加 App Group `group.com.aether.app`
- [ ] Widget target Deployment Target 设为 iOS 17+
- [ ] Widget Extension 构建成功：
  ```bash
  xcodebuild build \
    -project Aether.xcodeproj \
    -scheme AetherWidgets \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -configuration Debug
  ```
- [ ] 预期输出：`** BUILD SUCCEEDED **`
- [ ] 主屏幕添加 3 个 Widget（QuickChat / HealthInsight / RecentConversations）均正常显示
- [ ] Widget 通过 App Group 共享 SwiftData 可读取主 App 数据
- [ ] Widget deepLink 跳转（`aether://ask?query=` / `aether://conversation/<uuid>`）正常

## 4.18 MLX 端侧推理 SPM 解析检查

- [ ] `mlx-swift` SPM 依赖已添加到主 App target（`https://github.com/ml-explore/mlx-swift`）
- [ ] Xcode → File → Packages → Package Dependencies 中 mlx-swift 解析成功（无红色错误）
- [ ] mlx-swift 依赖版本与 mlx-swift-examples 兼容
- [ ] 真机构建时 MLX 模块可正常 import（`import MLX` / `import MLXLLM` / `import MLXTokenizerUtils`）
- [ ] 模拟器构建走占位实现（`OfflineLLMProvider` 不依赖 mlx-swift 编译），无链接错误
- [ ] 端侧模型下载（Llama-3.2-1B-Instruct Q4_K_M）在真机上可正常加载与推理

## 4.19 DeepLink 验证

- [ ] Info.plist 含 `CFBundleURLTypes`，URL Scheme 为 `aether`
- [ ] `aether://ask?query=你好` 在 Safari 中打开后跳转主 App 并自动发送消息
- [ ] `aether://conversation/<uuid>` 跳转到指定会话（uuid 为有效会话 ID）
- [ ] 无效 uuid 的 DeepLink 显示错误提示而非崩溃
- [ ] macOS 端 DeepLink 同样可用（通过 `open aether://ask?query=test` 命令测试）

## 4.20 App Group 共享 SwiftData 验证

- [ ] 主 App target Signing & Capabilities 已添加 App Group `group.com.aether.app`
- [ ] Widget target Signing & Capabilities 已添加相同 App Group
- [ ] Watch target Signing & Capabilities 已添加相同 App Group（如已创建 Watch target）
- [ ] 主 App 创建会话后，Widget 可读取该会话数据
- [ ] 主 App 生成健康洞察后，Widget 与 Watch App 可读取该洞察
- [ ] App Group 容器路径正确：
  ```swift
  FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aether.app")
  ```

## 4.21 xcframework 构建验证

> Rust `aether-core-ffi` crate 编译为三架构 xcframework，作为 `AetherRustBin` binaryTarget 被 Swift Package 引用。

- [ ] Rust 工具链已安装（`rustup show` 确认 Rust 1.75+）
- [ ] iOS/macOS 交叉编译目标已安装：
  ```bash
  rustup target add aarch64-apple-ios aarch64-apple-ios-simulator aarch64-apple-darwin
  ```
- [ ] aether-core 纯逻辑 crate 编译通过：
  ```bash
  cd rust/aether-core && cargo build
  ```
- [ ] aether-core-ffi C ABI 绑定层编译通过（三架构）：
  ```bash
  cd rust/aether-core-ffi
  cargo build --target aarch64-apple-ios
  cargo build --target aarch64-apple-ios-simulator
  cargo build --target aarch64-apple-darwin
  ```
- [ ] cbindgen 生成 C 头文件正确：
  ```bash
  cd rust/aether-core-ffi && cbindgen --config cbindgen.toml --crate aether-core-ffi --output aether_core_ffi.h
  ```
- [ ] 头文件 `aether_core_ffi.h` 包含所有 10 个模块的 FFI 函数声明（sha256_* / token_* / chunker_* / vector_* / sse_* / sandbox_* / inference_* / ratelimit_* / redact_* / free_string），有 `AETHER_CORE_FFI_H` include guard
- [ ] xcframework 打包成功：
  ```bash
  xcodebuild -create-xcframework \
    -library rust/aether-core-ffi/target/aarch64-apple-ios/release/libaether_core_ffi.a \
    -headers rust/aether-core-ffi/aether_core_ffi.h \
    -library rust/aether-core-ffi/target/aarch64-apple-ios-simulator/release/libaether_core_ffi.a \
    -headers rust/aether-core-ffi/aether_core_ffi.h \
    -library rust/aether-core-ffi/target/aarch64-apple-darwin/release/libaether_core_ffi.a \
    -headers rust/aether-core-ffi/aether_core_ffi.h \
    -output Packages/AetherCore/aether_core.xcframework
  ```
- [ ] xcframework 含三个 slice：
  ```bash
  xcodebuild -check-xcframework Packages/AetherCore/aether_core.xcframework
  ```
  预期输出：`ios-arm64: OK` / `ios-arm64-simulator: OK` / `macos-arm64: OK`
- [ ] `Package.swift` 中 `AetherRustBin` binaryTarget 指向 xcframework 路径正确
- [ ] `module.modulemap` 存在于 xcframework 各 slice 的 `Headers/` 目录中
- [ ] AetherRust Swift 10 个包装器文件编译通过（`Packages/AetherCore/Sources/AetherRust/*.swift`）
- [ ] AetherCore 单元测试通过：
  ```bash
  cd Packages/AetherCore && swift test
  ```

## 5. 提交审核前最终检查

### 5.1 功能验证
- [ ] **API Key 测试**：DeepSeek / Qwen 两个 provider 都能正常发起对话
- [ ] **网络异常测试**：断网时端侧推理自动切换，联网后切回云端
- [ ] **权限测试**：HealthKit / 麦克风 / 语音识别 / 日历 / 提醒事项均能在首次使用时弹窗授权
- [ ] **后台任务**：每日刷新 / 遥测上报 / 健康洞察生成均能在 BGTaskScheduler 中正常调度

### 5.2 稳定性验证
- [ ] **崩溃监控**：Bugly 已初始化，匿名用户 ID 已设置
- [ ] **错误上报**：LLM 错误已通过 CrashReportService 上报到 Bugly
- [ ] **日志上传**：TelemetryService 缓冲事件能批量上报到 BFF

### 5.3 隐私合规
- [ ] **PrivacyInfo.xcprivacy** 已包含在 Resources build phase
- [ ] **隐私清单中 API Reason**：UserDefaults (CA92.1) / FileTimestamp (C617.1) / SystemBootTime (35F9.1)
- [ ] **不追踪用户**：NSPrivacyTracking = false
- [ ] **数据收集最小化**：仅收集 App 功能与分析所需数据

### 5.4 可访问性
- [ ] VoiceOver 能正确朗读主要控件
- [ ] 动态字体（Dynamic Type）适配正常
- [ ] 高对比度模式 UI 可读

## 6. 产物命名规则

为统一各平台 Release 资产命名，便于用户识别与脚本化校验，所有 Release 产物遵循以下规则。

### 6.1 命名格式

```
Aether-{Platform}-{version}[-{qualifier}].{ext}
```

- `Platform`：iOS / macOS / Android / Windows / BFF
- `version`：与 tag 版本号一致（如 `1.2.0`）
- `qualifier`：可选，仅在区分构建变体时使用（如 `-unsigned` / `-x64`）
- `ext`：文件扩展名（zip / dmg / apk / tar.gz）

### 6.2 各平台产物

| 平台 | 文件名 | 说明 |
| --- | --- | --- |
| iOS | `Aether-iOS-{version}.zip` | iOS Simulator 构建产物 |
| macOS | `Aether-macOS-{version}.dmg` | 签名 + 公证模式 |
| macOS | `Aether-macOS-{version}-unsigned.dmg` | 未签名模式（qualifier=`-unsigned`） |
| Android | `Aether-Android-{version}.apk` | |
| Windows | `Aether-Windows-{version}-x64.zip` | qualifier=`-x64` |
| BFF | `Aether-BFF-{version}.zip` | |
| Source | `Aether-{version}-source.tar.gz` | 源码 tarball |
| Source | `Aether-{version}-source.zip` | 源码 zip |

### 6.3 校验文件

每个 Release 资产附带同名 `.sha256` 校验文件（如 `Aether-macOS-1.2.0.dmg.sha256`），内容为对应文件的 SHA256 哈希值，格式兼容 `shasum -c` 命令（详见第 8 节）。

## 7. macOS DMG 签名与公证

### 7.1 CI 自动判断逻辑

`release.yml` 的 `build-macos` job 根据仓库 Secrets 配置自动判断签名模式：

- 当仓库配置了以下 4 个 secrets 时，自动调用 `./scripts/build-dmg.sh --signed --notarize`：
  - `DEVELOPER_ID_APPLICATION`
  - `APPLE_ID`
  - `APP_SPECIFIC_PASSWORD`
  - `TEAM_ID`
- 否则回退至 unsigned 模式，调用 `./scripts/build-dmg.sh --unsigned`

### 7.2 产物命名

| 模式 | 产物文件名 |
| --- | --- |
| 签名 + 公证 | `Aether-macOS-{version}.dmg` |
| 未签名 | `Aether-macOS-{version}-unsigned.dmg` |

### 7.3 未签名模式 Release 备注

未签名模式下，Release body 中包含以下提示：

> ⚠️ macOS DMG 未签名，首次打开需右键 → 打开绕过 Gatekeeper

### 7.4 启用签名模式

在仓库 Settings → Secrets and variables → Actions 中配置以下 4 个 secrets 即可启用签名与公证：

| Secret | 说明 |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | 签名身份，如 `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID 账号邮箱 |
| `APP_SPECIFIC_PASSWORD` | 在 https://appleid.apple.com 生成的 App-Specific Password |
| `TEAM_ID` | Apple Developer Team ID |

配置完成后，推送 `v*` tag 触发 release.yml 将自动产出签名与公证的 DMG；未配置 secrets 时自动回退 unsigned 模式，Release notes 中标注"未签名版本"。

## 8. 产物 SHA256 校验

每个 Release 资产附 `.sha256` 校验文件，用户下载产物后可执行校验命令验证完整性。

### 8.1 校验命令

下载产物与对应 `.sha256` 文件后，执行：

```bash
shasum -a 256 -c Aether-macOS-1.2.0.dmg.sha256
# 预期输出：Aether-macOS-1.2.0.dmg: OK
```

### 8.2 说明

- 校验文件格式兼容 `shasum -c` 命令，无需手动比对哈希值
- 各平台通用：iOS / macOS / Android / Windows / BFF / Source 资产均附 `.sha256`
- 若校验失败（输出 `FAILED`），请重新下载产物并再次校验

## 9. 提交审核

- [ ] 在 App Store Connect 选择构建版本 → 添加审核备注
- [ ] 审核备注中说明：测试账号（如有）/ 触发特定功能的方法（如端侧模型下载）/ HealthKit 测试方式
- [ ] 审核备注中追加新功能测试方式说明：
  - **TTS 音色配置**：设置 → 语音朗读，切换不同音色、调节语速 / 音调 / 音量、点击试听预览，验证朗读使用所选音色
  - **Markdown 渲染**：发送包含代码块 / 表格 / 任务列表 / 多级标题的助手回复，验证渲染正确
  - **端侧 MLX 模型下载**：设置 → 端侧推理中下载模型，验证下载进度、断点续传、SHA256 校验；断网后自动切换端侧推理
  - **HealthKit 授权**：首次进入健康设置请求授权，验证心率 / 睡眠 / 步数读取，验证健康上下文注入 system prompt
- [ ] 提交审核，等待 Apple 审核反馈（通常 24-48 小时）
