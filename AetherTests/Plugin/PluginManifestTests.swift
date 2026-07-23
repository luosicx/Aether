import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// v1.1 Phase C 测试：PluginManifest 新增字段编解码。
///
/// 覆盖范围：
/// 1. dependencies / hooks / downloadURL / signature / minAppVersion 字段的往返编解码
/// 2. 向后兼容：缺失新字段时使用默认值
/// 3. PluginHook 枚举编解码
final class PluginManifestTests: XCTestCase {

    // MARK: - 新增字段往返编解码

    /// 包含所有新字段的 manifest 应支持 JSON 往返编解码
    func testNewFieldsCodableRoundTrip() throws {
        let manifest = PluginManifest(
            id: "new-fields-test",
            name: "新字段插件",
            version: "1.2.0",
            author: "测试作者",
            description: "测试新字段编解码",
            tools: [],
            permissions: [],
            entryPoint: "main.js",
            dependencies: ["dep-a", "dep-b"],
            hooks: [.onMessageReceived, .onToolCall],
            downloadURL: URL(string: "https://example.com/plugin.js"),
            signature: "base64-signature",
            minAppVersion: "1.1.0"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        XCTAssertEqual(decoded.id, "new-fields-test")
        XCTAssertEqual(decoded.dependencies, ["dep-a", "dep-b"])
        XCTAssertEqual(decoded.hooks, [.onMessageReceived, .onToolCall])
        XCTAssertEqual(decoded.downloadURL?.absoluteString, "https://example.com/plugin.js")
        XCTAssertEqual(decoded.signature, "base64-signature")
        XCTAssertEqual(decoded.minAppVersion, "1.1.0")
    }

    // MARK: - 向后兼容

    /// 缺失新字段的旧版 manifest JSON 应使用默认值解码
    func testBackwardCompatibilityMissingNewFields() throws {
        // 构造不含新字段的旧版 JSON
        let oldJSON = """
        {
            "id": "old-plugin",
            "name": "旧插件",
            "version": "1.0.0",
            "author": "作者",
            "description": "旧版 manifest",
            "tools": [],
            "permissions": [],
            "entryPoint": "main.js"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PluginManifest.self, from: oldJSON)

        XCTAssertEqual(decoded.id, "old-plugin")
        XCTAssertEqual(decoded.dependencies, [], "缺失 dependencies 应默认空数组")
        XCTAssertEqual(decoded.hooks, [], "缺失 hooks 应默认空数组")
        XCTAssertNil(decoded.downloadURL, "缺失 downloadURL 应为 nil")
        XCTAssertNil(decoded.signature, "缺失 signature 应为 nil")
        XCTAssertNil(decoded.minAppVersion, "缺失 minAppVersion 应为 nil")
    }

    // MARK: - PluginHook 编解码

    /// PluginHook 所有枚举值应可编解码
    func testPluginHookCodableAllCases() throws {
        for hook in PluginHook.allCases {
            let data = try JSONEncoder().encode(hook)
            let decoded = try JSONDecoder().decode(PluginHook.self, from: data)
            XCTAssertEqual(decoded, hook)
        }
    }

    /// PluginHook rawValue 应匹配预期字符串
    func testPluginHookRawValues() {
        XCTAssertEqual(PluginHook.onMessageReceived.rawValue, "onMessageReceived")
        XCTAssertEqual(PluginHook.onToolCall.rawValue, "onToolCall")
        XCTAssertEqual(PluginHook.onConversationCreated.rawValue, "onConversationCreated")
    }

    // MARK: - 默认值

    /// 使用默认参数构造的 manifest 新字段应有正确默认值
    func testDefaultValuesForNewFields() {
        let manifest = PluginManifest(
            id: "defaults-test",
            name: "默认值测试",
            version: "1.0.0",
            author: "作者",
            description: "测试默认值",
            tools: [],
            permissions: [],
            entryPoint: "main.js"
        )

        XCTAssertEqual(manifest.dependencies, [])
        XCTAssertEqual(manifest.hooks, [])
        XCTAssertNil(manifest.downloadURL)
        XCTAssertNil(manifest.signature)
        XCTAssertNil(manifest.minAppVersion)
    }

    // MARK: - 编码后包含新字段

    /// 编码后的 JSON 应包含新字段键（dependencies / hooks）
    func testEncodedJSONContainsNewFields() throws {
        let manifest = PluginManifest(
            id: "encode-test",
            name: "编码测试",
            version: "1.0.0",
            author: "作者",
            description: "测试编码输出",
            tools: [],
            permissions: [],
            entryPoint: "main.js",
            dependencies: ["x"],
            hooks: [.onMessageReceived]
        )

        let data = try JSONEncoder().encode(manifest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        XCTAssertNotNil(json["dependencies"], "编码后应包含 dependencies 字段")
        XCTAssertNotNil(json["hooks"], "编码后应包含 hooks 字段")
        XCTAssertNil(json["downloadURL"], "downloadURL 为 nil 时不应编码")
        XCTAssertNil(json["signature"], "signature 为 nil 时不应编码")
        XCTAssertNil(json["minAppVersion"], "minAppVersion 为 nil 时不应编码")
    }
}
