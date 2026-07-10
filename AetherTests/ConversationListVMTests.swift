import XCTest
import SwiftData
@testable import Aether

/// ConversationListVM 单元测试
@MainActor
final class ConversationListVMTests: XCTestCase {
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
        vm.load(modelContext: context)  // 必须先 load 才会初始化 storage
    }

    override func tearDownWithError() throws {
        vm = nil
        context = nil
        container = nil
    }

    /// createConversation 默认标题应为「新对话」
    func testLoadAndCreateConversation() {
        let conv = vm.createConversation()
        XCTAssertEqual(conv?.title, "新对话", "createConversation 默认标题应为「新对话」")
        XCTAssertEqual(vm.conversations.count, 1, "vm.conversations 应包含新建会话")
        XCTAssertEqual(vm.conversations.first?.title, "新对话")
    }

    /// 创建 2 条会话，togglePin 第二条后排序变化（置顶在前）
    func testTogglePinChangesSortOrder() {
        // A：createdAt 旧；B：createdAt 新
        let a = vm.createConversation(title: "A")!
        a.createdAt = Date(timeIntervalSince1970: 1000)
        let b = vm.createConversation(title: "B")!
        b.createdAt = Date(timeIntervalSince1970: 2000)

        // 重新 load 让排序按 createdAt 降序生效
        // 跳过 cleanup，避免测试中无消息的会话被清理导致断言失败
        vm.load(modelContext: context, cleanupEmpty: false)
        XCTAssertEqual(vm.conversations.map(\.title), ["B", "A"],
                       "初始应按 createdAt 降序：B 在前")

        // 置顶 A（旧的那条）后，A 应排到前面
        vm.togglePin(a)
        XCTAssertEqual(vm.conversations.map(\.title), ["A", "B"],
                       "置顶 A 后 A 应排到前面")
        XCTAssertTrue(vm.conversations.first?.isPinned ?? false,
                      "置顶后 isPinned 应为 true")
    }

    /// 首条用户消息长度 30 → 标题 prefix(20) + 「…」
    func testAutoTitleIfNeededLongTitle() {
        let conv = vm.createConversation()!
        let longContent = String(repeating: "a", count: 30)
        let msg = ChatMessage(role: "user", content: longContent)
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        let expectedPrefix = String(repeating: "a", count: 20)
        XCTAssertEqual(conv.title, expectedPrefix + "…",
                       "长度 30 应截断为 prefix(20) + 「…」")
    }

    /// 首条用户消息长度 15 → 标题不加「…」
    func testAutoTitleIfNeededShortTitle() {
        let conv = vm.createConversation()!
        let shortContent = String(repeating: "b", count: 15)
        let msg = ChatMessage(role: "user", content: shortContent)
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, String(repeating: "b", count: 15),
                       "长度 15 等于 prefix(20) 的实际长度，不应加「…」")
    }

    /// 标题已是「新对话」之外时不应被覆盖
    func testAutoTitleIfNeededDoesNotOverwriteExistingTitle() {
        let conv = vm.createConversation(title: "已有标题")!
        let msg = ChatMessage(role: "user", content: "some content that should not become title")
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, "已有标题",
                       "标题非「新对话」时 autoTitleIfNeeded 不应覆盖")
    }
}
