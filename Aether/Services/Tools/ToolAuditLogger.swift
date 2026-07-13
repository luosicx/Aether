import Foundation
import os

/// 工具调用审计日志器。
/// 记录每次工具调用的工具名、授权状态、时间戳以及参数键摘要（不记录完整敏感内容）。
final class ToolAuditLogger {
    static let shared = ToolAuditLogger()

    private let logQueue = DispatchQueue(label: "com.aether.toolauditlogger", qos: .utility)
    private let logFileURL: URL?
    private let dateFormatter: ISO8601DateFormatter
    private let osLog: OSLog

    private init() {
        logFileURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("aether.tool.audit.log")
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.aether", category: "ToolAudit")
    }

    /// 记录一次工具调用审计。
    /// - Parameters:
    ///   - toolName: 被调用工具名。
    ///   - argumentsSummary: 参数摘要，建议仅包含参数键名或脱敏后的摘要。
    ///   - authorized: 是否已获得用户授权。
    ///   - timestamp: 调用时间戳，默认当前时间。
    func log(toolName: String, argumentsSummary: String, authorized: Bool, timestamp: Date = Date()) {
        let entry = formatEntry(toolName: toolName, argumentsSummary: argumentsSummary, authorized: authorized, timestamp: timestamp)
        os_log("[Aether Tool Audit] %{public}@", log: osLog, type: .default, entry)
        logQueue.async { [weak self] in
            self?.appendToFile(entry)
        }
    }

    // MARK: - Private Helpers

    private func formatEntry(toolName: String, argumentsSummary: String, authorized: Bool, timestamp: Date) -> String {
        let date = dateFormatter.string(from: timestamp)
        return "\(date) | tool=\(toolName) | authorized=\(authorized) | args=[\(argumentsSummary)]"
    }

    private func appendToFile(_ text: String) {
        guard let url = logFileURL else { return }
        let line = (text + "\n").data(using: .utf8) ?? Data()
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: line, attributes: nil)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            if #available(iOS 13.4, macOS 10.15.4, *) {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                handle.seekToEndOfFile()
                handle.write(line)
            }
            try handle.close()
        } catch {
            // 审计日志写入失败静默处理，避免影响主流程。
        }
    }
}
