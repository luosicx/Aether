import XCTest
import AetherFoundation
@testable import Aether

/// `MCPClientManager` 配置驱动批量连接的单元测试。
///
/// 覆盖范围：
/// 1. autoConnect=true 的 local Server 自动连接
/// 2. 黑名单 Server 永不连接（即使 autoConnect=true）
/// 3. lan/public Server 加入候选列表等待用户审批
/// 4. approveCandidate / rejectCandidate 流程
/// 5. addDiscoveredCandidate 流程（zeroconf 发现）
final class MCPClientManagerConfigTests: XCTestCase {

    // MARK: - 1. autoConnect 自动连接

    /// autoConnect=true 的 local Server 应自动连接
    @MainActor
    func testAutoConnectLocalServer() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "fs_read", description: "读取文件", inputSchema: ["type": "object"])
            ])
        })

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "local-1",
                    name: "本地 Server",
                    transport: .stdio(command: "mcp-fs", args: [], env: nil),
                    trust: .local,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )

        let count = await manager.connectFromConfig(configFile)
        XCTAssertEqual(count, 1, "应连接 1 个 Server")
        XCTAssertEqual(manager.getConnectedServers().count, 1)
        XCTAssertTrue(manager.candidateServers.isEmpty, "local Server 不应进入候选列表")
    }

    /// autoConnect=false 的 local Server 不应自动连接
    @MainActor
    func testNonAutoConnectLocalServerNotConnected() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "local-2",
                    name: "本地不自动",
                    transport: .stdio(command: "x", args: [], env: nil),
                    trust: .local,
                    autoConnect: false,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )

        let count = await manager.connectFromConfig(configFile)
        XCTAssertEqual(count, 0, "autoConnect=false 不应连接")
        XCTAssertEqual(manager.getConnectedServers().count, 0)
    }

    // MARK: - 2. 黑名单优先

    /// 黑名单中的 Server 永不连接（即使 autoConnect=true）
    @MainActor
    func testBlacklistServerNeverConnected() async throws {
        let manager = MCPClientManager(
            clientFactory: { config in MockMCPClient(config: config) },
            permissionPolicy: PermissionPolicy(
                whitelist: nil,
                blacklist: ["bad-server"],
                defaultTrust: .lan
            )
        )

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "bad-server",
                    name: "恶意 Server",
                    transport: .stdio(command: "x", args: [], env: nil),
                    trust: .local,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )

        let count = await manager.connectFromConfig(configFile)
        XCTAssertEqual(count, 0, "黑名单 Server 不应连接")
        XCTAssertTrue(manager.rejectedServerIDs.contains("bad-server"), "应加入已拒绝集合")
    }

    /// policy 段的黑名单应被应用
    @MainActor
    func testPolicyBlacklistApplied() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "policy-bad",
                    name: "策略黑名单",
                    transport: .stdio(command: "x", args: [], env: nil),
                    trust: .local,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: MCPConfigFile.Policy(
                defaultTrust: .lan,
                blacklist: ["policy-bad"],
                whitelist: nil
            )
        )

        let count = await manager.connectFromConfig(configFile)
        XCTAssertEqual(count, 0, "policy 段黑名单应阻止连接")
        XCTAssertTrue(manager.rejectedServerIDs.contains("policy-bad"))
    }

    // MARK: - 3. 候选 Server 管理

    /// public Server 应加入候选列表（不自动连接）
    @MainActor
    func testPublicServerGoesToCandidates() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "public-1",
                    name: "公网 Server",
                    transport: .sse(url: "https://example.com/sse", headers: nil),
                    trust: .public,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )

        let count = await manager.connectFromConfig(configFile)
        XCTAssertEqual(count, 0, "public Server 不应自动连接")
        XCTAssertEqual(manager.candidateServers.count, 1)
        XCTAssertEqual(manager.candidateServers[0].id, "public-1")
        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "public-1"), .public)
    }

    /// approveCandidate 应触发连接并从候选列表移除
    @MainActor
    func testApproveCandidateTriggersConnect() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "search", description: "搜索", inputSchema: ["type": "object"])
            ])
        })

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "cand-1",
                    name: "候选",
                    transport: .sse(url: "https://example.com/sse", headers: nil),
                    trust: .public,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )

        _ = await manager.connectFromConfig(configFile)
        XCTAssertEqual(manager.candidateServers.count, 1)

        await manager.approveCandidate(serverID: "cand-1")

        XCTAssertTrue(manager.candidateServers.isEmpty, "批准后应从候选列表移除")
        XCTAssertTrue(manager.approvedServerIDs.contains("cand-1"))
        XCTAssertEqual(manager.getConnectedServers().count, 1)
    }

    /// rejectCandidate 应加入已拒绝集合
    @MainActor
    func testRejectCandidateAddsToRejected() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "reject-1",
                    name: "拒绝",
                    transport: .sse(url: "https://example.com/sse", headers: nil),
                    trust: .public,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )

        _ = await manager.connectFromConfig(configFile)
        manager.rejectCandidate(serverID: "reject-1")

        XCTAssertTrue(manager.candidateServers.isEmpty)
        XCTAssertTrue(manager.rejectedServerIDs.contains("reject-1"))
    }

    // MARK: - 4. addDiscoveredCandidate

    /// zeroconf 发现的 local Server 应直接连接
    @MainActor
    func testDiscoveredLocalServerAutoConnect() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "tool", description: "工具", inputSchema: [:])
            ])
        })

        let server = MCPConfigFile.Server(
            id: "discovered-local",
            name: "发现本地",
            transport: .stdio(command: "x", args: [], env: nil),
            trust: .local,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .local)

        // 异步连接需短暂等待
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(manager.getConnectedServers().count, 1)
        XCTAssertTrue(manager.candidateServers.isEmpty)
    }

    /// zeroconf 发现的 public Server 应加入候选列表
    @MainActor
    func testDiscoveredPublicServerGoesToCandidates() {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let server = MCPConfigFile.Server(
            id: "discovered-public",
            name: "发现公网",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)

        XCTAssertEqual(manager.candidateServers.count, 1)
        XCTAssertEqual(manager.candidateServers[0].id, "discovered-public")
    }

    /// 重复发现的 Server 不应重复添加
    @MainActor
    func testDiscoveredDuplicateNotAdded() {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let server = MCPConfigFile.Server(
            id: "dup-1",
            name: "重复",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)
        manager.addDiscoveredCandidate(server, boundary: .public)

        XCTAssertEqual(manager.candidateServers.count, 1, "重复发现不应追加")
    }

    /// 黑名单中的发现 Server 应直接拒绝
    @MainActor
    func testDiscoveredBlacklistedRejected() {
        let manager = MCPClientManager(
            clientFactory: { config in MockMCPClient(config: config) },
            permissionPolicy: PermissionPolicy(
                whitelist: nil,
                blacklist: ["discovered-bad"],
                defaultTrust: .lan
            )
        )

        let server = MCPConfigFile.Server(
            id: "discovered-bad",
            name: "发现黑名单",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)

        XCTAssertTrue(manager.candidateServers.isEmpty)
        XCTAssertTrue(manager.rejectedServerIDs.contains("discovered-bad"))
    }
}
