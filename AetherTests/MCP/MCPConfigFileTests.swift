import XCTest
import AetherFoundation
@testable import Aether

/// `mcp.json` 配置文件 schema 与 `MCPConfigFile` Codable 类型的单元测试。
///
/// 覆盖范围：
/// 1. 完整配置（servers/discovery/policy 三段）的编解码
/// 2. 缺省字段的解码（discovery / policy 可选）
/// 3. 与规划文档 3.3 节示例 JSON 的兼容性
/// 4. Server 配置中 trust / autoConnect / toolWhitelist 字段解析
final class MCPConfigFileTests: XCTestCase {

    // MARK: - 1. 完整配置编解码

    /// 完整三段配置应能正确编解码，字段保持一致
    func testFullConfigCodable() throws {
        let json = """
        {
          "servers": [
            {
              "id": "local-fs",
              "name": "本地文件系统",
              "transport": { "type": "stdio", "command": "mcp-fs", "args": [] },
              "trust": "local",
              "autoConnect": true,
              "toolWhitelist": ["fs_read", "fs_list"]
            }
          ],
          "discovery": {
            "zeroconf": true,
            "zeroconfType": "_aether_mcp._tcp.",
            "scanIntervalSec": 60
          },
          "policy": {
            "defaultTrust": "lan",
            "blacklist": ["malicious.example.com"]
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(MCPConfigFile.self, from: json)

        XCTAssertEqual(config.servers.count, 1, "应解析出 1 个 Server")
        XCTAssertEqual(config.servers[0].id, "local-fs")
        XCTAssertEqual(config.servers[0].name, "本地文件系统")
        XCTAssertEqual(config.servers[0].trust, .local)
        XCTAssertTrue(config.servers[0].autoConnect)
        XCTAssertEqual(config.servers[0].toolWhitelist, ["fs_read", "fs_list"])

        XCTAssertEqual(config.discovery?.zeroconf, true)
        XCTAssertEqual(config.discovery?.zeroconfType, "_aether_mcp._tcp.")
        XCTAssertEqual(config.discovery?.scanIntervalSec, 60)

        XCTAssertEqual(config.policy?.defaultTrust, .lan)
        XCTAssertEqual(config.policy?.blacklist, ["malicious.example.com"])
    }

    /// 编码后再解码应保持等价（round-trip）
    func testConfigRoundTrip() throws {
        let server = MCPConfigFile.Server(
            id: "rt-1",
            name: "Round Trip",
            transport: .sse(url: "http://localhost:3000/sse", headers: nil),
            trust: .lan,
            autoConnect: false,
            toolPolicy: ToolPolicy(blacklist: ["dangerous_tool"]),
            publicKeyPin: "sha256:abcdef"
        )
        let original = MCPConfigFile(
            servers: [server],
            discovery: MCPConfigFile.Discovery(zeroconf: true, zeroconfType: "_aether_mcp._tcp.", scanIntervalSec: 30),
            policy: MCPConfigFile.Policy(defaultTrust: .public, blacklist: ["bad.example.com"], whitelist: nil)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPConfigFile.self, from: data)

        XCTAssertEqual(decoded.servers, original.servers)
        XCTAssertEqual(decoded.discovery, original.discovery)
        XCTAssertEqual(decoded.policy, original.policy)
    }

    // MARK: - 2. 缺省字段解码

    /// 缺省 discovery / policy 段应能解析（仅 servers）
    func testMinimalConfigWithOnlyServers() throws {
        let json = """
        {
          "servers": [
            {
              "id": "min-1",
              "name": "Minimal",
              "transport": { "type": "sse", "url": "http://localhost/sse" }
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(MCPConfigFile.self, from: json)

        XCTAssertEqual(config.servers.count, 1)
        XCTAssertEqual(config.servers[0].id, "min-1")
        XCTAssertEqual(config.servers[0].trust, .lan, "缺省 trust 应为 lan")
        XCTAssertFalse(config.servers[0].autoConnect, "缺省 autoConnect 应为 false")
        XCTAssertNil(config.servers[0].toolWhitelist)
        XCTAssertNil(config.discovery)
        XCTAssertNil(config.policy)
    }

    /// Server 的 trust 字段缺省时应为 lan
    func testServerDefaultTrustIsLAN() throws {
        let json = """
        {
          "servers": [
            { "id": "t1", "name": "T1", "transport": { "type": "sse", "url": "http://x/sse" } }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(MCPConfigFile.self, from: json)
        XCTAssertEqual(config.servers[0].trust, .lan)
    }

    // MARK: - 3. trust 枚举解析

    /// trust 字段应正确解析 local / lan / public 三种取值
    func testTrustBoundaryParsing() throws {
        let cases: [(String, TrustBoundary)] = [
            ("local", .local),
            ("lan", .lan),
            ("public", .public)
        ]
        for (raw, expected) in cases {
            let json = """
            { "servers": [ { "id": "x", "name": "X", "transport": { "type": "sse", "url": "http://x" }, "trust": "\(raw)" } ] }
            """.data(using: .utf8)!
            let config = try JSONDecoder().decode(MCPConfigFile.self, from: json)
            XCTAssertEqual(config.servers[0].trust, expected, "trust=\(raw) 应解析为 \(expected)")
        }
    }

    /// 未知的 trust 取值应抛出解码错误
    func testUnknownTrustThrowsError() {
        let json = """
        { "servers": [ { "id": "x", "name": "X", "transport": { "type": "sse", "url": "http://x" }, "trust": "unknown" } ] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(MCPConfigFile.self, from: json))
    }

    // MARK: - 4. 转换为 MCPConfig

    /// MCPConfigFile.Server 应能转换为 MCPConfig（用于 MCPClientManager.connect）
    func testServerToMCPConfig() {
        let server = MCPConfigFile.Server(
            id: "conv-1",
            name: "转换测试",
            transport: .stdio(command: "node", args: ["server.js"], env: ["X": "1"]),
            trust: .local,
            autoConnect: true,
            toolPolicy: ToolPolicy(whitelist: ["a"]),
            publicKeyPin: nil
        )

        let config = server.toMCPConfig()
        XCTAssertEqual(config.id, "conv-1")
        XCTAssertEqual(config.name, "转换测试")
        XCTAssertEqual(config.enabled, true, "autoConnect=true 应映射为 enabled=true")

        guard case .stdio(let cmd, let args, let env) = config.transport else {
            return XCTFail("应为 stdio 传输")
        }
        XCTAssertEqual(cmd, "node")
        XCTAssertEqual(args, ["server.js"])
        XCTAssertEqual(env?["X"], "1")
    }

    /// SSE 传输的 Server 转换应保留 url 与 headers
    func testSSEServerToMCPConfig() {
        let server = MCPConfigFile.Server(
            id: "conv-sse",
            name: "SSE",
            transport: .sse(url: "http://example.com/sse", headers: ["Authorization": "Bearer x"]),
            trust: .public,
            autoConnect: false,
            publicKeyPin: nil
        )

        let config = server.toMCPConfig()
        XCTAssertEqual(config.id, "conv-sse")
        XCTAssertFalse(config.enabled)

        guard case .sse(let url, let headers) = config.transport else {
            return XCTFail("应为 sse 传输")
        }
        XCTAssertEqual(url, "http://example.com/sse")
        XCTAssertEqual(headers?["Authorization"], "Bearer x")
    }
}
