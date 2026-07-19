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
        XCTAssertEqual(status, .inProgress, "重复注册不应重置状态")
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

        let running = await sm.nodeIDs(in: .inProgress)
        XCTAssertEqual(running, [ids[1]])
    }

    // MARK: - 合法状态迁移

    func testLegalTransitionPendingToRunning() async throws {
        let sm = NodeStateMachine(nodeIDs: [UUID()])
        let id = UUID()
        await sm.register(nodeID: id)
        try await sm.markRunning(id)
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .inProgress)
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
        XCTAssertEqual(status, .inProgress)
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

    func testNodeNotFound() async throws {
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
        } catch {
            XCTFail("应为 nodeNotFound，实际: \(error)")
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

    // MARK: - 非法状态迁移（补充覆盖）

    /// running → skipped 应为非法迁移（仅 pending/failed 可跳过）。
    func testIllegalTransitionInProgressToSkipped() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markRunning(id)
        do {
            try await sm.markSkipped(id)
            XCTFail("running → skipped 应为非法迁移")
        } catch let error as NodeStateMachine.StateMachineError {
            if case .illegalTransition(let from, let to, _) = error {
                XCTAssertEqual(from, .inProgress, "源状态应为 inProgress")
                XCTAssertEqual(to, .skipped, "目标状态应为 skipped")
            } else {
                XCTFail("应为 illegalTransition，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 StateMachineError，实际：\(error)")
        }
        // 状态应保持 inProgress（迁移失败不修改状态）
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .inProgress, "非法迁移不应改变状态")
    }

    /// skipped → completed 应为非法迁移（skipped 为终止状态，仅可 reset）。
    func testIllegalTransitionSkippedToCompleted() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        try await sm.markSkipped(id)
        do {
            try await sm.markCompleted(id)
            XCTFail("skipped → completed 应为非法迁移")
        } catch let error as NodeStateMachine.StateMachineError {
            if case .illegalTransition(let from, let to, _) = error {
                XCTAssertEqual(from, .skipped, "源状态应为 skipped")
                XCTAssertEqual(to, .completed, "目标状态应为 completed")
            } else {
                XCTFail("应为 illegalTransition，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 StateMachineError，实际：\(error)")
        }
        // 状态应保持 skipped
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .skipped, "非法迁移不应改变状态")
    }

    /// pending → failed 应为非法迁移（必须先 running 才能 failed）。
    func testIllegalTransitionPendingToFailed() async throws {
        let id = UUID()
        let sm = NodeStateMachine(nodeIDs: [id])
        do {
            try await sm.markFailed(id)
            XCTFail("pending → failed 应为非法迁移（未经过 running）")
        } catch let error as NodeStateMachine.StateMachineError {
            if case .illegalTransition(let from, let to, _) = error {
                XCTAssertEqual(from, .pending, "源状态应为 pending")
                XCTAssertEqual(to, .failed, "目标状态应为 failed")
            } else {
                XCTFail("应为 illegalTransition，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 StateMachineError，实际：\(error)")
        }
        // 状态应保持 pending
        let status = await sm.status(of: id)
        XCTAssertEqual(status, .pending, "非法迁移不应改变状态")
    }

    // MARK: - 批量注册混合场景

    /// 批量注册时已存在的节点状态不应被重置，新节点应注册为 pending。
    func testRegisterBatchWithMixedExistingAndNew() async throws {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let sm = NodeStateMachine(nodeIDs: [id1])
        // 预先注册 id1 并标记为 running
        try await sm.markRunning(id1)

        // 批量注册 [id1, id2, id3]
        await sm.register(nodeIDs: [id1, id2, id3])

        // id1 状态不应被重置（仍为 inProgress）
        let status1 = await sm.status(of: id1)
        XCTAssertEqual(status1, .inProgress, "已存在的节点状态不应被批量注册重置")
        // id1 的尝试次数也不应被重置
        let count1 = await sm.attemptCount(of: id1)
        XCTAssertEqual(count1, 1, "已存在节点的尝试次数不应被批量注册重置")

        // id2、id3 应为 pending
        let status2 = await sm.status(of: id2)
        XCTAssertEqual(status2, .pending, "新节点应注册为 pending")
        let status3 = await sm.status(of: id3)
        XCTAssertEqual(status3, .pending, "新节点应注册为 pending")
        // 新节点尝试次数应为 0
        let count2 = await sm.attemptCount(of: id2)
        XCTAssertEqual(count2, 0, "新节点尝试次数应为 0")
        let count3 = await sm.attemptCount(of: id3)
        XCTAssertEqual(count3, 0, "新节点尝试次数应为 0")
    }
}
