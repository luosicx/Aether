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

## 6. 已知限制

- **未集成 Rust DLL**：Rust 侧 `cdylib` crate 可产出 Windows DLL，但当前未实际构建并接入 WPF 项目，Windows 端暂不调用 Rust core。
- **无测试覆盖**：Windows 项目当前无测试项目（`scripts/build-windows.ps1 -Command test` 已预留，但找不到 `*Test*.csproj` 会跳过）。
- **无 MSIX 打包**：当前仅以 zip 方式发布，未提供 MSIX 应用包安装方案。
- **仅支持 win-x64**：发布默认且仅验证 win-x64，未覆盖 win-arm64 架构。
