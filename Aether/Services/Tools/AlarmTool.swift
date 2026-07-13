import Foundation
import EventKit

/// 闹钟工具，通过 EventKit 创建提醒事项
final class AlarmTool: ToolProtocol, @unchecked Sendable {
    private let eventStore = EKEventStore()

    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "create_alarm",
            description: "创建一个日历事件并添加闹钟提醒",
            parameters: [
                "type": "object",
                "properties": [
                    "time": ["type": "string", "description": "闹钟时间，格式 HH:mm"],
                    "label": ["type": "string", "description": "闹钟标签"]
                ],
                "required": ["time"]
            ]
        )
    }

    /// 执行闹钟创建。流程：1) 必须提供 title 参数；2) 请求 EventKit 权限；
    /// 3) guard 时间格式 HH:mm（注意：当前实现在权限请求之后 guard，与 ReminderTool 不同）；
    /// 4) 创建 EKAlarm 并保存。返回成功或错误字符串。
    func execute(arguments: [String: Any]) async throws -> String {
        guard let time = arguments["time"] as? String else {
            return "错误：请提供闹钟时间"
        }
        let label = arguments["label"] as? String ?? "闹钟"
        // 时间格式校验放在权限请求之前，避免无效输入弹出权限弹窗
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let date = formatter.date(from: time) else {
            return "错误：时间格式无效"
        }
        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else { return "错误：无法访问日历" }
        let alarm = EKAlarm()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        alarm.absoluteDate = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)
        let event = EKEvent(eventStore: eventStore)
        event.title = label
        event.startDate = alarm.absoluteDate
        event.endDate = alarm.absoluteDate?.addingTimeInterval(60)
        event.addAlarm(alarm)
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent)
        return "已创建闹钟：\(label) 于 \(time)"
    }
}
