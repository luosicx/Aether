# SonarCloud 集成配置教程

> 本文档详细说明如何为 Aether 项目配置 SonarCloud 代码质量扫描，包含账号注册、Token 配置、质量门设置及常见问题排查。

## 目录

1. [SonarCloud 账号注册与项目创建](#1-sonarcloud-账号注册与项目创建)
2. [GitHub Secrets 配置](#2-github-secrets-配置)
3. [质量门配置](#3-质量门配置)
4. [本地扫描命令](#4-本地扫描命令)
5. [CI 流水线说明](#5-ci-流水线说明)
6. [常见问题排查](#6-常见问题排查)

---

## 1. SonarCloud 账号注册与项目创建

### 1.1 注册账号

1. 访问 [https://sonarcloud.io](https://sonarcloud.io)
2. 点击右上角 **Sign up**，选择 **Sign up with GitHub**（推荐）
3. 授权 SonarCloud 访问你的 GitHub 账号

### 1.2 导入项目

1. 登录后点击右上角 **+** → **Analyze new project**
2. 选择你的 GitHub Organization（如 `luosicx`）
3. 在仓库列表中勾选 `Aether` 项目
4. 点击 **Set Up**

### 1.3 获取项目信息

创建完成后，在 SonarCloud 项目页面记录以下信息：

| 字段 | 示例值 | 说明 |
|------|--------|------|
| **Organization Key** | `luosicx` | 对应 GitHub Organization 名 |
| **Project Key** | `luosicx_Aether` | SonarCloud 自动生成 |

---

## 2. GitHub Secrets 配置

CI 流水线需要两个 Secret 才能正常运行 SonarCloud 扫描：

### 2.1 生成 SONAR_TOKEN

1. 访问 [https://sonarcloud.io/account/security](https://sonarcloud.io/account/security)
2. 在 **Generate Token** 区域：
   - **Token name**：填写 `aether-ci`（自定义名称）
   - **Type**：选择 `Global Token`
   - **Expires in**：选择过期时间（建议 90 天或 1 年）
3. 点击 **Generate**，**立即复制** Token（页面关闭后无法再查看）

### 2.2 配置 GitHub Repository Secrets

1. 进入 GitHub 仓库页面 → **Settings** → **Secrets and variables** → **Actions**
2. 点击 **New repository secret**，分别添加：

| Secret 名称 | 值 | 说明 |
|-------------|---|------|
| `SONAR_TOKEN` | `squ_xxxxxxxxxxxxxxxxxxxxxx` | 上一步生成的 Token |
| `SONAR_HOST_URL` | `https://sonarcloud.io` | SonarCloud 固定地址 |

### 2.3 验证 Secrets 是否生效

推送代码到 `main` 分支或创建 PR 后，在 GitHub Actions 中查看 `code-quality` job：

- 如果 job **正常运行**且 SonarCloud 面板出现扫描结果 → 配置成功
- 如果 job **报错**或 **被跳过** → 参考下文[常见问题排查](#6-常见问题排查)

---

## 3. 质量门配置

### 3.1 SonarCloud 默认质量门

SonarCloud 默认使用 **Sonar way** 质量门，包含以下关键条件：

| 条件 | 默认阈值 | 说明 |
|------|---------|------|
| Coverage on New Code | >= 80% | 新增代码覆盖率 |
| Duplicated Lines on New Code | <= 3% | 新增代码重复率 |
| Maintainability Rating | A | 可维护性评级 |
| Reliability Rating | A | 可靠性评级 |
| Security Rating | A | 安全性评级 |

### 3.2 自定义质量门（可选）

1. 访问 [https://sonarcloud.io/quality_gates](https://sonarcloud.io/quality_gates)
2. 点击 **Create** 创建新质量门，或复制 **Sonar way** 后修改
3. 添加条件，例如：
   - `Coverage` >= `90%`（整体覆盖率）
   - `New Coverage` >= `80%`（新代码覆盖率）
4. 在项目设置中将自定义质量门关联到 Aether 项目

### 3.3 质量门状态检查

CI 中配置了 `sonar.qualitygate.wait=true`，这意味着：

- PR 提交后，CI 会等待 SonarCloud 返回质量门结果
- 如果质量门 **未通过**，CI job 会 **标记失败**
- 在 GitHub PR 页面可以看到 SonarCloud 的质量门状态检查

---

## 4. 本地扫描命令

### 4.1 前置条件

安装 SonarScanner CLI：

```bash
# macOS（通过 Homebrew）
brew install sonar-scanner

# 验证安装
sonar-scanner --version
```

### 4.2 执行本地扫描

```bash
# 设置 Token 环境变量
export SONAR_TOKEN="squ_xxxxxxxxxxxxxxxxxxxxxx"
export SONAR_HOST_URL="https://sonarcloud.io"

# 在项目根目录执行扫描
sonar-scanner

# 或指定额外参数
sonar-scanner \
  -Dsonar.projectKey=luosicx_Aether \
  -Dsonar.organization=luosicx
```

### 4.3 带覆盖率报告的本地扫描

```bash
# 1. 运行测试并生成覆盖率报告
xcodebuild test \
  -project Aether.xcodeproj \
  -scheme Aether \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult

# 2. 转换覆盖率为 Cobertura 格式
brew install xccov-to-cobertura 2>/dev/null || true
mkdir -p coverage-report
xccov-to-cobertura TestResults.xcresult -o coverage-report/cobertura.xml

# 3. 执行 SonarCloud 扫描
sonar-scanner
```

---

## 5. CI 流水线说明

### 5.1 流水线结构

```
unit-tests → coverage-summary → code-quality (SonarCloud)
                                    ↑
ui-tests ──────────────────────────┘
```

### 5.2 code-quality job 执行步骤

1. **Checkout** 代码（`fetch-depth: 0` 确保完整 Git 历史）
2. **下载覆盖率报告** artifact（从 unit-tests job 上传的 xcresult）
3. **转换覆盖率** 为 Cobertura XML 格式
4. **执行 SonarCloud 扫描**，读取 `sonar-project.properties` 配置
5. **等待质量门** 结果返回

### 5.3 关键配置文件

| 文件 | 作用 |
|------|------|
| `.github/workflows/ci.yml` | CI 流水线定义 |
| `sonar-project.properties` | SonarCloud 项目配置 |
| `.swiftlint.yml` | SwiftLint 规则（SonarCloud 可读取其结果） |

---

## 6. 常见问题排查

### 问题 1: CI 中 code-quality job 被跳过或静默失败

**原因**：`SONAR_TOKEN` 或 `SONAR_HOST_URL` 未在 GitHub Secrets 中配置。

**排查步骤**：
```bash
# 在 GitHub Actions 日志中搜索以下关键词
# "SonarQube Scan" → 查看扫描输出
# "SONAR_TOKEN" → 如果显示 "not set"，说明 Secret 未配置
```

**解决方案**：
1. 确认 Secret 名称完全匹配（区分大小写）：`SONAR_TOKEN`、`SONAR_HOST_URL`
2. 确认 Secret 添加在正确的层级（Repository level，而非 Environment level）
3. 对于 fork 仓库的 PR，GitHub 不会传递 Secrets → 这是预期行为

### 问题 2: SonarCloud 面板显示 "No analysis has been performed"

**原因**：扫描从未成功执行过。

**排查步骤**：
1. 检查 GitHub Actions 日志中 `code-quality` job 是否执行
2. 如果 job 存在但无结果，检查 Token 是否过期

**解决方案**：
```
1. 访问 https://sonarcloud.io/account/security
2. 检查 Token 状态，如已过期则重新生成
3. 更新 GitHub Secret 中的 SONAR_TOKEN
4. 重新触发 CI（推送空 commit 或重新运行 workflow）
```

### 问题 3: 覆盖率报告显示 0%

**原因**：Cobertura 转换失败或路径不匹配。

**排查步骤**：
```bash
# 在 CI 日志中检查 "Convert xcresult to cobertura" 步骤
# 如果显示 "WARN: cobertura conversion failed"，说明转换工具安装失败
```

**解决方案**：
1. 确认 `xccov-to-cobertura` 工具可通过 Homebrew 安装
2. 确认 `coverage-report/cobertura.xml` 路径与 `sonar-project.properties` 中 `sonar.swift.coverageReportPaths` 一致
3. 本地测试转换：`xccov-to-cobertura TestResults.xcresult -o test-cobertura.xml`

### 问题 4: 质量门始终显示 "Passed" 但代码质量有问题

**原因**：SonarCloud 的 Swift 分析器需要正确识别源码路径。

**排查步骤**：
1. 访问 SonarCloud 项目页面 → **Administration** → **General Settings**
2. 检查 **Source directories** 是否指向 `Aether`
3. 检查 **Test directories** 是否包含 `AetherTests`

### 问题 5: Fork PR 无法触发 SonarCloud 扫描

**原因**：GitHub Actions 对来自 fork 的 PR 默认不传递 Secrets（安全机制）。

**解决方案**：
1. 在仓库 **Settings** → **Actions** → **General** 中启用：
   - "Run workflows from fork pull requests"
   - "Send write tokens to workflows from pull requests"（谨慎开启）
2. 或者使用 SonarCloud 的 **PR Decoration** 功能（由 SonarCloud 自身处理 PR 评论，不依赖 CI Secrets）

---

## 附录：快速检查清单

配置完成后，按以下清单逐项确认：

- [ ] SonarCloud 账号已注册，项目已创建
- [ ] `SONAR_TOKEN` 已添加到 GitHub Repository Secrets
- [ ] `SONAR_HOST_URL` 已设置为 `https://sonarcloud.io`
- [ ] `sonar-project.properties` 存在于项目根目录
- [ ] CI 中 `code-quality` job 执行成功
- [ ] SonarCloud 面板显示扫描结果（代码行数、覆盖率等）
- [ ] 质量门状态在 PR 页面可见
