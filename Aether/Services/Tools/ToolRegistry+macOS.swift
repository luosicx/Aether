/// Task 2.6: macOS 独有工具注册扩展。
/// 仅属于 Aether-macOS target，无需 #if os(macOS) 条件编译。
/// 在 macOS App init() 中调用 ToolRegistry.shared.registerMacOSTools()。

import Foundation

extension ToolRegistry {
    /// 注册 macOS 独有工具（11 个）。
    /// 调用时机：macOS App init() 中，在 ToolRegistry.shared 初始化后调用。
    func registerMacOSTools() {
        register(tool: AppleScriptTool())
        register(tool: ScreenshotTool())
        register(tool: OCRTool())
        register(tool: TerminalCommandTool())
        register(tool: WindowManagementTool())
        register(tool: AppManagementTool())
        register(tool: FileOperationTool())
        register(tool: FinderTool())
        register(tool: SafariControlTool())
        register(tool: SystemControlTool())
        register(tool: InputAutomationTool())

        // 注册 macOS 工具后重新恢复启用状态（包含新增工具的默认值）
        restoreEnabledStates()
    }
}
