import XCTest
import SwiftData
@testable import Aether

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
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self,
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

    // MARK: - createConversation 默认值

    /// createConversation 不传参时应使用默认 title "新对话" 与默认 systemPrompt
    func testCreateConversationDefaultTitleAndSystemPrompt() {
        let conv = storage.createConversation()
        XCTAssertEqual(conv.title, "新对话", "默认 title 应为「新对话」")
        XCTAssertEqual(conv.systemPrompt, "你是一个有帮助的AI助手。", "默认 systemPrompt 应为「你是一个有帮助的AI助手。」")
        XCTAssertEqual(conv.isPinned, false, "新建会话 isPinned 应为 false")
        XCTAssertEqual(conv.unreadCount, 0, "新建会话 unreadCount 应为 0")
        XCTAssertEqual(conv.messages.count, 0, "新建会话 messages 应为空")
    }

    /// createConversation 自定义 title 与 systemPrompt 应被采用
    func testCreateConversationCustomTitleAndSystemPrompt() {
        let conv = storage.createConversation(title: "自定义标题", systemPrompt: "你是翻译助手")
        XCTAssertEqual(conv.title, "自定义标题")
        XCTAssertEqual(conv.systemPrompt, "你是翻译助手")
    }

    // MARK: - fetchConversations 排序

    /// fetchConversations：两个置顶会话之间应按 createdAt 降序排列
    func testFetchConversationsPinnedSortedByCreatedAt() {
        let oldDate = Date(timeIntervalSince1970: 1000)
        let newDate = Date(timeIntervalSince1970: 2000)

        let a = storage.createConversation(title: "旧置顶")
        a.createdAt = oldDate
        storage.togglePin(a)

        let b = storage.createConversation(title: "新置顶")
        b.createdAt = newDate
        storage.togglePin(b)

        // 两个都置顶 → 按 createdAt 降序：新置顶在前
        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.map(\.title), ["新置顶", "旧置顶"],
                       "两个置顶会话应按 createdAt 降序排列")
    }

    /// fetchConversations：无置顶时纯按 createdAt 降序
    func testFetchConversationsNoPinnedSortByCreatedAt() {
        let oldDate = Date(timeIntervalSince1970: 1000)
        let midDate = Date(timeIntervalSince1970: 1500)
        let newDate = Date(timeIntervalSince1970: 2000)

        let a = storage.createConversation(title: "旧")
        a.createdAt = oldDate
        let b = storage.createConversation(title: "中")
        b.createdAt = midDate
        let c = storage.createConversation(title: "新")
        c.createdAt = newDate

        XCTAssertEqual(storage.fetchConversations().map(\.title), ["新", "中", "旧"],
                       "无置顶时应纯按 createdAt 降序")
    }

    /// fetchConversations 空仓库应返回空数组
    func testFetchConversationsEmptyReturnsEmptyArray() {
        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.count, 0, "空仓库应返回空数组")
    }

    // MARK: - deleteConversation 清理

    /// deleteConversation 应级联删除关联的消息
    func testDeleteConversationCascadesMessages() {
        let conv = storage.createConversation(title: "测试")
        _ = storage.addMessage(to: conv, role: "user", content: "消息1")
        _ = storage.addMessage(to: conv, role: "assistant", content: "回复1")
        XCTAssertEqual(conv.messages.count, 2)

        storage.deleteConversation(conv)

        // 验证 ChatMessage 也被清理
        let msgDescriptor = FetchDescriptor<ChatMessage>()
        let remainingMessages = (try? context.fetch(msgDescriptor)) ?? []
        XCTAssertEqual(remainingMessages.count, 0, "删除会话后关联消息应被级联删除")
    }

    // MARK: - cleanupEmptyConversations

    /// cleanupEmptyConversations 应删除无消息的空会话，保留有消息的会话
    func testCleanupEmptyConversationsRemovesEmptyOnly() {
        let empty1 = storage.createConversation(title: "空1")
        let empty2 = storage.createConversation(title: "空2")
        let nonEmpty = storage.createConversation(title: "非空")
        _ = storage.addMessage(to: nonEmpty, role: "user", content: "hello")

        XCTAssertEqual(storage.fetchConversations().count, 3, "清理前应有 3 条会话")

        storage.cleanupEmptyConversations()

        let convs = storage.fetchConversations()
        XCTAssertEqual(convs.count, 1, "清理后应只剩 1 条非空会话")
        XCTAssertEqual(convs.first?.title, "非空", "剩余的应为有消息的会话")
        // 空会话应被删除
        XCTAssertFalse(convs.contains(where: { $0.title == "空1" }))
        XCTAssertFalse(convs.contains(where: { $0.title == "空2" }))
        // 非空会话的消息应保留
        XCTAssertEqual(nonEmpty.messages.count, 1, "非空会话的消息应保留")
        _ = empty1  // 避免未使用变量警告
        _ = empty2
    }

    /// cleanupEmptyConversations 无数据时应幂等不报错
    func testCleanupEmptyConversationsIdempotentWhenEmpty() {
        storage.cleanupEmptyConversations()
        XCTAssertEqual(storage.fetchConversations().count, 0, "空仓库清理后仍应为空")
    }

    // MARK: - addMessage

    /// addMessage 带 imageData 应正确存储图片数据
    func testAddMessageWithImageData() {
        let conv = storage.createConversation(title: "图片测试")
        let imageData = "test-image".data(using: .utf8)!
        let msg = storage.addMessage(to: conv, role: "user", content: "看图", imageData: imageData)

        XCTAssertEqual(msg.imageData, imageData, "imageData 应被正确存储")
        XCTAssertEqual(conv.messages.first?.imageData, imageData, "会话消息应含 imageData")
    }

    // MARK: - wipeAllData

    /// wipeAllData 应清空所有 Conversation / ChatMessage / DocumentChunk / MessageFeedback
    func testWipeAllDataClearsEverything() {
        // 准备数据
        let conv = storage.createConversation(title: "会话")
        _ = storage.addMessage(to: conv, role: "user", content: "消息")
        let chunk = DocumentChunk(content: "分块", source: "test.pdf", chunkIndex: 0)
        context.insert(chunk)
        let feedback = MessageFeedback(messageId: UUID(), isPositive: true)
        context.insert(feedback)
        let insight = HealthInsight(insightType: "sleep", content: "洞察")
        context.insert(insight)
        _ = storage.fetchPreference()

        // 验证有数据
        XCTAssertEqual(storage.fetchConversations().count, 1)
        XCTAssertEqual((try? context.fetch(FetchDescriptor<ChatMessage>()))?.count ?? 0, 1)
        XCTAssertEqual((try? context.fetch(FetchDescriptor<DocumentChunk>()))?.count ?? 0, 1)
        XCTAssertEqual((try? context.fetch(FetchDescriptor<MessageFeedback>()))?.count ?? 0, 1)

        // 执行清空
        storage.wipeAllData()

        // 验证全部清空
        XCTAssertEqual(storage.fetchConversations().count, 0, "wipeAllData 后 Conversation 应为空")
        XCTAssertEqual((try? context.fetch(FetchDescriptor<ChatMessage>()))?.count ?? 0, 0, "wipeAllData 后 ChatMessage 应为空")
        XCTAssertEqual((try? context.fetch(FetchDescriptor<DocumentChunk>()))?.count ?? 0, 0, "wipeAllData 后 DocumentChunk 应为空")
        XCTAssertEqual((try? context.fetch(FetchDescriptor<MessageFeedback>()))?.count ?? 0, 0, "wipeAllData 后 MessageFeedback 应为空")
        XCTAssertEqual((try? context.fetch(FetchDescriptor<HealthInsight>()))?.count ?? 0, 0, "wipeAllData 后 HealthInsight 应为空")
        XCTAssertEqual((try? context.fetch(FetchDescriptor<UserPreference>()))?.count ?? 0, 0, "wipeAllData 后 UserPreference 应为空")
    }

    /// wipeAllData 幂等：空仓库调用不报错
    func testWipeAllDataIdempotentOnEmpty() {
        storage.wipeAllData()
        storage.wipeAllData()  // 再次调用不应崩溃
        XCTAssertEqual(storage.fetchConversations().count, 0)
    }

    // MARK: - saveFeedback / fetchFeedback / updateFeedback

    /// saveFeedback + fetchFeedback 往返
    func testSaveAndFetchFeedback() {
        let messageId = UUID()
        storage.saveFeedback(messageId: messageId, isPositive: true, citations: [])

        let fetched = storage.fetchFeedback(messageId: messageId)
        XCTAssertNotNil(fetched, "saveFeedback 后应能 fetch 到")
        XCTAssertTrue(fetched?.isPositive == true, "fetch 到的 isPositive 应为 true")
    }

    /// fetchFeedback 未保存的 messageId 应返回 nil
    func testFetchFeedbackNotFoundReturnsNil() {
        let result = storage.fetchFeedback(messageId: UUID())
        XCTAssertNil(result, "未保存的 messageId 应返回 nil")
    }

    /// saveFeedback isPositive=false 时对 citations chunk 权重 *= 0.8
    func testSaveFeedbackNegativeReducesChunkWeight() {
        let chunk = DocumentChunk(content: "分块", source: "test.pdf", chunkIndex: 0)
        chunk.weight = 1.0
        context.insert(chunk)

        storage.saveFeedback(messageId: UUID(), isPositive: false, citations: [chunk])

        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.001, "踩后 chunk.weight 应 *= 0.8 → 0.8")
    }

    /// saveFeedback isPositive=true 时对 citations chunk 权重 /= 0.8，上限 1.0
    func testSaveFeedbackPositiveIncreasesChunkWeightCappedAt1() {
        let chunk = DocumentChunk(content: "分块", source: "test.pdf", chunkIndex: 0)
        chunk.weight = 0.5
        context.insert(chunk)

        storage.saveFeedback(messageId: UUID(), isPositive: true, citations: [chunk])

        // 0.5 / 0.8 = 0.625，未超过 1.0
        XCTAssertEqual(chunk.weight, 0.625, accuracy: 0.001, "赞后 chunk.weight 应 /= 0.8 → 0.625")
    }

    /// saveFeedback isPositive=true 时权重不超过 1.0 上限
    func testSaveFeedbackPositiveWeightCappedAtOne() {
        let chunk = DocumentChunk(content: "分块", source: "test.pdf", chunkIndex: 0)
        chunk.weight = 0.9
        context.insert(chunk)

        storage.saveFeedback(messageId: UUID(), isPositive: true, citations: [chunk])

        // 0.9 / 0.8 = 1.125 → 应被 min(1.0) 限制
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.001, "赞后 chunk.weight 不应超过 1.0")
    }

    /// updateFeedback 切换赞/踩应调整权重
    func testUpdateFeedbackTogglesChunkWeight() {
        let chunk = DocumentChunk(content: "分块", source: "test.pdf", chunkIndex: 0)
        chunk.weight = 1.0
        context.insert(chunk)

        // 先踩：1.0 * 0.8 = 0.8
        storage.saveFeedback(messageId: UUID(), isPositive: false, citations: [chunk])
        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.001)

        // 找到 feedback 记录后切换为赞：0.8 / 0.8 = 1.0
        let feedbacks = (try? context.fetch(FetchDescriptor<MessageFeedback>())) ?? []
        guard let feedback = feedbacks.first else {
            XCTFail("应能 fetch 到 feedback 记录")
            return
        }
        storage.updateFeedback(feedback, isPositive: true, citations: [chunk])
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.001, "切换为赞后权重应恢复到 1.0")
    }

    /// updateFeedback 状态不变时不调整权重
    func testUpdateFeedbackNoChangeNoWeightAdjust() {
        let chunk = DocumentChunk(content: "分块", source: "test.pdf", chunkIndex: 0)
        chunk.weight = 0.8
        context.insert(chunk)

        storage.saveFeedback(messageId: UUID(), isPositive: false, citations: [chunk])
        let weightBefore = chunk.weight

        let feedbacks = (try? context.fetch(FetchDescriptor<MessageFeedback>())) ?? []
        guard let feedback = feedbacks.first else {
            XCTFail("应能 fetch 到 feedback 记录")
            return
        }
        // 再次设为踩（状态不变）
        storage.updateFeedback(feedback, isPositive: false, citations: [chunk])
        XCTAssertEqual(chunk.weight, weightBefore, "状态不变时权重不应调整")
    }

    // MARK: - renameConversation

    /// renameConversation 改为空字符串应也能保存
    func testRenameConversationToEmpty() {
        let conv = storage.createConversation(title: "原标题")
        storage.renameConversation(conv, to: "")
        XCTAssertEqual(storage.fetchConversations().first?.title, "", "改名为空字符串应被保存")
    }

    // MARK: - togglePin

    /// togglePin 两次应恢复原状态
    func testTogglePinTwiceRestoresState() {
        let conv = storage.createConversation(title: "测试")
        XCTAssertFalse(conv.isPinned, "初始 isPinned 应为 false")
        storage.togglePin(conv)
        XCTAssertTrue(conv.isPinned, "toggle 一次后 isPinned 应为 true")
        storage.togglePin(conv)
        XCTAssertFalse(conv.isPinned, "toggle 两次后 isPinned 应恢复为 false")
    }
}
