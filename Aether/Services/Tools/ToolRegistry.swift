/// 工具注册中心（跨平台：iOS + macOS）
///
/// 单例，负责注册、查找和执行所有工具。@MainActor 隔离。
/// 初始化时按平台条件注册工具：跨平台工具（Location/DeviceInfo/Clipboard/OpenURL/Contacts/Weather/Shortcuts 等）
/// 始终注册，macOS 独有工具（AppleScript/Screenshot/OCR/Terminal/Window/App/File/Finder/Safari/SystemControl/InputAutomation）
/// 仅在 macOS 下注册。
/// 调用方式：ToolRegistry.shared.execute(name:arguments:) 执行指定工具。
import Foundation
import EventKit
import UserNotifications
import AetherFoundation

/// 工具注册中心，单例。默认注册 4 个工具：AlarmTool / ReminderTool / DateTimeTool / CalculatorTool。@MainActor 隔离。
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()
    /// 工具字典，key 为工具名
    private var tools: [String: ToolProtocol] = [:]

    // MARK: - 启用状态与敏感工具

    /// UserDefaults 键前缀
    private let enabledToolDefaultsKeyPrefix = "aether.tool.enabled."
    /// 默认禁用的 macOS 高危工具（注册名）。
    /// 注：任务中的 `control_safari.run_js` 与 `create_shortcut.run_script` 是子操作概念，
    /// 这里以父工具 `control_safari` / `create_shortcut` 为粒度进行启用/禁用控制。
    let defaultDisabledTools: Set<String> = [
        "run_terminal_command",
        "run_applescript",
        "control_safari",
        "create_shortcut",
        "simulate_input"
    ]
    /// 敏感工具集合，包含需要显式授权才能启用的工具或子操作标识。
    /// 同时包含任务中的 `ocr_screen` 与实际注册名 `extract_text_from_image`，保证两端都能匹配。
    let sensitiveTools: Set<String> = [
        "read_clipboard",
        "search_contacts",
        "get_location",
        "take_screenshot",
        "ocr_screen",
        "extract_text_from_image",
        "run_terminal_command",
        "run_applescript",
        "control_safari.run_js",
        "create_shortcut.run_script",
        "manage_file",
        "manage_window",
        "simulate_input"
    ]
    /// 当前已启用的工具名集合。初始化时从 UserDefaults 恢复默认值。
    private(set) var enabledTools: Set<String> = []

    /// 私有初始化，注册全部工具（跨平台 + macOS 独有条件注册）
    private init() {
        // 原有 4 个工具
        register(tool: AlarmTool())
        register(tool: ReminderTool())
        register(tool: DateTimeTool())
        register(tool: CalculatorTool())
        // 跨平台工具（6 个，含 2 个剪贴板工具共 7 个注册项）
        register(tool: LocationTool())
        register(tool: DeviceInfoTool())
        register(tool: ReadClipboardTool())
        register(tool: WriteClipboardTool())
        register(tool: OpenURLTool())
        register(tool: ContactsTool())
        register(tool: WeatherTool())
        // 快捷指令工具（3 个，跨平台）
        register(tool: RunShortcutTool())
        register(tool: ListShortcutsTool())
        register(tool: CreateShortcutTool())
        // macOS 独有工具（11 个，条件注册）
        #if os(macOS)
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
        #endif

        // 注册完成后，按默认值 + UserDefaults 恢复启用状态
        restoreEnabledStates()
    }

    /// 注册工具，同名覆盖
    func register(tool: ToolProtocol) {
        tools[tool.definition.name] = tool
    }

    /// 按名注销工具。工具不存在时不报错（no-op）。
    /// - Parameter name: 工具名
    func unregister(name: String) {
        tools.removeValue(forKey: name)
    }

    /// 批量注册工具，逐个调用 register，同名覆盖。
    /// - Parameter tools: 待注册的工具数组
    func registerBatch(tools: [ToolProtocol]) {
        for tool in tools {
            register(tool: tool)
        }
    }

    /// 按名获取工具，未命中返回 nil
    func getTool(named name: String) -> ToolProtocol? {
        tools[name]
    }

    /// 获取所有已注册工具名（顺序不保证）
    /// - Returns: 工具名数组
    func getToolNames() -> [String] {
        Array(tools.keys)
    }

    /// 当前已注册工具数量（只读）
    var toolCount: Int {
        tools.count
    }

    /// 执行工具。未注册或已禁用抛 NSError。返回工具执行结果字符串。
    func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = tools[name] else {
            throw NSError(domain: "ToolRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "工具 \(name) 未注册"])
        }
        guard isEnabled(name: name) else {
            throw NSError(domain: "ToolRegistry", code: 3, userInfo: [NSLocalizedDescriptionKey: "工具 \(name) 未启用"])
        }
        return try await tool.execute(arguments: arguments)
    }

    /// 所有工具的 ToolDef 数组，用于告知 LLM 可调用工具
    var allToolDefs: [ToolDef] {
        tools.values.map { tool in
            ToolDef(
                type: "function",
                function: ToolDef.FunctionDef(
                    name: tool.definition.name,
                    description: tool.definition.description,
                    parameters: tool.definition.parameters.mapValues(AnyCodable.init)
                )
            )
        }
    }

    /// 仅返回已启用工具的 ToolDefinition 数组
    func availableTools() -> [ToolDefinition] {
        tools.values
            .filter { isEnabled(name: $0.definition.name) }
            .map { $0.definition }
    }

    /// 仅返回已启用工具的 LLM ToolDef 数组
    var availableToolDefs: [ToolDef] {
        tools.values
            .filter { isEnabled(name: $0.definition.name) }
            .map { tool in
                ToolDef(
                    type: "function",
                    function: ToolDef.FunctionDef(
                        name: tool.definition.name,
                        description: tool.definition.description,
                        parameters: tool.definition.parameters.mapValues(AnyCodable.init)
                    )
                )
            }
    }

    /// 返回当前已注册且属于高危/敏感的工具定义，供设置页展示开关。
    /// 仅包含实际已注册的工具（macOS 独占工具在 iOS 上不会出现在结果中）。
    var dangerousToolDefs: [ToolDefinition] {
        tools.values
            .filter { defaultDisabledTools.contains($0.definition.name) }
            .map { $0.definition }
            .sorted { $0.name < $1.name }
    }

    // MARK: - 启用状态管理

    /// 指定工具是否已启用。未注册工具返回 false。
    func isEnabled(name: String) -> Bool {
        guard tools[name] != nil else { return false }
        return enabledTools.contains(name)
    }

    /// 设置指定工具的启用状态，并持久化到 UserDefaults。
    func setEnabled(name: String, value: Bool) {
        guard tools[name] != nil else { return }
        if value {
            enabledTools.insert(name)
        } else {
            enabledTools.remove(name)
        }
        UserDefaults.standard.set(value, forKey: userDefaultsKey(for: name))
    }

    /// 指定工具是否需要显式授权（敏感工具）。
    /// 支持父工具名匹配其敏感子操作（如 `control_safari` 匹配 `control_safari.run_js`）。
    func requiresAuthorization(name: String) -> Bool {
        if sensitiveTools.contains(name) { return true }
        return sensitiveTools.contains { $0.hasPrefix("\(name).") }
    }

    // MARK: - Private Helpers

    /// 从 UserDefaults 恢复所有已注册工具的启用状态。无记录时按 defaultDisabledTools 决定默认值。
    private func restoreEnabledStates() {
        var result = Set<String>()
        for name in tools.keys {
            let key = userDefaultsKey(for: name)
            if UserDefaults.standard.object(forKey: key) == nil {
                // 无持久化记录时：高危工具默认关闭，其余默认开启
                if !defaultDisabledTools.contains(name) {
                    result.insert(name)
                    UserDefaults.standard.set(true, forKey: key)
                } else {
                    UserDefaults.standard.set(false, forKey: key)
                }
            } else {
                if UserDefaults.standard.bool(forKey: key) {
                    result.insert(name)
                }
            }
        }
        enabledTools = result
    }

    /// 构造指定工具在 UserDefaults 中的键名
    private func userDefaultsKey(for name: String) -> String {
        "\(enabledToolDefaultsKeyPrefix)\(name)"
    }
}

// MARK: - Day 11: DateTimeTool
/// 获取当前日期与时间工具，支持可选时区参数
final class DateTimeTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "get_current_time",
            description: "获取当前日期与时间，可选时区参数",
            parameters: [
                "type": "object",
                "properties": [
                    "timezone": ["type": "string", "description": "时区标识，如 Asia/Shanghai、America/New_York；不传则用系统时区"]
                ],
                "required": []
            ]
        )
    }

    /// 返回格式化当前时间。timezone 参数可选，不传用系统时区。
    func execute(arguments: [String: Any]) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        if let tz = arguments["timezone"] as? String {
            formatter.timeZone = TimeZone(identifier: tz) ?? TimeZone.current
        }
        return formatter.string(from: Date())
    }
}

// MARK: - Day 11: CalculatorTool
/// 数学表达式求值工具，用 NSExpression 实现，不引入第三方库
final class CalculatorTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "calculate",
            description: "对数学表达式求值，支持加减乘除、括号、浮点数",
            parameters: [
                "type": "object",
                "properties": [
                    "expression": ["type": "string", "description": "数学表达式，如 1 + 2 * 3、(1+2)*3、3.14 * 2"]
                ],
                "required": ["expression"]
            ]
        )
    }

    /// 对表达式求值。流程：1) 表达式校验（只允许数字/运算符/括号）；
    /// 2) 除零检测；3) 整数字面量补 .0（避免 NSExpression 整数除法）；
    /// 4) 整数结果显示为整数（避免 6.0 显示）；5) 浮点用 %g 去尾数。
    func execute(arguments: [String: Any]) async throws -> String {
        guard let expression = arguments["expression"] as? String, !expression.isEmpty else {
            return "错误：请提供表达式"
        }
        // 简单校验：只允许数字、空格、运算符、括号、小数点
        let allowed = CharacterSet(charactersIn: "0123456789+-*/(). ")
        guard expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "错误：表达式无效"
        }
        // 提前拦截除零：检测 / 0
        if expression.contains("/ 0") || expression.contains("/0") {
            return "错误：除零"
        }
        // 表达式必须以数字或右括号结尾，避免 NSExpression 解析失败（如 "1 + "）
        guard let last = expression.last, last.isNumber || last == ")" else {
            return "错误：表达式无效"
        }
        // 整数字面量后补 .0，避免 NSExpression 做整数除法（如 15 / 4 返回 3）
        let normalized: String = {
            let pattern = #"(?<![\d.])\d+(?![\d.])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return expression }
            let range = NSRange(expression.startIndex..., in: expression)
            return regex.stringByReplacingMatches(in: expression, range: range, withTemplate: "$0.0")
        }()
        let expr = NSExpression(format: normalized)
        guard let number = expr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return "错误：表达式无效"
        }
        let doubleValue = number.doubleValue
        // 整数结果显示为整数
        if doubleValue == doubleValue.rounded() && abs(doubleValue) < 1e15 {
            return String(Int(doubleValue))
        }
        // 浮点数用 %g 去掉浮点误差尾数（如 3.14*2 -> 6.28 而非 6.2800000000000002）
        return String(format: "%g", doubleValue)
    }
}

// MARK: - Day 11: 本地通知服务
/// 封装 UNUserNotificationCenter，用于在 AI 回复完成等场景推送本地通知
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// 请求通知授权（失败静默，不处理错误）
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // 失败静默
        }
    }

    /// 发送本地通知（1 秒后触发）
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
