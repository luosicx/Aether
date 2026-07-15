import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 13.4 + 15.3 测试：插件系统核心功能。
///
/// 覆盖范围：
/// 1. PluginManifest 编解码（含 [String: Any] 参数的自定义 Codable）
/// 2. PluginManager 安装 / 卸载 / 查询
/// 3. PluginToolAdapter definition 映射 + execute 返回
/// 4. loadPluginTools / unloadPluginTools 注册到 ToolRegistry
/// 5. 版本管理：getVersion / hotUpdate / checkForUpdates
@MainActor
final class PluginManagerTests: XCTestCase {
    private let registry = ToolRegistry.shared

    // MARK: - 辅助：构造测试用插件清单

    /// 构造一个标准测试插件清单
    private func makeTestManifest(
        id: String = "test-plugin-\(UUID().uuidString.prefix(8))",
        name: String = "测试插件",
        version: String = "1.0.0",
        tools: [PluginManifest.PluginToolDef] = [
            PluginManifest.PluginToolDef(
                name: "test_tool",
                description: "测试工具",
                parameters: ["type": "object", "properties": [:]]
            )
        ],
        permissions: [PluginPermission] = [PluginPermission(type: .network, description: "需要网络")]
    ) -> PluginManifest {
        PluginManifest(
            id: id, name: name, version: version, author: "测试作者",
            description: "用于单元测试的插件", tools: tools,
            permissions: permissions, entryPoint: "main.js"
        )
    }

    // MARK: - PluginManifest 编解码

    /// PluginManifest 应支持 JSON 往返编解码，字段保持一致
    func testManifestCodableRoundTrip() throws {
        let manifest = makeTestManifest(id: "codec-test", version: "2.1.0")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        XCTAssertEqual(decoded.id, "codec-test")
        XCTAssertEqual(decoded.name, "测试插件")
        XCTAssertEqual(decoded.version, "2.1.0")
        XCTAssertEqual(decoded.author, "测试作者")
        XCTAssertEqual(decoded.description, "用于单元测试的插件")
        XCTAssertEqual(decoded.entryPoint, "main.js")
        XCTAssertEqual(decoded.tools.count, 1)
        XCTAssertEqual(decoded.tools[0].name, "test_tool")
        XCTAssertEqual(decoded.tools[0].description, "测试工具")
        XCTAssertEqual(decoded.permissions.count, 1)
        XCTAssertEqual(decoded.permissions[0].type, .network)
    }

    /// PluginManifest 编解码应正确处理 parameters JSON Schema（含嵌套字典）
    func testManifestCodablePreservesParametersSchema() throws {
        let tool = PluginManifest.PluginToolDef(
            name: "search",
            description: "搜索工具",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "搜索关键词"]
                ],
                "required": ["query"]
            ]
        )
        let manifest = makeTestManifest(id: "schema-test", tools: [tool], permissions: [])
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: data)

        XCTAssertEqual(decoded.tools[0].parameters["type"] as? String, "object")
        let props = decoded.tools[0].parameters["properties"] as? [String: Any]
        XCTAssertNotNil(props)
        let query = props?["query"] as? [String: Any]
        XCTAssertEqual(query?["type"] as? String, "string")
        let required = decoded.tools[0].parameters["required"] as? [String]
        XCTAssertEqual(required, ["query"])
    }

    /// PluginManifest 应支持 Hashable（可用于 Set / Dictionary key）
    func testManifestHashable() {
        let manifest = makeTestManifest(id: "hash-test")
        let set: Set<PluginManifest> = [manifest]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - PluginManager 安装 / 卸载

    /// install 应成功安装插件，installedPluginList 包含该插件
    func testInstallAddsPlugin() throws {
        let manager = PluginManager()
        let manifest = makeTestManifest(id: "install-test")
        try manager.install(manifest: manifest)
        XCTAssertTrue(manager.isInstalled("install-test"))
        XCTAssertEqual(manager.installedPluginList.count, 1)
    }

    /// install 空 ID 应抛出错误
    func testInstallEmptyIDThrows() {
        let manager = PluginManager()
        let manifest = makeTestManifest(id: "")
        XCTAssertThrowsError(try manager.install(manifest: manifest))
    }

    /// uninstall 应移除已安装的插件
    func testUninstallRemovesPlugin() throws {
        let manager = PluginManager()
        let manifest = makeTestManifest(id: "uninstall-test")
        try manager.install(manifest: manifest)
        XCTAssertTrue(manager.isInstalled("uninstall-test"))
        try manager.uninstall(pluginID: "uninstall-test")
        XCTAssertFalse(manager.isInstalled("uninstall-test"))
    }

    /// uninstall 未安装的插件应抛出错误
    func testUninstallNonExistentThrows() {
        let manager = PluginManager()
        XCTAssertThrowsError(try manager.uninstall(pluginID: "non-existent-plugin"))
    }

    /// isInstalled 未安装时返回 false
    func testIsInstalledReturnsFalseForUninstalled() {
        let manager = PluginManager()
        XCTAssertFalse(manager.isInstalled("not-installed"))
    }

    /// install 同 ID 插件应覆盖（视为更新）
    func testInstallOverridesSameID() throws {
        let manager = PluginManager()
        try manager.install(manifest: makeTestManifest(id: "override-test", version: "1.0.0"))
        try manager.install(manifest: makeTestManifest(id: "override-test", version: "2.0.0"))
        XCTAssertEqual(manager.installedPluginList.count, 1)
        XCTAssertEqual(manager.getVersion(pluginID: "override-test"), "2.0.0")
    }

    // MARK: - PluginToolAdapter

    /// PluginToolAdapter 应正确映射 definition（name / description / parameters）
    func testAdapterDefinitionMapping() {
        let toolDef = PluginManifest.PluginToolDef(
            name: "adapter_tool",
            description: "适配器测试工具",
            parameters: ["type": "object", "properties": [:]]
        )
        let manifest = makeTestManifest(id: "adapter-test", tools: [toolDef])
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)
        XCTAssertEqual(adapter.definition.name, "adapter_tool")
        XCTAssertEqual(adapter.definition.description, "适配器测试工具")
        XCTAssertEqual(adapter.definition.parameters["type"] as? String, "object")
    }

    /// PluginToolAdapter.execute 应返回包含插件名和工具名的结果
    func testAdapterExecuteReturnsResult() async throws {
        let toolDef = PluginManifest.PluginToolDef(
            name: "exec_tool", description: "执行测试",
            parameters: ["type": "object"]
        )
        let manifest = makeTestManifest(id: "exec-test", name: "我的插件", tools: [toolDef])
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)
        let result = try await adapter.execute(arguments: [:])
        XCTAssertTrue(result.contains("我的插件"), "结果应包含插件名")
        XCTAssertTrue(result.contains("exec_tool"), "结果应包含工具名")
    }

    // MARK: - loadPluginTools / unloadPluginTools

    /// loadPluginTools 应将插件工具注册到 ToolRegistry
    func testLoadPluginToolsRegistersToRegistry() throws {
        let manager = PluginManager()
        let toolName = "plugin_load_test_\(UUID().uuidString.prefix(8))"
        let toolDef = PluginManifest.PluginToolDef(
            name: toolName, description: "加载测试", parameters: ["type": "object"]
        )
        let manifest = makeTestManifest(id: "load-test", tools: [toolDef])
        try manager.install(manifest: manifest)

        defer {
            try? manager.uninstall(pluginID: "load-test")
        }

        XCTAssertNil(registry.getTool(named: toolName), "加载前工具不应注册")
        try manager.loadPluginTools(pluginID: "load-test")
        XCTAssertNotNil(registry.getTool(named: toolName), "加载后工具应注册到 ToolRegistry")
    }

    /// unloadPluginTools 应从 ToolRegistry 注销插件工具
    func testUnloadPluginToolsRemovesFromRegistry() throws {
        let manager = PluginManager()
        let toolName = "plugin_unload_test_\(UUID().uuidString.prefix(8))"
        let toolDef = PluginManifest.PluginToolDef(
            name: toolName, description: "卸载测试", parameters: ["type": "object"]
        )
        let manifest = makeTestManifest(id: "unload-test", tools: [toolDef])
        try manager.install(manifest: manifest)
        try manager.loadPluginTools(pluginID: "unload-test")
        XCTAssertNotNil(registry.getTool(named: toolName), "加载后工具应存在")

        try manager.unloadPluginTools(pluginID: "unload-test")
        XCTAssertNil(registry.getTool(named: toolName), "卸载后工具应从 ToolRegistry 移除")
    }

    /// loadPluginTools 未安装的插件应抛出错误
    func testLoadPluginToolsNotInstalledThrows() {
        let manager = PluginManager()
        XCTAssertThrowsError(try manager.loadPluginTools(pluginID: "non-existent"))
    }

    /// loadPluginTools 多工具应全部注册
    func testLoadPluginToolsMultipleTools() throws {
        let manager = PluginManager()
        let tools = [
            PluginManifest.PluginToolDef(name: "multi_a", description: "A", parameters: ["type": "object"]),
            PluginManifest.PluginToolDef(name: "multi_b", description: "B", parameters: ["type": "object"]),
        ]
        let manifest = makeTestManifest(id: "multi-test", tools: tools)
        try manager.install(manifest: manifest)
        defer { try? manager.uninstall(pluginID: "multi-test") }

        try manager.loadPluginTools(pluginID: "multi-test")
        XCTAssertNotNil(registry.getTool(named: "multi_a"))
        XCTAssertNotNil(registry.getTool(named: "multi_b"))
    }

    // MARK: - Task 15: 版本管理

    /// getVersion 应返回已安装插件的版本号
    func testGetVersionReturnsInstalledVersion() throws {
        let manager = PluginManager()
        try manager.install(manifest: makeTestManifest(id: "version-test", version: "3.2.1"))
        XCTAssertEqual(manager.getVersion(pluginID: "version-test"), "3.2.1")
    }

    /// getVersion 未安装插件应返回 nil
    func testGetVersionReturnsNilForUninstalled() {
        let manager = PluginManager()
        XCTAssertNil(manager.getVersion(pluginID: "non-existent"))
    }

    /// hotUpdate 应卸载旧工具、加载新工具
    func testHotUpdateReplacesTools() throws {
        let manager = PluginManager()
        let oldTool = PluginManifest.PluginToolDef(
            name: "hot_old_tool", description: "旧工具", parameters: ["type": "object"]
        )
        let newTool = PluginManifest.PluginToolDef(
            name: "hot_new_tool", description: "新工具", parameters: ["type": "object"]
        )
        try manager.install(manifest: makeTestManifest(
            id: "hotupdate-test", version: "1.0.0", tools: [oldTool]
        ))
        try manager.loadPluginTools(pluginID: "hotupdate-test")
        defer { try? manager.uninstall(pluginID: "hotupdate-test") }

        XCTAssertNotNil(registry.getTool(named: "hot_old_tool"))
        XCTAssertNil(registry.getTool(named: "hot_new_tool"))

        try manager.hotUpdate(pluginID: "hotupdate-test", newManifest: makeTestManifest(
            id: "hotupdate-test", version: "2.0.0", tools: [newTool]
        ))

        XCTAssertNil(registry.getTool(named: "hot_old_tool"), "热更新后旧工具应被卸载")
        XCTAssertNotNil(registry.getTool(named: "hot_new_tool"), "热更新后新工具应被加载")
        XCTAssertEqual(manager.getVersion(pluginID: "hotupdate-test"), "2.0.0")
    }

    /// hotUpdate 未安装插件应抛出错误
    func testHotUpdateNotInstalledThrows() {
        let manager = PluginManager()
        XCTAssertThrowsError(try manager.hotUpdate(
            pluginID: "non-existent", newManifest: makeTestManifest(id: "non-existent")
        ))
    }

    /// checkForUpdates 应返回 nil（简化实现无远程更新）
    func testCheckForUpdatesReturnsNil() async throws {
        let manager = PluginManager()
        try manager.install(manifest: makeTestManifest(id: "check-update"))
        defer { try? manager.uninstall(pluginID: "check-update") }
        let result = try await manager.checkForUpdates(pluginID: "check-update")
        XCTAssertNil(result, "简化实现应返回 nil")
    }

    // MARK: - PluginPermission 编解码

    /// PluginPermission 应支持 Codable 往返
    func testPermissionCodableRoundTrip() throws {
        let perm = PluginPermission(type: .clipboard, description: "需要剪贴板")
        let data = try JSONEncoder().encode(perm)
        let decoded = try JSONDecoder().decode(PluginPermission.self, from: data)
        XCTAssertEqual(decoded.type, .clipboard)
        XCTAssertEqual(decoded.description, "需要剪贴板")
    }

    /// PluginPermission.PermissionType 所有枚举值应可编解码
    func testPermissionTypeAllCasesCodable() throws {
        for type in [
            PluginPermission.PermissionType.network,
            .fileSystem, .clipboard, .notifications, .contacts, .location
        ] {
            let perm = PluginPermission(type: type, description: nil)
            let data = try JSONEncoder().encode(perm)
            let decoded = try JSONDecoder().decode(PluginPermission.self, from: data)
            XCTAssertEqual(decoded.type, type)
        }
    }
}
