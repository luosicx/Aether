#if os(iOS) || os(macOS)
import XCTest
@testable import Aether

/// v2.0: CloudKitSyncManager 状态管理逻辑单元测试。
///
/// 覆盖：
/// - lastSyncDate 更新（triggerSync 与 UserDefaults 持久化）
/// - pendingChangesCount 更新（含负值截断）
/// - conflictCount 更新（recordConflict 递增）
/// - isSyncing 状态切换（beginSync / finishSync / triggerSync 复位 / 重入跳过）
@MainActor
final class CloudKitSyncManagerTests: XCTestCase {
    private var manager: CloudKitSyncManager!

    override func setUp() async throws {
        try await super.setUp()
        // 清空 iCloud 同步相关 UserDefaults，保证初始状态干净
        UserDefaults.standard.removeObject(forKey: AetherApp.iCloudSyncEnabledKey)
        UserDefaults.standard.removeObject(forKey: AetherApp.lastICloudSyncDateKey)
        manager = CloudKitSyncManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialPendingChangesCountIsZero() {
        XCTAssertEqual(manager.pendingChangesCount, 0, "初始待同步条目数应为 0")
    }

    func testInitialConflictCountIsZero() {
        XCTAssertEqual(manager.conflictCount, 0, "初始冲突数应为 0")
    }

    func testInitialIsSyncingIsFalse() {
        XCTAssertFalse(manager.isSyncing, "初始 isSyncing 应为 false")
    }

    func testInitialLastSyncDateIsNilWhenNoUserDefaults() {
        XCTAssertNil(manager.lastSyncDate, "UserDefaults 无记录时 lastSyncDate 应为 nil")
    }

    // MARK: - lastSyncDate 更新

    func testTriggerSyncUpdatesLastSyncDate() async {
        XCTAssertNil(manager.lastSyncDate)
        await manager.triggerSync()
        XCTAssertNotNil(manager.lastSyncDate, "triggerSync 后 lastSyncDate 不应为 nil")
    }

    func testTriggerSyncSetsLastSyncDateToRecentTime() async {
        let before = Date()
        await manager.triggerSync()
        let after = Date()
        guard let last = manager.lastSyncDate else {
            XCTFail("lastSyncDate 不应为 nil")
            return
        }
        XCTAssertTrue(last >= before && last <= after, "lastSyncDate 应在触发时间窗口内")
    }

    func testTriggerSyncPersistsLastSyncDateToUserDefaults() async {
        await manager.triggerSync()
        let stored = UserDefaults.standard.object(forKey: AetherApp.lastICloudSyncDateKey) as? Date
        XCTAssertNotNil(stored, "triggerSync 后应持久化到 UserDefaults")
        XCTAssertEqual(stored, manager.lastSyncDate)
    }

    // MARK: - isSyncing 状态切换

    func testBeginSyncSetsIsSyncingTrue() {
        XCTAssertFalse(manager.isSyncing)
        manager.beginSync()
        XCTAssertTrue(manager.isSyncing, "beginSync 后 isSyncing 应为 true")
    }

    func testFinishSyncSetsIsSyncingFalse() {
        manager.beginSync()
        XCTAssertTrue(manager.isSyncing)
        manager.finishSync()
        XCTAssertFalse(manager.isSyncing, "finishSync 后 isSyncing 应为 false")
    }

    func testTriggerSyncLeavesIsSyncingFalseAfterCompletion() async {
        await manager.triggerSync()
        XCTAssertFalse(manager.isSyncing, "triggerSync 完成后 isSyncing 应复位为 false")
    }

    func testTriggerSyncIsNoOpWhenAlreadySyncing() async {
        manager.beginSync()
        let before = manager.lastSyncDate
        await manager.triggerSync()
        XCTAssertEqual(manager.lastSyncDate, before, "已同步中再次触发应跳过，lastSyncDate 不变")
        XCTAssertTrue(manager.isSyncing, "已同步中再次触发不应改变 isSyncing")
    }

    // MARK: - pendingChangesCount 更新

    func testUpdatePendingCountSetsValue() {
        manager.updatePendingCount(5)
        XCTAssertEqual(manager.pendingChangesCount, 5)
    }

    func testUpdatePendingCountClampsNegativeToZero() {
        manager.updatePendingCount(-3)
        XCTAssertEqual(manager.pendingChangesCount, 0, "负值应被截断为 0")
    }

    func testPendingCountCanBeUpdatedAndCleared() {
        manager.updatePendingCount(8)
        XCTAssertEqual(manager.pendingChangesCount, 8)
        manager.updatePendingCount(0)
        XCTAssertEqual(manager.pendingChangesCount, 0)
    }

    // MARK: - conflictCount 更新

    func testRecordConflictIncrementsCount() {
        manager.recordConflict()
        manager.recordConflict()
        manager.recordConflict()
        XCTAssertEqual(manager.conflictCount, 3, "三次 recordConflict 后冲突数应为 3")
    }

    func testRecordConflictSingleIncrement() {
        let initial = manager.conflictCount
        manager.recordConflict()
        XCTAssertEqual(manager.conflictCount, initial + 1, "recordConflict 应使冲突数 +1")
    }
}
#endif
