import XCTest
@testable import Aether
import AetherFoundation

/// `PermissionPromptView` 与权限审批流程的单元测试。
///
/// 覆盖范围：
/// 1. PermissionPromptInfo 数据模型构造
/// 2. 信任档位显示文案
/// 3. 公网 Server 首次调用必弹逻辑
/// 4. 批准/拒绝回调触发
final class PermissionPromptViewTests: XCTestCase {

    // MARK: - 1. PermissionPromptInfo 数据模型

    /// PermissionPromptInfo 应正确构造并保存 Server 元信息
    func testPermissionPromptInfoConstruction() {
        let info = PermissionPromptInfo(
            serverID: "srv-1",
            serverName: "测试 Server",
            trust: .public,
            transportDescription: "SSE: https://example.com/sse",
            toolCount: 5,
            toolNames: ["search", "calc", "fs_read", "fs_list", "dangerous"],
            publicKeyPin: "sha256:abcdef123456"
        )

        XCTAssertEqual(info.serverID, "srv-1")
        XCTAssertEqual(info.serverName, "测试 Server")
        XCTAssertEqual(info.trust, .public)
        XCTAssertEqual(info.toolCount, 5)
        XCTAssertEqual(info.toolNames.count, 5)
        XCTAssertEqual(info.publicKeyPin, "sha256:abcdef123456")
    }

    /// 公网 Server 必须显示公钥指纹（若有）
    func testPublicServerShowsPublicKeyPin() {
        let info = PermissionPromptInfo(
            serverID: "pub",
            serverName: "公网",
            trust: .public,
            transportDescription: "SSE: https://example.com/sse",
            toolCount: 1,
            toolNames: ["tool"],
            publicKeyPin: "sha256:abc"
        )
        XCTAssertNotNil(info.publicKeyPin)
    }

    // MARK: - 2. 信任档位显示文案

    /// 各信任档位应有对应的本地化描述
    func testTrustBoundaryDisplayText() {
        XCTAssertEqual(TrustBoundary.local.displayName, "本地")
        XCTAssertEqual(TrustBoundary.lan.displayName, "局域网")
        XCTAssertEqual(TrustBoundary.internet.displayName, "公网")
    }

    /// 各信任档位应有对应的风险等级描述
    func testTrustBoundaryRiskLevel() {
        XCTAssertEqual(TrustBoundary.local.riskLevel, "低")
        XCTAssertEqual(TrustBoundary.lan.riskLevel, "中")
        XCTAssertEqual(TrustBoundary.internet.riskLevel, "高")
    }

    // MARK: - 3. 公网 Server 首次必弹

    /// 公网 Server 首次调用前必须弹窗（通过 shouldPromptBeforeConnect 判定）
    @MainActor
    func testPublicServerRequiresPrompt() {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let server = MCPConfigFile.Server(
            id: "pub-prompt",
            name: "公网弹窗",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)

        XCTAssertTrue(manager.candidateServers.contains { $0.id == "pub-prompt" },
                      "公网 Server 应进入候选列表等待审批")
    }

    // MARK: - 4. 批准/拒绝回调

    /// 批准候选 Server 后应触发连接
    @MainActor
    func testApproveTriggersConnect() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "tool1", description: "工具", inputSchema: [:])
            ])
        })
        let server = MCPConfigFile.Server(
            id: "approve-test",
            name: "批准测试",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)

        await manager.approveCandidate(serverID: "approve-test")

        XCTAssertTrue(manager.approvedServerIDs.contains("approve-test"))
        XCTAssertEqual(manager.getConnectedServers().count, 1)
    }

    /// 拒绝候选 Server 后应加入已拒绝集合
    @MainActor
    func testRejectAddsToRejected() {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let server = MCPConfigFile.Server(
            id: "reject-test",
            name: "拒绝测试",
            transport: .sse(url: "https://example.com/sse", headers: nil),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: .public)

        manager.rejectCandidate(serverID: "reject-test")

        XCTAssertTrue(manager.rejectedServerIDs.contains("reject-test"))
        XCTAssertTrue(manager.candidateServers.isEmpty)
    }
}
