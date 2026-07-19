import Foundation
import CryptoKit
import os
import AetherServices

// MARK: - PublicKeyPinVerifier

/// MCP Server 公钥指纹校验器（CryptoKit SHA-256）。
///
/// 防止中间人攻击：在建立 SSE 连接前，校验 Server 暴露的公钥指纹是否匹配预期。
/// 指纹格式：`sha256:<base64-encoded-SHA256-digest>`，与 HPKP 公钥固定类似。
///
/// - Note: 公钥来源由调用方决定（例如 TLS 证书公钥、Server `initialize` 响应中的公钥字段）。
struct PublicKeyPinVerifier {

    /// 指纹算法前缀（仅支持 SHA-256）
    static let algorithmPrefix = "sha256:"

    /// 校验指纹格式是否合法（`sha256:base64` 格式）。
    /// - Parameter pin: 待校验的指纹字符串
    /// - Returns: 合法返回 true，缺失前缀、空 base64、含非法字符均返回 false
    static func isValidPinFormat(_ pin: String) -> Bool {
        guard pin.hasPrefix(algorithmPrefix) else { return false }
        let base64Part = String(pin.dropFirst(algorithmPrefix.count))
        guard !base64Part.isEmpty else { return false }
        // base64 字符集：A-Z a-z 0-9 + / =
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        return base64Part.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 计算公钥的 SHA-256 指纹。
    /// - Parameter publicKeyBytes: 公钥原始字节（如 SubjectPublicKeyInfo DER 编码）
    /// - Returns: `sha256:base64` 格式指纹
    static func computePin(publicKeyBytes: Data) -> String {
        let digest = SHA256.hash(data: publicKeyBytes)
        let base64 = Data(digest).base64EncodedString()
        return "\(algorithmPrefix)\(base64)"
    }

    /// 校验公钥指纹是否匹配预期。
    /// - Parameters:
    ///   - publicKeyBytes: 实际公钥字节
    ///   - expectedPin: 预期指纹（`sha256:base64` 格式）
    /// - Returns: 匹配返回 true，不匹配或格式非法返回 false
    static func verify(publicKeyBytes: Data, expectedPin: String) -> Bool {
        guard isValidPinFormat(expectedPin) else { return false }
        let actualPin = computePin(publicKeyBytes: publicKeyBytes)
        return actualPin == expectedPin
    }
}

// MARK: - ToolNamePrefixer

/// MCP 工具名前缀工具。
///
/// 防止诱导调用：所有 MCP 工具注册到 `ToolRegistry` 时加 `serverID__toolName` 前缀，
/// 使 LLM 必须显式选择某 Server 的工具才能调用，避免 Server 提供的工具名与
/// 本地工具同名而造成误导。
///
/// 同时防止前缀注入攻击：恶意 Server ID 中若包含 `__` 试图劫持其他 Server 的工具，
/// 由 `sanitizeServerID(_:)` 清洗为不含分隔符的合法 ID。
enum ToolNamePrefixer {

    /// 分隔符（双下划线，与 Swift 标识符兼容）
    static let separator = "__"

    /// 为工具名加 Server 前缀。
    /// - Parameters:
    ///   - serverID: Server 唯一标识（自动清洗）
    ///   - toolName: 工具原名
    /// - Returns: 带前缀的工具名 `serverID__toolName`
    static func prefix(serverID: String, toolName: String) -> String {
        let sanitized = sanitizeServerID(serverID)
        return "\(sanitized)\(separator)\(toolName)"
    }

    /// 从带前缀的工具名解析回 (serverID, toolName)。
    /// - Parameter prefixed: 带前缀的工具名
    /// - Returns: 解析结果元组（无分隔符或任一段为空返回 nil）
    static func unprefix(_ prefixed: String) -> (serverID: String, toolName: String)? {
        guard let range = prefixed.range(of: separator) else { return nil }
        let serverID = String(prefixed[..<range.lowerBound])
        let toolName = String(prefixed[range.upperBound...])
        guard !serverID.isEmpty, !toolName.isEmpty else { return nil }
        return (serverID, toolName)
    }

    /// 清洗 Server ID，仅保留字母数字与下划线，并折叠 `__` 为单下划线。
    /// 防止前缀注入攻击：恶意 Server ID 含 `__` 试图劫持其他工具。
    /// - Parameter serverID: 原始 Server ID
    /// - Returns: 仅含 `[A-Za-z0-9_]` 且不含 `__` 的清洗后 ID
    static func sanitizeServerID(_ serverID: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        var sanitized = String(serverID.unicodeScalars.filter { allowed.contains($0) })
        // 折叠所有 `__`（分隔符）为单 `_`，防止恶意 ID 劫持其他 Server 的工具名解析
        while sanitized.contains(separator) {
            sanitized = sanitized.replacingOccurrences(of: separator, with: "_")
        }
        return sanitized
    }
}

// MARK: - ToolRateLimiter

/// MCP 工具速率限制器。
///
/// 防止工具数过多导致 `ToolRegistry` 膨胀与 LLM 上下文爆炸：
/// 单个 Server 注册的工具数上限为 100，超出部分截断注册。
struct ToolRateLimiter {

    /// 单 Server 工具数上限
    static let maxToolsPerServer = 100

    /// 判定工具数量是否在上限内。
    /// - Parameter toolCount: 工具数量
    /// - Returns: 在上限内（≤100）返回 true
    static func isWithinLimit(toolCount: Int) -> Bool {
        toolCount <= maxToolsPerServer
    }

    /// 计算截断后的可注册工具数量。
    /// - Parameter toolCount: 原始工具数量
    /// - Returns: 不超过上限的数量（min(count, 100)）
    static func cappedRegisterCount(toolCount: Int) -> Int {
        min(toolCount, maxToolsPerServer)
    }
}

// MARK: - MCPPromptSanitizer

/// MCP 提示模板安全过滤器。
///
/// 通过 `PromptInjectionDetector` 过滤 MCP Server 返回的提示模板内容，
/// 防止恶意 Server 通过 `prompts/get` 返回的模板内容注入提示。
enum MCPPromptSanitizer {

    /// 清洗结果。
    struct SanitizationResult: Sendable, Equatable {
        /// 清洗后的内容（被阻止时为空字符串）
        let sanitized: String
        /// 是否被阻止（命中提示注入规则）
        let blocked: Bool
        /// 命中原因（被阻止时非空）
        let reason: String?
    }

    /// 清洗提示模板内容。
    /// - Parameter input: 待清洗的提示模板内容
    /// - Returns: 清洗结果（命中注入规则时 blocked=true，sanitized 为空）
    static func sanitize(_ input: String) -> SanitizationResult {
        if PromptInjectionDetector.isSuspicious(input) {
            let reason = PromptInjectionDetector.reason(for: input) ?? "检测到提示注入"
            return SanitizationResult(sanitized: "", blocked: true, reason: reason)
        }
        return SanitizationResult(sanitized: input, blocked: false, reason: nil)
    }
}

// MARK: - MCPAuditLogger

/// MCP 工具调用审计日志器。
///
/// 扩展 `ToolAuditLogger`，增加 Server ID 上下文，记录每次 MCP 工具调用的：
/// - Server ID（区分不同 MCP Server）
/// - 工具名（不含前缀的原名）
/// - 参数摘要（脱敏后）
/// - 结果摘要
/// - 授权状态
///
/// 审计日志同时写入：
/// 1. OSLog（统一日志系统）
/// 2. 缓存目录的 `aether.mcp.audit.log` 文件
/// 3. 底层 `ToolAuditLogger`（保持与本地工具审计一致）
final class MCPAuditLogger {

    static let shared = MCPAuditLogger()

    /// 底层审计日志器（用于复用本地工具审计路径）
    private let underlyingLogger = ToolAuditLogger.shared
    /// 串行队列，确保文件写入有序
    private let logQueue = DispatchQueue(label: "com.aether.mcp.auditlogger", qos: .utility)
    /// 日志文件 URL
    private let logFileURL: URL?
    /// 日期格式化器（ISO 8601 含毫秒）
    private let dateFormatter: ISO8601DateFormatter
    /// OSLog 实例
    private let osLog: OSLog

    private init() {
        logFileURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("aether.mcp.audit.log")
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.aether", category: "MCPAudit")
    }

    /// 记录一次 MCP 工具调用审计。
    /// - Parameters:
    ///   - serverID: MCP Server ID
    ///   - toolName: 工具名（不含 Server 前缀的原名）
    ///   - argumentsSummary: 参数摘要（建议仅包含键名或脱敏后的摘要）
    ///   - resultSummary: 结果摘要
    ///   - authorized: 是否已授权
    func logToolCall(
        serverID: String,
        toolName: String,
        argumentsSummary: String,
        resultSummary: String,
        authorized: Bool
    ) {
        let entry = formatEntry(
            serverID: serverID,
            toolName: toolName,
            argumentsSummary: argumentsSummary,
            resultSummary: resultSummary,
            authorized: authorized
        )
        os_log("[Aether MCP Audit] %{public}@", log: osLog, type: .default, entry)
        // 同时委托底层 ToolAuditLogger（带 serverID 前缀，便于全局工具审计查询）
        underlyingLogger.log(
            toolName: "\(serverID)\(ToolNamePrefixer.separator)\(toolName)",
            argumentsSummary: argumentsSummary,
            authorized: authorized
        )
        logQueue.async { [weak self] in
            self?.appendToFile(entry)
        }
    }

    /// 格式化审计日志条目（公开供测试验证格式）。
    /// - Returns: 格式化后的日志字符串
    func formatEntry(
        serverID: String,
        toolName: String,
        argumentsSummary: String,
        resultSummary: String,
        authorized: Bool
    ) -> String {
        let date = dateFormatter.string(from: Date())
        return "\(date) | server=\(serverID) | tool=\(toolName) | authorized=\(authorized) | args=[\(argumentsSummary)] | result=[\(resultSummary)]"
    }

    // MARK: - Private

    /// 追加写入日志文件
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
            // 审计日志写入失败静默处理，避免影响主流程
        }
    }
}
