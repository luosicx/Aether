import XCTest
import SwiftData
@testable import AIBuilder

/// ChatStorage 单元测试：使用 in-memory ModelContainer
@MainActor
final class ChatStorageTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var storage: ChatStorage!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self,
            configurations: config
        )
        context = ModelContext(container)
        storage = ChatStorage(modelContext: context)
    }

    override func tearDownWithError() throws {
        storage = nil
        context = nil
        container = nil
    }

    func testCreateConversationAndFetch() {
        _ = storage.createConversation(title: "测试会话")
        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.count, 1, "创建 1 条会话后应能 fetch 到 1 条")
        XCTAssertEqual(convs.first?.title, "测试会话")
    }

    func testFetchConversationsMixedSort() {
        // A：置顶 + createdAt 旧；B：未置顶 + createdAt 新；C：未置顶 + createdAt 旧
        let oldDate = Date(timeIntervalSince1970: 1000)
        let newDate = Date(timeIntervalSince1970: 2000)

        let a = storage.createConversation(title: "A")
        a.createdAt = oldDate
        storage.togglePin(a)  // 置顶 A

        let b = storage.createConversation(title: "B")
        b.createdAt = newDate

        let c = storage.createConversation(title: "C")
        c.createdAt = oldDate

        // 期望排序：A（置顶在前）→ B（未置顶 + createdAt 新）→ C（未置顶 + createdAt 旧）
        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.map(\.title), ["A", "B", "C"], "应按 isPinned 降序 + createdAt 降序混合排序")
    }

    func testRenameConversation() {
        let conv = storage.createConversation(title: "原标题")
        storage.renameConversation(conv, to: "新标题")
        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.first?.title, "新标题", "renameConversation 后标题应更新")
    }

    func testTogglePinChangesSort() {
        let a = storage.createConversation(title: "A")
        a.createdAt = Date(timeIntervalSince1970: 1000)
        let b = storage.createConversation(title: "B")
        b.createdAt = Date(timeIntervalSince1970: 2000)

        // 初始：B（createdAt 新）在前
        XCTAssertEqual(storage.fetchConversations().map(\.title), ["B", "A"], "初始应按 createdAt 降序")

        // togglePin A 后：A 应排到前面
        storage.togglePin(a)
        XCTAssertEqual(storage.fetchConversations().map(\.title), ["A", "B"], "置顶后会话应排到前面")
    }

    func testDeleteConversation() {
        let a = storage.createConversation(title: "A")
        a.createdAt = Date(timeIntervalSince1970: 1000)
        let b = storage.createConversation(title: "B")
        b.createdAt = Date(timeIntervalSince1970: 2000)

        XCTAssertEqual(storage.fetchConversations().count, 2)
        storage.deleteConversation(a)
        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.count, 1, "删除后列表应收缩到 1 条")
        XCTAssertEqual(convs.first?.title, "B")
    }

    func testAddMessageToConversation() {
        let conv = storage.createConversation(title: "测试")
        let msg = storage.addMessage(to: conv, role: "user", content: "你好")
        XCTAssertEqual(conv.messages.count, 1, "addMessage 后 conversation.messages 应含 1 条")
        XCTAssertEqual(conv.messages.first?.content, "你好")
        XCTAssertEqual(msg.conversation, conv, "消息应反向关联到 conversation")
    }

    func testFetchPreferenceCreatesDefaultIfMissing() {
        // 初始无记录时 fetchPreference 应创建默认 UserPreference 并保存
        let pref1 = storage.fetchPreference()
        XCTAssertEqual(pref1.preferredTone, "默认")
        XCTAssertEqual(pref1.preferredTools, [])
        XCTAssertEqual(pref1.customFact, "")

        // 再次 fetchPreference 应返回同一条记录（不应再创建）
        let pref2 = storage.fetchPreference()
        XCTAssertEqual(pref1.persistentModelID, pref2.persistentModelID, "再次 fetch 应返回同一条记录")
    }

    func testSavePreferencePersists() {
        storage.savePreference(tone: "正式", tools: ["calculate"], fact: "用户喜欢简洁回答")
        let pref = storage.fetchPreference()
        XCTAssertEqual(pref.preferredTone, "正式")
        XCTAssertEqual(pref.preferredTools, ["calculate"])
        XCTAssertEqual(pref.customFact, "用户喜欢简洁回答")
    }
}
