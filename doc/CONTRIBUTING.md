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
- 测试用例数：UT 248 / UIT 13（每新增功能需补对应测试）
- 当前目标：0 skip；若必须跳过，需写明原因并在 Issue 跟踪

### 2.6 国际化规范

- 用户可见文本必须进入 `Aether/Resources/Localizable.xcstrings`。
- SwiftUI 控件直接传字符串字面量即可自动提取；动态拼接文本使用 `String(format: NSLocalizedString(...), ...)`。
- 新增字符串后运行 `python3 scripts/extract_strings.py` 检查遗漏，并补充 `en` / `zh-Hant` 翻译。

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

   # 4.2 运行 UT（248 用例，0 skip）
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
    - [ ] 已通过本地 UT (248 用例)
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

## 6. 联系

- Issue：https://github.com/luosicx/Aether/issues
- Discussion：https://github.com/luosicx/Aether/discussions

---

再次感谢你的贡献！
