# 贡献指南

感谢你对 Aether 项目的兴趣！本文档描述如何参与项目开发，包括环境搭建、代码规范、提交规范与 PR 流程。

## 1. 开发环境搭建

### 1.1 系统要求

| 项 | 要求 | 说明 |
|---|---|---|
| macOS | 14+ | 编译 iOS / macOS 双端 |
| Xcode | 16+ | 编译 SwiftData / Observation 等新 API |
| iOS Deployment Target | 17.0+ | 真机与模拟器均需 ≥ iOS 17 |
| macOS Deployment Target | 14+ | macOS 目标平台 |
| Git | 2.30+ | 提交与 PR |
| Node.js（可选） | 20+ | 部署 BFF Cloudflare Workers 时使用 |
| Android（可选） | Android Studio Hedgehog+ / JDK 17 / Android SDK 35（Build Tools 35.0.0）/ Kotlin 1.9+ / NDK r25+ / Gradle 8.7 | Gradle 8.7 已随仓库提交 `gradlew`，无需手动安装；NDK 用于编译 Rust .so；可选 Rust 1.75+ 与 target `aarch64-linux-android` + `x86_64-linux-android` |
| Windows（可选） | Windows 10/11 x64 / .NET 8 SDK / Visual Studio 2022 或 VS Code / Rust 1.75+（可选） | 构建 WPF Windows 客户端时使用；可选 Rust target `x86_64-pc-windows-msvc` 生成 `aether_core_ffi.dll` |

### 1.2 获取源码

```bash
git clone <your-fork-url>
cd Aether
open Aether.xcodeproj
```

### 1.3 安装依赖

- 项目主体无需第三方包管理器（CocoaPods / SPM 仅可选 mlx-swift 端侧推理）
- 如需启用端侧推理：在 Xcode → File → Add Package Dependencies 添加 mlx-swift
- BFF 部署：`npm install -g wrangler`

### 1.4 首次运行

1. Xcode 顶部 Scheme 选择 `Aether-iOS / Aether-macOS / AetherWatch / AetherWidgets`
2. 目标设备选择 **iPhone 17 模拟器**（iOS 测试）或 **My Mac**（macOS 测试）
3. 按 `Cmd + R` 运行
4. App 启动后进入设置填入 DeepSeek API Key（https://platform.deepseek.com 申请）

### 1.5 快捷构建命令

项目根目录的 `Makefile` 封装了全平台构建命令，无需手敲 `xcodebuild` / `gradlew` / `dotnet`：

**构建**

| 平台 | 命令 | 说明 |
|------|------|------|
| Apple - iOS | `make build-ios` | 构建 iOS Simulator 版本 |
| Apple - macOS | `make build-macos` | 构建 macOS 版本 |
| Apple - Watch | `make build-watch` | 构建 watchOS App |
| Apple - Widget | `make build-widget` | 构建 Widget Extension |
| Android | `make build-android` | 构建 Debug APK |
| Windows | `make build-windows` | 在 Windows 上执行（需 `make` 与 `pwsh`） |

**Rust 与测试**

| 类型 | 命令 |
|------|------|
| Rust 单元测试 | `make test-rust` |
| iOS 测试 | `make test-ios` |
| macOS 测试 | `make test-macos` |
| 单元测试 | `make test-unit` |

**清理**：`make clean`

> 各 `make` 目标内部调用 `scripts/build-*.sh` / `scripts/build-*.ps1`，也可直接执行对应脚本。Android 与 Windows 构建详见 `doc/ANDROID_BUILD.md` 与 `doc/WINDOWS_BUILD.md`。

### 1.6 Windows 端开发环境

Windows 客户端位于 `windows/`，基于 WPF .NET 8 + C# 12 构建。

**必需依赖**：

- Windows 10 / 11 x64
- .NET 8 SDK：`winget install Microsoft.DotNet.SDK.8`
- Visual Studio 2022（含 `.NET desktop development` 工作负载）或 VS Code + C# Dev Kit 扩展

**可选依赖（构建 Rust DLL）**：

- Rust 1.75+：`winget install Rustlang.Rustup`
- 添加 Windows MSVC target：`rustup target add x86_64-pc-windows-msvc`
- 构建 DLL：`cargo build -p aether-core-ffi --target x86_64-pc-windows-msvc --release`，将生成的 `aether_core_ffi.dll` 置于 `windows/Aether.Windows/Native/`

**首次构建**：

```powershell
cd windows
dotnet build
dotnet test   # 运行 Aether.Windows.Tests
```

> Rust DLL 缺失时 `AetherNativeBridge` 走纯 C# 回退实现，开发期可不构建 DLL。

### 1.7 Android 端开发环境

Android 客户端位于 `android/`，基于 Kotlin 1.9 + Jetpack Compose + Gradle 8.7 构建。

**必需依赖**：

- Android Studio Hedgehog（2023.1.1）+
- JDK 17：`brew install openjdk@17`（macOS）或 `winget install Microsoft.OpenJDK.17`（Windows）
- Android SDK API 29+（Build Tools 35.0.0）：通过 Android Studio SDK Manager 安装
- Kotlin 1.9+（随 Android Studio 自带）
- Android NDK r25+：通过 Android Studio SDK Manager 安装

**可选依赖（构建 Rust .so）**：

- Rust 1.75+
- 添加 Android target：`rustup target add aarch64-linux-android x86_64-linux-android`
- 安装 `cargo-ndk`：`cargo install cargo-ndk`
- 构建 .so（两个 ABI）：

  ```bash
  cargo ndk -t arm64-v8a build -p aether-core-ffi --release
  cargo ndk -t x86_64 build -p aether-core-ffi --release
  ```

  将生成的 `libaether_core_ffi.so` 分别置于 `android/app/src/main/jniLibs/arm64-v8a/` 与 `android/app/src/main/jniLibs/x86_64/`

**首次构建**：

```bash
cd android
./gradlew assembleDebug         # 构建 Debug APK
./gradlew testDebugUnitTest     # 运行单元测试（Robolectric）
```

> Rust .so 缺失时 `Redact` / `SseBridge` / `VectorMath` 走纯 Kotlin 回退实现，单元测试默认走回退路径，无需构建 .so 即可跑测试。

## 2. 代码规范

### 2.1 Swift 命名

- 类型（class / struct / enum / protocol / actor）使用 **UpperCamelCase**：`ChatViewModel`、`ToolProtocol`
- 方法 / 属性 / 变量使用 **lowerCamelCase**：`sendMessage`、`streamingText`
- 常量使用 **lowerCamelCase**：`maxReActLoops = 5`、`toolTimeout = 15`
- 文件名与类型名一致：`ChatViewModel.swift` 含 `class ChatViewModel`

### 2.2 SwiftUI 风格

- 使用 `@Observable` 不用 `ObservableObject` + `@Published`
- View 用 `struct` + `body` 计算属性，避免在 View 内持有状态（用 `@State` 最小化）
- 跨平台 View 用 `NavigationSplitView` 而非 `NavigationStack`，让 macOS / iPad 自动双栏
- 条件编译用 `#if os(iOS)` / `#if os(macOS)` 隔离平台特定代码

### 2.3 SwiftData 使用

- 持久化实体用 `@Model` 宏：`@Model final class Conversation { ... }`
- 关系用 `@Relationship` 并指定 `deleteRule`：`@Relationship(deleteRule: .cascade) var messages: [ChatMessage]`
- Schema 注册在 `AetherApp` 的 `ModelContainer`：`Schema([Conversation.self, ChatMessage.self, ...])`
- 不直接操作 CoreData，所有读写经 `ChatStorage` 服务封装

### 2.4 多平台条件编译规范

```swift
import SwiftUI
#if os(iOS)
import BGTaskScheduler
import ActivityKit
import HealthKit
import WatchConnectivity
#endif

class MyService {
    func doWork() {
        #if os(iOS)
        // iOS-only 实现
        #else
        // macOS 优雅降级（返回空 / 占位 / 不调用）
        #endif
    }
}
```

**关键约束**：
- iOS-only 框架（BGTaskScheduler / ActivityKit / HealthKit / WatchConnectivity）必须用 `#if os(iOS)` 守卫
- macOS 独有工具整体文件用 `#if os(macOS)` 包裹
- macOS 入口（如 HealthKit 设置）在 macOS 隐藏但 Model 仍注册以维持 schema 一致性

### 2.5 测试规范

- 单元测试（UT）放 `AetherTests/`，命名 `<ClassName>Tests.swift`
- UI 测试（UIT）放 `AetherUITests/`，避免依赖真实网络（用 `UITEST_DISABLE_NETWORK` 启动参数桩回复）
- 测试用例数：UT 3502 / UIT 30（每新增功能需补对应测试）
- 当前目标：0 skip；若必须跳过，需写明原因并在 Issue 跟踪

### 2.6 国际化规范

- 用户可见文本必须进入 `Aether/Resources/Localizable.xcstrings`（当前 888 keys，支持 8 种语言：zh-Hans / zh-Hant / en / ja / ko / fr / de / es）。
- SwiftUI 控件直接传字符串字面量即可自动提取；动态拼接文本使用 `String(format: NSLocalizedString(...), ...)`。
- 新增字符串后运行 `python3 scripts/extract_strings.py` 检查遗漏，并补充全部 8 种语言翻译（zh-Hans 为源语言，其余 7 种为翻译目标）。
- App 内语言切换支持 9 个选项（跟随系统 + 8 种语言），切换后提示用户重启 App 生效。

### 2.7 代码风格强制规则

以下规则通过 SwiftLint 强制执行（`.swiftlint.yml` 已配置），提交前必须通过检查：

| 规则 | 严重级别 | 说明 |
|------|----------|------|
| `force_unwrapping` | warning | 禁止强制解包 `!`（如 `value!`），应使用 `guard let` / `if let` 安全解包 |
| `force_cast` | warning | 禁止强制类型转换 `as!`，应使用 `as?` + 可选绑定 |
| `force_try` | warning | 禁止 `try!` 强制try，应使用 `try` + `do-catch` 或 `try?` |
| `implicitly_unwrapped_optional` | warning | 谨慎使用隐式解包可选类型 `var x: String!`，仅限 IB Outlet 等场景 |
| `empty_count` / `empty_string` | warning | 空集合用 `.isEmpty`，空字符串用 `.isEmpty` 而非 `== ""` |
| `explicit_init` | warning | 避免冗余的 `init` 调用（如 `String(s)` → `s`） |

> **例外**：UT 中为简化测试可酌情使用 `!`，但建议尽量遵循规则。CI 中 SwiftLint error 会阻断合并，warning 不阻断但建议修复。

### 2.8 SwiftLint 与 SwiftFormat 配置

#### SwiftLint

项目根目录已配置 `.swiftlint.yml`，定义了检查目录、启用规则、禁用规则与参数阈值。

**本地检查**：CI 通过 SonarCloud 进行代码质量检查（见 `.github/workflows/ci.yml` 的 `code-quality` job）。

**配置要点**：
- 检查目录：`Aether` / `AetherTests` / `AetherUITests`
- 排除目录：`Pods` / `DerivedData` / `.build` / `Aether.xcodeproj`
- opt-in 规则：`force_unwrapping` / `implicitly_unwrapped_optional` / `empty_count` / `empty_string` / `explicit_init`
- 禁用规则：`trailing_newline` / `leading_whitespace` / `todo` / `identifier_name` / `type_name`（与 SwiftUI 风格不兼容）
- 行长度：warning 200 / error 300
- 函数体长度：warning 150 / error 300
- 圈复杂度：warning 20 / error 40

> **安装**：`brew install swiftlint`

#### SwiftFormat

项目根目录已配置 `.swiftformat`，统一代码格式化。

**配置要点**：
- Swift 版本：5.9
- 缩进：4 空格
- Allman 风格：关闭（`--allman false`）
- 禁用：`wrapSingleGuards` / `wrapArguments` / `redundantParens`

> **安装**：`brew install swiftformat`

### 2.9 Pre-commit Hooks

项目提供两种 pre-commit 安装方式，任选其一。**提交前自动检查**：大文件（>1MB）、私钥泄露、合并冲突标记、SwiftFormat/SwiftLint 校验。

#### 方式 A：Git native hooks（推荐，零依赖）

```bash
make install-hooks
```

安装到 `.git/hooks/pre-commit`，卸载：`rm .git/hooks/pre-commit`。

#### 方式 B：Python pre-commit 框架

需先安装 Python pre-commit 框架（`pip install pre-commit`）：

```bash
pre-commit install
# 首次运行安装所有 hooks
pre-commit run --all-files
```

配置见 `.pre-commit-config.yaml`，包含：
- `pre-commit-hooks v4.6.0`：trailing-whitespace / end-of-file-fixer / check-yaml / check-json / check-merge-conflict / check-added-large-files / detect-private-key / check-case-conflict
- Local hooks：swiftformat-check / swiftlint（strict）

跳过特定 hook：`SKIP=swiftlint git commit -m "..."`

#### 配套：`.gitattributes`（P1-13 / H-C2）

仓库根目录已配置 `.gitattributes`，标准化所有文件的行尾（LF 默认，Windows 脚本 CRLF）、文件类型（文本/二进制）、merge 策略（锁文件 `merge=ours`）、diff 行为（大文件 `-diff`）。开发者无需手动处理行尾问题。

### 2.10 Windows 端代码规范（C# 12 + WPF）

Windows 端遵循 [Microsoft C# Coding Conventions](https://learn.microsoft.com/dotnet/csharp/fundamentals/coding-style/coding-conventions) 与 WPF MVVM 模式。

**命名**：

- 类型（class / struct / enum / interface / record）使用 **PascalCase**：`ChatViewModel`、`IAetherApiClient`
- 方法 / 属性 / 事件使用 **PascalCase**：`SendMessage`、`StreamingText`
- 局部变量 / 参数使用 **camelCase**：`messageContent`、`apiKey`
- 私有字段使用 `_camelCase`：`_httpClient`、`_disposed`
- 接口以 `I` 前缀：`IAetherApiClient`、`IBffConfigStore`
- XAML 文件与控件名使用 PascalCase：`ChatPage.xaml`、`SettingsPage`

**MVVM 模式**：

- View（`*.xaml` + `*.xaml.cs`）仅负责 UI 绑定，不写业务逻辑
- ViewModel（`*ViewModel.cs`）实现 `INotifyPropertyChanged` 或继承 `ObservableObject`，通过 `SetProperty(ref _field, value)` 触发属性变更通知
- 命令使用 `RelayCommand`（CommunityToolkit.Mvvm）或自定义 `ICommand` 实现，命名 `<Action>Command`：`SendCommand`、`DeleteConversationCommand`
- 数据绑定优先用 `Binding` 路径，避免在 code-behind 直接操作控件
- 服务（`AetherApiClient` / `BffConfigStore` 等）通过构造函数注入，便于单元测试

**异步**：

- 异步方法以 `Async` 后缀命名：`SendMessageAsync`、`LoadConversationsAsync`
- 使用 `async` / `await`，避免 `.Result` / `.Wait()` 阻塞调用
- I/O 操作返回 `Task<T>`，事件处理返回 `async void`

**XAML 规范**：

- `x:Class` 与文件路径一致：`<Page x:Class="Aether.Windows.Views.ChatPage">`
- 资源（`Style` / `DataTemplate`）优先放 `App.xaml` 或 `*/Design/DesignTokens.cs`
- `Binding` 优先用 `Mode=TwoWay` + `UpdateSourceTrigger=PropertyChanged`
- 控件命名使用 `x:Name` PascalCase：`MessageListBox`、`SendButton`

**DPAPI 加密**：

- BFF Token 等敏感信息必须经 `BffConfigStore` 通过 `ProtectedData.Protect(..., DataProtectionScope.CurrentUser)` 加密后写入配置文件，禁止明文存储。

### 2.11 Android 端代码规范（Kotlin + Jetpack Compose）

Android 端遵循 [Kotlin Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html) 与 Jetpack Compose MVVM 模式。

**命名**：

- 类型（class / object / interface / enum）使用 **PascalCase**：`ChatViewModel`、`AetherApi`
- 方法 / 属性使用 **camelCase**：`sendMessage`、`streamingText`
- 包名全小写：`com.aether.app.ui.chat`
- 文件名与类型名一致：`ChatViewModel.kt` 含 `class ChatViewModel`
- Composable 函数使用 **PascalCase**：`ChatScreen`、`MessageBubble`

**MVVM + Compose 模式**：

- View（`*Screen.kt`）为 `@Composable` 函数，无业务逻辑，仅描述 UI
- ViewModel（`*ViewModel.kt`）继承 `androidx.lifecycle.ViewModel`，通过 `StateFlow` / `MutableStateFlow` 暴露 UI 状态
- 状态用 `data class` 封装：`data class ChatUiState(val messages: List<Message> = emptyList(), val inputText: String = "")`
- 副作用（Side Effect）用 `LaunchedEffect` / `collectAsStateWithLifecycle` 处理
- 依赖注入通过 `viewModel { ... }` 工厂或 Hilt（如启用）

**协程与 Flow**：

- I/O 操作用 `viewModelScope.launch { withContext(Dispatchers.IO) { ... } }`
- 数据流用 `Flow` / `StateFlow`，UI 层用 `collectAsStateWithLifecycle()`
- 不要在 `Main` 调度器执行阻塞操作

**Room 数据库**：

- `@Entity` 类名以 `Entity` 后缀：`ConversationEntity`、`MessageEntity`
- `@Dao` 接口名以 `Dao` 后缀：`ConversationDao`、`MessageDao`
- 外键关系明确声明 `onDelete` 策略：`ForeignKey(..., onDelete = CASCADE)`
- 数据库操作返回 `Flow<List<T>>` 实现响应式查询

**Rust JNI 桥接**：

- JNI 包装类（`Redact` / `SseBridge` / `VectorMath`）在 `com.aether.app.rust` 包下
- `System.loadLibrary` 失败时回退到纯 Kotlin 实现，**禁止假设 .so 必然加载成功**
- 单元测试默认走回退路径，覆盖率必须与 Rust 实现路径一致

**国际化**：

- 用户可见文本必须进入 `res/values/strings.xml`，禁止硬编码字符串
- 使用 `stringResource(R.string.<key>)` 在 Composable 中引用
- 新增 key 必须同步补充 8 种语言：`values-zh-rCN`（默认）/ `values-zh-rTW` / `values-en` / `values-ja` / `values-ko` / `values-fr` / `values-de` / `values-es`

## 3. 提交规范

使用 **Conventional Commits** 格式：

```
<type>(<scope>): <subject>

<body>

<footer>
```

### 3.1 type 列表

| type | 含义 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat(rag): 支持 Markdown 文档分块` / `feat(windows): 接入 DPAPI 加密 BFF Token` / `feat(android): 接入 Room 数据库` |
| `fix` | bug 修复 | `fix(voice): 修复 AVAudioSession 未激活崩溃` / `fix(windows): 修复流式聊天内存泄漏` / `fix(android): 修复长按菜单不消失` |
| `docs` | 文档更新 | `docs(arch): 更新架构图到 Mermaid` / `docs(windows): 补充 WPF 构建说明` |
| `refactor` | 重构 | `refactor(viewmodel): 提取 ReAct 循环到独立方法` / `refactor(android): 抽取 KnowledgeBaseViewModel 公共逻辑` |
| `test` | 测试相关 | `test(tool): 补充 LocationToolTests` / `test(windows): 补充 MarkdownRendererTest` / `test(android): 补充 SseBridgeTest` |
| `chore` | 构建 / 工具 / 杂项 | `chore(ci): 升级到 macos-14 runner` / `chore(android): 升级 NDK r26` |
| `perf` | 性能优化 | `perf(markdown): 加 NSCache 缓存 parseBlocks` / `perf(android): Room 查询加索引` |
| `style` | 代码风格（不影响逻辑） | `style: 统一缩进 4 空格` |

### 3.2 scope 推荐

- **功能模块**：`rag` / `voice` / `tool` / `llm` / `bff` / `ondevice` / `health` / `intent` / `markdown`
- **架构层**：`view` / `viewmodel` / `model` / `service` / `repository` / `dao`
- **平台**（**新增跨平台**）：`ios` / `macos` / `windows` / `android`
- **流程**：`test` / `ci` / `docs` / `arch` / `i18n`

> **跨平台 scope 使用规则**：
> - 改动仅影响单一平台时，scope 用该平台名：`feat(windows): ...` / `fix(android): ...`
> - 改动同时影响多端共享代码（如 Rust crate `aether-core-ffi`）时，scope 用 `ffi`：`feat(ffi): 新增 Redactor 模块`
> - 改动同时影响多端但分别提交时，拆为多个 commit：`feat(windows): ...` + `feat(android): ...`
> - 跨平台 PR 标题用 `feat(multiplatform): ...`，body 中列出各端改动

### 3.3 示例

```
feat(voice): TTS 音色可调节

新增 TTSConfig 持久化音色 ID / 语速 / 音调 / 音量到 UserDefaults，
TTSVoiceCatalog 提供系统音色目录，TTSVoicePickerView 提供试听。

Closes #123
```

```
feat(windows): 接入 DPAPI 加密 BFF Token

BffConfigStore 调用 ProtectedData.Protect 加密 BFF Token，
绑定 CurrentUser 范围，仅同一 Windows 用户可解密。
新增 BffConfigStoreTest 覆盖加解密往返与异常路径。

Closes #456
```

```
feat(android): 接入 Room 持久化会话与消息

新增 AetherDatabase / ConversationDao / MessageDao，
外键 onDelete = CASCADE 自动级联删除。
RepositorySyncManager 在 Dispatchers.IO 上执行所有 DB 操作，
通过 Flow 回调 UI 层。新增 ConversationRepositoryRoomTest。

Closes #789
```

## 4. PR 流程

### 4.1 准备 PR

1. Fork 本仓库到个人 GitHub 账号
2. 本地 clone fork：
   ```bash
   git clone https://github.com/<your-name>/Aether.git
   cd Aether
   git remote add upstream https://github.com/luosicx/Aether.git
   ```
3. 创建特性分支：
   ```bash
   git checkout -b feat/<short-description>
   ```
4. 编写代码 + 补充测试，确保本地通过：
   ```bash
   # 4.1 代码质量由 CI SonarCloud job 检查（无需本地运行）

   # 4.2 Apple 端：运行 UT（3502 用例，0 skip）
   xcodebuild test -project Aether.xcodeproj -scheme Aether-iOS \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     -only-testing:AetherTests \
     -configuration Debug CODE_SIGNING_ALLOWED=NO

   # 4.3 Apple 端：运行 UIT（30 用例，0 skip）
   xcodebuild test -project Aether.xcodeproj -scheme Aether-iOS \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     -only-testing:AetherUITests \
     -configuration Debug CODE_SIGNING_ALLOWED=NO

   # 4.4 Windows 端：运行 dotnet test（在 windows/ 目录下）
   cd windows && dotnet test

   # 4.5 Android 端：运行单元测试（在 android/ 目录下）
   cd android && ./gradlew testDebugUnitTest
   ```
5. 提交（按 Conventional Commits）：
   ```bash
   git add <files>
   git commit -m "feat(<scope>): <subject>"
   ```
6. 同步上游：
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```
7. 推送到 fork：
   ```bash
   git push origin feat/<short-description>
   ```
8. 在 GitHub 上发起 PR：`<your-branch>` → `luosicx/Aether:main`

### 4.2 PR 标题与描述要求

- **标题**：`<type>(<scope>): <subject>`（与最后一个 commit 一致）
- **描述**：
  - **What changed**：列出本次变更点
  - **Why**：变更动机（解决什么问题 / 满足什么需求）
  - **How to test**：测试步骤
  - **Checklist**：
    - [ ] 已通过 CI SonarCloud 代码质量检查
    - [ ] 已通过本地 Apple UT (3502 用例)
    - [ ] 已通过本地 Apple UIT (30 用例)
    - [ ] 已通过本地 Windows 测试（如涉及 `windows/`，`dotnet test`）
    - [ ] 已通过本地 Android 测试（如涉及 `android/`，`./gradlew testDebugUnitTest`）
    - [ ] 已更新相关文档（如有用户可见变更）
    - [ ] 已补充测试用例（如有新功能）

### 4.3 CI 要求

- PR 自动触发 GitHub Actions CI（`.github/workflows/ci.yml`）
- 必须 **Build 成功** + **Test 0 failures**
- CI 通过 SonarCloud 进行代码质量检查（`code-quality` job），存在 error 会阻断合并
- 跨平台 PR：CI 必须全部 **14 个 job 通过**（含 iOS-build / macOS-build / windows-build / android-build / Rust 各 target / coverage-summary 等），Coverage 当前阈值 84.25%
- Reviewer 审核通过后合并

### 4.4 Windows 端 PR 测试要求

涉及 `windows/` 改动的 PR，提交前必须本地通过：

```powershell
cd windows
dotnet build                                      # 构建成功
dotnet test                                        # 运行 Aether.Windows.Tests（必须 0 failures）
```

**测试覆盖要求**：

- 新增 Service / ViewModel 必须补对应 `*Test.cs`（如 `BffConfigStoreTest.cs` / `SettingsViewModelTest.cs`）
- 新增 Markdown 渲染规则必须扩展 `MarkdownRendererTest.cs`
- 新增语言 key 必须同步补充 8 种 `Strings.*.resx`，否则 `LanguageServiceTest` 会失败
- CI 中 `windows-build` job（`windows-latest` runner，约 2m58s）会自动跑 `dotnet test`，本地通过不代表 CI 通过（CI 会做 DPAPI / 流式 SSE 等更严格的集成测试）

### 4.5 Android 端 PR 测试要求

涉及 `android/` 改动的 PR，提交前必须本地通过：

```bash
cd android
./gradlew assembleDebug                            # 构建成功
./gradlew testDebugUnitTest                        # 运行 Robolectric 单元测试（必须 0 failures）
```

**测试覆盖要求**：

- 新增 ViewModel 必须补对应 `*Test.kt`（如 `ChatViewModelDeleteTest.kt` / `HealthViewModelTest.kt`）
- 新增 Repository / Dao 必须补 `*Test.kt`，使用 Robolectric 内存数据库（`Room.inMemoryDatabaseBuilder`）
- 新增 Rust JNI 包装类必须补 `*Test.kt`，**测试走纯 Kotlin 回退路径**（不依赖 .so）
- 新增 strings.xml key 必须同步补充 8 种 `values-<locale>/strings.xml`，否则 `LanguageManagerTest` 会失败
- CI 中 `android-build` job（`ubuntu-latest` runner，约 2m40s）会自动跑 `./gradlew testDebugUnitTest`

### 4.6 跨平台 PR 测试要求

同时影响多端的 PR（如修改 Rust crate `aether-core-ffi`）：

- **本地**：必须分别在三端跑测试（Apple UT/UIT + Windows `dotnet test` + Android `./gradlew testDebugUnitTest`）
- **CI**：14 个 job 全部 pass，Coverage ≥ 84.25%
- **PR 描述**：必须列出每个平台的测试结果与影响范围
- **回滚预案**：若某端 CI 失败且无法快速修复，可在 PR 描述中说明并临时跳过该端 CI（需 Reviewer 同意），但合并后必须立即开 follow-up Issue 跟进

## 5. spec 驱动开发说明

本项目采用 **spec 驱动开发**，每个重大变更前先写 spec 文档。

### 5.1 spec 三件套

每个 spec 位于 `.trae/specs/<change-id>/` 目录，包含：

| 文件 | 用途 |
|------|------|
| `spec.md` | 变更规格：Why / What Changes / Impact / Requirements / Scenarios |
| `tasks.md` | 任务分解：可验证的小任务列表，含 SubTasks |
| `checklist.md` | 验收清单：每个 checkpoint 勾选验证 |

### 5.2 change-id 命名规范

`<verb>-<object>` 格式：
- `feat-voice-tts-customization`
- `fix-macos-settings-close-voice-freeze`
- `update-docs-to-latest-v2`
- `adapt-multiplatform-ios-ipad-macos`

### 5.3 流程

1. 写 spec.md / tasks.md / checklist.md 三件套
2. 用户审批 spec
3. 用 Sub-Agent 并行实施各 Task
4. 系统验证 checklist 全部通过
5. 提 PR

历史 spec 见 `.trae/specs/` 目录（44+ 个 spec 覆盖 Day 1-20 全部功能）。

## 6. Watch App 开发指南

> **平台范围**：Watch App 为 **Apple 平台独有**（iOS 配套 watchOS App），Windows 端与 Android 端不提供等价能力。Watch target 仅在 macOS + Xcode 环境下构建。

Aether 的 watchOS App 源代码位于 `AetherWatch/` 目录，采用 SwiftUI 原生开发，支持 watchOS 10+。

### 6.1 目录结构

```
AetherWatch/
├── WatchApp.swift              # App 入口（@main，TabView 三标签）
└── Views/
    ├── WatchQuickChatView.swift    # 快速对话（通过 WatchConnectivity 发送到 iPhone）
    ├── WatchHealthInsightView.swift # 健康洞察（读取共享 SwiftData HealthInsight）
    └── WatchSettingsView.swift     # 设置（字体大小 / 朗读开关）
```

### 6.2 ⚠️ 手动创建 Xcode Target

Watch App 源代码已就绪，但**需在 Xcode 中手动创建 target**：

1. Xcode → File → New → Target → watchOS App
2. Product Name 填 `AetherWatch`，Interface 选 SwiftUI，Language 选 Swift
3. Bundle Identifier 设为 `<主 App Bundle ID>.watchkitapp`
4. 删除 Xcode 自动生成的文件，将 `AetherWatch/` 目录下的源文件添加到 target
5. 在 Watch target 的 Signing & Capabilities 中添加 **App Group**：`group.com.aether.app`
6. 在主 App target 的 Signing & Capabilities 中也添加相同 App Group（如未添加）

### 6.3 数据同步机制

- **WatchConnectivity**：`WCSession` 双向通信，`transferUserInfo` 用于异步传递对话历史，`sendMessage` 用于实时 quickChat
- **共享 SwiftData**：通过 App Group 容器共享 `HealthInsight` 模型，Watch 端可直接读取健康洞察
- **配对要求**：Watch App 需与 iPhone 上的主 App 配对运行（非独立运行模式）

### 6.4 开发注意事项

- Watch 端不支持工具调用与端侧 MLX 推理，quickChat 通过 WatchConnectivity 转发到 iPhone 处理
- `HealthInsight` 模型必须在 Watch target 的 ModelContainer 中注册以保持 schema 一致性
- Watch UI 应使用 `.containerRelativeFrame` 适配各表盘尺寸，避免硬编码尺寸

## 7. Widget Extension 开发指南

> **平台范围**：Widget Extension 为 **Apple 平台独有**（iOS / iPadOS 主屏与今日视图，macOS 桌面 Widget），基于 WidgetKit + AppIntents 框架。Windows 端与 Android 端不提供等价能力，未来不计划移植（系统机制差异过大）。

Aether 的桌面 Widget 源代码位于 `AetherWidgets/` 目录，采用 WidgetKit + AppIntents 框架。

### 7.1 目录结构

```
AetherWidgets/
├── AetherWidgetBundle.swift            # Widget Bundle 入口（注册 3 个 Widget）
├── QuickChatWidget.swift               # 快捷提问 Widget（AppIntentConfiguration）
├── HealthInsightWidget.swift           # 健康洞察 Widget（TimelineProvider）
└── RecentConversationsWidget.swift     # 最近会话 Widget（TimelineProvider）
```

### 7.2 ⚠️ 手动创建 Xcode Target

Widget Extension 源代码已就绪，但**需在 Xcode 中手动创建 target**：

1. Xcode → File → New → Target → Widget Extension
2. Product Name 填 `AetherWidgets`，Interface 选 SwiftUI，取消勾选 "Include Configuration App Intent"（手动添加）
3. Bundle Identifier 设为 `<主 App Bundle ID>.widgets`
4. 删除 Xcode 自动生成的文件，将 `AetherWidgets/` 目录下的源文件添加到 target
5. 在 Widget target 的 Signing & Capabilities 中添加 **App Group**：`group.com.aether.app`
6. 在主 App target 中也添加相同 App Group

### 7.3 数据共享机制

- **App Group 共享 SwiftData**：Widget 通过 `group.com.aether.app` 容器读取主 App 的 SwiftData 数据（Conversation / ChatMessage / HealthInsight）
- **ModelContainer 配置**：Widget 端创建 `ModelContainer` 时需指定 App Group 容器 URL：
  ```swift
  let containerURL = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.aether.app")!
  let config = ModelConfiguration(url: containerURL.appending(path: "Aether.store"))
  ```

### 7.4 三个 Widget 说明

| Widget | 类型 | 数据源 | 交互 |
|--------|------|--------|------|
| QuickChatWidget | AppIntentConfiguration | 无（用户输入 query） | deepLink `aether://ask?query=` 跳转主 App |
| HealthInsightWidget | TimelineProvider | 共享 SwiftData `HealthInsight` | deepLink `aether://conversation/<uuid>` 跳转 |
| RecentConversationsWidget | TimelineProvider | 共享 SwiftData `Conversation` | deepLink 跳转指定会话 |

### 7.5 开发注意事项

- Widget 为只读访问，不可通过 Widget 修改 SwiftData 数据
- Timeline 刷新频率受系统限制（最快 15 分钟），重要数据变更时使用 `WidgetCenter.shared.reloadAllTimelines()` 主动刷新
- Widget 进程独立于主 App，不可访问主 App 的内存状态（如 `@Observable` ViewModel）

## 8. 本地化工作流

Aether 支持 8 种语言（zh-Hans / zh-Hant / en / ja / ko / fr / de / es），源语言为 zh-Hans。

### 8.1 新增字符串流程

1. 在 SwiftUI 代码中使用字符串字面量（如 `Text("发送")`），构建时 Xcode 自动提取到 `Localizable.xcstrings`
2. 运行提取脚本检查遗漏：
   ```bash
   python3 scripts/extract_strings.py
   ```
3. 在 Xcode String Catalog 编辑器中为每个 key 补充 8 种语言翻译
4. 翻译优先级：zh-Hans（源） → zh-Hant / en（必填） → ja / ko / fr / de / es（必填）

### 8.2 App 内语言切换

- 设置页提供 9 个选项：跟随系统 + 8 种语言
- 切换后写入 `AppleLanguages` UserDefaults，并提示用户重启 App
- 重启后 `Bundle.main.preferredLocalizations` 自动读取新语言

### 8.3 翻译质量要求

- 术语统一：Aether 译为「以太」（zh-Hans/zh-Hant）或保留「Aether」（其他语言）
- 工具描述翻译：`ToolRegistry.allToolDefs` 的 `description` 字段需本地化，用户偏好工具列表显示中文描述
- 错误提示翻译：所有 `LLMError` / `ToolError` 的 `userMessage` 需本地化

## 9. 无障碍开发指南

Aether 致力于为所有用户提供良好的无障碍体验，遵循苹果 HIG 无障碍指南。

### 9.1 VoiceOver 标签

- 所有可交互控件必须添加 `accessibilityLabel`（如发送按钮：`.accessibilityLabel("发送")`）
- 复杂视图使用 `accessibilityElement(children: .combine)` 合并子元素标签
- 提供 `accessibilityHint` 说明操作结果（如 `.accessibilityHint("发送消息")`）

### 9.2 accessibilityIdentifier

- 关键交互控件必须添加 `accessibilityIdentifier` 供 UITest 定位（如 `.accessibilityIdentifier("sendButton")`）
- 当前已覆盖 13 个关键元素：sendButton / messageInputField / voiceInputButton / knowledgeBaseButton / settingsButton / conversationListButton / newConversationButton / importDocumentButton / downloadModelButton / deleteModelButton / requestHealthAuthButton / thumbsUpButton / thumbsDownButton

### 9.3 Dynamic Type 适配

- 文本使用 `.font(.body)` / `.font(.headline)` 等语义字体，不硬编码字号
- 长文本设置 `.minimumScaleFactor(0.5)` 防止 Dynamic Type XL 时截断
- Form 行避免 `fixedSize()`，让系统自适应行高

### 9.4 无障碍审计清单

新增 View 时请逐项检查：

- [ ] 可交互控件含 `accessibilityLabel`
- [ ] 关键控件含 `accessibilityIdentifier`
- [ ] 复杂视图含 `accessibilityElement(children: .combine)`
- [ ] 文本使用语义字体（非硬编码字号）
- [ ] VoiceOver 开启时可正确朗读所有元素
- [ ] Dynamic Type XL 下无截断

## 10. 联系

- Issue：https://github.com/luosicx/Aether/issues
- Discussion：https://github.com/luosicx/Aether/discussions

---

再次感谢你的贡献！
