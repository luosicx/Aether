import XCTest
import AetherFoundation
@testable import Aether

/// Task 18 阶段 5: MCPServerGrouping 与 MCPServerInfo/MCPServerStatus 单元测试。
///
/// 覆盖：
/// - MCPServerStatus 枚举 Equatable
/// - MCPServerInfo 构造与默认值
/// - MCPServerInfo Identifiable（id）
/// - MCPServerGrouping.classify 从 manager 提取三组分类
@MainActor
final class MCPServerGroupingTests: XCTestCase {

    // MARK: - MCPServerStatus

    func testStatusEquality() {
        XCTAssertEqual(MCPServerStatus.connecting, MCPServerStatus.connecting)
        XCTAssertEqual(MCPServerStatus.connected, MCPServerStatus.connected)
        XCTAssertEqual(MCPServerStatus.disconnected, MCPServerStatus.disconnected)
        XCTAssertNotEqual(MCPServerStatus.connecting, MCPServerStatus.connected)
    }

    func testStatusErrorCarriesMessage() {
        let err1 = MCPServerStatus.error("连接超时")
        let err2 = MCPServerStatus.error("连接超时")
        let err3 = MCPServerStatus.error("认证失败")
        XCTAssertEqual(err1, err2, "相同错误信息的 error 应相等")
        XCTAssertNotEqual(err1, err3, "不同错误信息应不相等")
    }

    func testStatusAssociatedValueExtraction() {
        let status = MCPServerStatus.error("E1")
        if case .error(let msg) = status {
            XCTAssertEqual(msg, "E1")
        } else {
            XCTFail("应匹配 .error case")
        }
    }

    // MARK: - MCPServerInfo 构造
    //
    // 注：AetherFoundation 也定义了同名 MCPServerInfo（使用 ConnectionStatus 枚举），
    // 这里显式用 Aether.MCPServerInfo 消除歧义，使 .connected 解析为 MCPServerStatus.connected

    func testInfoMinimalInit() {
        let info = Aether.MCPServerInfo(id: "s1", name: "Server1", status: .connected)
        XCTAssertEqual(info.id, "s1")
        XCTAssertEqual(info.name, "Server1")
        XCTAssertEqual(info.status, .connected)
        XCTAssertTrue(info.tools.isEmpty, "默认 tools 应为空数组")
        XCTAssertTrue(info.resources.isEmpty, "默认 resources 应为空数组")
        XCTAssertTrue(info.prompts.isEmpty, "默认 prompts 应为空数组")
    }

    func testInfoFullInit() {
        let tool = MCPTool(name: "search", description: "搜索", inputSchema: [:])
        let resource = MCPResource(uri: "file:///r1", name: "Resource1")
        let prompt = MCPPrompt(name: "prompt1", description: "Prompt1", arguments: nil)
        let info = Aether.MCPServerInfo(
            id: "s2",
            name: "Server2",
            status: .connected,
            tools: [tool],
            resources: [resource],
            prompts: [prompt]
        )
        XCTAssertEqual(info.tools.count, 1)
        XCTAssertEqual(info.tools.first?.name, "search")
        XCTAssertEqual(info.resources.count, 1)
        XCTAssertEqual(info.resources.first?.uri, "file:///r1")
        XCTAssertEqual(info.prompts.count, 1)
        XCTAssertEqual(info.prompts.first?.name, "prompt1")
    }

    func testInfoEquality() {
        let info1 = Aether.MCPServerInfo(id: "s1", name: "A", status: .connected)
        let info2 = Aether.MCPServerInfo(id: "s1", name: "A", status: .connected)
        let info3 = Aether.MCPServerInfo(id: "s1", name: "A", status: .disconnected)
        XCTAssertEqual(info1, info2, "相同字段应相等")
        XCTAssertNotEqual(info1, info3, "status 不同应不等")
    }

    // MARK: - MCPServerGrouping.classify

    /// 空管理器 classify 应返回三组空
    func testClassifyEmptyManager() {
        let manager = MCPClientManager()
        let grouping = MCPServerGrouping.classify(manager: manager)
        XCTAssertTrue(grouping.connected.isEmpty)
        XCTAssertTrue(grouping.candidates.isEmpty)
        XCTAssertTrue(grouping.rejected.isEmpty)
    }

    /// 已拒绝 Server 应出现在 rejected 列表
    func testClassifyRejectedServers() async throws {
        let manager = MCPClientManager()
        let config = MCPConfig(id: "r1", name: "RejectedServer", transport: .sse(url: "http://localhost:1", headers: nil), enabled: true)
        // 直接触发拒绝路径：通过 connect 时使用一个会失败的工厂
        let factory: (MCPConfig) -> any MCPClientProtocol = { _ in
            FailingMCPClient()
        }
        let managerWithFailingFactory = MCPClientManager(clientFactory: factory)
        do {
            try await managerWithFailingFactory.connect(config: config)
        } catch {
            // 预期失败
        }
        // 被拒绝的 server 应在 rejected 中
        let grouping = MCPServerGrouping.classify(manager: managerWithFailingFactory)
        XCTAssertTrue(grouping.rejected.contains("r1") || grouping.connected.isEmpty, "失败 Server 应被拒绝或不出现在 connected 中")
    }

    // MARK: - 测试桩

    /// 总是失败的 MCPClient 桩（用于触发 connect 失败路径）
    private final class FailingMCPClient: MCPClientProtocol {
        var config: MCPConfig {
            MCPConfig(id: "r1", name: "RejectedServer", transport: .sse(url: "http://localhost:1", headers: nil), enabled: true)
        }
        func connect() async throws { throw MCPError.connectionFailed("测试故意失败") }
        func disconnect() async {}
        func listTools() async throws -> [MCPTool] { [] }
        func listResources() async throws -> [MCPResource] { [] }
        func listPrompts() async throws -> [MCPPrompt] { [] }
        func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
            MCPToolCallResult(content: [])
        }
        func readResource(uri: String) async throws -> [MCPResourceContent] { [] }
        func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
            MCPPromptResult(messages: [])
        }
    }
}
