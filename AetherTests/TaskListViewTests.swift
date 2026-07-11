import XCTest
@testable import Aether

/// TaskListView 单元测试：覆盖 TaskListItem 值类型。
/// TaskListView 本体仅为 Markdown 任务列表的纯渲染视图，无 internal 逻辑；
/// TaskListItem 的 id 唯一性是 ForEach 渲染正确性的关键契约，故验证其行为。
final class TaskListViewTests: XCTestCase {

    // MARK: - TaskListItem: Identifiable

    /// 验证每个 TaskListItem 实例拥有独立 id（ForEach 依赖此唯一性）。
    func testEachItemHasUniqueId() {
        let a = TaskListItem(isCompleted: false, text: "买菜")
        let b = TaskListItem(isCompleted: false, text: "买菜")
        XCTAssertNotEqual(a.id, b.id, "两个 TaskListItem 实例 id 应不同")
        // id 为 UUID 类型（Identifiable 契约，编译期保证）
        let _: UUID = a.id
    }

    /// 验证批量创建的 item id 互不相同。
    func testBatchItemsHaveUniqueIds() {
        let items = (0..<10).map { i in
            TaskListItem(isCompleted: i % 2 == 0, text: "任务\(i)")
        }
        let ids = items.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "10 个 item 的 id 应互不相同")
    }

    // MARK: - TaskListItem: 字段存储

    /// 验证 isCompleted 与 text 正确存储。
    func testStoresFields() {
        let item = TaskListItem(isCompleted: true, text: "完成报告")
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.text, "完成报告")
    }

    /// 验证 isCompleted=false 时也正确存储。
    func testStoresUncompletedState() {
        let item = TaskListItem(isCompleted: false, text: "待办")
        XCTAssertFalse(item.isCompleted)
        XCTAssertEqual(item.text, "待办")
    }

    /// 验证空文本也可存储（边界值）。
    func testStoresEmptyText() {
        let item = TaskListItem(isCompleted: false, text: "")
        XCTAssertEqual(item.text, "")
    }
}
