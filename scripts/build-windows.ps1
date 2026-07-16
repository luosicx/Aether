#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Aether Windows 构建脚本

.DESCRIPTION
    支持 WPF .NET 8 项目 (windows/Aether.Windows/) 的构建、发布、测试与清理。

.USAGE
    pwsh ./scripts/build-windows.ps1 -Command <build|publish|test|clean> [options]

.PARAMETER Command
    build     执行 dotnet restore + dotnet build --configuration Debug (默认)
    publish   执行 dotnet publish -c Release -r win-x64 --self-contained
    test      执行 dotnet test windows/Aether.Windows.Tests/ (xUnit)
    clean     执行 dotnet clean

.PARAMETER Configuration
    Debug | Release (默认 Debug)

.PARAMETER Runtime
    win-x64 | win-arm64 (默认 win-x64)

.EXAMPLE
    pwsh ./scripts/build-windows.ps1 -Command build
    pwsh ./scripts/build-windows.ps1 -Command publish -Configuration Release -Runtime win-x64
    pwsh ./scripts/build-windows.ps1 -Command clean
#>
[CmdletBinding()]
param(
    [ValidateSet('build', 'publish', 'test', 'clean')]
    [string]$Command = 'build',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = "Stop"

# 切换到项目根目录下的 Windows 项目目录
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptRoot ".." "windows" "Aether.Windows"
$projectDir = (Resolve-Path -LiteralPath $projectDir -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrEmpty($projectDir) -or -not (Test-Path -LiteralPath $projectDir)) {
    Write-Host "[ERROR] 未找到 Windows 项目目录: $projectDir" -ForegroundColor Red
    exit 1
}
Set-Location -LiteralPath $projectDir

# ====================================================================
# 日志函数
# ====================================================================

function Write-Info {
    param([string]$msg)
    Write-Host "[INFO] $msg" -ForegroundColor Green
}

function Write-Warn {
    param([string]$msg)
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Write-Ok {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Cyan
}

# ====================================================================
# 环境检查
# ====================================================================

function Test-DotNet {
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Err "未找到 dotnet CLI，请安装 .NET 8 SDK"
        Write-Err "下载地址: https://dotnet.microsoft.com/download/dotnet/8.0"
        exit 1
    }
    Write-Info "dotnet 版本: $(dotnet --version)"
}

# ====================================================================
# 命令实现
# ====================================================================

function Invoke-Build {
    Write-Info "开始构建 Windows (Configuration=$Configuration)"
    Write-Info "工作目录: $projectDir"

    Write-Info "执行 dotnet restore"
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        Write-Err "dotnet restore 失败 (exit=$LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Info "执行 dotnet build --configuration $Configuration"
    dotnet build --configuration $Configuration
    if ($LASTEXITCODE -ne 0) {
        Write-Err "dotnet build 失败 (exit=$LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Ok "BUILD SUCCEEDED: Windows $Configuration"
}

function Invoke-Publish {
    Write-Info "开始发布 Windows (Configuration=$Configuration, Runtime=$Runtime, SelfContained=true)"
    Write-Info "工作目录: $projectDir"

    Write-Info "执行 dotnet publish -c $Configuration -r $Runtime --self-contained"
    dotnet publish -c $Configuration -r $Runtime --self-contained
    if ($LASTEXITCODE -ne 0) {
        Write-Err "dotnet publish 失败 (exit=$LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Ok "PUBLISH SUCCEEDED: Windows $Configuration $Runtime"
}

function Invoke-Test {
    Write-Info "开始运行 Windows 测试"
    Write-Info "工作目录: $projectDir"

    # 测试项目位于 windows/Aether.Windows.Tests/（与 Aether.Windows 平级）
    $testProjectDir = Join-Path $scriptRoot ".." "windows" "Aether.Windows.Tests"
    $testProjectDir = (Resolve-Path -LiteralPath $testProjectDir -ErrorAction SilentlyContinue).Path

    if ([string]::IsNullOrEmpty($testProjectDir) -or -not (Test-Path -LiteralPath $testProjectDir)) {
        Write-Warn "未找到测试项目目录 windows/Aether.Windows.Tests/"
        Write-Warn "test 命令已预留，待添加测试项目后即可使用"
        return
    }

    $testCsproj = Get-ChildItem -Path $testProjectDir -Filter "*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $testCsproj) {
        Write-Warn "windows/Aether.Windows.Tests/ 下未找到 .csproj 文件"
        return
    }

    Write-Info "执行 dotnet test $($testCsproj.FullName) --configuration $Configuration"
    dotnet test $testCsproj.FullName --configuration $Configuration --logger trx
    if ($LASTEXITCODE -ne 0) {
        Write-Err "dotnet test 失败 (exit=$LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Ok "TEST SUCCEEDED: Windows"
}

function Invoke-Clean {
    Write-Info "清理 Windows 构建产物"
    Write-Info "工作目录: $projectDir"

    Write-Info "执行 dotnet clean"
    dotnet clean
    if ($LASTEXITCODE -ne 0) {
        Write-Err "dotnet clean 失败 (exit=$LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Ok "已清理 Windows 构建产物"
}

# ====================================================================
# 主逻辑
# ====================================================================

Write-Info "Aether Windows 构建脚本"
Write-Info "Command=$Command, Configuration=$Configuration, Runtime=$Runtime"

Test-DotNet

switch ($Command) {
    'build'   { Invoke-Build }
    'publish' { Invoke-Publish }
    'test'    { Invoke-Test }
    'clean'   { Invoke-Clean }
}
