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
| Node.js（可选） | 18+ | 部署 BFF Cloudflare Workers 时使用 |

### 1.2 获取源码

```bash
git clone <your-fork-url>
cd AIBuiler
open Aether.xcodeproj
```

### 1.3 安装依赖

- 项目主体无需第三方包管理器（CocoaPods / SPM 仅可选 mlx-swift 端侧推理）
- 如需启用端侧推理：在 Xcode → File → Add Package Dependencies 添加 mlx-swift
- BFF 部署：`npm install -g wrangler`

### 1.4 首次运行

1. Xcode 顶部 Scheme 选择 `Aether`
2. 目标设备选择 **iPhone 17 模拟器**（iOS 测试）或 **My Mac**（macOS 测试）
3. 按 `Cmd + R` 运行
4. App 启动后进入设置填入 DeepSeek API Key（https://platform.deepseek.com 申请）

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
- 测试用例数：UT 266 / UIT 13（每新增功能需补对应测试）
- 当前目标：0 skip；若必须跳过，需写明原因并在 Issue 跟踪

### 2.6 国际化规范

- 用户可见文本必须进入 `Aether/Resources/Localizable.xcstrings`（当前 387 keys，支持 8 种语言：zh-Hans / zh-Hant / en / ja / ko / fr / de / es）。
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

**本地检查**：

```bash
# 运行 SwiftLint 检查（未安装时脚本会提示安装方法并跳过，不报错）
scripts/run_swiftlint.sh
```

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
| `feat` | 新功能 | `feat(rag): 支持 Markdown 文档分块` |
| `fix` | bug 修复 | `fix(voice): 修复 AVAudioSession 未激活崩溃` |
| `docs` | 文档更新 | `docs(arch): 更新架构图到 Mermaid` |
| `refactor` | 重构 | `refactor(viewmodel): 提取 ReAct 循环到独立方法` |
| `test` | 测试相关 | `test(tool): 补充 LocationToolTests` |
| `chore` | 构建 / 工具 / 杂项 | `chore(ci): 升级到 macos-14 runner` |
| `perf` | 性能优化 | `perf(markdown): 加 NSCache 缓存 parseBlocks` |
| `style` | 代码风格（不影响逻辑） | `style: 统一缩进 4 空格` |

### 3.2 scope 推荐

- `rag` / `voice` / `tool` / `llm` / `bff` / `ondevice` / `health` / `intent` / `view` / `viewmodel` / `model` / `service` / `test` / `ci` / `docs` / `macos` / `ios`

### 3.3 示例

```
feat(voice): TTS 音色可调节

新增 TTSConfig 持久化音色 ID / 语速 / 音调 / 音量到 UserDefaults，
TTSVoiceCatalog 提供系统音色目录，TTSVoicePickerView 提供试听。

Closes #123
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
   # 4.1 运行 SwiftLint 检查（必须 0 error，warning 建议修复）
   scripts/run_swiftlint.sh

   # 4.2 运行 UT（266 用例，0 skip）
   xcodebuild test -project Aether.xcodeproj -scheme Aether \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     -only-testing:AetherTests \
     -configuration Debug CODE_SIGNING_ALLOWED=NO

   # 4.3 运行 UIT（13 用例，0 skip）
   xcodebuild test -project Aether.xcodeproj -scheme Aether \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     -only-testing:AetherUITests \
     -configuration Debug CODE_SIGNING_ALLOWED=NO
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
    - [ ] 已通过 SwiftLint 检查（`scripts/run_swiftlint.sh`，0 error）
    - [ ] 已通过本地 UT (266 用例)
    - [ ] 已通过本地 UIT (13 用例)
    - [ ] 已更新相关文档（如有用户可见变更）
    - [ ] 已补充测试用例（如有新功能）

### 4.3 CI 要求

- PR 自动触发 GitHub Actions CI（`.github/workflows/ci.yml`）
- 必须 **Build 成功** + **Test 0 failures**
- CI 集成 SwiftLint 检查脚本（`scripts/run_swiftlint.sh`），存在 error 会阻断合并
- Reviewer 审核通过后合并

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
5. 在 Watch target 的 Signing & Capabilities 中添加 **App Group**：`group.com.aether.shared`
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
5. 在 Widget target 的 Signing & Capabilities 中添加 **App Group**：`group.com.aether.shared`
6. 在主 App target 中也添加相同 App Group

### 7.3 数据共享机制

- **App Group 共享 SwiftData**：Widget 通过 `group.com.aether.shared` 容器读取主 App 的 SwiftData 数据（Conversation / ChatMessage / HealthInsight）
- **ModelContainer 配置**：Widget 端创建 `ModelContainer` 时需指定 App Group 容器 URL：
  ```swift
  let containerURL = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.aether.shared")!
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
