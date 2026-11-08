#if os(macOS)
import XCTest
import CoreGraphics
@testable import Aether

/// v2.0 macOS 多窗口状态管理器单元测试。
///
/// 测试策略：每个用例使用独立的 UserDefaults suite（唯一 UUID 名称）隔离，
/// 避免污染 `UserDefaults.standard` 及其他用例。通过注入 userDefaults 验证
/// 持久化、恢复、覆盖、移除等行为。
@MainActor
final class WindowStateManagerTests: XCTestCase {
    /// 被测管理器（注入隔离的 userDefaults）
    private var manager: WindowStateManager!
    /// 隔离的 UserDefaults 实例
    private var userDefaults: UserDefaults!
    /// 唯一 suite 名称，确保每个用例的存储互不干扰
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "WindowStateManagerTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "WindowStateManagerTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建测试用 UserDefaults"])
        }
        userDefaults = defaults
        manager = WindowStateManager(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        manager = nil
        if let suiteName, let userDefaults {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - saveWindowState / loadWindowState

    /// saveWindowState 应正确保存窗口状态，loadWindowState 能读回一致数据
    func testSaveWindowStateStoresAndLoadsState() {
        let id = UUID()
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

        manager.saveWindowState(conversationId: id, frame: frame, isFocused: true)
        let state = manager.loadWindowState(conversationId: id)

        XCTAssertNotNil(state, "保存后应能加载到状态")
        XCTAssertEqual(state?.conversationId, id)
        XCTAssertEqual(state?.frame, frame)
        XCTAssertEqual(state?.isFocused, true)
    }

    /// loadWindowState 对不存在的 conversationId 应返回 nil
    func testLoadWindowStateReturnsNilForNonExistentConversation() {
        let state = manager.loadWindowState(conversationId: UUID())
        XCTAssertNil(state, "不存在的 conversationId 应返回 nil")
    }

    // MARK: - removeWindowState

    /// removeWindowState 应正确移除已保存的状态
    func testRemoveWindowStateRemovesState() {
        let id = UUID()
        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                isFocused: false)
        XCTAssertNotNil(manager.loadWindowState(conversationId: id))

        manager.removeWindowState(conversationId: id)

        XCTAssertNil(manager.loadWindowState(conversationId: id), "移除后应返回 nil")
    }

    /// removeWindowState 对不存在的 conversationId 应为无副作用操作（不崩溃）
    func testRemoveWindowStateForNonExistentIsNoOp() {
        let unknownId = UUID()
        manager.removeWindowState(conversationId: unknownId)
        XCTAssertTrue(manager.getAllWindowStates().isEmpty, "移除不存在的状态不应产生副作用")
    }

    // MARK: - getAllWindowStates

    /// getAllWindowStates 应返回所有已保存的窗口状态
    func testGetAllWindowStatesReturnsAllSavedStates() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        manager.saveWindowState(conversationId: id1,
                                frame: CGRect(x: 1, y: 1, width: 10, height: 10), isFocused: true)
        manager.saveWindowState(conversationId: id2,
                                frame: CGRect(x: 2, y: 2, width: 20, height: 20), isFocused: false)
        manager.saveWindowState(conversationId: id3,
                                frame: CGRect(x: 3, y: 3, width: 30, height: 30), isFocused: true)

        let all = manager.getAllWindowStates()
        XCTAssertEqual(all.count, 3, "应返回全部 3 个窗口状态")
        let ids = Set(all.map(\.conversationId))
        XCTAssertEqual(ids, Set([id1, id2, id3]), "返回的状态应包含所有已保存的 conversationId")
    }

    /// getAllWindowStates 在无任何状态时应返回空数组
    func testGetAllWindowStatesEmptyWhenNone() {
        XCTAssertEqual(manager.getAllWindowStates(), [], "初始状态下应返回空数组")
    }

    // MARK: - 覆盖与时间戳

    /// 对同一 conversationId 重复 saveWindowState 应覆盖旧状态，仅保留最新值
    func testOverwriteExistingStateReplacesWithLatest() {
        let id = UUID()
        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                isFocused: false)
        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                                isFocused: true)

        let state = manager.loadWindowState(conversationId: id)
        XCTAssertEqual(state?.frame, CGRect(x: 200, y: 200, width: 800, height: 600), "应被最新 frame 覆盖")
        XCTAssertEqual(state?.isFocused, true, "应被最新 isFocused 覆盖")
        XCTAssertEqual(manager.getAllWindowStates().count, 1, "覆盖后总数应仍为 1")
    }

    /// saveWindowState 应更新 lastActiveAt 为当前时间
    func testSaveWindowStateUpdatesLastActiveAt() {
        let id = UUID()
        let before = Date()

        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                isFocused: true)

        let state = manager.loadWindowState(conversationId: id)
        XCTAssertNotNil(state?.lastActiveAt, "lastActiveAt 不应为 nil")
        XCTAssertGreaterThanOrEqual(state?.lastActiveAt ?? .distantPast, before,
                                    "lastActiveAt 应不早于保存前的时间")
    }

    /// 重复保存应刷新 lastActiveAt（后一次不早于前一次）
    func testOverwriteRefreshesLastActiveAt() async throws {
        let id = UUID()
        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                isFocused: false)
        let firstDate = try XCTUnwrap(manager.loadWindowState(conversationId: id)?.lastActiveAt)

        // 等待一小段时间确保 Date() 推进
        try await Task.sleep(nanoseconds: 50_000_000)

        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                isFocused: false)
        let secondDate = try XCTUnwrap(manager.loadWindowState(conversationId: id)?.lastActiveAt)

        XCTAssertGreaterThan(secondDate, firstDate, "重复保存应刷新 lastActiveAt")
    }

    // MARK: - 持久化

    /// saveWindowState 应通过 UserDefaults 持久化，新实例（同 UserDefaults）能恢复
    func testSaveWindowStatePersistsAcrossInstances() {
        let id = UUID()
        let frame = CGRect(x: 10, y: 20, width: 640, height: 480)

        manager.saveWindowState(conversationId: id, frame: frame, isFocused: true)

        // 用同一 UserDefaults 新建实例，模拟应用重启后恢复
        let restored = WindowStateManager(userDefaults: userDefaults)
        let state = restored.loadWindowState(conversationId: id)

        XCTAssertEqual(state?.frame, frame, "新实例应能从 UserDefaults 恢复 frame")
        XCTAssertTrue(state?.isFocused ?? false, "新实例应能从 UserDefaults 恢复 isFocused")
        XCTAssertEqual(state?.conversationId, id)
    }

    /// 状态应使用 "aether.window." 前缀的 key 持久化，移除后 key 应被清除
    func testRemoveWindowStateRemovesFromUserDefaults() {
        let id = UUID()
        manager.saveWindowState(conversationId: id,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                isFocused: true)
        let key = "aether.window." + id.uuidString

        XCTAssertNotNil(userDefaults.data(forKey: key), "保存后 UserDefaults 中应存在对应 key")

        manager.removeWindowState(conversationId: id)

        XCTAssertNil(userDefaults.data(forKey: key), "移除后 UserDefaults 中应清除对应 key")
    }

    // MARK: - windowStates 属性

    /// windowStates 属性应反映 save / remove 的变更
    func testWindowStatesDictionaryReflectsChanges() {
        XCTAssertTrue(manager.windowStates.isEmpty, "初始状态下 windowStates 应为空")

        let id1 = UUID()
        let id2 = UUID()
        manager.saveWindowState(conversationId: id1,
                                frame: CGRect(x: 0, y: 0, width: 1, height: 1), isFocused: false)
        manager.saveWindowState(conversationId: id2,
                                frame: CGRect(x: 0, y: 0, width: 2, height: 2), isFocused: true)

        XCTAssertEqual(manager.windowStates.count, 2, "保存 2 个状态后 windowStates 应有 2 项")
        XCTAssertNotNil(manager.windowStates[id1])
        XCTAssertNotNil(manager.windowStates[id2])

        manager.removeWindowState(conversationId: id1)
        XCTAssertEqual(manager.windowStates.count, 1, "移除 1 个后 windowStates 应剩 1 项")
        XCTAssertNil(manager.windowStates[id1], "被移除的 id 应不在字典中")
    }
}
#endif
