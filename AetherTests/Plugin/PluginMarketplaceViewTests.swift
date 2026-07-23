import XCTest
import SwiftUI
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// PluginMarketplaceView 单元测试。
///
/// 注：PluginMarketplaceView 与 PluginDetailView 中的 filteredPlugins / permissionIcon /
/// permissionLabel / loadPlugins / installPlugin 均为 private 方法或 @ViewBuilder，
/// 无法在不修改实现代码的前提下直接测试（项目未引入 ViewInspector）。
/// 本文件改为测试：
/// 1. 视图可被实例化（smoke test）
/// 2. PluginPermission.PermissionType 枚举完备性（视图 permissionIcon/permissionLabel 的输入域）
/// 3. PluginMarketplaceService.searchPlugins 搜索逻辑（filteredPlugins 的底层依赖）
@MainActor
final class PluginMarketplaceViewTests: XCTestCase {

    // MARK: - 视图实例化 smoke test

    /// PluginMarketplaceView 应可使用默认初始化器实例化
    func testMarketplaceViewCanBeInstantiated() {
        let view = PluginMarketplaceView()
        XCTAssertNotNil(view, "PluginMarketplaceView 应可被实例化")
    }

    /// PluginDetailView 应可使用 manifest + marketplace 实例化
    func testDetailViewCanBeInstantiated() {
        let manifest = PluginManifest(
            id: "detail-test", name: "详情测试", version: "1.0.0",
            author: "测试", description: "详情页测试", tools: [], permissions: [],
            entryPoint: "main.js"
        )
        let marketplace = PluginMarketplaceService()
        let view = PluginDetailView(plugin: manifest, marketplace: marketplace) { _ in }
        XCTAssertNotNil(view, "PluginDetailView 应可被实例化")
    }

    // MARK: - PluginPermission.PermissionType 枚举完备性

    /// PermissionType 应包含全部 8 个权限类型
    func testPermissionTypeAllCasesCount() {
        XCTAssertEqual(PluginPermission.PermissionType.allCases.count, 8, "应包含 8 个权限类型")
    }

    /// PermissionType rawValue 应与 case 名一致（视图 permissionIcon/permissionLabel 依赖此枚举）
    func testPermissionTypeRawValues() {
        XCTAssertEqual(PluginPermission.PermissionType.network.rawValue, "network")
        XCTAssertEqual(PluginPermission.PermissionType.fileSystem.rawValue, "fileSystem")
        XCTAssertEqual(PluginPermission.PermissionType.clipboard.rawValue, "clipboard")
        XCTAssertEqual(PluginPermission.PermissionType.notifications.rawValue, "notifications")
        XCTAssertEqual(PluginPermission.PermissionType.contacts.rawValue, "contacts")
        XCTAssertEqual(PluginPermission.PermissionType.location.rawValue, "location")
        XCTAssertEqual(PluginPermission.PermissionType.health.rawValue, "health")
        XCTAssertEqual(PluginPermission.PermissionType.photoLibrary.rawValue, "photoLibrary")
    }

    /// PermissionType rawValue 应支持往返初始化
    func testPermissionTypeRawValueRoundTrip() {
        for type in PluginPermission.PermissionType.allCases {
            let restored = PluginPermission.PermissionType(rawValue: type.rawValue)
            XCTAssertEqual(restored, type, "rawValue 往返应还原原 case：\(type.rawValue)")
        }
    }

    /// PermissionType 各 case 应互不相同（Hashable 一致性）
    func testPermissionTypeHashableDeduplication() {
        let types = PluginPermission.PermissionType.allCases
        XCTAssertEqual(Set(types).count, types.count, "所有权限类型应可去重")
    }

    // MARK: - searchPlugins 边界用例（filteredPlugins 的底层依赖）

    /// searchPlugins 应支持部分词匹配（contains 语义）
    func testSearchPluginsPartialMatch() async throws {
        let service = try await makeServiceWithPlugins([
            makeManifest(id: "1", name: "Weather Forecast", description: "天气"),
            makeManifest(id: "2", name: "Calculator", description: "计算器"),
        ])
        // "Weath" 应部分匹配 "Weather Forecast"
        XCTAssertEqual(service.searchPlugins(query: "Weath").count, 1, "应支持部分词匹配")
        XCTAssertEqual(service.searchPlugins(query: "Weath").first?.id, "1")
    }

    /// searchPlugins 查询含前后空格时不应自动 trim（实现未 trim，" Weather " 不匹配 "Weather"）
    func testSearchPluginsQueryWithWhitespace() async throws {
        let service = try await makeServiceWithPlugins([
            makeManifest(id: "1", name: "Weather", description: "天气", author: "Alice"),
        ])
        // 实现使用 contains，不 trim 查询；" Weather " 不匹配 "Weather"
        XCTAssertEqual(service.searchPlugins(query: "Weather").count, 1)
        XCTAssertEqual(service.searchPlugins(query: " Weather ").count, 0, "含空格的查询不应匹配（实现未 trim）")
    }

    /// searchPlugins 应支持 CJK 字符搜索
    func testSearchPluginsWithCJK() async throws {
        let service = try await makeServiceWithPlugins([
            makeManifest(id: "1", name: "天气插件", description: "weather", author: "Alice"),
            makeManifest(id: "2", name: "计算器", description: "calculator", author: "Bob"),
        ])
        XCTAssertEqual(service.searchPlugins(query: "天气").count, 1, "应支持中文搜索")
        XCTAssertEqual(service.searchPlugins(query: "天气").first?.id, "1")
        XCTAssertEqual(service.searchPlugins(query: "计算").count, 1)
    }

    // MARK: - 辅助

    private func makeManifest(id: String, name: String, description: String = "",
                              author: String = "测试") -> PluginManifest {
        PluginManifest(
            id: id, name: name, version: "1.0.0", author: author,
            description: description, tools: [], permissions: [],
            entryPoint: "main.js"
        )
    }

    private func makeServiceWithPlugins(_ plugins: [PluginManifest]) async throws -> PluginMarketplaceService {
        let jsonData = try JSONEncoder().encode(plugins)
        let mockURL = URL(string: "https://mock.example.com/marketplace-view-registry.json")!
        PluginMockURLProtocol.mockData[mockURL] = jsonData
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PluginMockURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        try await service.fetchPluginList()
        return service
    }
}
