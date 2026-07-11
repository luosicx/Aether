# 安全漏洞修复记录

## 概述

本修复针对 Aether 项目中 LLM 可调用的系统/自动化工具存在的越权执行、命令注入、路径遍历与输入模拟等安全风险，引入工具风险分级与执行前确认框架，并对高危险工具进行加固。

## 修复内容

### 1. 工具风险分级与确认框架

- 在 `ToolProtocol` 中新增 `ToolRiskLevel`（normal / sensitive / dangerous）。
- 新增 `ToolConfirmationService` 协议与默认实现 `DefaultToolConfirmationService`。
- `ToolRegistry.execute(name:arguments:)` 在执行敏感/危险工具前，先调用 `confirmationService.confirm(tool:arguments:)`；用户取消时抛出 `NSError(domain: "ToolRegistry", code: 2)`。

### 2. 高危工具加固

| 工具 | 风险等级 | 关键加固措施 |
|------|----------|--------------|
| `TerminalCommandTool` | dangerous | 白名单机制，仅允许 `ls/pwd/git/brew`；命令按 token 拆分后直接设置 `Process.executableURL`，禁止通过 `/bin/bash -c` 执行任意字符串；30 秒超时。 |
| `AppleScriptTool` | dangerous | 新增 `isEnabled` 开关，默认关闭；未启用时直接返回错误。 |
| `FileOperationTool` | dangerous | 引入 `FileOperationSandbox`，限制只能访问文档目录与临时目录；阻止 `..` 路径遍历；删除/覆盖操作默认需要二次确认。 |
| `SafariControlTool` | dangerous | `run_js` 已禁用；`navigate`/`new_tab` 仅允许 https 且域名白名单（openai.com、deepseek.com、apple.com、google.com）。 |
| `InputAutomationTool` | dangerous | 鼠标点击/拖拽限制在距离屏幕边缘 50px 的安全区域；禁止模拟系统键（space/return 等）与系统级修饰键组合（command/option/control）。 |

## 集成测试

新增测试覆盖确认框架：

- `ToolRegistryTests.testExecuteDangerousToolDeniedThrowsCode2`：确认服务拒绝时，危险工具执行被取消并返回 `ToolRegistry` code 2。
- `ToolRegistryTests.testExecuteNormalToolDoesNotRequireConfirmation`：普通工具无需确认即可执行成功。

## 相关文件

- `Aether/Core/Protocols/ToolProtocol.swift`
- `Aether/Services/Tools/ToolConfirmationService.swift`
- `Aether/Services/Tools/ToolRegistry.swift`
- `Aether/Services/Tools/TerminalCommandTool.swift`
- `Aether/Services/Tools/AppleScriptTool.swift`
- `Aether/Services/Tools/FileOperationTool.swift`
- `Aether/Services/Tools/SafariControlTool.swift`
- `Aether/Services/Tools/InputAutomationTool.swift`
- `AetherTests/ToolRegistryTests.swift`
