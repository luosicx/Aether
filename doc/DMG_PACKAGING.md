# Aether macOS .dmg 打包指南

本指南介绍如何使用 `scripts/build-dmg.sh` 脚本为 Aether（以太）构建 macOS `.dmg` 安装包，涵盖无签名本地测试与签名 + 公证公开分发两种模式。

> **平台说明**：本文档仅覆盖 **macOS 独有**的 `.dmg` 打包方式。Aether 在各平台的分发格式如下：
>
> | 平台 | 分发格式 | 参考文档 |
> |------|----------|----------|
> | macOS | `.dmg`（本文档） | `doc/DMG_PACKAGING.md` |
> | Windows | `.exe` + `aether_core_ffi.dll` | `doc/WINDOWS_BUILD.md` |
> | Android | `.apk` | `doc/ANDROID_BUILD.md` |
> | iOS | TestFlight / App Store（通过 Xcode Organizer 上传） | Xcode Organizer 内置流程 |
>
> 跨平台 CI 集成详见 `.github/workflows/release.yml`。

## 项目信息

| 项 | 值 |
| --- | --- |
| 项目名 | Aether（以太） |
| Xcode 工程 | `Aether.xcodeproj` |
| Scheme | `Aether` |
| Bundle ID | `com.aether.app` |
| 部署目标 | macOS 14.0 |
| 打包脚本 | `scripts/build-dmg.sh` |

## 脚本参数说明

| 参数 | 说明 |
| --- | --- |
| `--unsigned` | 无签名模式（默认），Release 构建后直接生成 .dmg |
| `--signed` | Developer ID 签名模式，Archive 后导出签名 .app |
| `--notarize` | 配合 `--signed` 使用，提交 Apple 公证并装订票据 |
| `--app-version <ver>` | 覆盖版本号（默认从 Info.plist 读取） |
| `--help` | 查看用法 |

## 环境变量

签名 + 公证模式需要以下环境变量：

| 变量 | 说明 |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | 签名身份，如 `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID 邮箱 |
| `APP_SPECIFIC_PASSWORD` | App 专用密码（https://appleid.apple.com 生成） |
| `TEAM_ID` | 开发者团队 ID |

---

## 1. 前置条件

### 1.1 通用要求

- macOS 14.0+ 开发机
- Xcode 16+（含 Xcode Command Line Tools）
- 命令行验证：
  ```bash
  xcodebuild -version
  xcode-select -p
  ```

### 1.2 公证模式额外要求

若使用 `--signed --notarize` 进行公开分发，还需准备：

- **Apple Developer 账号**：付费会员资格
- **Developer ID Application 证书**：在 Apple Developer → Certificates, Identifiers & Profiles 中创建
- **App-Specific Password**：登录 https://appleid.apple.com 后生成
- **Team ID**：Apple Developer 账户概览页可查

---

## 2. 快速打包（无签名）

适用于本地测试与内部体验，不经过签名和公证流程。

### 2.1 执行命令

```bash
./scripts/build-dmg.sh --unsigned
```

### 2.2 全流程说明

1. **Release 构建**：使用 `xcodebuild` 以 Release 配置编译 `Aether` scheme
2. **定位 .app**：从构建产物中找到 `Aether.app`
3. **生成 .dmg**：将 `Aether.app` 与 `/Applications` 软链接一同打包为 UDZO 格式的只读 .dmg

### 2.3 产物

- 路径：`build/dmg/Aether-macOS-{version}-unsigned.dmg`
- 用途：**仅本地测试用**，不可公开分发

### 2.4 用户安装方式

由于未签名，安装时需绕过 Gatekeeper：

1. 双击 `.dmg` 挂载卷
2. 将 `Aether.app` 拖入 `/Applications`
3. 首次启动：在 Finder 中右键 `Aether.app` → **打开** → 在弹出的 Gatekeeper 警告中再次点击 **打开**

> ⚠️ 未签名版本在他人设备上会被 Gatekeeper 拦截，仅适合自己测试或团队内部使用。

---

## 3. 分发打包（签名 + 公证）

适用于公开分发，产物可被 Gatekeeper 直接放行。

### 3.1 配置环境变量

在执行脚本前导出以下变量（建议写入 `~/.zshrc` 或临时 `export`）：

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export TEAM_ID="TEAMID"
```

> 🔐 请勿将含敏感信息的变量提交到版本库，建议通过本地 profile 或 CI Secrets 注入。

### 3.2 执行命令

```bash
./scripts/build-dmg.sh --signed --notarize
```

如需覆盖版本号：

```bash
./scripts/build-dmg.sh --signed --notarize --app-version 1.2.0
```

### 3.3 全流程说明

1. **Archive**：使用 `xcodebuild archive` 将 `Aether` scheme 归档为 `.xcarchive`
2. **导出 Developer ID 签名 .app**：通过 `ExportArchive` 以 `Developer ID` 分发方式导出
3. **强化运行时签名**：使用 `codesign` 应用 Hardened Runtime 与 Developer ID 签名
4. **提交公证**：通过 `xcrun notarytool submit` 将 .app 上传至 Apple 公证服务
5. **装订票据**：公证通过后使用 `xcrun stapler staple` 将公证票据装订到 .app
6. **生成 .dmg**：将签名 + 公证完成的 .app 打包为 UDZO 格式只读 .dmg

### 3.4 产物

- 路径：`build/dmg/Aether-macOS-{version}.dmg`
- 用途：可直接公开分发，Gatekeeper 放行

### 3.5 提示

- 公证过程通常需要 **5–30 分钟**，脚本会自动等待结果
- 在网络不佳或 Apple 服务繁忙时可能更久，请耐心等待
- 若脚本在中途失败，可重新执行；公证若已通过，可手动执行 `xcrun stapler staple` 完成装订

---

## 4. 产物说明

### 4.1 命名规则

| 模式 | 文件名 |
| --- | --- |
| 签名模式 | `Aether-macOS-{版本}.dmg` |
| 无签名模式 | `Aether-macOS-{版本}-unsigned.dmg` |

### 4.2 输出目录

```
build/dmg/
└── Aether-macOS-{version}[-unsigned].dmg
```

### 4.3 DMG 元信息

| 属性 | 值 |
| --- | --- |
| 卷标 | `Aether` |
| 格式 | UDZO（zlib 压缩只读） |
| 内部结构 | `Aether.app` + `/Applications` 软链接 |

### 4.4 拖拽安装说明

挂载 .dmg 后，用户可见两个图标：

```
┌─────────────────────────────────────┐
│  Aether                              │
│                                      │
│   ┌──────────┐    ┌─────────────┐   │
│   │ Aether.app│ → │ Applications │   │
│   └──────────┘    └─────────────┘   │
│                                      │
└─────────────────────────────────────┘
```

将 `Aether.app` 拖至 `Applications` 软链接即可完成安装。

---

## 5. 故障排查

### 5.1 `xcodebuild` 失败

| 可能原因 | 排查方式 |
| --- | --- |
| Scheme 不匹配 | 确认 scheme 为 `Aether`：`xcodebuild -list` |
| 部署目标错误 | 确认 deployment target 为 macOS 14.0 |
| 平台条件编译缺失 | macOS 独有工具应使用 `#if os(macOS)` 守卫 |
| 派生数据损坏 | 清理后重试：`xcodebuild clean -scheme Aether-macOS` |

### 5.2 `codesign` 失败

| 可能原因 | 排查方式 |
| --- | --- |
| 证书未安装 | 在「钥匙串访问」中检查 Developer ID Application 证书是否存在 |
| 钥匙串未解锁 | `security unlock-keychain ~/Library/Keychains/login.keychain-db` |
| 证书名不一致 | `security find-identity -p codesigning -v`，确认与 `DEVELOPER_ID_APPLICATION` 完全一致 |
| Hardened Runtime 缺失 | 确认导出方式为 `Developer ID`，会自动启用 Hardened Runtime |

### 5.3 `notarytool` 失败

查看详细日志：

```bash
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --team-id "$TEAM_ID"
```

| 可能原因 | 解决方案 |
| --- | --- |
| 未启用强化运行时 | 确认 `--options runtime` 已传入 codesign |
| 含未签名 helper / 嵌入式二进制 | 对所有嵌入可执行文件递归签名 |
| Info.plist 缺少权限声明 | 补充 `NSAppleEventsUsageDescription` 等所需 entitlements |
| 凭据错误 | 确认 `APPLE_ID` / `APP_SPECIFIC_PASSWORD` / `TEAM_ID` 正确无误 |

### 5.4 `hdiutil` 失败

| 可能原因 | 排查方式 |
| --- | --- |
| 磁盘空间不足 | 检查 `/` 与 `build/` 所在卷可用空间 |
| staging 目录权限错误 | `ls -la build/dmg/staging/` 检查归属与可读写权限 |
| 软链接失效 | 确认 `/Applications` 软链接指向有效 |
| 进程占用 | 卸载已挂载的 .dmg：`hdiutil detach /Volumes/Aether` |

### 5.5 Gatekeeper 仍警告

诊断命令：

```bash
# 检查签名与公证状态
spctl -a -t exec -v Aether.app

# 验证公证票据是否已装订
xcrun stapler validate Aether.app

# 查看 .app 的签名详情
codesign -dvvv --verbose=4 Aether.app
```

常见原因：公证通过但未装订票据、签名后修改了文件内容、或 DMG 本身未随 .app 一起签名。

---

## 6. GitHub Release 集成

### 6.1 本地打包后手动上传

完成签名 + 公证后，使用 GitHub CLI 创建 Release 并上传 .dmg：

```bash
gh release create v{version} \
  build/dmg/Aether-macOS-{version}.dmg \
  --title "Aether v{version}" \
  --notes "Release notes"
```

如需附带 Release Notes 文件：

```bash
gh release create v{version} \
  build/dmg/Aether-macOS-{version}.dmg \
  --title "Aether v{version}" \
  --notes-file doc/CHANGELOG.md
```

### 6.2 CI 自动集成（release.yml）

`release.yml` 的 `build-macos` job 已自动判断签名模式，无需手动配置 workflow 文件。在仓库 Settings → Secrets and variables → Actions 中配置以下 4 个 secrets 即可启用签名与公证：

| Secret | 说明 |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | 签名身份，如 `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID 账号邮箱 |
| `APP_SPECIFIC_PASSWORD` | 在 https://appleid.apple.com 生成的 App-Specific Password |
| `TEAM_ID` | Apple Developer Team ID |

#### 自动判断逻辑

- 4 个 secrets 均配置时：调用 `./scripts/build-dmg.sh --signed --notarize`，产出 `Aether-macOS-{version}.dmg`
- 任一 secret 缺失时：回退 unsigned 模式，调用 `./scripts/build-dmg.sh --unsigned`，产出 `Aether-macOS-{version}-unsigned.dmg`，Release notes 中标注"未签名版本"

#### 触发流程

1. 在仓库 Settings → Secrets and variables → Actions 中配置上述 4 个 secrets
2. 推送 `v*` tag（如 `v1.2.0`）触发 release.yml
3. `build-macos` job 自动执行 Archive → 签名 → 公证 → 装订 → 打包 DMG
4. 产物作为 Release 资产上传至 GitHub Release 页面，附带 `.sha256` 校验文件

#### 签名验证

下载 DMG 挂载后，对 .app 执行以下命令验证签名与公证状态：

```bash
spctl -a -t exec -v Aether.app
# 退出码 0 表示签名通过，输出含 "accepted"
```

#### 未签名模式提示

未配置 secrets 时，Release body 中包含以下提示：

> ⚠️ macOS DMG 未签名，首次打开需右键 → 打开绕过 Gatekeeper

---

> 📚 相关文档：[ReleaseChecklist.md](./ReleaseChecklist.md) · [CHANGELOG.md](./CHANGELOG.md)
