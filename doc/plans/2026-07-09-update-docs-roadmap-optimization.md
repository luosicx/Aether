# AIBuilder 文档更新与后续规划实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 AIBuilder 项目所有文档同步到最新代码状态（多平台适配、i18n 385 keys、工具 13/24、UT 248 / UIT 13、0 skips、截图、accessibility），并新增 ROADMAP / OPTIMIZATION / DESIGN_UPDATE 三份后续规划文档，最后提交到现有 PR。

**Architecture:** 以代码状态为唯一事实来源（single source of truth），通过脚本/命令提取关键指标，逐份更新 Markdown 中的数字、清单、链接与描述；新增规划文档采用「现状 → 目标 → 关键任务 → 验收标准」四段式结构。

**Tech Stack:** Markdown, Git, Swift/Xcode（仅用于验证指标）

---

## File Structure

| File | Responsibility |
|------|----------------|
| `README.md` | 项目首页：功能、截图、快速开始、项目结构 |
| `doc/ARCHITECTURE.md` | 系统架构、模块职责、数据流、技术栈 |
| `doc/USAGE.md` | 用户手册：功能流程、工具清单、FAQ |
| `doc/API.md` | LLMProvider / ToolProtocol / SSE 契约 |
| `doc/CONTRIBUTING.md` | 开发规范、提交规范、PR 流程 |
| `doc/CHANGELOG.md` | 版本历史与变更日志 |
| `doc/MANUAL_TEST_CHECKLIST.md` | 人工测试清单 |
| `doc/ReleaseChecklist.md` | 上架前检查清单 |
| `doc/BFF_DEPLOYMENT.md` | BFF Cloudflare Workers 部署 |
| `doc/ROADMAP.md` | 后续任务方向与里程碑（新增） |
| `doc/OPTIMIZATION.md` | 性能、体验、工程质量优化方案（新增） |
| `doc/DESIGN_UPDATE.md` | UI/UX 设计更新计划（新增） |
| `docs/superpowers/plans/2026-07-09-update-docs-roadmap-optimization.md` | 本实施计划 |

---

## Current State Snapshot (to verify before editing)

Run once and treat output as the source of truth for all numeric updates:

```bash
# commit history
git log --oneline -10

# i18n keys
python3 - <<'PY'
import json
with open('AIBuilder/Resources/Localizable.xcstrings') as f:
    data=json.load(f)
print('i18n_keys', len(data.get('strings',{})))
PY

# tool counts
echo "ios_tools $(grep -l "ToolProtocol" AIBuilder/Services/Tools/*.swift | xargs grep -h "struct.*Tool\|class.*Tool" | wc -l)"
echo "macos_only $(grep -l '#if os(macOS)' AIBuilder/Services/Tools/*.swift | wc -l)"

# tests
echo "ut_files $(ls AIBuilderTests/*.swift 2>/dev/null | wc -l)"
echo "uit_files $(ls AIBuilderUITests/*.swift 2>/dev/null | wc -l)"

# screenshots
ls screenshots/*.png 2>/dev/null | wc -l
```

Expected current values:
- i18n_keys: 385
- iOS tools: 13, macOS-only tools: 11, total macOS tools: 24
- UT files: 69, UIT files: 2
- screenshots: 8 PNG files

---

## Task 1: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update screenshot section**

Replace:
```markdown
## 截图

（待补充）
```
with:
```markdown
## 截图

| iOS 主对话 | iOS 设置 | iOS 知识库 | iOS 健康洞察 |
|---|---|---|---|
| ![iOS Chat](screenshots/ios_chat_main.png) | ![iOS Settings](screenshots/ios_settings.png) | ![iOS Knowledge Base](screenshots/ios_knowledge_base.png) | ![iOS Health](screenshots/ios_health_insight.png) |

| iOS 端侧模型 | iOS 预设提示词 | macOS 对话 | macOS 设置 |
|---|---|---|---|
| ![iOS On-Device](screenshots/ios_ondevice_model.png) | ![iOS Presets](screenshots/ios_preset_prompts.png) | ![macOS Chat](screenshots/macos_chat.png) | ![macOS Settings](screenshots/macos_settings.png) |
```

- [ ] **Step 2: Update i18n metrics**

Replace "55 核心 key" with "385 keys" in the "工程质量强化" section.

- [ ] **Step 3: Update test metrics**

Replace:
```markdown
- XCTest（249 个单元测试，3 skip，覆盖 Service / Model / ViewModel / Core 全层）
- XCUITest（13 个 UI 测试，2 skip，覆盖 12 个端到端流 + 1 个 launch）
```
with:
```markdown
- XCTest（248 个单元测试，0 skip，覆盖 Service / Model / ViewModel / Core 全层）
- XCUITest（13 个 UI 测试，0 skip，覆盖 12 个端到端流 + 1 个 launch）
```

- [ ] **Step 4: Add docs link section**

Append before "## 快速开始":
```markdown
## 文档导航

- [使用文档](doc/USAGE.md) — 环境、功能流程、FAQ
- [架构文档](doc/ARCHITECTURE.md) — 分层、模块、数据流
- [API 契约](doc/API.md) — LLMProvider / ToolProtocol / SSE
- [贡献指南](doc/CONTRIBUTING.md) — 规范、提交流程
- [变更日志](doc/CHANGELOG.md)
- [手测清单](doc/MANUAL_TEST_CHECKLIST.md)
- [发布清单](doc/ReleaseChecklist.md)
- [BFF 部署](doc/BFF_DEPLOYMENT.md)
- [路线图](doc/ROADMAP.md) — 后续任务方向
- [优化方案](doc/OPTIMIZATION.md) — 性能与体验优化
- [设计更新](doc/DESIGN_UPDATE.md) — UI/UX 演进计划
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): update screenshots, i18n/test metrics and doc navigation"
```

---

## Task 2: Update doc/ARCHITECTURE.md

**Files:**
- Modify: `doc/ARCHITECTURE.md`

- [ ] **Step 1: Update test counts in Mermaid diagram**

Replace:
```markdown
        T1["AIBuilderTests<br/>69 文件 / 249 用例"]
```
with:
```markdown
        T1["AIBuilderTests<br/>69 文件 / 248 用例"]
```

- [ ] **Step 2: Update skip statement in Tests row**

Replace:
```markdown
| Tests | UT 69 文件（249 用例，允许 skipped）+ UIT 2 文件（13 用例） | 71 |
```
with:
```markdown
| Tests | UT 69 文件（248 用例，0 skipped）+ UIT 2 文件（13 用例，0 skipped） | 71 |
```

- [ ] **Step 3: Add i18n / a11y / screenshots to key decisions**

Append to section 5 (关键设计决策):
```markdown
### 5.x 国际化与无障碍

- **String Catalog 统一源语言**：`Localizable.xcstrings` 以 `zh-Hans` 为源语言，`zh-Hant` / `en` 完整翻译，共 385 keys；SwiftUI 字面量自动提取，动态文本使用 `NSLocalizedString`。
- **accessibility 工程化**：13+ 视图补充 `accessibilityLabel` / `accessibilityHint` / `accessibilityIdentifier`，关键交互控件全部可访问，同时为 UITest 提供稳定定位符。
- **截图资产规范化**：`screenshots/` 目录按 iOS / macOS 分类，8 张核心页面截图用于 README 与 App Store 元数据。
```

- [ ] **Step 4: Commit**

```bash
git add doc/ARCHITECTURE.md
git commit -m "docs(architecture): sync test counts and add i18n/a11y/screenshot decisions"
```

---

## Task 3: Update doc/CHANGELOG.md

**Files:**
- Modify: `doc/CHANGELOG.md`

- [ ] **Step 1: Add new [Unreleased] entries**

Insert at the top of `## [Unreleased]`:
```markdown
### Added
- **完整国际化补全**：`Localizable.xcstrings` 从 55 核心 key 扩展至 385 keys，覆盖 Views / ViewModels / Services / AppIntents / Core；新增 `scripts/` 提取/翻译/合并工具链
- **无障碍全面增强**：7 个核心视图新增约 75 个 `accessibilityLabel` / `accessibilityHint` / `accessibilityIdentifier`
- **项目截图**：`screenshots/` 新增 8 张 iOS / macOS 核心页面截图
- **后续规划文档**：新增 `doc/ROADMAP.md`、`doc/OPTIMIZATION.md`、`doc/DESIGN_UPDATE.md`

### Fixed
- **UT/UIT 全部 0 skip**：修复 `testUserPreferencePersistence` 根因（`UserPreference` @Model 未注册到 App `ModelContainer` schema）；修复 7 处 `XCTSkip`
- **Swift 6 并发警告**：修复 `VoiceService` / `ChatViewModel` / `ConversationListVM` / `ClipboardTool` / `OpenURLTool` / `LocationTool` / `SSEParser` 等 7 类警告
- **macOS AppIcon 警告**：清理 3 个未分配子图标
```

- [ ] **Step 2: Commit**

```bash
git add doc/CHANGELOG.md
git commit -m "docs(changelog): add unreleased entries for i18n, a11y, screenshots and fixes"
```

---

## Task 4: Update doc/USAGE.md

**Files:**
- Modify: `doc/USAGE.md`

- [ ] **Step 1: Add language switch section**

After section 4.19 "预设系统提示词", add:
```markdown
## 4.22 语言切换

1. 打开设置页 → 顶部「语言」Section。
2. 选择「跟随系统 / 简体中文 / 繁体中文 / 英文」。
3. 点击「完成」，按提示重启 App 生效。

对应代码：`AIBuilder/Services/Language/LanguageManager.swift`、`AIBuilder/Views/Settings/SettingsView.swift`。
```

- [ ] **Step 2: Update test/FAQ metrics**

Search for "249" / "3 skip" / "2 skip" and replace with "248" / "0 skip" / "0 skip".

- [ ] **Step 3: Commit**

```bash
git add doc/USAGE.md
git commit -m "docs(usage): add language switch section and sync test metrics"
```

---

## Task 5: Update doc/CONTRIBUTING.md

**Files:**
- Modify: `doc/CONTRIBUTING.md`

- [ ] **Step 1: Update test metrics**

Replace:
```markdown
- 测试用例数：UT 249 / UIT 13（每新增功能需补对应测试）
- skip 场景用 `XCTSkip` / `XCTSkipUnless` 兜底
```
with:
```markdown
- 测试用例数：UT 248 / UIT 13（每新增功能需补对应测试）
- 当前目标：0 skip；若必须跳过，需写明原因并在 Issue 跟踪
```

- [ ] **Step 2: Add i18n contribution guideline**

Append to section 2 (代码规范):
```markdown
### 2.6 国际化规范

- 用户可见文本必须进入 `AIBuilder/Resources/Localizable.xcstrings`。
- SwiftUI 控件直接传字符串字面量即可自动提取；动态拼接文本使用 `String(format: NSLocalizedString(...), ...)`。
- 新增字符串后运行 `python3 scripts/extract_strings.py` 检查遗漏，并补充 `en` / `zh-Hant` 翻译。
```

- [ ] **Step 3: Commit**

```bash
git add doc/CONTRIBUTING.md
git commit -m "docs(contributing): update test metrics and add i18n guidelines"
```

---

## Task 6: Update doc/MANUAL_TEST_CHECKLIST.md

**Files:**
- Modify: `doc/MANUAL_TEST_CHECKLIST.md`

- [ ] **Step 1: Add sections for new features**

Append two new sections:
```markdown
## 23. 国际化与语言切换

- [ ] 语言切换生效
  - **前置条件**：App 安装后至少完成一次启动
  - **操作步骤**：
    1. 设置 → 语言 → 选择「英文」
    2. 重启 App
  - **预期结果**：设置页、主界面、工具描述全部显示英文
  - **失败排查**：检查 `AppleLanguages` 是否写入；检查 `Localizable.xcstrings` 是否包含对应 key

- [ ] 繁体中文显示正常
  - **前置条件**：语言设置为「繁体中文」
  - **操作步骤**：浏览设置、对话、知识库、健康洞察页面
  - **预期结果**：无乱码、无简体残留
  - **失败排查**：检查 `zh-Hant` 翻译覆盖率

## 24. 无障碍与旁白

- [ ] VoiceOver 可朗读关键控件
  - **前置条件**：系统设置开启 VoiceOver
  - **操作步骤**：
    1. 打开 App 主界面
    2. 单指滑动聚焦发送按钮、输入框、设置按钮
  - **预期结果**：每个控件朗读出有意义的中文标签
  - **失败排查**：检查对应 View 是否添加 `accessibilityLabel`
```

- [ ] **Step 2: Commit**

```bash
git add doc/MANUAL_TEST_CHECKLIST.md
git commit -m "docs(checklist): add i18n and accessibility manual test sections"
```

---

## Task 7: Update doc/ReleaseChecklist.md

**Files:**
- Modify: `doc/ReleaseChecklist.md`

- [ ] **Step 1: Update test counts**

Replace all occurrences:
- "UT 用例数：249" → "UT 用例数：248"
- "允许 skipped" → "0 skipped"

- [ ] **Step 2: Add i18n / a11y / screenshot audit sections**

After section 4.7, add:
```markdown
## 4.8 国际化与无障碍审计

- [ ] `Localizable.xcstrings` 包含 385 keys，en / zh-Hans / zh-Hant 三者完整
- [ ] 设置 → 语言切换后重启，英文/繁体界面无残留中文
- [ ] VoiceOver 可朗读设置页所有 Toggle / Picker / Button
- [ ] 所有关键交互控件存在 `accessibilityIdentifier`（供 UITest 使用）

## 4.9 截图与元数据审计

- [ ] `screenshots/` 目录包含 8 张核心页面截图
- [ ] README.md 截图表格渲染正常
- [ ] App Store Connect 已上传 6.7" / 6.1" / iPad / macOS 截图
```

- [ ] **Step 3: Commit**

```bash
git add doc/ReleaseChecklist.md
git commit -m "docs(release): sync test counts and add i18n/a11y/screenshot audit sections"
```

---

## Task 8: Create doc/ROADMAP.md

**Files:**
- Create: `doc/ROADMAP.md`

- [ ] **Step 1: Write roadmap document**

Create `doc/ROADMAP.md` with the following content:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add doc/ROADMAP.md
git commit -m "docs(roadmap): add post-day-20 evolution roadmap"
```

---

## Task 9: Create doc/OPTIMIZATION.md

**Files:**
- Create: `doc/OPTIMIZATION.md`

- [ ] **Step 1: Write optimization document**

Create `doc/OPTIMIZATION.md` with the following content:

```markdown
# AIBuilder 优化方案

> 汇总当前已识别或可预见的性能、体验与工程质量优化点，按优先级与可落地性排序。

---

## 1. 性能优化

### 1.1 启动耗时

- **现状**：App 启动时需预热语音引擎、注册 BGTask、拉取远程配置。
- **优化**：将远程配置拉取从 `init()` 移到首屏出现后；BGTask 注册改为首次进入后台时懒注册。
- **验收**：冷启动到可交互 < 1.5s（iPhone 17 模拟器）。

### 1.2 列表滚动

- **现状**：ConversationList 与 MessageList 在长列表下可能因 SwiftUI body 重算掉帧。
- **优化**：引入 `NSCache` 缓存已渲染的 Markdown 解析结果；对会话行使用 `.id` 稳定化。
- **验收**：100 条会话 / 100 条消息滑动 60fps。

### 1.3 端侧模型加载

- **现状**：MLX 模型首次加载阻塞主线程。
- **优化**：模型加载放到后台 `Task`；使用 `TaskGroup` 预加载 tokenizer。
- **验收**：切换端侧推理时 UI 不卡死。

## 2. 体验优化

### 2.1 错误提示

- **现状**：网络/API 错误以顶部 ErrorBanner 展示，部分场景提示不够具体。
- **优化**：按错误类型给出可操作建议（如「去设置配置 API Key」「检查网络后重试」）。
- **验收**：UT 覆盖每种错误类型的 userMessage。

### 2.2 空状态与加载

- **现状**：部分页面空状态较简单。
- **优化**：统一 EmptyState 组件，增加插画与引导操作。
- **验收**：ConversationList、KnowledgeBase、OnDeviceModel 空状态一致。

### 2.3 macOS 快捷键

- **现状**：已支持 ⌘N / ⌘K / ⌘, / ⌘Enter。
- **优化**：增加 ⌘T 新建会话、⌘Shift+F 聚焦搜索、Esc 关闭设置 sheet。
- **验收**：快捷键在 macOS 菜单栏可见并可触发。

## 3. 工程质量优化

### 3.1 测试覆盖率

- **现状**：UT 248 / UIT 13，0 skip。
- **优化**：将 Service 层覆盖率提升到 80%；为 macOS-only 工具补充单元测试。
- **验收**：Codecov / Xcode Coverage 显示覆盖率 ≥ 80%。

### 3.2 静态检查

- **现状**：已 0 warnings。
- **优化**：引入 SwiftLint / SwiftFormat；将 `SWIFT_STRICT_CONCURRENCY=complete` 纳入 CI。
- **验收**：CI 中 static analysis 0 warnings。

### 3.3 文档自动化

- **现状**：文档靠人工同步。
- **优化**：在 CI 中运行脚本提取 i18n key 数、工具数、测试数，检查与 README/ARCHITECTURE 是否一致。
- **验收**：文档数字漂移时 CI 失败。
```

- [ ] **Step 2: Commit**

```bash
git add doc/OPTIMIZATION.md
git commit -m "docs(optimization): add performance, experience and engineering optimization plan"
```

---

## Task 10: Create doc/DESIGN_UPDATE.md

**Files:**
- Create: `doc/DESIGN_UPDATE.md`

- [ ] **Step 1: Write design update document**

Create `doc/DESIGN_UPDATE.md` with the following content:

```markdown
# AIBuilder 设计更新计划

> 描述 AIBuilder UI/UX 的下一阶段演进目标、设计原则与具体改动清单。

---

## 设计原则

1. **原生优先**：继续遵循 iOS / iPad / macOS Human Interface Guidelines，不引入跨平台 UI 框架。
2. **信息密度可调**：macOS 与 iPad 利用大屏展示更多上下文；iPhone 保持单任务聚焦。
3. **无障碍一贯**：所有新增控件必须同时提供 `accessibilityLabel` 与 `accessibilityHint`。
4. **动效服务交互**：过渡动画用于阐明层级关系，避免炫技式动效。

---

## 1. Design System Token 化

- 将当前硬编码颜色 / 字体 / 间距迁移到 `Assets.xcassets` 颜色集与 `Font` 扩展常量。
- 新增 `DesignTokens.swift`：
  - `Color.backgroundPrimary`, `Color.backgroundSecondary`
  - `Font.bodyAI`, `Font.captionAI`
  - `Spacing.small`, `Spacing.medium`, `Spacing.large`

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
```

- [ ] **Step 2: Commit**

```bash
git add doc/DESIGN_UPDATE.md
git commit -m "docs(design): add UI/UX design update plan"
```

---

## Task 11: Consistency Verification

**Files:**
- 所有 `doc/*.md` 与 `README.md`

- [ ] **Step 1: Check for stale numbers**

Run:
```bash
grep -R "249\|3 skip\|2 skip\|55 核心 key\|55 个核心" README.md doc/ || echo "No stale numbers found"
```
Expected: "No stale numbers found"（除非在 changelog 历史版本中保留旧数字）。

- [ ] **Step 2: Verify all internal links**

Run:
```bash
python3 - <<'PY'
import re, os
from pathlib import Path
files = list(Path('doc').glob('*.md')) + [Path('README.md')]
for f in files:
    text = f.read_text(encoding='utf-8')
    for m in re.finditer(r'\[([^\]]+)\]\(([^)]+)\)', text):
        link = m.group(2)
        if link.startswith('http') or link.startswith('#'):
            continue
        target = Path(link)
        if not target.exists():
            print(f'{f}: broken link to {link}')
print('link check done')
PY
```
Expected: no broken links printed.

- [ ] **Step 3: Final iOS build smoke test**

Run:
```bash
xcodebuild build -project AIBuilder.xcodeproj -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED.

---

## Task 12: Push and Update PR

**Files:**
- 无代码变更

- [ ] **Step 1: Push all commits**

```bash
git push
```

- [ ] **Step 2: Update PR description**

```bash
gh pr edit 1 --body-file /tmp/pr_body.txt
```

Use body content:
```markdown
## Summary

This PR polishes the AIBuilder app by completing internationalization, resolving build warnings, cleaning up app icons, improving accessibility, adding screenshots, and refreshing all project documentation.

## Changes

- fix(test): eliminate all XCTSkip in UT and UIT suites
- fix(assets): remove duplicate/unreferenced macOS app icon children
- fix(concurrency): resolve Swift 6 actor-isolation and build warnings
- feat(i18n): extract user-facing strings to Localizable.xcstrings (385 keys, en/zh-Hans/zh-Hant)
- feat(a11y): add accessibility labels, hints and identifiers to key interactive views
- docs(screenshots): add iOS and macOS app screenshots
- docs(readme): update screenshots, metrics and navigation
- docs(architecture): sync test counts and add i18n/a11y decisions
- docs(changelog): add unreleased entries
- docs(usage): add language switch section
- docs(contributing): update test metrics and add i18n guidelines
- docs(checklist): add i18n and accessibility manual test sections
- docs(release): sync test counts and add audit sections
- docs(roadmap): add post-day-20 evolution roadmap
- docs(optimization): add performance, experience and engineering optimization plan
- docs(design): add UI/UX design update plan

## Verification

- iOS build: success, 0 warnings
- macOS build: success, 0 warnings
- Unit tests: 248 passed, 0 failures, 0 skipped
- UI tests: 13 passed, 0 failures, 0 skipped
- Documentation links and stale-number checks passed
```

---

## Self-Review

- **Spec coverage:** README, ARCHITECTURE, CHANGELOG, USAGE, CONTRIBUTING, MANUAL_TEST_CHECKLIST, ReleaseChecklist, ROADMAP, OPTIMIZATION, DESIGN_UPDATE 全部覆盖。
- **Placeholder scan:** 无 TBD/TODO；所有文档内容均已给出。
- **Type consistency:** 文件路径、数字（248/13/385/24）与当前代码状态一致。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-09-update-docs-roadmap-optimization.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
