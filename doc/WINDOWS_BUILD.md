# Windows 构建指南

本指南说明如何构建 Aether Windows 客户端。

---

## 1. 概述

Aether Windows 客户端使用 **WPF .NET 8** 技术栈。

> **注意**：实际使用的是 **WPF**（Windows Presentation Foundation），而非 WinUI 3。项目通过 `UseWPF=true` 启用 WPF，目标框架为 `net8.0-windows`。

源码位于 `windows/Aether.Windows/` 目录。

---

## 2. 环境要求

| 项 | 要求 | 说明 |
|----|------|------|
| .NET SDK | 8.0 | 构建 WPF .NET 8 项目 |
| 操作系统 | Windows 10+ | WPF 仅支持 Windows；`net8.0-windows` TFM 需要 Windows SDK |
| PowerShell | 7+（pwsh） | 执行 `scripts/build-windows.ps1` 构建脚本 |

> 下载 .NET 8 SDK：https://dotnet.microsoft.com/download/dotnet/8.0

---

## 3. 快速开始

### 3.1 使用 make（推荐）

在 **Windows** 上（需安装 `make` 与 `pwsh`），项目根目录执行：

```powershell
make build-windows
```

> `make` 在 Windows 上可通过 Chocolatey（`choco install make`）或 Scoop（`scoop install make`）安装。

### 3.2 直接调用 PowerShell 脚本

```powershell
pwsh scripts/build-windows.ps1 -Command build
```

脚本会切换到 `windows/Aether.Windows/` 目录，依次执行 `dotnet restore` 与 `dotnet build --configuration Debug`。

### 3.3 直接使用 dotnet CLI

在 `windows/Aether.Windows/` 目录下：

```powershell
cd windows/Aether.Windows
dotnet restore
dotnet build --configuration Debug
```

---

## 4. 技术栈说明

`windows/Aether.Windows/Aether.Windows.csproj` 关键配置：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
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

---

## 5. 发布说明

### 5.1 使用 make

```powershell
make publish-windows
```

### 5.2 使用 PowerShell 脚本

```powershell
pwsh scripts/build-windows.ps1 -Command publish
```

默认发布参数：`-Configuration Release -Runtime win-x64 --self-contained`，产出**自包含**的 win-x64 发布包（不依赖目标机器预装 .NET 运行时）。

也可指定参数：

```powershell
pwsh scripts/build-windows.ps1 -Command publish -Configuration Release -Runtime win-x64
```

### 5.3 发布产物

产物位于 `windows/Aether.Windows/bin/Release/net8.0-windows/win-x64/publish/`，可整体打包为 zip 分发。

---

## 6. 已实现功能（v1.5）

- **会话列表 UI + 设置页 + DPAPI Token 加密**：新增 `ConversationListPage` + `SettingsPage` + 3 个 ViewModel；BFF 配置从硬编码改为 `BffConfigStore` 持久化（DPAPI 加密 Token）。
- **消息气泡左右区分 + TypingIndicator**：用户消息右对齐 AetherPurple，AI 消息左对齐 LiquidGlass；流式响应时显示三圆点闪烁动画。
- **Markdown 渲染（Markdig 0.37.0）**：AI 消息用 `RichTextBox` + `FlowDocument` 渲染（支持标题 / 代码块 / 表格 / 任务列表 / 链接 / 加粗斜体）。
- **i18n 国际化（8 种语言 .resx）**：8 种语言 `.resx` 文件（zh-Hans / en / ja / ko / fr / de / es / zh-Hant），`LanguageService` 管理语言切换。
- **已集成 Rust DLL（SSE 解析 + 向量数学 + 脱敏）**：通过 `windows/Aether.Windows/Native/` 目录引用 `aether_core_ffi.dll`，CI 在 `windows-build` job 中自动构建并下载到该目录；`AetherNativeBridge` 提供 P/Invoke 桥接（DLL 不存在时安全降级），`AetherApiClient.UseRustSse` 可切换 SSE 解析路径。
- **已新增 Aether.Windows.Tests xUnit 项目**：`windows/Aether.Windows.Tests/` 提供模型与 API 客户端测试，CI 在 `windows-build` job 中执行 `dotnet test`，`scripts/build-windows.ps1 -Command test` 同样会扫描并运行测试项目。
- **支持 win-x64 与 win-arm64**：通过 `RuntimeIdentifiers` 配置两种架构，使用 `build-windows.ps1 -Runtime win-arm64` 指定目标架构（默认 win-x64）。

### 6.1 功能清单

| 功能 | 状态 | 说明 |
|------|------|------|
| 会话列表 UI | ✅ | ConversationListPage（加载 / 创建 / 删除 / 置顶） |
| 设置页 | ✅ | SettingsPage（BFF URL / Token / 模型 / 语言） |
| Markdown 渲染 | ✅ | Markdig 0.37.0 + RichTextBox + FlowDocument |
| i18n 国际化 | ✅ | 8 种语言 .resx，LanguageService 切换 |
| DPAPI Token 加密 | ✅ | BffConfigStore 持久化，System.Security.Cryptography.ProtectedData |
| 消息气泡左右区分 | ✅ | 用户右对齐 AetherPurple / AI 左对齐 LiquidGlass |
| TypingIndicator | ✅ | 流式响应三圆点闪烁 |
| Rust DLL 集成 | ✅ | SSE 解析 + 向量数学 + 脱敏 |
| 单元测试 | ✅ | Aether.Windows.Tests xUnit |
| 多架构发布 | ✅ | win-x64 + win-arm64 |

---

## 7. 依赖列表

`windows/Aether.Windows/Aether.Windows.csproj` 关键 NuGet 依赖：

| 包名 | 版本 | 用途 |
|------|------|------|
| Markdig | 0.37.0 | Markdown 解析为 FlowDocument，AI 消息渲染（标题 / 代码块 / 表格 / 任务列表 / 链接 / 加粗斜体） |
| System.Security.Cryptography.ProtectedData | 9.0.0 | DPAPI 加密 BFF Token，本地持久化（BffConfigStore） |

> WPF .NET 8 自带的 `PresentationFramework` / `System.Net.Http` / `System.Text.Json` 等基础库随 `net8.0-windows` TFM 自动引入，无需显式声明。

---

## 8. 已知限制

- **无 MSIX 打包**：当前仅以 zip 方式发布，未提供 MSIX 应用包安装方案。
- **无端侧 MLX 推理**：未集成 mlx-swift，仅依赖 BFF 代理 LLM 服务。
- **无多模态**：未实现 NativeVision / ASR / TTS，无可视化 / 语音能力。
- **无 HealthKit**：Windows 平台无 HealthKit 等价 API，未实现健康洞察 UI。
- **无 RAG 知识库 UI**：API 已提供 `searchDocuments` 端点，客户端未实现 UI。
- **无工具调用 UI**：工具调用由 BFF 端执行，客户端无独立 UI。
- **无离线模式**：依赖 BFF 在线服务，无本地推理 / 缓存。
- **无本地数据库**：未集成 SQLite / EF Core，无会话本地持久化（除 `BffConfigStore` 外）。
- **无 watchOS / Widget**：Windows 平台无对应扩展机制。
