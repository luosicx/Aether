import XCTest
import SwiftData
@testable import Aether

/// Task 20 阶段 2: NodeStateMachine 单元测试
///
/// 覆盖：
/// - 节点注册（单个/批量）
/// - 状态查询
/// - 合法状态迁移（pending → running → completed/failed/skipped）
/// - 非法状态迁移抛错
/// - 节点未找到错误
/// - 尝试次数计数
/// - 重置节点 / 重置全部
/// - 全部终止判断
/// - completedCount / totalCount
@MainActor
final class NodeStateMachineTests: XCTestCase {

    // MARK: - 注册

    func testRegisterSingle() async {
        let sm = NodeStateMachine()
        let id = UUID()
        await sm.register(nodeID: id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .pending)
    }

    func testRegisterBatch() async {
        let sm = NodeStateMachine()
        let ids = [UUID(), UUID(), UUID()]
        await sm.register(nodeIDs: ids)
        for id in ids {
            let status = await sm.status(of: id)
            XCTAssertEqual(status, .pending)
        }
    }

    func testInitWithNodeIDs() async {
        let ids = [UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        for id in ids {
            let status = await sm.status(of: id)
            XCTAssertEqual(status, .pending)
        }
    }

    func testRegisterDuplicateIgnored() async {
        let sm = NodeStateMachine()
        let id = UUID()
        await sm.register(nodeID: id)
        // 注册已存在节点不应重置状态
        try? await sm.markRunning(id)
        await sm.register(nodeID: id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .running, "重复注册不应重置状态")
    }

    // MARK: - 状态查询

    func testStatusOfUnregistered() async {
        let sm = NodeStateMachine()
        let status = await sm.status(of: UUID())
        XCTAssertNil(status)
    }

    func testNodeIDsInStatus() async {
        let ids = [UUID(), UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        try? await sm.markRunning(ids[0])
        try? await sm.markCompleted(ids[0])
        try? await sm.markRunning(ids[1])

        let pending = await sm.nodeIDs(in: .pending)
        XCTAssertEqual(pending, [ids[2]])

        let completed = await sm.nodeIDs(in: .completed)
        XCTAssertEqual(completed, [ids[0]])

        let running = await sm.nodeIDs(in: .running)
        XCTAssertEqual(running, [ids[1]])
    }

    // MARK: - 合法状态迁移

    func testLegalTransitionPendingToRunning() async throws {
        let sm = NodeStateMachine(nodeIDs: [UUID()])
        let id = UUID()
        await sm.register(nodeID: id)
        try await sm.markRunning(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .running)
    }

    func testLegalTransitionRunningToCompleted() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        try await sm.markCompleted(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .completed)
    }

    func testLegalTransitionRunningToFailed() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        try await sm.markFailed(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .failed)
    }

    func testLegalTransitionPendingToSkipped() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markSkipped(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .skipped)
    }

    func testLegalTransitionFailedToRunning() async throws {
        // 重试：failed → running
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        try await sm.markFailed(id)
        try await sm.markRunning(id) // 重试
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .running)
    }

    func testLegalTransitionFailedToSkipped() async throws {
        // 用户跳过失败节点：failed → skipped
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        try await sm.markFailed(id)
        try await sm.markSkipped(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .skipped)
    }

    // MARK: - 非法状态迁移

    func testIllegalTransitionPendingToCompleted() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        do {
            try await sm.markCompleted(id)
            XCTFail("pending → completed 应为非法迁移")
        } catch let error as NodeStateMachine.StateMachineError {
            if case .illegalTransition(let from, let to, _) = error {
                XCTAssertEqual(from, .pending)
                XCTAssertEqual(to, .completed)
            } else {
                XCTFail("应为 illegalTransition")
            }
        }
    }

    func testIllegalTransitionCompletedToRunning() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        try await sm.markCompleted(id)
        do {
            try await sm.markRunning(id)
            XCTFail("completed → running 应为非法迁移")
        } catch let error as NodeStateMachine.StateMachineError {
            if case .illegalTransition = error {
                // 预期
            } else {
                XCTFail("应为 illegalTransition")
            }
        }
    }

    func testIllegalTransitionSkippedToRunning() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markSkipped(id)
        do {
            try await sm.markRunning(id)
            XCTFail("skipped → running 应为非法迁移")
        } catch {
            // 预期
        }
    }

    // MARK: - 节点未找到

    func testNodeNotFound() async {
        let sm = NodeStateMachine()
        do {
            try await sm.markRunning(UUID())
            XCTFail("应抛出 nodeNotFound")
        } catch let error as NodeStateMachine.StateMachineError {
            if case .nodeNotFound = error {
                // 预期
            } else {
                XCTFail("应为 nodeNotFound")
            }
        }
    }

    // MARK: - 尝试次数

    func testAttemptCount() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        // 首次 running
        try await sm.markRunning(id)
        var count = await sm.attemptCount(of: id)
        XCTAssertEqual(count, 1)
        // 失败后重试
        try await sm.markFailed(id)
        try await sm.markRunning(id)
        count = await sm.attemptCount(of: id)
        XCTAssertEqual(count, 2)
    }

    // MARK: - 重置

    func testResetNode() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        try await sm.markFailed(id)
        await sm.reset(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .pending)
        let count = await sm.attemptCount(of: id)
        XCTAssertEqual(count, 0)
    }

    func testResetAll() async throws {
        let ids = [UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        try await sm.markRunning(ids[0])
        try await sm.markCompleted(ids[0])
        try await sm.markRunning(ids[1])
        await sm.resetAll()
        for id in ids {
            let status = await sm.status(of: id)
            XCTAssertEqual(status, .pending)
        }
    }

    // MARK: - override

    func testOverrideStatus() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        // 直接覆盖为 completed（绕过迁移校验）
        await sm.override(nodeID: id, status: .completed)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .completed, "override 应直接设置状态")
    }

    // MARK: - 终止状态判断

    func testIsAllTerminalEmpty() async {
        let sm = NodeStateMachine()
        let result = await sm.isAllTerminal()
        XCTAssertFalse(result, "空状态机不应视为全部终止")
    }

    func testIsAllTerminalAllCompleted() async throws {
        let ids = [UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        try await sm.markRunning(ids[0])
        try await sm.markCompleted(ids[0])
        try await sm.markRunning(ids[1])
        try await sm.markCompleted(ids[1])
        let result = await sm.isAllTerminal()
        XCTAssertTrue(result)
    }

    func testIsAllTerminalMixed() async throws {
        let ids = [UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        try await sm.markRunning(ids[0])
        try await sm.markCompleted(ids[0])
        // ids[1] 仍为 pending
        let result = await sm.isAllTerminal()
        XCTAssertFalse(result)
    }

    // MARK: - 计数

    func testCompletedCount() async throws {
        let ids = [UUID(), UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        try await sm.markRunning(ids[0])
        try await sm.markCompleted(ids[0])
        try await sm.markSkipped(ids[1])
        // ids[2] 仍为 pending
        let completed = await sm.completedCount
        XCTAssertEqual(completed, 2, "completed + skipped 应计为 2")
    }

    func testTotalCount() async {
        let ids = [UUID(), UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        let total = await sm.totalCount
        XCTAssertEqual(total, 3)
    }

    // MARK: - snapshot

    func testSnapshot() async throws {
        let ids = [UUID(), UUID()]
        let sm = NodeStateMachine(nodeIDs: ids)
        try await sm.markRunning(ids[0])
        try await sm.markCompleted(ids[0])
        let snapshot = await sm.snapshot()
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[ids[0]], .completed)
        XCTAssertEqual(snapshot[ids[1]], .pending)
    }
}
