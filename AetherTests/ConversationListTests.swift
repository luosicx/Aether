import XCTest
import SwiftUI
import SwiftData
@testable import Aether

/// ConversationList 单元测试
///
/// 注意：`filteredConversations` / `allFilteredSelected` 均为 private 计算属性，
/// `searchText` / `selectedConversations` 为 @State private，无法从外部设置或读取。
/// 在不修改实现代码的前提下，搜索过滤逻辑与批量选择逻辑无法直接单元测试。
/// 本测试验证 View 可正常构造，以及 VM 数据源可被正确访问。
@MainActor
final class ConversationListTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var vm: ConversationListVM!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
        vm = ConversationListVM()
        vm.load(modelContext: context)
    }

    override func tearDownWithError() throws {
        vm = nil
        context = nil
        container = nil
    }

    // MARK: - View 构造

    /// 空会话列表时 View 可正常构造
    func testViewInitWithEmptyConversations() {
        let view = ConversationList(
            conversationListVM: vm,
            onSelect: { _ in },
            onCreate: {}
        )
        XCTAssertTrue(view.conversationListVM.conversations.isEmpty,
                      "空 VM 构造的 View 应无会话")
    }

    /// 有会话时 View 可正常构造并访问 VM 数据
    func testViewInitWithConversations() {
        vm.createConversation(title: "测试会话A")
        vm.createConversation(title: "测试会话B")

        let view = ConversationList(
            conversationListVM: vm,
            onSelect: { _ in },
            onCreate: {}
        )
        XCTAssertEqual(view.conversationListVM.conversations.count, 2,
                       "View 应能通过 conversationListVM 访问会话列表")
    }

    /// onSelect / onCreate 回调可正常传入
    func testViewCallbacksCanBeAssigned() {
        var selectedConv: Conversation?
        var created = false

        vm.createConversation(title: "可选中会话")

        let view = ConversationList(
            conversationListVM: vm,
            onSelect: { conv in selectedConv = conv },
            onCreate: { created = true }
        )
        // 验证 View 持有正确的 VM 引用
        XCTAssertFalse(view.conversationListVM.conversations.isEmpty)
        // 回调尚未执行（需 UI 渲染才会触发）
        XCTAssertNil(selectedConv)
        XCTAssertFalse(created)
    }

    // MARK: - VM 数据源（filteredConversations 的底层依赖）

    /// VM 的 conversations 列表标题可被正确读取，为搜索过滤提供数据基础
    func testVMConversationTitlesAccessible() {
        vm.createConversation(title: "Hello World")
        vm.createConversation(title: "SwiftUI")
        vm.createConversation(title: "hello SWIFT")

        let titles = vm.conversations.map(\.title)
        XCTAssertEqual(titles.count, 3)
        XCTAssertTrue(titles.contains("Hello World"))
        XCTAssertTrue(titles.contains("SwiftUI"))
        XCTAssertTrue(titles.contains("hello SWIFT"))
    }

    /// Conversation.title 的 lowercased + contains 行为符合搜索过滤算法预期
    /// （此处测试 String 过滤原语，而非 View 的 private filteredConversations 属性）
    /// 模拟 filteredConversations 的搜索过滤逻辑：空关键词走 guard 提前返回全部，
    /// 非空关键词使用 lowercased().contains() 进行不区分大小写匹配。
    func testConversationTitleFilteringPrimitives() {
        // 使用硬编码的标题数组，模拟 VM.conversations 中的标题列表
        let titles = ["Hello World", "SwiftUI Guide", "hello swift"]
        XCTAssertEqual(titles.count, 3)

        // 模拟 filteredConversations 的搜索过滤逻辑
        func filterTitles(_ keyword: String) -> [String] {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            // 空关键词走 guard 提前返回全部（与 filteredConversations 行为一致）
            guard !trimmed.isEmpty else {
                return titles
            }
            let lowercased = trimmed.lowercased()
            return titles.filter { $0.lowercased().contains(lowercased) }
        }

        // 空关键词 → 全部匹配（走 guard 提前返回）
        XCTAssertEqual(filterTitles("").count, 3, "空关键词应匹配全部")

        // 纯空格关键词 → trim 后为空 → 走 guard 提前返回全部
        XCTAssertEqual(filterTitles("   ").count, 3, "纯空格关键词应匹配全部")

        // 大小写混合关键词 → 不区分大小写匹配
        XCTAssertEqual(filterTitles("SWIFT").count, 2, "swift 应匹配 SwiftUI Guide 和 hello swift")

        // 小写关键词 → 不区分大小写匹配
        XCTAssertEqual(filterTitles("swift").count, 2, "小写 swift 应匹配 SwiftUI Guide 和 hello swift")

        // 部分匹配 → hello 应匹配 Hello World 和 hello swift
        XCTAssertEqual(filterTitles("hello").count, 2, "hello 应匹配 Hello World 和 hello swift")

        // 完整匹配 → 仅匹配一个
        XCTAssertEqual(filterTitles("guide").count, 1, "guide 应仅匹配 SwiftUI Guide")

        // 特殊字符关键词 → 不匹配任何
        XCTAssertEqual(filterTitles("@#$").count, 0, "特殊字符应不匹配任何会话标题")
    }

    /// 置顶会话可通过 VM 的 togglePin 切换，为 allFilteredSelected 的批量选择提供数据基础
    func testVMCanTogglePinForBatchSelection() {
        let conv = vm.createConversation(title: "会话1")!
        XCTAssertFalse(conv.isPinned, "新建会话默认未置顶")
        vm.togglePin(conv)
        XCTAssertTrue(conv.isPinned, "togglePin 后应置顶")
    }
}
