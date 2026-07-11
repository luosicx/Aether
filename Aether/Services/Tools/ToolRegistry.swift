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

/// 工具注册中心，单例。默认注册 4 个工具：AlarmTool / ReminderTool / DateTimeTool / CalculatorTool。@MainActor 隔离。
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()
    /// 工具字典，key 为工具名
    private var tools: [String: ToolProtocol] = [:]
    /// 工具执行确认服务，可注入自定义实现（如 UI 确认）。
    var confirmationService: ToolConfirmationService? = DefaultToolConfirmationService()

    /// 私有初始化，注册全部工具（跨平台 + macOS 独有条件注册）
    private init() {
        registerAllTools()
    }

    /// 根据当前设置重新构建工具注册表。
    /// 设置变更（如 AppleScript 开关）后调用，可动态增删工具。
    func refreshRegisteredTools() {
        tools.removeAll()
        registerAllTools()
    }

    /// 注册全部工具，供 init 与 refreshRegisteredTools 复用。
    private func registerAllTools() {
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
        if AppleScriptTool.isEnabled {
            register(tool: AppleScriptTool())
        }
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
    }

    /// 注册工具，同名覆盖
    func register(tool: ToolProtocol) {
        tools[tool.definition.name] = tool
    }

    /// 按名获取工具，未命中返回 nil
    func getTool(named name: String) -> ToolProtocol? {
        tools[name]
    }

    /// 执行工具。未注册抛 NSError；敏感/危险工具需经 confirmationService 确认。返回工具执行结果字符串。
    func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = tools[name] else {
            throw NSError(domain: "ToolRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "工具 \(name) 未注册"])
        }
        switch tool.riskLevel {
        case .sensitive, .dangerous:
            let confirmed = await confirmationService?.confirm(tool: tool, arguments: arguments) ?? false
            guard confirmed else {
                throw NSError(domain: "ToolRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "用户取消了工具执行"])
            }
        default:
            break
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
}

// MARK: - Day 11: DateTimeTool
/// 获取当前日期与时间工具，支持可选时区参数
final class DateTimeTool: ToolProtocol {
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
final class CalculatorTool: ToolProtocol {
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
