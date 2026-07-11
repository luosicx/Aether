import XCTest
@testable import Aether

/// StepCardView 单元测试：覆盖 ToolStepSnapshot 值类型与内嵌 Status 枚举。
/// ToolStepSnapshot 用于切断对 @Observable ViewModel 的观察链，其 Equatable
/// 一致性是 ReAct 步骤 diffing 的关键契约，故逐字段验证相等性。
/// 注：StepCardView 的 statusText/statusIcon/statusColor 为 private，不在此测试范围。
final class StepCardViewTests: XCTestCase {

    // MARK: - Status 枚举

    /// 验证 Status 拥有 running / completed / failed 三个 case。
    func testStatusCasesExist() {
        let statuses: [ToolStepSnapshot.Status] = [.running, .completed, .failed]
        XCTAssertEqual(statuses.count, 3, "Status 应有 3 个 case")
    }

    /// 验证 Status 可比较：相同 case 相等、不同 case 不等。
    func testStatusEquatable() {
        XCTAssertEqual(ToolStepSnapshot.Status.running, .running)
        XCTAssertEqual(ToolStepSnapshot.Status.completed, .completed)
        XCTAssertEqual(ToolStepSnapshot.Status.failed, .failed)
        XCTAssertNotEqual(ToolStepSnapshot.Status.running, .completed)
        XCTAssertNotEqual(ToolStepSnapshot.Status.completed, .failed)
        XCTAssertNotEqual(ToolStepSnapshot.Status.running, .failed)
    }

    // MARK: - ToolStepSnapshot: Identifiable

    /// 验证 id 可访问且为 UUID（Identifiable 一致性）。
    func testSnapshotIdIsAccessible() {
        let snapshot = makeSnapshot()
        // id 类型为 UUID（Identifiable 契约，编译期保证），验证可正常读取且稳定
        let idValue: UUID = snapshot.id
        XCTAssertEqual(idValue, snapshot.id)
    }

    // MARK: - ToolStepSnapshot: Equatable（全字段参与）

    /// 验证所有字段相同时两个 snapshot 相等。
    func testEqualWhenAllFieldsSame() {
        let id = UUID()
        let a = makeSnapshot(id: id)
        let b = makeSnapshot(id: id)
        XCTAssertEqual(a, b, "所有字段相同时应相等")
    }

    /// 验证仅 id 不同时不相等。
    func testNotEqualWhenIdDiffers() {
        let a = makeSnapshot(id: UUID())
        let b = makeSnapshot(id: UUID())
        XCTAssertNotEqual(a, b, "id 不同时应不等")
    }

    /// 验证仅 toolName 不同时不相等。
    func testNotEqualWhenToolNameDiffers() {
        let id = UUID()
        let a = makeSnapshot(id: id, toolName: "weather")
        let b = makeSnapshot(id: id, toolName: "calculator")
        XCTAssertNotEqual(a, b)
    }

    /// 验证仅 status 不同时不相等。
    func testNotEqualWhenStatusDiffers() {
        let id = UUID()
        let a = makeSnapshot(id: id, status: .running)
        let b = makeSnapshot(id: id, status: .completed)
        XCTAssertNotEqual(a, b)
    }

    /// 验证仅 arguments 不同时不相等。
    func testNotEqualWhenArgumentsDiffers() {
        let id = UUID()
        let a = makeSnapshot(id: id, arguments: "{\"x\":1}")
        let b = makeSnapshot(id: id, arguments: "{\"x\":2}")
        XCTAssertNotEqual(a, b)
    }

    /// 验证仅 loopIndex 不同时不相等。
    func testNotEqualWhenLoopIndexDiffers() {
        let id = UUID()
        let a = makeSnapshot(id: id, loopIndex: 1)
        let b = makeSnapshot(id: id, loopIndex: 2)
        XCTAssertNotEqual(a, b)
    }

    /// 验证仅 result 不同时不相等。
    func testNotEqualWhenResultDiffers() {
        let id = UUID()
        let a = makeSnapshot(id: id, result: "晴")
        let b = makeSnapshot(id: id, result: "雨")
        XCTAssertNotEqual(a, b)
    }

    /// 验证仅 thought 不同时不相等。
    func testNotEqualWhenThoughtDiffers() {
        let id = UUID()
        let a = makeSnapshot(id: id, thought: "需要查天气")
        let b = makeSnapshot(id: id, thought: "需要查日历")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ToolStepSnapshot: 可选值处理

    /// 验证 result 与 thought 为 nil 时仍可正常构造与比较。
    func testHandlesNilOptionals() {
        let id = UUID()
        let a = makeSnapshot(id: id, result: nil, thought: nil)
        let b = makeSnapshot(id: id, result: nil, thought: nil)
        XCTAssertEqual(a, b)
        XCTAssertNil(a.result)
        XCTAssertNil(a.thought)
    }

    /// 验证 nil 与非 nil 可选值导致不等。
    func testNilVsNonNilOptionalNotEqual() {
        let id = UUID()
        let a = makeSnapshot(id: id, result: nil)
        let b = makeSnapshot(id: id, result: "有结果")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ToolStepSnapshot: 字段存储

    /// 验证构造后各字段正确读取。
    func testStoresAllFields() {
        let id = UUID()
        let snapshot = ToolStepSnapshot(
            id: id,
            toolName: "reminder",
            status: .completed,
            result: "已设置",
            thought: "用户要求提醒",
            arguments: "{\"time\":\"09:00\"}",
            loopIndex: 3
        )
        XCTAssertEqual(snapshot.id, id)
        XCTAssertEqual(snapshot.toolName, "reminder")
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertEqual(snapshot.result, "已设置")
        XCTAssertEqual(snapshot.thought, "用户要求提醒")
        XCTAssertEqual(snapshot.arguments, "{\"time\":\"09:00\"}")
        XCTAssertEqual(snapshot.loopIndex, 3)
    }

    // MARK: - 辅助

    /// 构造默认 snapshot，允许覆盖任意字段以便复用。
    private func makeSnapshot(
        id: UUID = UUID(),
        toolName: String = "weather",
        status: ToolStepSnapshot.Status = .running,
        result: String? = nil,
        thought: String? = nil,
        arguments: String = "{}",
        loopIndex: Int = 1
    ) -> ToolStepSnapshot {
        ToolStepSnapshot(
            id: id,
            toolName: toolName,
            status: status,
            result: result,
            thought: thought,
            arguments: arguments,
            loopIndex: loopIndex
        )
    }
}
