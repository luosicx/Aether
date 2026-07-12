/// 快捷指令工具集（跨平台：iOS + macOS）
///
/// 提供快捷指令的执行、列出和创建能力，包含三个工具：
/// - RunShortcutTool：按名称执行快捷指令
/// - ListShortcutsTool：列出设备上所有快捷指令
/// - CreateShortcutTool：生成 .shortcut 文件并打开 Shortcuts 应用导入
/// macOS 通过 Process 调用 shortcuts CLI 实现，iOS 通过 NSUserActivity 触发。
/// 调用方式：各工具的 execute(arguments:) 方法。
import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - RunShortcutTool
/// 快捷指令执行工具，跨平台
final class RunShortcutTool: ToolProtocol {
    /// 工具定义
    /// - name: `run_shortcut`
    /// - parameters: `name`（必填，String）— 快捷指令名称；
    ///   `input`（可选，String）— 输入内容
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_shortcut",
            description: "按名称执行快捷指令并返回结果",
            parameters: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "快捷指令名称"],
                    "input": ["type": "string", "description": "输入内容（可选）"]
                ],
                "required": ["name"]
            ]
        )
    }

    /// 执行快捷指令
    ///
    /// - Parameter arguments: 含 `name` 及可选 `input` 的参数字典
    /// - Returns: 执行结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return "错误：请提供快捷指令名称"
        }
        let input = arguments["input"] as? String
        #if os(macOS)
        // macOS: 用 Process 执行 shortcuts run 命令
        return try await runShortcutViaCLI(name: name, input: input)
        #else
        // iOS: 用 NSUserActivity 触发快捷指令
        let activity = NSUserActivity(activityType: "com.apple.shortcuts.RunShortcut")
        activity.userInfo = ["shortcutName": name]
        if let input = input {
            activity.userInfo?["input"] = input
        }
        activity.becomeCurrent()
        return "已触发快捷指令：\(name)"
        #endif
    }

    #if os(macOS)
    /// 通过 Process 调用 shortcuts CLI 执行快捷指令
    private func runShortcutViaCLI(name: String, input: String?) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        var args = ["run", name]
        if let input = input {
            args += ["-i", input]
        }
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "快捷指令执行失败：\(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // 退出码非 0 时根据输出判断是否为未找到快捷指令
        if process.terminationStatus != 0 {
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.contains("not found") || output.contains("找不到") {
                return "未找到快捷指令：\(name)"
            }
            return "快捷指令执行失败：\(output)"
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.isEmpty ? "已执行快捷指令：\(name)" : output
    }
    #endif
}

// MARK: - ListShortcutsTool
/// 快捷指令列表工具，跨平台
final class ListShortcutsTool: ToolProtocol {
    /// 工具定义
    /// - name: `list_shortcuts`
    /// - parameters: 无入参
    var definition: ToolDefinition {
        ToolDefinition(
            name: "list_shortcuts",
            description: "列出设备上所有可用的快捷指令名称",
            parameters: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        )
    }

    /// 列出快捷指令
    ///
    /// - Parameter arguments: 无参数
    /// - Returns: 快捷指令名称列表字符串，或平台不支持提示
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        #if os(macOS)
        return try await listShortcutsViaCLI()
        #else
        return "iOS 不支持列出快捷指令，请在快捷指令 App 中查看"
        #endif
    }

    #if os(macOS)
    /// 通过 Process 调用 shortcuts list 列出所有快捷指令名称
    private func listShortcutsViaCLI() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return "获取快捷指令列表失败：\(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        // 按行分割并过滤空行
        let names = output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
        return names.isEmpty ? "当前没有可用的快捷指令" : names.joined(separator: "\n")
    }
    #endif
}

// MARK: - CreateShortcutTool
/// 快捷指令创建工具，跨平台。生成 .shortcut 文件并打开 Shortcuts 应用导入
final class CreateShortcutTool: ToolProtocol {
    /// 工具定义
    /// - name: `create_shortcut`
    /// - parameters: `name`（必填）— 快捷指令名称；`action`（必填）— 动作类型；
    ///   `url`/`text` 按动作类型按需传入
    var definition: ToolDefinition {
        ToolDefinition(
            name: "create_shortcut",
            description: "创建快捷指令，支持 open_url/show_text/copy_to_clipboard 三种基础动作",
            parameters: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "快捷指令名称"],
                    "action": ["type": "string", "description": "动作类型：open_url/show_text/copy_to_clipboard"],
                    "url": ["type": "string", "description": "URL（open_url 时需要）"],
                    "text": ["type": "string", "description": "文本内容（show_text/copy_to_clipboard 时需要）"]
                ],
                "required": ["name", "action"]
            ]
        )
    }

    /// 创建快捷指令
    ///
    /// - Parameter arguments: 含 `name`、`action` 及其所需参数的字典
    /// - Returns: 创建结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return "错误：请提供快捷指令名称"
        }
        guard let actionType = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        // 安全策略：禁止创建包含任意 Shell 脚本的快捷指令
        if actionType == "run_script" {
            return "错误：run_script 动作已被禁用，不允许创建执行 Shell 脚本的快捷指令"
        }
        // 构建 WFWorkflow plist
        let workflowAction = buildWorkflowAction(action: actionType, arguments: arguments)
        guard let action = workflowAction else {
            return "错误：不支持的动作类型，支持 open_url/show_text/copy_to_clipboard"
        }
        // 构建 .shortcut 文件（WFWorkflow plist 格式）
        let workflow: [String: Any] = [
            "WFWorkflowActions": [action],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowTypes": ["NCWidget", "WatchKit"],
            "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": 4282601983,
                "WFWorkflowIconGlyph": 59511
            ]
        ]
        let shortcutData: [String: Any] = [
            "WFWorkflow": workflow
        ]
        do {
            // 序列化为 binary plist 并写入临时目录
            let plistData = try PropertyListSerialization.data(fromPropertyList: shortcutData, format: .binary, options: 0)
            let fileName = "\(name).shortcut"
            let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(fileName)
            try plistData.write(to: URL(fileURLWithPath: filePath))
            // 打开 Shortcuts 应用导入
            #if os(macOS)
            NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
            #else
            await UIApplication.shared.open(URL(fileURLWithPath: filePath))
            #endif
            return "已创建快捷指令：\(name)，请在 Shortcuts 应用中确认保存"
        } catch {
            return "快捷指令创建失败：\(error.localizedDescription)"
        }
    }

    /// 根据 action 类型构建对应的 WFWorkflowAction 字典
    private func buildWorkflowAction(action: String, arguments: [String: Any]) -> [String: Any]? {
        switch action {
        case "open_url":
            guard let url = arguments["url"] as? String else { return nil }
            return [
                "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
                "WFWorkflowActionParameters": [
                    "URL": url,
                    "WFWorkflowActionText": "Opening URL: \(url)"
                ]
            ]
        case "show_text":
            guard let text = arguments["text"] as? String else { return nil }
            return [
                "WFWorkflowActionIdentifier": "is.workflow.actions.showresult",
                "WFWorkflowActionParameters": [
                    "Text": text
                ]
            ]
        case "copy_to_clipboard":
            guard let text = arguments["text"] as? String else { return nil }
            // 先设置文本，再拷贝到剪贴板
            let setTextAction: [String: Any] = [
                "WFWorkflowActionIdentifier": "is.workflow.actions.setvariable",
                "WFWorkflowActionParameters": [
                    "WFVariableName": "Text",
                    "WFTextActionText": text
                ]
            ]
            _ = setTextAction
            return [
                "WFWorkflowActionIdentifier": "is.workflow.actions.copytoclipboard",
                "WFWorkflowActionParameters": [
                    "WFClipboardContent": text
                ]
            ]
        default:
            return nil
        }
    }
}

#if os(iOS)
import UIKit
#endif
