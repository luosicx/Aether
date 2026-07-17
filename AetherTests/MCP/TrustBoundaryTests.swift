import XCTest
@testable import Aether

/// `TrustBoundary` 枚举与 `PermissionPolicy` 类型的单元测试。
///
/// 覆盖范围：
/// 1. TrustBoundary 三档（local/lan/public）判定逻辑
/// 2. PermissionPolicy 优先级：黑名单 > 白名单 > 用户确认
/// 3. 黑名单 Server 永不连接
/// 4. 白名单工具自动放行
/// 5. 公网 Server 强制用户确认
final class TrustBoundaryTests: XCTestCase {

    // MARK: - 1. TrustBoundary 判定

    /// stdio 传输应判定为 local 信任边界
    func testStdioTransportIsLocalBoundary() {
        let server = MCPConfigFile.Server(
            id: "s1", name: "S1",
            transport: .stdio(command: "node", args: [], env: nil),
            trust: .local, autoConnect: false, toolWhitelist: nil, toolBlacklist: nil, publicKeyPin: nil
        )
        let boundary = TrustBoundary.classify(server: server)
        XCTAssertEqual(boundary, .local)
    }

    /// localhost / 127.0.0.1 / 192.168.x.x / 10.x.x.x / 172.16-31.x.x 应判定为 lan
    func testPrivateNetworkURLsAreLANBoundary() {
        let hosts = ["127.0.0.1", "localhost", "192.168.1.1", "10.0.0.5", "172.16.0.1", "172.31.255.255"]
        for host in hosts {
            let server = MCPConfigFile.Server(
                id: "h", name: "H",
                transport: .sse(url: "http://\(host)/sse", headers: nil),
                trust: .lan, autoConnect: false, toolWhitelist: nil, toolBlacklist: nil, publicKeyPin: nil
            )
            let boundary = TrustBoundary.classify(server: server)
            XCTAssertEqual(boundary, .lan, "\(host) 应判定为 lan")
        }
    }

    /// 公网域名应判定为 public
    func testPublicDomainIsPublicBoundary() {
        let server = MCPConfigFile.Server(
            id: "p1", name: "P1",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public, autoConnect: false, toolWhitelist: nil, toolBlacklist: nil, publicKeyPin: nil
        )
        let boundary = TrustBoundary.classify(server: server)
        XCTAssertEqual(boundary, .public)
    }

    /// TrustBoundary 应能从 trust 字段直接构造
    func testTrustBoundaryFromRawValue() {
        XCTAssertEqual(TrustBoundary(rawValue: "local"), .local)
        XCTAssertEqual(TrustBoundary(rawValue: "lan"), .lan)
        XCTAssertEqual(TrustBoundary(rawValue: "public"), .public)
        XCTAssertNil(TrustBoundary(rawValue: "unknown"))
    }

    /// TrustBoundary 严重度排序：public > lan > local
    func testTrustBoundarySeverity() {
        XCTAssertLessThan(TrustBoundary.local.severity, TrustBoundary.lan.severity)
        XCTAssertLessThan(TrustBoundary.lan.severity, TrustBoundary.public.severity)
    }

    /// local 边界应默认放行（仍受 ToolAuthorization 约束）
    func testLocalBoundaryAutoApprove() {
        XCTAssertTrue(TrustBoundary.local.shouldAutoApprove, "local 边界应默认放行")
        XCTAssertFalse(TrustBoundary.lan.shouldAutoApprove, "lan 边界需用户首次确认")
        XCTAssertFalse(TrustBoundary.public.shouldAutoApprove, "public 边界需用户确认")
    }
}

/// PermissionPolicy 单元测试。
final class PermissionPolicyTests: XCTestCase {

    // MARK: - 2. 策略优先级

    /// 黑名单中的 Server 应返回 .deny（即使同时命中白名单）
    func testBlacklistOverridesWhitelist() {
        let policy = PermissionPolicy(
            whitelist: ["trusted.com"],
            blacklist: ["trusted.com"],
            defaultTrust: .lan
        )
        let decision = policy.decide(for: "trusted.com", trust: .lan)
        XCTAssertEqual(decision, .deny, "黑名单应优先于白名单")
    }

    /// 黑名单 Server 永不连接（即使 autoConnect=true）
    func testBlacklistAlwaysDeny() {
        let policy = PermissionPolicy(
            whitelist: nil,
            blacklist: ["malicious.example.com"],
            defaultTrust: .lan
        )
        let decision = policy.decide(for: "malicious.example.com", trust: .public)
        XCTAssertEqual(decision, .deny)
    }

    /// 白名单中的 Server 应返回 .allow
    func testWhitelistAllows() {
        let policy = PermissionPolicy(
            whitelist: ["trusted.example.com"],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decide(for: "trusted.example.com", trust: .lan)
        XCTAssertEqual(decision, .allow)
    }

    /// 不在白/黑名单的 lan Server 应返回 .requireConfirmation
    func testLANRequiresConfirmation() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decide(for: "lan-server.example.com", trust: .lan)
        XCTAssertEqual(decision, .requireConfirmation)
    }

    /// public 信任档位的 Server 必须返回 .requireConfirmation（首次必弹）
    func testPublicAlwaysRequiresConfirmation() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decide(for: "public-server.example.com", trust: .public)
        XCTAssertEqual(decision, .requireConfirmation, "public Server 首次必弹确认")
    }

    /// local 信任档位应返回 .allow（默认放行）
    func testLocalAutoAllow() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decide(for: "local-server", trust: .local)
        XCTAssertEqual(decision, .allow)
    }

    // MARK: - 3. 工具级策略

    /// 白名单工具自动放行（不弹窗）
    func testToolWhitelistAutoAllow() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decideToolCall(
            serverID: "s1",
            toolName: "fs_read",
            toolWhitelist: ["fs_read", "fs_list"],
            toolBlacklist: []
        )
        XCTAssertEqual(decision, .allow)
    }

    /// 黑名单工具自动拒绝
    func testToolBlacklistDeny() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decideToolCall(
            serverID: "s1",
            toolName: "dangerous_tool",
            toolWhitelist: ["fs_read"],
            toolBlacklist: ["dangerous_tool"]
        )
        XCTAssertEqual(decision, .deny, "工具黑名单应优先")
    }

    /// 黑名单工具优先于白名单
    func testToolBlacklistOverridesWhitelist() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decideToolCall(
            serverID: "s1",
            toolName: "tool",
            toolWhitelist: ["tool"],
            toolBlacklist: ["tool"]
        )
        XCTAssertEqual(decision, .deny)
    }

    /// 既不在白名单也不在黑名单的工具应返回 .requireConfirmation
    func testToolNotInListRequiresConfirmation() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decideToolCall(
            serverID: "s1",
            toolName: "unknown_tool",
            toolWhitelist: ["fs_read"],
            toolBlacklist: []
        )
        XCTAssertEqual(decision, .requireConfirmation)
    }

    /// 白名单为 nil 时所有工具均需确认
    func testNilWhitelistRequiresConfirmation() {
        let policy = PermissionPolicy(
            whitelist: [],
            blacklist: [],
            defaultTrust: .lan
        )
        let decision = policy.decideToolCall(
            serverID: "s1",
            toolName: "any_tool",
            toolWhitelist: nil,
            toolBlacklist: nil
        )
        XCTAssertEqual(decision, .requireConfirmation)
    }
}
