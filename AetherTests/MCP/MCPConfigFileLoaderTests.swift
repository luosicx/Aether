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

    // MARK: - 5. 损坏 JSON 容错（mergeLoad）

    /// 项目 JSON 合法、用户 JSON 损坏时，mergeLoad 应静默跳过用户配置，仅返回项目配置且不抛错。
    /// loadOptional 内部会捕获解码错误并返回 nil，因此损坏文件不会阻塞合并流程。
    func testMergeLoadCorruptedUserJSONSilentlySkipped() throws {
        let projectJSON = """
        {
          "servers": [
            { "id": "p1", "name": "P1", "transport": { "type": "sse", "url": "http://p/sse" } }
          ]
        }
        """
        let projectURL = try writeJSON(projectJSON, fileName: "project-valid.json")
        // 写入损坏的用户 JSON（文件存在但内容无法解析）
        let userURL = try writeJSON("{ not a valid json }", fileName: "user-corrupted.json")

        let loader = MCPConfigFileLoader()
        // 不应抛出错误：损坏的用户 JSON 被 loadOptional 静默跳过
        let config = try loader.mergeLoad(projectURL: projectURL, userURL: userURL)

        XCTAssertEqual(config.servers.count, 1, "损坏的用户 JSON 应被静默跳过，仅返回项目配置")
        XCTAssertEqual(config.servers[0].id, "p1", "应返回项目级配置")
    }

    /// 项目 JSON 损坏、用户 JSON 合法时，mergeLoad 应静默跳过项目配置，仅返回用户配置。
    func testMergeLoadCorruptedProjectJSONSilentlySkipped() throws {
        let projectURL = try writeJSON("{ broken json ]", fileName: "project-corrupted.json")
        let userJSON = """
        {
          "servers": [
            { "id": "u1", "name": "U1", "transport": { "type": "sse", "url": "http://u/sse" } }
          ]
        }
        """
        let userURL = try writeJSON(userJSON, fileName: "user-valid.json")

        let loader = MCPConfigFileLoader()
        let config = try loader.mergeLoad(projectURL: projectURL, userURL: userURL)

        XCTAssertEqual(config.servers.count, 1, "损坏的项目 JSON 应被静默跳过，仅返回用户配置")
        XCTAssertEqual(config.servers[0].id, "u1", "应返回用户级配置")
    }

    /// 项目文件不存在、仅用户文件合法时，应返回用户配置。
    /// 覆盖 mergeLoad 中 `userConfig ?? projectConfig ?? 空配置` 的回退分支。
    func testMergeLoadUserOnlyWhenProjectMissing() throws {
        let userJSON = """
        {
          "servers": [
            { "id": "uo", "name": "UserOnly", "transport": { "type": "sse", "url": "http://uo/sse" } }
          ]
        }
        """
        let userURL = try writeJSON(userJSON, fileName: "user-only.json")
        let projectURL = tempDir.appendingPathComponent("missing-project.json")

        let loader = MCPConfigFileLoader()
        let config = try loader.mergeLoad(projectURL: projectURL, userURL: userURL)

        XCTAssertEqual(config.servers.count, 1, "项目文件不存在时应仅返回用户配置")
        XCTAssertEqual(config.servers[0].id, "uo")
    }

    // MARK: - 6. discovery / policy 字段合并

    /// 项目级 discovery 存在、用户级 discovery 为 nil 时，合并后 discovery 应来自项目；
    /// 反之用户级 discovery 应整体覆盖项目级。
    func testMergeLoadDiscoveryFieldMerge() throws {
        let projectJSON = """
        {
          "servers": [],
          "discovery": { "zeroconf": true, "zeroconfType": "_proj._tcp.", "scanIntervalSec": 30 }
        }
        """
        let projectURL = try writeJSON(projectJSON, fileName: "proj-disc.json")

        let loader = MCPConfigFileLoader()

        // 用户级无 discovery → 合并后取项目级
        let userNoDiscoveryURL = try writeJSON("{ \"servers\": [] }", fileName: "user-nodisc.json")
        let mergedFromProject = try loader.mergeLoad(projectURL: projectURL, userURL: userNoDiscoveryURL)
        XCTAssertEqual(mergedFromProject.discovery?.zeroconf, true, "用户级 discovery 为 nil 时应取项目级")
        XCTAssertEqual(mergedFromProject.discovery?.zeroconfType, "_proj._tcp.")
        XCTAssertEqual(mergedFromProject.discovery?.scanIntervalSec, 30)

        // 用户级有 discovery → 整体覆盖项目级
        let userWithDiscoveryJSON = """
        {
          "servers": [],
          "discovery": { "zeroconf": false, "zeroconfType": "_user._tcp.", "scanIntervalSec": 120 }
        }
        """
        let userWithDiscoveryURL = try writeJSON(userWithDiscoveryJSON, fileName: "user-disc.json")
        let mergedFromUser = try loader.mergeLoad(projectURL: projectURL, userURL: userWithDiscoveryURL)
        XCTAssertEqual(mergedFromUser.discovery?.zeroconf, false, "用户级 discovery 应覆盖项目级")
        XCTAssertEqual(mergedFromUser.discovery?.zeroconfType, "_user._tcp.")
        XCTAssertEqual(mergedFromUser.discovery?.scanIntervalSec, 120)
    }

    /// 项目级 policy 存在、用户级 policy 为 nil 时，合并后 policy 应来自项目；
    /// 反之用户级 policy 应整体覆盖项目级（不为 nil 时整体替换，非字段级合并）。
    func testMergeLoadPolicyFieldMerge() throws {
        let projectJSON = """
        {
          "servers": [],
          "policy": { "defaultTrust": "local", "blacklist": ["proj-bad"] }
        }
        """
        let projectURL = try writeJSON(projectJSON, fileName: "proj-pol.json")

        let loader = MCPConfigFileLoader()

        // 用户级无 policy → 合并后取项目级
        let userNoPolicyURL = try writeJSON("{ \"servers\": [] }", fileName: "user-nopol.json")
        let mergedFromProject = try loader.mergeLoad(projectURL: projectURL, userURL: userNoPolicyURL)
        XCTAssertEqual(mergedFromProject.policy?.defaultTrust, .local, "用户级 policy 为 nil 时应取项目级")
        XCTAssertEqual(mergedFromProject.policy?.blacklist, ["proj-bad"])

        // 用户级有 policy → 整体覆盖项目级
        let userWithPolicyJSON = """
        {
          "servers": [],
          "policy": { "defaultTrust": "public", "whitelist": ["user-good"] }
        }
        """
        let userWithPolicyURL = try writeJSON(userWithPolicyJSON, fileName: "user-pol.json")
        let mergedFromUser = try loader.mergeLoad(projectURL: projectURL, userURL: userWithPolicyURL)
        XCTAssertEqual(mergedFromUser.policy?.defaultTrust, .internet, "用户级 policy 应覆盖项目级")
        XCTAssertEqual(mergedFromUser.policy?.whitelist, ["user-good"])
        XCTAssertNil(mergedFromUser.policy?.blacklist, "用户级 policy 完整覆盖项目级（非字段级合并）")
    }

    // MARK: - 7. App Support 加载与目录创建

    /// 注入自定义 FileManager 指向临时目录，验证 loadFromAppSupport 正确加载并合并项目级与用户级配置。
    /// MockFileManager 将 applicationSupportDirectory 重定向到临时目录，避免污染真实 App Support。
    func testLoadFromAppSupportWithMockFileManager() throws {
        // 准备临时 App Support 根目录与 Aether 子目录
        let mockAppSupport = tempDir.appendingPathComponent("MockAppSupport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mockAppSupport, withIntermediateDirectories: true)
        let aetherDir = mockAppSupport.appendingPathComponent(MCPConfigFileLoader.appSupportSubdirectory)
        try FileManager.default.createDirectory(at: aetherDir, withIntermediateDirectories: true)

        // 写入项目级配置（含一个会被覆盖的 server 和一个项目独有的 server）
        let projectJSON = """
        {
          "servers": [
            { "id": "as-proj", "name": "AppSupportProject", "transport": { "type": "sse", "url": "http://proj/sse" } },
            { "id": "as-proj-only", "name": "ProjectOnly", "transport": { "type": "sse", "url": "http://po/sse" } }
          ]
        }
        """
        try projectJSON.data(using: .utf8)?.write(
            to: aetherDir.appendingPathComponent(MCPConfigFileLoader.projectFileName)
        )

        // 写入用户级配置（覆盖 as-proj，并新增独有 server）
        let userJSON = """
        {
          "servers": [
            { "id": "as-proj", "name": "AppSupportUser", "transport": { "type": "sse", "url": "http://user/sse" } },
            { "id": "as-user-only", "name": "UserOnly", "transport": { "type": "sse", "url": "http://uo/sse" } }
          ]
        }
        """
        try userJSON.data(using: .utf8)?.write(
            to: aetherDir.appendingPathComponent(MCPConfigFileLoader.userFileName)
        )

        // 注入 MockFileManager，使 loadFromAppSupport 使用临时目录
        let mockFileManager = MockFileManager(appSupportURL: mockAppSupport)
        let loader = MCPConfigFileLoader()
        let config = try loader.loadFromAppSupport(fileManager: mockFileManager)

        // 验证合并结果：as-proj 被用户级覆盖，as-proj-only 与 as-user-only 保留
        XCTAssertEqual(
            config.servers.count, 3,
            "应合并为 3 个 server（as-proj 覆盖 + as-proj-only + as-user-only）"
        )
        let proj = config.servers.first { $0.id == "as-proj" }
        XCTAssertEqual(proj?.name, "AppSupportUser", "as-proj 应被用户级覆盖")
        let projOnly = config.servers.first { $0.id == "as-proj-only" }
        XCTAssertEqual(projOnly?.name, "ProjectOnly", "项目独有的 as-proj-only 应保留")
        let userOnly = config.servers.first { $0.id == "as-user-only" }
        XCTAssertEqual(userOnly?.name, "UserOnly", "用户独有的 as-user-only 应保留")

        // 验证 Aether 子目录存在（loadFromAppSupport 内部 appSupportURL 会确保目录存在）
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: aetherDir.path),
            "Aether 子目录应存在"
        )
    }

    /// 调用 loadFromAppSupport 时若 Aether 子目录不存在，appSupportURL 应自动创建该目录。
    /// 通过 MockFileManager 重定向到临时目录，初始不创建 Aether 子目录，调用后验证目录被创建。
    func testAppSupportURLCreatesDirectory() throws {
        // 准备临时 App Support 根目录（Aether 子目录故意不创建）
        let mockAppSupport = tempDir.appendingPathComponent("MockAppSupportForCreate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mockAppSupport, withIntermediateDirectories: true)
        let aetherDir = mockAppSupport.appendingPathComponent(MCPConfigFileLoader.appSupportSubdirectory)

        // 验证 Aether 子目录初始不存在
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: aetherDir.path),
            "测试前置：Aether 子目录应不存在"
        )

        // 调用 loadFromAppSupport 应触发 appSupportURL 内部的目录创建逻辑
        let mockFileManager = MockFileManager(appSupportURL: mockAppSupport)
        let loader = MCPConfigFileLoader()
        // 配置文件不存在时返回空配置，但不影响目录创建的副作用
        let config = try loader.loadFromAppSupport(fileManager: mockFileManager)

        // 验证 Aether 子目录已自动创建
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: aetherDir.path),
            "Aether 子目录应被 appSupportURL 自动创建"
        )
        XCTAssertTrue(config.servers.isEmpty, "无配置文件时应返回空配置")
    }

    // MARK: - 辅助

    /// 将 JSON 字符串写入临时文件
    private func writeJSON(_ json: String, fileName: String) throws -> URL {
        let url = tempDir.appendingPathComponent(fileName)
        try json.data(using: .utf8)?.write(to: url)
        return url
    }
}

// MARK: - 测试辅助

/// 测试用的 FileManager 子类：将 applicationSupportDirectory 重定向到指定 URL。
/// 用于测试 `MCPConfigFileLoader.loadFromAppSupport` 与 `appSupportURL` 的目录创建行为，
/// 避免污染真实 App Support 目录。仅重写 `url(for:in:appropriateFor:create:)`，
/// 其他方法（如 fileExists / createDirectory）沿用 FileManager 默认实现，操作真实文件系统。
private final class MockFileManager: FileManager {
    /// 模拟的 Application Support 目录 URL
    private let mockAppSupportURL: URL

    init(appSupportURL: URL) {
        self.mockAppSupportURL = appSupportURL
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .applicationSupportDirectory {
            return mockAppSupportURL
        }
        return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
    }
}
