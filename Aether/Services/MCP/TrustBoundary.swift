import Foundation
import AetherFoundation

// MARK: - TrustBoundary

/// MCP Server 信任边界三档枚举。
///
/// - local：本机 stdio 子进程，默认放行（仍受 `ToolAuthorization` 约束）。
/// - lan：局域网 SSE，需用户首次确认；白名单工具自动放行。
/// - internet：公网 SSE，强制用户确认或拒绝（黑名单优先）。
public enum TrustBoundary: String, Codable, Sendable, Equatable, Hashable, Comparable {
    case local
    case lan
    case internet = "public"

    /// 严重度排序：local < lan < internet
    public var severity: Int {
        switch self {
        case .local: return 0
        case .lan: return 1
        case .internet: return 2
        }
    }

    /// 是否应默认放行（local 边界默认放行，lan/internet 需用户确认）
    public var shouldAutoApprove: Bool {
        self == .local
    }

    /// Comparable 实现：按 severity 排序
    public static func < (lhs: TrustBoundary, rhs: TrustBoundary) -> Bool {
        lhs.severity < rhs.severity
    }

    /// 根据 Server 配置判定信任边界。
    /// - Parameter server: MCPConfigFile.Server 配置
    /// - Returns: 信任边界档位
    public static func classify(server: MCPConfigFile.Server) -> TrustBoundary {
        // stdio 传输强制为 local（本机子进程）
        if case .stdio = server.transport {
            return .local
        }
        // SSE 传输：检查 URL 是否为私有网络
        if case .sse(let urlString, _) = server.transport {
            if isPrivateNetworkURL(urlString) {
                return .lan
            }
            return .internet
        }
        return server.trust
    }

    /// 判断 URL 字符串是否为私有网络（localhost / 127.0.0.1 / 192.168.x / 10.x / 172.16-31.x）
    private static func isPrivateNetworkURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return false
        }
        if host == "localhost" { return true }
        // IPv4 私有地址段
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        // 127.0.0.0/8 回环
        if parts[0] == 127 { return true }
        // 10.0.0.0/8
        if parts[0] == 10 { return true }
        // 192.168.0.0/16
        if parts[0] == 192 && parts[1] == 168 { return true }
        // 172.16.0.0/12（172.16.0.0 - 172.31.255.255）
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}

// MARK: - PermissionDecision

/// 权限决策结果。
public enum PermissionDecision: String, Sendable, Equatable {
    case allow
    case deny
    case requireConfirmation
}

// MARK: - PermissionPolicy

/// MCP Server 与工具调用的权限策略。
///
/// 策略优先级：黑名单 > 白名单 > 用户确认。
/// - 黑名单：自动拒绝（永不连接）
/// - 白名单：自动放行（不弹窗）
/// - 用户确认：弹窗 `PermissionPromptView`
public struct PermissionPolicy: Sendable, Equatable {
    /// 默认信任档位（用于未显式声明 trust 的 Server）
    public let defaultTrust: TrustBoundary
    /// Server 白名单（自动放行）
    public let whitelist: [String]
    /// Server 黑名单（自动拒绝，优先级最高）
    public let blacklist: [String]

    /// 构造权限策略
    /// - Parameters:
    ///   - whitelist: Server 白名单
    ///   - blacklist: Server 黑名单
    ///   - defaultTrust: 默认信任档位
    public init(whitelist: [String]?, blacklist: [String]?, defaultTrust: TrustBoundary) {
        self.whitelist = whitelist ?? []
        self.blacklist = blacklist ?? []
        self.defaultTrust = defaultTrust
    }

    /// 判定 Server 连接权限。
    /// - Parameters:
    ///   - serverID: Server 唯一标识
    ///   - trust: 信任档位
    /// - Returns: 权限决策（.allow / .deny / .requireConfirmation）
    public func decide(for serverID: String, trust: TrustBoundary) -> PermissionDecision {
        // 黑名单优先级最高：永不连接
        if blacklist.contains(serverID) {
            return .deny
        }
        // 白名单：自动放行
        if whitelist.contains(serverID) {
            return .allow
        }
        // 按信任档位决策
        switch trust {
        case .local:
            return .allow
        case .lan, .internet:
            return .requireConfirmation
        }
    }

    /// 判定工具调用权限。
    /// - Parameters:
    ///   - serverID: Server 唯一标识（保留用于未来按 Server 差异化策略；当前仅按工具名判定）
    ///   - toolName: 工具名
    ///   - toolWhitelist: 工具白名单（nil 表示全部需确认）
    ///   - toolBlacklist: 工具黑名单
    /// - Returns: 权限决策
    public func decideToolCall(
        serverID _: String,
        toolName: String,
        toolWhitelist: [String]?,
        toolBlacklist: [String]?
    ) -> PermissionDecision {
        // 黑名单优先
        if let blacklist = toolBlacklist, blacklist.contains(toolName) {
            return .deny
        }
        // 白名单自动放行
        if let whitelist = toolWhitelist, whitelist.contains(toolName) {
            return .allow
        }
        // 其余需用户确认
        return .requireConfirmation
    }
}
