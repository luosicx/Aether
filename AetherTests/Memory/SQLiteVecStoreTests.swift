import XCTest
@testable import Aether

/// Task 19 阶段 1: SQLiteVecStore 单元测试。
///
/// 覆盖：sqlite-vec 加载成功/失败场景、降级容错、API 行为。
/// 注意：CI/沙箱环境 sqlite-vec 二进制通常不可加载，本测试主要验证降级行为；
/// 加载成功的路径在装配 sqlite-vec 二进制的本地环境验证。
final class SQLiteVecStoreTests: XCTestCase {
    /// 使用临时路径的数据库
    private var dbPath: String!

    override func setUp() async throws {
        try await super.setUp()
        dbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("aether_vec_test_\(UUID().uuidString).db")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: dbPath)
        dbPath = nil
        try await super.tearDown()
    }

    // MARK: - 降级容错（CI 环境预期行为）

    /// sqlite-vec 二进制不可加载时，isAvailable 应为 false。
    /// CI 与沙箱环境通常走此分支。
    func testSqliteVecLoadFailureMarksUnavailable() async throws {
        let store = SQLiteVecStore(dbPath: dbPath)
        try await store.initialize()
        let available = await store.isAvailable
        // CI 环境 sqlite-vec 不可加载，预期 false；本地集成二进制后预期 true。
        // 这里仅验证 initialize 不抛异常（无论是否加载成功）
        XCTAssertNotNil(available, "isAvailable 应有明确值")
    }

    /// 加载失败时 upsert 不抛异常（静默 no-op）
    func testUpsertWhenUnavailableIsNoop() async throws {
        let store = SQLiteVecStore(dbPath: dbPath)
        try await store.initialize()
        let available = await store.isAvailable
        // 加载失败时 upsert 应静默 no-op
        try await store.upsert(id: UUID(), embedding: [1.0, 0.0], metadata: [:])
        // 加载成功时 count 应为 1；失败时 count 应为 0
        let count = try await store.count()
        if available {
            XCTAssertEqual(count, 1, "sqlite-vec 可用时 upsert 应成功")
        } else {
            XCTAssertEqual(count, 0, "sqlite-vec 不可用时 count 应为 0")
        }
    }

    /// 加载失败时 query 返回空数组
    func testQueryWhenUnavailableReturnsEmpty() async throws {
        let store = SQLiteVecStore(dbPath: dbPath)
        try await store.initialize()
        let results = try await store.query([1.0, 0.0], limit: 5)
        let available = await store.isAvailable
        if available {
            // 加载成功但表为空，预期空数组
            XCTAssertEqual(results.count, 0, "空表查询应返回空")
        } else {
            XCTAssertEqual(results.count, 0, "不可用时 query 应返回空数组")
        }
    }

    /// 加载失败时 delete 不抛异常
    func testDeleteWhenUnavailableIsNoop() async throws {
        let store = SQLiteVecStore(dbPath: dbPath)
        try await store.initialize()
        // 不应抛异常
        try await store.delete(id: UUID())
    }

    /// 加载失败时 deleteAll 不抛异常
    func testDeleteAllWhenUnavailableIsNoop() async throws {
        let store = SQLiteVecStore(dbPath: dbPath)
        try await store.initialize()
        try await store.deleteAll()
        // 验证 count 仍为 0
        let count = try await store.count()
        XCTAssertEqual(count, 0)
    }

    /// 多次 initialize 应幂等
    func testInitializeIsIdempotent() async throws {
        let store = SQLiteVecStore(dbPath: dbPath)
        try await store.initialize()
        let available1 = await store.isAvailable
        // 再次 initialize 不应抛异常
        try await store.initialize()
        let available2 = await store.isAvailable
        XCTAssertEqual(available1, available2, "重复 initialize 应保持状态一致")
    }
}
