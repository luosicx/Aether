import Foundation

/// 单条审计日志记录。
struct ToolAuditLogEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let toolName: String
    /// 已脱敏的参数 JSON 字符串。
    let redactedParameters: String
    /// 用户在确认弹窗上的选择。
    let userDecision: ToolConfirmationDecision
}

/// 高危工具执行审计日志。
///
/// 记录工具名、时间、脱敏参数与用户决定。内存中保留最近条目，并持久化到 `UserDefaults`。
@MainActor
final class ToolAuditLog {
    static let shared = ToolAuditLog()

    private let defaults: UserDefaults
    private let defaultsKey = "toolAuditLog"
    /// 内存缓存，按时间升序排列。
    private var entries: [ToolAuditLogEntry] = []
    /// 持久化条目上限，防止无限制增长。
    private let maxPersistedEntries = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// 记录一次高危/敏感工具执行。
    ///
    /// - Parameters:
    ///   - toolName: 工具名。
    ///   - parameters: 原始参数（会被脱敏后存储）。
    ///   - decision: 用户决定。
    func record(toolName: String, parameters: [String: Any], decision: ToolConfirmationDecision) {
        let entry = ToolAuditLogEntry(
            id: UUID(),
            timestamp: Date(),
            toolName: toolName,
            redactedParameters: ToolParameterRedactor.redact(parameters: parameters),
            userDecision: decision
        )
        entries.append(entry)
        trimAndSave()
    }

    /// 获取最近审计记录。
    /// - Parameter limit: 最大返回条数，默认 100。
    /// - Returns: 按时间倒序排列的记录。
    func recentEntries(limit: Int = 100) -> [ToolAuditLogEntry] {
        Array(entries.suffix(limit).reversed())
    }

    /// 所有记录（按时间升序）。
    func allEntries() -> [ToolAuditLogEntry] {
        entries
    }

    /// 清空内存与持久化记录。
    func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: defaultsKey)
    }

    /// 持久化条目数量。
    var count: Int { entries.count }

    // MARK: - 私有方法

    private func trimAndSave() {
        if entries.count > maxPersistedEntries {
            entries = Array(entries.suffix(maxPersistedEntries))
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ToolAuditLogEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }
}
