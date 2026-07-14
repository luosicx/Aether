import Foundation
import EventKit
import AetherFoundation

/// 提醒工具，通过 EventKit 创建带 dueDate 的提醒事项
final class ReminderTool: ToolProtocol, @unchecked Sendable {
    private let eventStore = EKEventStore()

    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "create_reminder",
            description: "创建一个提醒事项",
            parameters: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "提醒标题"],
                    "date": ["type": "string", "description": "提醒日期，格式 YYYY-MM-DD HH:mm，可选"]
                ],
                "required": ["title"]
            ]
        )
    }

    /// 执行提醒创建。流程：1) 必须提供 title；2) 日期解析在权限请求之前（为何：避免无效日期被静默忽略，
    /// 且不依赖 EventKit 权限，与 AlarmTool 行为对齐）；3) 请求 EventKit 权限；
    /// 4) 创建 EKReminder 并设置 dueDateComponents + EKAlarm；5) 保存。返回成功或错误字符串。
    func execute(arguments: [String: Any]) async throws -> String {
        guard let title = arguments["title"] as? String else {
            return "错误：请提供提醒标题"
        }
        // 先解析 date（在权限请求之前），无效格式直接返回错误
        // 与 AlarmTool 行为一致，避免无效日期被静默忽略
        var parsedDate: Date?
        if let dateStr = arguments["date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let date = formatter.date(from: dateStr) else {
                return "错误：日期格式无效，应为 yyyy-MM-dd HH:mm"
            }
            parsedDate = date
        }
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { return "错误：无法访问提醒事项" }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        if let date = parsedDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            reminder.dueDateComponents = components
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        try eventStore.save(reminder, commit: true)
        return "已创建提醒：\(title)"
    }
}
