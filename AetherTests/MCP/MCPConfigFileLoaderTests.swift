import XCTest
import AetherFoundation
@testable import Aether

/// `MCPConfigFileLoader` 单元测试。
///
/// 覆盖范围：
/// 1. 从指定 URL 加载配置文件
/// 2. 项目级与用户级覆盖（用户级优先）
/// 3. 文件不存在时返回 nil
/// 4. JSON 格式错误时抛出解码错误
/// 5. 合并多个配置源（项目级 + 用户级）
final class MCPConfigFileLoaderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPConfigFileLoaderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        super.tearDown()
    }

    // MARK: - 1. 从 URL 加载

    /// 从指定 URL 加载合法 JSON 应返回 MCPConfigFile
    func testLoadValidConfigFromURL() throws {
        let json = """
        {
          "servers": [
            { "id": "s1", "name": "S1", "transport": { "type": "sse", "url": "http://localhost/sse" }, "autoConnect": true }
          ]
        }
        """
        let url = try writeJSON(json, fileName: "mcp.json")

        let loader = MCPConfigFileLoader()
        let config = try loader.load(from: url)

        XCTAssertEqual(config.servers.count, 1)
        XCTAssertEqual(config.servers[0].id, "s1")
        XCTAssertTrue(config.servers[0].autoConnect)
    }

    // MARK: - 2. 文件不存在

    /// 文件不存在时应抛出错误
    func testLoadNonExistentFileThrows() {
        let url = tempDir.appendingPathComponent("nonexistent.json")
        let loader = MCPConfigFileLoader()

        XCTAssertThrowsError(try loader.load(from: url))
    }

    // MARK: - 3. JSON 格式错误

    /// 非法 JSON 应抛出解码错误
    func testLoadInvalidJSONThrows() throws {
        let url = try writeJSON("{ invalid json }", fileName: "bad.json")
        let loader = MCPConfigFileLoader()

        XCTAssertThrowsError(try loader.load(from: url))
    }

    // MARK: - 4. 合并项目级与用户级

    /// 用户级配置应覆盖项目级同 ID 的 Server
    func testUserLevelOverridesProjectLevel() throws {
        let projectJSON = """
        {
          "servers": [
            { "id": "shared", "name": "项目级", "transport": { "type": "sse", "url": "http://project/sse" } },
            { "id": "proj-only", "name": "仅项目", "transport": { "type": "sse", "url": "http://proj-only/sse" } }
          ]
        }
        """
        let userJSON = """
        {
          "servers": [
            { "id": "shared", "name": "用户级覆盖", "transport": { "type": "sse", "url": "http://user/sse" }, "autoConnect": true }
          ]
        }
        """
        let projectURL = try writeJSON(projectJSON, fileName: "project-mcp.json")
        let userURL = try writeJSON(userJSON, fileName: "user-mcp.json")

        let loader = MCPConfigFileLoader()
        let merged = try loader.mergeLoad(projectURL: projectURL, userURL: userURL)

        XCTAssertEqual(merged.servers.count, 2, "应合并为 2 个 Server（shared 覆盖 + proj-only 保留）")
        let shared = merged.servers.first { $0.id == "shared" }
        XCTAssertEqual(shared?.name, "用户级覆盖", "shared 应被用户级覆盖")
        XCTAssertTrue(shared?.autoConnect ?? false)
        let projOnly = merged.servers.first { $0.id == "proj-only" }
        XCTAssertEqual(projOnly?.name, "仅项目", "proj-only 应保留")
    }

    /// 项目级存在但用户级不存在时，应仅加载项目级
    func testProjectOnlyWhenUserMissing() throws {
        let projectJSON = """
        { "servers": [ { "id": "p1", "name": "P1", "transport": { "type": "sse", "url": "http://p" } } ] }
        """
        let projectURL = try writeJSON(projectJSON, fileName: "project.json")
        let userURL = tempDir.appendingPathComponent("missing-user.json")

        let loader = MCPConfigFileLoader()
        let config = try loader.mergeLoad(projectURL: projectURL, userURL: userURL)

        XCTAssertEqual(config.servers.count, 1)
        XCTAssertEqual(config.servers[0].id, "p1")
    }

    /// 两个文件都不存在时应返回空配置
    func testBothMissingReturnsEmptyConfig() throws {
        let loader = MCPConfigFileLoader()
        let config = try loader.mergeLoad(
            projectURL: tempDir.appendingPathComponent("missing1.json"),
            userURL: tempDir.appendingPathComponent("missing2.json")
        )
        XCTAssertTrue(config.servers.isEmpty)
    }

    // MARK: - 辅助

    /// 将 JSON 字符串写入临时文件
    private func writeJSON(_ json: String, fileName: String) throws -> URL {
        let url = tempDir.appendingPathComponent(fileName)
        try json.data(using: .utf8)?.write(to: url)
        return url
    }
}
