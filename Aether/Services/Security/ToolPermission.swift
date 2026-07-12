import Foundation

/// 工具权限标识，每个 case 对应一个已注册的工具名。
///
/// 用于 `ToolPermissionStore` 的粒度开关，以及判断工具是否需要用户确认。
enum ToolPermission: String, CaseIterable, Sendable {
    // MARK: - 安全工具（默认启用，无需确认）
    case createAlarm = "create_alarm"
    case createReminder = "create_reminder"
    case getCurrentTime = "get_current_time"
    case calculate = "calculate"
    case getWeather = "get_weather"
    case getDeviceInfo = "get_device_info"
    case writeClipboard = "write_clipboard"
    case openURL = "open_url"
    case runShortcut = "run_shortcut"
    case listShortcuts = "list_shortcuts"
    case createShortcut = "create_shortcut"
    case manageWindow = "manage_window"
    case manageApp = "manage_app"
    case finderAction = "finder_action"
    case systemControl = "system_control"

    // MARK: - 高危工具（默认禁用，执行前需确认）
    case runTerminalCommand = "run_terminal_command"
    case runAppleScript = "run_applescript"
    case controlSafari = "control_safari"
    case simulateInput = "simulate_input"
    case manageFile = "manage_file"

    // MARK: - 敏感工具（默认启用，执行前需按次确认）
    case readClipboard = "read_clipboard"
    case searchContacts = "search_contacts"
    case getLocation = "get_location"
    case takeScreenshot = "take_screenshot"
    case extractTextFromImage = "extract_text_from_image"

    /// 注册在 `ToolRegistry` 中的工具名。
    var toolName: String { rawValue }

    /// 是否为高危工具（默认禁用，执行前必须弹窗确认）。
    var isHighRisk: Bool {
        switch self {
        case .runTerminalCommand, .runAppleScript, .controlSafari, .simulateInput, .manageFile:
            return true
        default:
            return false
        }
    }

    /// 是否为敏感工具（默认启用，但每次执行前需确认）。
    var isSensitive: Bool {
        switch self {
        case .readClipboard, .searchContacts, .getLocation, .takeScreenshot, .extractTextFromImage:
            return true
        default:
            return false
        }
    }

    /// 默认启用状态。高危工具默认关闭，其余默认开启。
    var isEnabledByDefault: Bool { !isHighRisk }

    /// 执行前是否需要用户确认。
    var requiresConfirmation: Bool { isHighRisk || isSensitive }
}
