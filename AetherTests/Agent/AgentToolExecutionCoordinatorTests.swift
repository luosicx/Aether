import XCTest
@testable import Aether

/// Task 20 阶段 2: AgentToolExecutionCoordinator 单元测试。
///
/// 覆盖：
/// - actor 初始状态（executionCount=0, currentToolName=nil, isIdle=true）
/// - 成功调用：executionCount 自增、history 记录
/// - 失败调用：抛错时 executionCount 仍自增、history 经 recordFailure 记录
/// - 历史记录环形缓冲（100 条上限）
/// - reset() 清空状态
/// - ToolExecutionRecord 字段（toolName/startedAt/finishedAt/success/error/duration）
///
/// 命名说明：P2-6 Task 10 新增 `ToolExecutionCoordinator`（@MainActor final class）用于
/// ChatViewModel ReAct 工具执行循环；本测试类对应 actor 版本，重命名为
/// `AgentToolExecutionCoordinatorTests` 以匹配被测类 `AgentToolExecutionCoordinator`。
@MainActor
final class AgentToolExecutionCoordinatorTests: XCTestCase {

    /// 共享实例在跨测试间累积状态，使用独立实例避免互相干扰
    private var coordinator: AgentToolExecutionCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        coordinator = AgentToolExecutionCoordinator()
    }

    override func tearDown() async throws {
        coordinator = nil
        try await super.tearDown()
    }

    // MARK: - 初始状态

    /// 新实例 executionCount 应为 0
    func testInitialExecutionCount() async {
        let count = await coordinator.executionCount
        XCTAssertEqual(count, 0, "新实例 executionCount 应为 0")
    }

    /// 新实例 currentToolName 应为 nil
    func testInitialCurrentToolName() async {
        let name = await coordinator.currentToolName
        XCTAssertNil(name, "新实例 currentToolName 应为 nil")
    }

    /// 新实例应空闲
    func testInitiallyIdle() async {
        let idle = await coordinator.isIdle
        XCTAssertTrue(idle, "新实例应处于空闲状态")
    }

    /// 新实例历史应为空
    func testInitialHistoryEmpty() async {
        let history = await coordinator.historyRecords()
        XCTAssertTrue(history.isEmpty, "新实例历史应为空")
    }

    // MARK: - 成功调用

    /// 成功调用 calculate 工具应返回结果并增加计数
    func testSuccessfulExecutionIncrementsCount() async throws {
        let result = try await coordinator.execute(
            name: "calculate",
            arguments: ["expression": "1 + 2"]
        )
        XCTAssertEqual(result, "3", "calculate 1+2 应返回 3")
        let count = await coordinator.executionCount
        XCTAssertEqual(count, 1, "成功调用后 executionCount 应为 1")
    }

    /// 成功调用后历史应有一条记录
    func testSuccessfulExecutionRecordsHistory() async throws {
        _ = try await coordinator.execute(name: "calculate", arguments: ["expression": "2 * 3"])
        let history = await coordinator.historyRecords()
        XCTAssertEqual(history.count, 1, "历史应记录 1 条")
        let record = try XCTUnwrap(history.first)
        XCTAssertEqual(record.toolName, "calculate")
        XCTAssertTrue(record.success, "成功调用记录的 success 应为 true")
        XCTAssertNil(record.error, "成功调用记录的 error 应为 nil")
        XCTAssertGreaterThanOrEqual(record.finishedAt, record.startedAt)
        XCTAssertGreaterThanOrEqual(record.duration, 0)
    }

    /// 多次调用应累积历史
    func testMultipleExecutionsAccumulateHistory() async throws {
        for i in 1...3 {
            _ = try await coordinator.execute(name: "calculate", arguments: ["expression": "\(i) + 0"])
        }
        let count = await coordinator.executionCount
        XCTAssertEqual(count, 3)
        let history = await coordinator.historyRecords()
        XCTAssertEqual(history.count, 3)
    }

    // MARK: - 失败调用

    /// 未注册工具应抛错，但 executionCount 仍自增
    func testUnregisteredToolThrowsButIncrementsCount() async {
        do {
            _ = try await coordinator.execute(name: "nonexistent_tool_xyz", arguments: [:])
            XCTFail("未注册工具应抛错")
        } catch {
            // 预期抛错
        }
        let count = await coordinator.executionCount
        XCTAssertEqual(count, 1, "即使失败 executionCount 也应自增（execute 入口已计数）")
    }

    /// 未注册工具抛错时，execute 内部不会调用 appendHistory（因为 throws 提前返回）
    /// 但通过 recordFailure 可手动记录失败
    func testRecordFailureAddsHistoryEntry() async throws {
        let startedAt = Date()
        struct TestError: Error {}
        await coordinator.recordFailure(toolName: "failing_tool", startedAt: startedAt, error: TestError())
        let history = await coordinator.historyRecords()
        XCTAssertEqual(history.count, 1, "recordFailure 应添加 1 条历史")
        let record = try XCTUnwrap(history.first)
        XCTAssertEqual(record.toolName, "failing_tool")
        XCTAssertFalse(record.success)
        XCTAssertNotNil(record.error)
    }

    // MARK: - 环形缓冲

    /// 历史超过 100 条应保留最新 100 条
    func testHistoryBufferLimit100() async throws {
        // 添加 105 条历史记录
        for i in 0..<105 {
            let startedAt = Date()
            struct TestError: Error {}
            await coordinator.recordFailure(toolName: "tool_\(i)", startedAt: startedAt, error: TestError())
        }
        let history = await coordinator.historyRecords()
        XCTAssertEqual(history.count, 100, "历史应限制在 100 条")
        // 应保留最后 100 条（tool_5 ~ tool_104）
        XCTAssertEqual(history.first?.toolName, "tool_5")
        XCTAssertEqual(history.last?.toolName, "tool_104")
    }

    // MARK: - reset

    /// reset 应清空所有状态
    func testResetClearsState() async throws {
        _ = try await coordinator.execute(name: "calculate", arguments: ["expression": "1 + 1"])
        let countBefore = await coordinator.executionCount
        XCTAssertEqual(countBefore, 1)
        let historyBefore = await coordinator.historyRecords()
        XCTAssertFalse(historyBefore.isEmpty)

        await coordinator.reset()

        let countAfter = await coordinator.executionCount
        XCTAssertEqual(countAfter, 0, "reset 后 executionCount 应为 0")
        let historyAfter = await coordinator.historyRecords()
        XCTAssertTrue(historyAfter.isEmpty, "reset 后历史应清空")
        let idle = await coordinator.isIdle
        XCTAssertTrue(idle, "reset 后应处于空闲状态")
    }

    // MARK: - ToolExecutionRecord

    /// ToolExecutionRecord.duration 应为 finishedAt - startedAt
    func testRecordDurationCalculation() {
        let start = Date()
        let end = start.addingTimeInterval(1.5)
        let record = ToolExecutionRecord(
            toolName: "test",
            startedAt: start,
            finishedAt: end,
            success: true,
            error: nil
        )
        XCTAssertEqual(record.duration, 1.5, accuracy: 0.001, "duration 应等于 finishedAt - startedAt")
    }

    /// ToolExecutionRecord 应支持 Codable
    func testRecordCodable() throws {
        let record = ToolExecutionRecord(
            toolName: "calculate",
            startedAt: Date(timeIntervalSince1970: 1000),
            finishedAt: Date(timeIntervalSince1970: 1001.5),
            success: false,
            error: "执行失败"
        )
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ToolExecutionRecord.self, from: encoded)
        XCTAssertEqual(decoded.toolName, "calculate")
        XCTAssertEqual(decoded.success, false)
        XCTAssertEqual(decoded.error, "执行失败")
        XCTAssertEqual(decoded.duration, 1.5, accuracy: 0.001)
    }

    // MARK: - 串行化语义

    /// 连续多次调用应按顺序串行执行（actor 隔离保证）
    func testSerialExecutionOrder() async throws {
        // 使用 calculate 工具连续调用，验证结果按顺序返回
        var results: [String] = []
        for i in 1...5 {
            let result = try await coordinator.execute(name: "calculate", arguments: ["expression": "\(i) + 10"])
            results.append(result)
        }
        XCTAssertEqual(results, ["11", "12", "13", "14", "15"], "串行调用应返回正确顺序的结果")
        let count = await coordinator.executionCount
        XCTAssertEqual(count, 5)
    }
}
