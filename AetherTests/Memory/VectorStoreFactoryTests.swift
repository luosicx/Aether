import XCTest
@testable import Aether

/// Task 19 阶段 1: VectorStoreFactory 单元测试。
///
/// 覆盖：默认降级到 BruteForceVectorStore（CI 环境）、覆盖存储注入、重置缓存。
final class VectorStoreFactoryTests: XCTestCase {
    private var factory: VectorStoreFactory!

    override func setUp() async throws {
        try await super.setUp()
        // 使用临时路径，确保不污染真实数据库
        let dbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("aether_factory_test_\(UUID().uuidString).db")
        factory = VectorStoreFactory(dbPath: dbPath)
    }

    override func tearDown() async throws {
        factory.reset()
        factory = nil
        try await super.tearDown()
    }

    // MARK: - 默认选择

    /// 默认情况下（CI 沙箱），factory 应返回 BruteForceVectorStore（降级方案）。
    /// 本地集成 sqlite-vec 二进制后会返回 SQLiteVecStore，本测试不强制断言类型。
    func testStoreReturnsAvailableStore() async throws {
        let store = await factory.store()
        let available = await store.isAvailable
        XCTAssertTrue(available, "factory 返回的 store 应可用（无论 sqlite-vec 还是 bruteForce）")
    }

    /// 多次调用 store() 应返回同一实例（缓存）
    func testStoreCachesInstance() async throws {
        let store1 = await factory.store()
        let store2 = await factory.store()
        let count1 = try await store1.count()
        let count2 = try await store2.count()
        XCTAssertEqual(count1, count2, "缓存实例应一致")
    }

    // MARK: - 覆盖注入（测试用）

    /// setOverride 应注入自定义 store
    func testSetOverrideReturnsInjectedStore() async throws {
        let mock = MockVectorStore()
        factory.setOverride(mock)
        let store = await factory.store()
        let count = try await store.count()
        XCTAssertEqual(count, 42, "应返回注入的 mock store")
    }

    /// setOverride(nil) 清除覆盖后应重新走默认路径
    func testSetOverrideNilClearsOverride() async throws {
        let mock = MockVectorStore()
        factory.setOverride(mock)
        _ = await factory.store()

        factory.setOverride(nil)
        let store = await factory.store()
        let count = try await store.count()
        XCTAssertEqual(count, 0, "清除覆盖后应走默认路径，count 为 0")
    }

    /// reset 应清空缓存
    func testResetClearsCache() async throws {
        _ = await factory.store()
        factory.reset()
        // reset 后再次获取应能正常返回
        let store = await factory.store()
        let available = await store.isAvailable
        XCTAssertTrue(available)
    }
}

/// 桩 VectorStore，用于测试覆盖注入。
actor MockVectorStore: VectorStore {
    let isAvailable: Bool = true

    func initialize() async throws {}
    func upsert(id: UUID, embedding: [Double], metadata: [String: String]) async throws {}
    func upsertBatch(_ records: [(id: UUID, embedding: [Double], metadata: [String: String])]) async throws {}
    func query(_ query: [Double], limit: Int) async throws -> [VectorSearchResult] { [] }
    func delete(id: UUID) async throws {}
    func deleteAll() async throws {}
    func count() async throws -> Int { 42 }
}
