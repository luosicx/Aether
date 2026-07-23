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

    override func setUp() {
        super.setUp()
        // v1.1 Phase C: 注入 ToolRegistry 到 PluginManager，使 loadPluginTools 可注册工具
        PluginManager.toolRegistry = ToolRegistry.shared
    }

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

    /// PluginToolAdapter.execute 应通过 JavaScriptCore 执行 JS 代码并返回结果
    func testAdapterExecuteReturnsResult() async throws {
        // 使用内联 JS 作为 entryPoint（无文件时 PluginToolAdapter 回退到内联执行）
        let jsCode = """
        function execute(args) {
            return "Hello from " + (args.name || "unknown");
        }
        """
        let toolDef = PluginManifest.PluginToolDef(
            name: "exec_tool", description: "执行测试",
            parameters: ["type": "object"]
        )
        let manifest = PluginManifest(
            id: "exec-test", name: "我的插件", version: "1.0.0", author: "测试",
            description: "测试", tools: [toolDef], permissions: [],
            entryPoint: jsCode
        )
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)
        let result = try await adapter.execute(arguments: ["name": "Aether"])
        XCTAssertTrue(result.contains("Hello from Aether"), "JS 执行结果应包含期望字符串，实际：\(result)")
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
        XCTAssertNil(result, "默认 updateChecker 应返回 nil")
    }

    // MARK: - v1.1 Phase C: 本地插件扫描

    /// scanLocalPlugins 应扫描插件目录并加载 manifest.json + 入口 JS
    func testScanLocalPluginsLoadsFromDisk() throws {
        let manager = PluginManager()
        let pluginID = "scan-test-\(UUID().uuidString.prefix(8))"

        // 构造插件目录与文件
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: pluginDir) }

        // 写入 manifest.json
        let manifest = PluginManifest(
            id: pluginID, name: "扫描插件", version: "1.0.0", author: "测试",
            description: "扫描测试", tools: [], permissions: [],
            entryPoint: "main.js"
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: pluginDir.appendingPathComponent("manifest.json"))

        // 写入 main.js
        let jsContent = "function execute(args) { return 'scanned'; }"
        try jsContent.data(using: .utf8)?.write(to: pluginDir.appendingPathComponent("main.js"))

        // 扫描
        let loaded = try manager.scanLocalPlugins()
        XCTAssertTrue(loaded.contains(where: { $0.id == pluginID }), "扫描结果应包含磁盘插件")
        XCTAssertTrue(manager.isInstalled(pluginID), "扫描后插件应被安装")
        XCTAssertEqual(manager.getVersion(pluginID: pluginID), "1.0.0")
    }

    /// scanLocalPlugins 缺少入口 JS 文件时应跳过该插件
    func testScanLocalPluginsSkipsMissingEntryFile() throws {
        let manager = PluginManager()
        let pluginID = "scan-skip-\(UUID().uuidString.prefix(8))"

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: pluginDir) }

        // 只写 manifest.json，不写 main.js
        let manifest = PluginManifest(
            id: pluginID, name: "缺JS插件", version: "1.0.0", author: "测试",
            description: "缺 JS", tools: [], permissions: [],
            entryPoint: "main.js"
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: pluginDir.appendingPathComponent("manifest.json"))

        let loaded = try manager.scanLocalPlugins()
        XCTAssertFalse(loaded.contains(where: { $0.id == pluginID }), "缺少入口文件应被跳过")
        XCTAssertFalse(manager.isInstalled(pluginID), "缺少入口文件不应安装")
    }

    /// entryFileURL 应返回插件入口 JS 的完整路径
    func testEntryFileURLReturnsCorrectPath() throws {
        let manager = PluginManager()
        try manager.install(manifest: makeTestManifest(id: "entry-test"))
        defer { try? manager.uninstall(pluginID: "entry-test") }

        let url = manager.entryFileURL(for: "entry-test")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.path.hasSuffix("Plugins/entry-test/main.js") ?? false,
                      "入口文件路径应包含插件 ID 和 entryPoint，实际：\(url?.path ?? "nil")")
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
        // v1.1 Phase C: 覆盖所有权限类型（含新增 health / photoLibrary）
        for type in PluginPermission.PermissionType.allCases {
            let perm = PluginPermission(type: type, description: nil)
            let data = try JSONEncoder().encode(perm)
            let decoded = try JSONDecoder().decode(PluginPermission.self, from: data)
            XCTAssertEqual(decoded.type, type)
        }
    }

    // MARK: - toolRegistry 未注入时的 no-op 路径

    /// loadPluginTools 在 toolRegistry 未注入时应为 no-op（不抛错且无副作用）
    func testLoadPluginToolsNoOpWhenToolRegistryNotInjected() throws {
        // 临时置空 toolRegistry
        PluginManager.toolRegistry = nil
        defer { PluginManager.toolRegistry = ToolRegistry.shared }

        let manager = PluginManager()
        let toolName = "noop_load_\(UUID().uuidString.prefix(8))"
        let toolDef = PluginManifest.PluginToolDef(
            name: toolName, description: "no-op 测试", parameters: ["type": "object"]
        )
        let manifest = makeTestManifest(id: "noop-load-test", tools: [toolDef])
        try manager.install(manifest: manifest)
        defer { try? manager.uninstall(pluginID: "noop-load-test") }

        // loadPluginTools 不应抛错（no-op）
        XCTAssertNoThrow(try manager.loadPluginTools(pluginID: "noop-load-test"))
        // 工具不应被注册到 ToolRegistry
        XCTAssertNil(registry.getTool(named: toolName), "toolRegistry 未注入时工具不应被注册")
    }

    /// unloadPluginTools 在 toolRegistry 未注入时应为 no-op（不抛错且无副作用）
    func testUnloadPluginToolsNoOpWhenToolRegistryNotInjected() throws {
        PluginManager.toolRegistry = nil
        defer { PluginManager.toolRegistry = ToolRegistry.shared }

        let manager = PluginManager()
        let toolName = "noop_unload_\(UUID().uuidString.prefix(8))"
        let toolDef = PluginManifest.PluginToolDef(
            name: toolName, description: "no-op 卸载", parameters: ["type": "object"]
        )
        let manifest = makeTestManifest(id: "noop-unload-test", tools: [toolDef])
        try manager.install(manifest: manifest)
        defer { try? manager.uninstall(pluginID: "noop-unload-test") }

        // unloadPluginTools 不应抛错（no-op）
        XCTAssertNoThrow(try manager.unloadPluginTools(pluginID: "noop-unload-test"))
    }

    // MARK: - scanLocalPlugins 边界场景

    /// scanLocalPlugins 在插件目录不存在时应返回空数组
    func testScanLocalPluginsReturnsEmptyWhenDirectoryMissing() throws {
        let manager = PluginManager()
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginsDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)

        // PluginManager.init 会创建目录，这里删除以模拟目录缺失
        try? fm.removeItem(at: pluginsDir)
        defer { try? fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true) }

        XCTAssertFalse(fm.fileExists(atPath: pluginsDir.path), "测试前目录不应存在")

        let loaded = try manager.scanLocalPlugins()
        XCTAssertEqual(loaded.count, 0, "目录不存在时应返回空数组")
    }

    /// scanLocalPlugins 在 manifest.json 损坏时应跳过该插件，仅返回有效插件
    func testScanLocalPluginsSkipsCorruptedManifest() throws {
        let manager = PluginManager()
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginsDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)

        // 损坏插件目录
        let corruptedID = "scan-corrupted-\(UUID().uuidString.prefix(8))"
        let corruptedDir = pluginsDir.appendingPathComponent(corruptedID, isDirectory: true)
        try fm.createDirectory(at: corruptedDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: corruptedDir) }
        // 写入损坏的 manifest.json（非 JSON 格式）
        try "this is not valid json".data(using: .utf8)?
            .write(to: corruptedDir.appendingPathComponent("manifest.json"))
        // 也写入口 JS 文件（满足存在性检查）
        try "function execute(args) {}".data(using: .utf8)?
            .write(to: corruptedDir.appendingPathComponent("main.js"))

        // 有效插件目录
        let validID = "scan-valid-\(UUID().uuidString.prefix(8))"
        let validDir = pluginsDir.appendingPathComponent(validID, isDirectory: true)
        try fm.createDirectory(at: validDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: validDir) }
        let validManifest = PluginManifest(
            id: validID, name: "有效插件", version: "1.0.0", author: "测试",
            description: "有效", tools: [], permissions: [],
            entryPoint: "main.js"
        )
        let validManifestData = try JSONEncoder().encode(validManifest)
        try validManifestData.write(to: validDir.appendingPathComponent("manifest.json"))
        try "function execute(args) { return 'ok'; }".data(using: .utf8)?
            .write(to: validDir.appendingPathComponent("main.js"))

        // 扫描
        let loaded = try manager.scanLocalPlugins()

        // 损坏插件应被跳过
        XCTAssertFalse(loaded.contains(where: { $0.id == corruptedID }), "损坏 manifest 的插件应被跳过")
        XCTAssertFalse(manager.isInstalled(corruptedID), "损坏插件不应被安装")

        // 有效插件应被加载
        XCTAssertTrue(loaded.contains(where: { $0.id == validID }), "有效插件应被加载")
        XCTAssertTrue(manager.isInstalled(validID), "有效插件应被安装")

        // 清理安装状态
        try? manager.uninstall(pluginID: validID)
    }

    /// uninstall 在 unloadPluginTools 失败时仍应成功（源码用 try? 容忍卸载错误）
    func testUninstallToleratesUnloadFailure() throws {
        // toolRegistry 未注入时 unloadPluginTools 为 no-op；测试 uninstall 仍能成功
        PluginManager.toolRegistry = nil
        defer { PluginManager.toolRegistry = ToolRegistry.shared }

        let manager = PluginManager()
        let toolName = "uninstall_tolerant_\(UUID().uuidString.prefix(8))"
        let toolDef = PluginManifest.PluginToolDef(
            name: toolName, description: "卸载容错", parameters: ["type": "object"]
        )
        let manifest = makeTestManifest(id: "uninstall-tolerant-test", tools: [toolDef])
        try manager.install(manifest: manifest)
        XCTAssertTrue(manager.isInstalled("uninstall-tolerant-test"))

        // uninstall 内部用 try? 调用 unloadPluginTools，即使无 toolRegistry 也应成功
        XCTAssertNoThrow(try manager.uninstall(pluginID: "uninstall-tolerant-test"))
        XCTAssertFalse(manager.isInstalled("uninstall-tolerant-test"), "uninstall 后插件应被移除")
    }
}
