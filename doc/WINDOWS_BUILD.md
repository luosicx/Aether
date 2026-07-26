# Windows 构建指南

本指南说明如何构建 Aether Windows 客户端。

---

## 1. 概述

Aether Windows 客户端使用 **WPF .NET 8** 技术栈。

> **注意**：实际使用的是 **WPF**（Windows Presentation Foundation），而非 WinUI 3。项目通过 `UseWPF=true` 启用 WPF，目标框架为 `net8.0-windows`。

源码位于 `windows/Aether.Windows/` 目录，单元测试位于 `windows/Aether.Windows.Tests/` 目录。

---

## 2. 环境要求

| 项 | 要求 | 说明 |
|----|------|------|
| 操作系统 | Windows 10 / 11 x64 | WPF 仅支持 Windows；`net8.0-windows` TFM 需要 Windows SDK |
| .NET SDK | 8.0 | 构建 WPF .NET 8 项目 |
| IDE | Visual Studio 2022 或 VS Code | 需含 .NET 桌面开发工作负载 |
| PowerShell | 7+（pwsh） | 执行 `scripts/build-windows.ps1` 构建脚本 |
| Rust | 1.75+（可选） | 构建 `aether_core_ffi.dll` 所需；不构建 DLL 时可省略 |
| Rust target | x86_64-pc-windows-msvc | `rustup target add x86_64-pc-windows-msvc` |

> 下载 .NET 8 SDK：https://dotnet.microsoft.com/download/dotnet/8.0
>
> 下载 Rust：https://rustup.rs

---

## 3. 项目结构

`windows/Aether.Windows/` 包含 13 个 `.cs` 源文件，按职责拆分：

```
windows/Aether.Windows/
├── Aether.Windows.csproj          # WPF .NET 8 项目文件
├── App.xaml / App.xaml.cs         # 应用入口
├── MainWindow.xaml / .cs          # 主窗口
├── Services/                      # 业务服务
│   ├── AetherApiClient.cs         # BFF API 客户端（含 SSE 流式）
│   ├── BffConfigStore.cs          # BFF 配置持久化（DPAPI 加密 Token）
│   ├── LanguageService.cs         # 多语言切换
│   └── MarkdownRenderer.cs        # Markdig → FlowDocument 渲染
├── ViewModels/                    # MVVM ViewModel
│   ├── ChatViewModel.cs
│   ├── ConversationListViewModel.cs
│   └── SettingsViewModel.cs
├── Views/                         # WPF 页面
│   ├── ChatPage.xaml
│   ├── ConversationListPage.xaml
│   └── SettingsPage.xaml
├── Models/                        # 数据模型
├── Design/                        # 设计令牌（颜色 / 间距）
├── Converters/                    # XAML 值转换器
├── Native/                        # Rust FFI 桥接
│   └── AetherNativeBridge.cs      # P/Invoke 调用 aether_core_ffi.dll
└── Properties/                    # 资源文件（8 种语言 .resx）
    ├── Strings.resx               # 默认 zh-Hans
    ├── Strings.en.resx
    ├── Strings.ja.resx
    ├── Strings.ko.resx
    ├── Strings.fr.resx
    ├── Strings.de.resx
    ├── Strings.es.resx
    └── Strings.zh-Hant.resx
```

单元测试项目 `windows/Aether.Windows.Tests/` 包含 7 个测试文件，共 72 个测试用例（xUnit）。

---

## 4. 构建步骤

### 4.1 使用 make（推荐）

在 **Windows** 上（需安装 `make` 与 `pwsh`），项目根目录执行：

```powershell
make build-windows
```

> `make` 在 Windows 上可通过 Chocolatey（`choco install make`）或 Scoop（`scoop install make`）安装。

### 4.2 构建 Rust FFI DLL（可选）

若需重建 `aether_core_ffi.dll`（CI 已自动构建并下载，本地无 Rust 环境可跳过）：

```powershell
rustup target add x86_64-pc-windows-msvc
cd rust/aether-core-ffi
cargo build -p aether-core-ffi --target x86_64-pc-windows-msvc --release
```

产物路径：`rust/target/x86_64-pc-windows-msvc/release/aether_core_ffi.dll`

将 DLL 复制到 Native 目录：

```powershell
copy rust\target\x86_64-pc-windows-msvc\release\aether_core_ffi.dll windows\Aether.Windows\Native\
```

> `Aether.Windows.csproj` 通过 `Condition="Exists('Native\aether_core_ffi.dll')"` 条件引用 DLL，本地无 DLL 时不破坏构建，`AetherNativeBridge` 会捕获 `DllNotFoundException` 安全降级。

### 4.3 构建 .NET 项目

在 `windows/Aether.Windows/` 目录下：

```powershell
cd windows/Aether.Windows
dotnet restore
dotnet build --configuration Debug
```

也可通过 PowerShell 脚本：

```powershell
pwsh scripts/build-windows.ps1 -Command build
```

脚本会切换到 `windows/Aether.Windows/` 目录，依次执行 `dotnet restore` 与 `dotnet build --configuration Debug`。

### 4.4 运行测试

```powershell
dotnet test windows/Aether.Windows.Tests/Aether.Windows.Tests.csproj --configuration Debug --logger trx
```

也可通过脚本：

```powershell
pwsh scripts/build-windows.ps1 -Command test
```

> CI 在 `windows-build` job 中执行 `dotnet test --configuration Debug --logger trx`，TRX 日志供 GitHub Actions 测试报告消费。

---

## 5. 技术栈说明

`windows/Aether.Windows/Aether.Windows.csproj` 关键配置：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <RuntimeIdentifiers>win-x64;win-arm64</RuntimeIdentifiers>
    <UseWPF>true</UseWPF>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <LangVersion>latest</LangVersion>
    <RootNamespace>Aether.Windows</RootNamespace>
  </PropertyGroup>
</Project>
```

- `TargetFramework=net8.0-windows`：依赖 Windows，使用 .NET 8
- `UseWPF=true`：启用 WPF（非 WinUI 3）
- `OutputType=WinExe`：生成 Windows 可执行文件
- `RuntimeIdentifiers=win-x64;win-arm64`：RID 包含两种架构，但 Rust FFI DLL 仅构建 x64，实际仅支持 win-x64

---

## 6. 发布说明

### 6.1 使用 make

```powershell
make publish-windows
```

### 6.2 使用 PowerShell 脚本

```powershell
pwsh scripts/build-windows.ps1 -Command publish
```

默认发布参数：`-Configuration Release -Runtime win-x64 --self-contained`，产出**自包含**的 win-x64 发布包（不依赖目标机器预装 .NET 运行时）。

也可指定参数：

```powershell
pwsh scripts/build-windows.ps1 -Command publish -Configuration Release -Runtime win-x64
```

### 6.3 发布产物

产物位于 `windows/Aether.Windows/bin/Release/net8.0-windows/win-x64/publish/`，可整体打包为 zip 分发。

---

## 7. 已实现功能（v1.5）

- **会话列表 UI + 设置页 + DPAPI Token 加密**：新增 `ConversationListPage` + `SettingsPage` + 3 个 ViewModel；BFF 配置从硬编码改为 `BffConfigStore` 持久化（DPAPI 加密 Token）。
- **消息气泡左右区分 + TypingIndicator**：用户消息右对齐 AetherPurple，AI 消息左对齐 LiquidGlass；流式响应时显示三圆点闪烁动画。
- **Markdown 渲染（Markdig 0.37.0）**：AI 消息用 `RichTextBox` + `FlowDocument` 渲染（支持标题 / 代码块 / 表格 / 任务列表 / 链接 / 加粗斜体）。
- **i18n 国际化（8 种语言 .resx）**：8 种语言 `.resx` 文件（zh-Hans / en / ja / ko / fr / de / es / zh-Hant），`LanguageService` 管理语言切换。
- **已集成 Rust DLL（SSE 解析 + 向量数学 + 脱敏）**：通过 `windows/Aether.Windows/Native/` 目录引用 `aether_core_ffi.dll`，CI 在 `windows-build` job 中自动构建并下载到该目录；`AetherNativeBridge` 提供 P/Invoke 桥接（DLL 不存在时安全降级），`AetherApiClient.UseRustSse` 可切换 SSE 解析路径。
- **流式聊天（SSE）**：`AetherApiClient` 通过 SSE 接收 BFF 流式响应，支持 Rust DLL 与纯 C# 双路径。
- **已新增 Aether.Windows.Tests xUnit 项目**：`windows/Aether.Windows.Tests/` 提供 7 个测试文件、72 个测试用例，CI 在 `windows-build` job 中执行 `dotnet test`，`scripts/build-windows.ps1 -Command test` 同样会扫描并运行测试项目。

### 7.1 功能清单

| 功能 | 状态 | 说明 |
|------|------|------|
| 会话列表 UI | ✅ | ConversationListPage（加载 / 创建 / 删除 / 置顶） |
| 设置页 | ✅ | SettingsPage（BFF URL / Token / 模型 / 语言） |
| Markdown 渲染 | ✅ | Markdig 0.37.0 + RichTextBox + FlowDocument |
| i18n 国际化 | ✅ | 8 种语言 .resx，LanguageService 切换 |
| DPAPI Token 加密 | ✅ | BffConfigStore 持久化，System.Security.Cryptography.ProtectedData |
| 消息气泡左右区分 | ✅ | 用户右对齐 AetherPurple / AI 左对齐 LiquidGlass |
| TypingIndicator | ✅ | 流式响应三圆点闪烁 |
| 流式聊天（SSE） | ✅ | Rust DLL + 纯 C# 双路径 |
| Rust FFI 集成 | ✅ | SSE 解析 + 向量数学 + 脱敏 |
| 单元测试 | ✅ | Aether.Windows.Tests xUnit，7 文件 72 用例 |

---

## 8. 依赖列表

`windows/Aether.Windows/Aether.Windows.csproj` 关键 NuGet 依赖：

| 包名 | 版本 | 用途 |
|------|------|------|
| Markdig | 0.37.0 | Markdown 解析为 FlowDocument，AI 消息渲染（标题 / 代码块 / 表格 / 任务列表 / 链接 / 加粗斜体） |
| System.Security.Cryptography.ProtectedData | 9.0.0 | DPAPI 加密 BFF Token，本地持久化（BffConfigStore） |

> WPF .NET 8 自带的 `PresentationFramework` / `System.Net.Http` / `System.Text.Json` 等基础库随 `net8.0-windows` TFM 自动引入，无需显式声明。

---

## 9. CI 集成

CI 工作流定义于 `.github/workflows/ci.yml` 的 `windows-build` job（第 1051-1114 行），运行在 `windows-latest` runner，超时 20 分钟，依赖 `rust` job。

关键步骤：

1. **Setup .NET 8**：`actions/setup-dotnet@v4` 安装 .NET SDK 8.0.x
2. **Setup Rust toolchain**：`dtolnay/rust-toolchain@stable` 安装 Rust 并添加 `x86_64-pc-windows-msvc` target
3. **Rust cache**：`Swatinem/rust-cache@v2` 缓存 Rust 编译产物
4. **Build Rust DLL**：`cargo build -p aether-core-ffi --target x86_64-pc-windows-msvc --release`
5. **Upload DLL artifact**：将 `aether_core_ffi.dll` 上传为 artifact `aether-core-windows-dll`
6. **Download DLL into Native/**：下载 DLL 到 `windows/Aether.Windows/Native/`
7. **Restore dependencies**：`dotnet restore`
8. **Build (Debug)**：`dotnet build --configuration Debug --no-restore`
9. **Test**：`dotnet test windows/Aether.Windows.Tests/Aether.Windows.Tests.csproj --configuration Debug --logger trx`
10. **Upload build artifact**：上传 `windows/Aether.Windows/bin/Debug/` 为 artifact `windows-exe`

---

## 10. 已知限制

- **仅 x64 架构**：Rust FFI DLL 仅构建 `x86_64-pc-windows-msvc`，无 ARM64 产物（csproj `RuntimeIdentifiers` 包含 `win-arm64` 但实际不可用）。
- **无 MSIX 打包**：当前仅以 zip 方式发布，未提供 MSIX 应用包安装方案。
- **无端侧 MLX 推理**：未集成 mlx-swift，仅依赖 BFF 代理 LLM 服务。
- **无多模态**：未实现 NativeVision / ASR / TTS，无可视化 / 语音能力。
- **无 HealthKit**：Windows 平台无 HealthKit 等价 API，未实现健康洞察 UI。
- **无 RAG 知识库 UI**：API 已提供 `searchDocuments` 端点，客户端未实现 UI（资源 key 已预留）。
- **无工具调用 UI**：工具调用由 BFF 端执行，客户端无独立 UI。
- **无离线模式**：依赖 BFF 在线服务，无本地推理 / 缓存。
- **无本地数据库**：未集成 SQLite / EF Core，无会话本地持久化（除 `BffConfigStore` 外）。
- **无 UI 自动化测试**：未集成 WPF UI 自动化测试框架，仅覆盖模型与服务层单元测试。
- **无 watchOS / Widget**：Windows 平台无对应扩展机制。
