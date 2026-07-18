import XCTest
@testable import Aether
import AetherFoundation

/// `MCPSettingsView` 三组 Server 显示与审批操作的单元测试。
///
/// 覆盖范围：
/// 1. 三组分类（已连接 / 候选 / 已拒绝）正确分组
/// 2. 手动连接/断开操作
/// 3. 审批操作（批准/拒绝）
/// 4. 黑名单 Server 显示在已拒绝组
final class MCPSettingsViewTests: XCTestCase {

    // MARK: - 1. 三组分类

    /// 已连接的 Server 应出现在"已连接"组
    @MainActor
    func testConnectedServersGrouped() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "tool", description: "工具", inputSchema: [:])
            ])
        })
        try await manager.connect(config: MCPConfig(
            id: "connected-1",
            name: "已连接 Server",
            transport: .sse(url: "http://localhost/sse", headers: nil),
            enabled: true
        ))

        let groups = MCPServerGrouping.classify(manager: manager)
        XCTAssertEqual(groups.connected.count, 1)
        XCTAssertEqual(groups.connected[0].name, "已连接 Server")
        XCTAssertTrue(groups.candidates.isEmpty)
        XCTAssertTrue(groups.rejected.isEmpty)
    }

    /// 候选 Server 应出现在"候选"组
    @MainActor
    func testCandidateServersGrouped() {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let server = MCPConfigFile.Server(
            id: "cand-1",
            name: "候选 Server",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)

        let groups = MCPServerGrouping.classify(manager: manager)
        XCTAssertTrue(groups.connected.isEmpty)
        XCTAssertEqual(groups.candidates.count, 1)
        XCTAssertEqual(groups.candidates[0].id, "cand-1")
        XCTAssertTrue(groups.rejected.isEmpty)
    }

    /// 已拒绝 Server ID 应出现在"已拒绝"组
    @MainActor
    func testRejectedServersGrouped() {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        manager.rejectCandidate(serverID: "rejected-1")
        manager.rejectCandidate(serverID: "rejected-2")

        let groups = MCPServerGrouping.classify(manager: manager)
        XCTAssertTrue(groups.connected.isEmpty)
        XCTAssertTrue(groups.candidates.isEmpty)
        XCTAssertEqual(groups.rejected.count, 2)
        XCTAssertTrue(groups.rejected.contains("rejected-1"))
        XCTAssertTrue(groups.rejected.contains("rejected-2"))
    }

    /// 三组同时有数据时应正确分类
    @MainActor
    func testAllThreeGroupsPopulated() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        // 已连接
        try await manager.connect(config: MCPConfig(
            id: "conn",
            name: "已连接",
            transport: .sse(url: "http://localhost/sse", headers: nil),
            enabled: true
        ))
        // 候选
        manager.addDiscoveredCandidate(
            MCPConfigFile.Server(
                id: "cand", name: "候选",
                transport: .sse(url: "https://example.com/sse", headers: nil),
                trust: .public, autoConnect: false,
                publicKeyPin: nil
            ),
            boundary: .public
        )
        // 已拒绝
        manager.rejectCandidate(serverID: "rej")

        let groups = MCPServerGrouping.classify(manager: manager)
        XCTAssertEqual(groups.connected.count, 1)
        XCTAssertEqual(groups.candidates.count, 1)
        XCTAssertEqual(groups.rejected.count, 1)
    }

    // MARK: - 2. 手动连接/断开

    /// 手动连接候选 Server 应触发 approveCandidate
    @MainActor
    func testManualApprove() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "tool", description: "工具", inputSchema: [:])
            ])
        })
        manager.addDiscoveredCandidate(
            MCPConfigFile.Server(
                id: "manual", name: "手动",
                transport: .sse(url: "https://example.com/sse", headers: nil),
                trust: .public, autoConnect: false,
                publicKeyPin: nil
            ),
            boundary: .public
        )

        await manager.approveCandidate(serverID: "manual")

        XCTAssertTrue(manager.approvedServerIDs.contains("manual"))
        XCTAssertEqual(manager.getConnectedServers().count, 1)
    }

    /// 手动断开已连接 Server
    @MainActor
    func testManualDisconnect() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        try await manager.connect(config: MCPConfig(
            id: "disc",
            name: "断开测试",
            transport: .sse(url: "http://localhost/sse", headers: nil),
            enabled: true
        ))
        XCTAssertEqual(manager.getConnectedServers().count, 1)

        await manager.disconnect(serverID: "disc")
        XCTAssertEqual(manager.getConnectedServers().count, 0)
    }

    // MARK: - 3. 黑名单显示

    /// 黑名单 Server 应显示在已拒绝组（即使未显式 rejectCandidate）
    @MainActor
    func testBlacklistServerInRejectedGroup() async {
        let manager = MCPClientManager(
            clientFactory: { config in MockMCPClient(config: config) },
            permissionPolicy: PermissionPolicy(
                whitelist: nil,
                blacklist: ["blacklisted"],
                defaultTrust: .lan
            )
        )

        // 通过配置触发黑名单加入 rejectedServerIDs
        let configFile = MCPConfigFile(
            servers: [
                MCPConfigFile.Server(
                    id: "blacklisted",
                    name: "黑名单",
                    transport: .stdio(command: "x", args: [], env: nil),
                    trust: .local,
                    autoConnect: true,
                    publicKeyPin: nil
                )
            ],
            discovery: nil,
            policy: nil
        )
        _ = await manager.connectFromConfig(configFile)

        let groups = MCPServerGrouping.classify(manager: manager)
        XCTAssertTrue(groups.rejected.contains("blacklisted"))
    }
}
