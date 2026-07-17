import XCTest
import SwiftData
@testable import Aether
import AetherFoundation

/// SwiftDataMessageRepository 单元测试：使用 in-memory ModelContainer
@MainActor
final class SwiftDataMessageRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: SwiftDataMessageRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self,
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self,
            Memory.self,
            configurations: config
        )
        context = ModelContext(container)
        repo = SwiftDataMessageRepository(context: context)
    }

    override func tearDownWithError() throws {
        repo = nil
        context = nil
        container = nil
    }

    private func makeConversation(id: UUID = UUID(), title: String = "测试会话") throws -> Conversation {
        let conv = Conversation(title: title)
        conv.id = id
        context.insert(conv)
        try context.save()
        return conv
    }

    func testFetchMessagesEmpty() async throws {
        let messages = try await repo.fetchMessages(conversationId: UUID())
        XCTAssertTrue(messages.isEmpty, "无消息时应返回空数组")
    }

    func testSaveNewMessageAndFetch() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let msgId = UUID()
        let now = Date()
        let dto = ChatMessageDTO(
            id: msgId, conversationId: convId, role: "user",
            content: "你好", createdAt: now
        )
        try await repo.save(dto)

        let fetched = try await repo.fetchMessages(conversationId: convId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, msgId)
        XCTAssertEqual(fetched.first?.content, "你好")
        XCTAssertEqual(fetched.first?.role, "user")
        XCTAssertEqual(fetched.first?.conversationId, convId)
    }

    func testSaveUpdatesExistingMessage() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let msgId = UUID()
        let dto = ChatMessageDTO(
            id: msgId, conversationId: convId, role: "user",
            content: "原文", createdAt: Date()
        )
        try await repo.save(dto)

        let updated = ChatMessageDTO(
            id: msgId, conversationId: convId, role: "assistant",
            content: "修改后", toolCallId: "tc-1", toolName: "search",
            injectionChecked: true, createdAt: Date()
        )
        try await repo.save(updated)

        let fetched = try await repo.fetchMessages(conversationId: convId)
        XCTAssertEqual(fetched.count, 1, "更新不应新增消息")
        XCTAssertEqual(fetched.first?.content, "修改后")
        XCTAssertEqual(fetched.first?.role, "assistant")
        XCTAssertEqual(fetched.first?.toolCallId, "tc-1")
        XCTAssertEqual(fetched.first?.toolName, "search")
        XCTAssertEqual(fetched.first?.injectionChecked, true)
    }

    func testSaveMessageWithImageDataAndToolCalls() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let msgId = UUID()
        let imageData = Data([0x01, 0x02, 0x03]).base64EncodedString()
        let attached = Data([0xFF, 0xEE]).base64EncodedString()
        let toolCalls = [ToolCallDTO(id: "call-1", name: "search", arguments: "{}")]
        let dto = ChatMessageDTO(
            id: msgId, conversationId: convId, role: "assistant",
            content: "结果", toolCalls: toolCalls,
            imageData: imageData, attachedImage: attached, createdAt: Date()
        )
        try await repo.save(dto)

        let fetched = try await repo.fetchMessages(conversationId: convId)
        XCTAssertEqual(fetched.first?.imageData, imageData)
        XCTAssertEqual(fetched.first?.attachedImage, attached)
        XCTAssertEqual(fetched.first?.toolCalls?.count, 1)
        XCTAssertEqual(fetched.first?.toolCalls?.first?.name, "search")
    }

    func testSaveMessageWithoutConversationStillInserts() async throws {
        // conversationId 不存在时，消息仍被 insert（但不关联 conversation）
        let msgId = UUID()
        let dto = ChatMessageDTO(
            id: msgId, conversationId: UUID(), role: "system",
            content: "系统提示", createdAt: Date()
        )
        try await repo.save(dto)
        // 不关联任何 conversation，fetchMessages 查不到
        let fetched = try await repo.fetchMessages(conversationId: dto.conversationId)
        XCTAssertTrue(fetched.isEmpty, "无关联 conversation 的消息不应被 fetchMessages 返回")
    }

    func testFetchMessagesSortedByTimestamp() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let old = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        try await repo.save(ChatMessageDTO(id: UUID(), conversationId: convId, role: "user", content: "B", createdAt: newer))
        try await repo.save(ChatMessageDTO(id: UUID(), conversationId: convId, role: "user", content: "A", createdAt: old))

        let fetched = try await repo.fetchMessages(conversationId: convId)
        XCTAssertEqual(fetched.map(\.content), ["A", "B"], "应按 timestamp 正序排列")
    }

    func testDeleteByConversationId() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        try await repo.save(ChatMessageDTO(id: UUID(), conversationId: convId, role: "user", content: "1", createdAt: Date()))
        try await repo.save(ChatMessageDTO(id: UUID(), conversationId: convId, role: "assistant", content: "2", createdAt: Date()))

        try await repo.delete(conversationId: convId)
        let fetched = try await repo.fetchMessages(conversationId: convId)
        XCTAssertTrue(fetched.isEmpty, "删除会话所有消息后应为空")
    }

    func testDeleteByMessageId() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let keepId = UUID()
        let deleteId = UUID()
        try await repo.save(ChatMessageDTO(id: keepId, conversationId: convId, role: "user", content: "保留", createdAt: Date()))
        try await repo.save(ChatMessageDTO(id: deleteId, conversationId: convId, role: "assistant", content: "删除", createdAt: Date()))

        try await repo.delete(messageId: deleteId)
        let fetched = try await repo.fetchMessages(conversationId: convId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, keepId)
    }

    func testSubmitFeedbackCreatesNew() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let msgId = UUID()
        try await repo.save(ChatMessageDTO(id: msgId, conversationId: convId, role: "assistant", content: "回复", createdAt: Date()))

        try await repo.submitFeedback(messageId: msgId, isPositive: true, citations: ["src1"])

        let descriptor = FetchDescriptor<MessageFeedback>(
            predicate: #Predicate { $0.messageId == msgId }
        )
        let feedback = try context.fetch(descriptor)
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.isPositive, true)
    }

    func testSubmitFeedbackUpdatesExisting() async throws {
        let convId = UUID()
        _ = try makeConversation(id: convId)
        let msgId = UUID()
        try await repo.save(ChatMessageDTO(id: msgId, conversationId: convId, role: "assistant", content: "回复", createdAt: Date()))
        try await repo.submitFeedback(messageId: msgId, isPositive: true, citations: nil)
        try await repo.submitFeedback(messageId: msgId, isPositive: false, citations: nil)

        let descriptor = FetchDescriptor<MessageFeedback>(
            predicate: #Predicate { $0.messageId == msgId }
        )
        let feedback = try context.fetch(descriptor)
        XCTAssertEqual(feedback.count, 1, "应更新而非新建")
        XCTAssertEqual(feedback.first?.isPositive, false)
    }

    func testSubmitFeedbackNonExistentMessageIsNoop() async throws {
        // 消息不存在时应安全返回（guard let return）
        try await repo.submitFeedback(messageId: UUID(), isPositive: nil, citations: nil)
        let all = try context.fetch(FetchDescriptor<MessageFeedback>())
        XCTAssertTrue(all.isEmpty)
    }

    func testChatMessageToDTOWithoutConversation() throws {
        // 覆盖 toDTO 的 conversation?.id ?? UUID() 分支
        let msg = ChatMessage(role: "system", content: "无会话")
        msg.id = UUID()
        context.insert(msg)
        try context.save()
        let dto = msg.toDTO()
        XCTAssertEqual(dto.content, "无会话")
        XCTAssertEqual(dto.role, "system")
        // 无 conversation 时生成新 UUID（非 nil）
        XCTAssertNotEqual(dto.conversationId, msg.id)
    }

    func testChatMessageToDTOWithoutToolCallData() throws {
        let conv = Conversation(title: "T")
        conv.id = UUID()
        context.insert(conv)
        let msg = ChatMessage(role: "assistant", content: "无工具调用")
        msg.id = UUID()
        msg.conversation = conv
        conv.messages.append(msg)
        context.insert(msg)
        try context.save()
        let dto = msg.toDTO()
        XCTAssertNil(dto.toolCalls, "无 toolCallData 时 toolCalls 应为 nil")
    }
}

/// SwiftDataConversationRepository 单元测试
@MainActor
final class SwiftDataConversationRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: SwiftDataConversationRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self,
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self,
            Memory.self,
            configurations: config
        )
        context = ModelContext(container)
        repo = SwiftDataConversationRepository(context: context)
    }

    override func tearDownWithError() throws {
        repo = nil
        context = nil
        container = nil
    }

    func testFetchAllEmpty() async throws {
        let all = try await repo.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testSaveNewAndFetchAll() async throws {
        let id = UUID()
        let now = Date()
        let dto = ConversationDTO(
            id: id, title: "会话1", createdAt: now, updatedAt: now,
            isPinned: true, unreadCount: 2, order: 1
        )
        try await repo.save(dto)

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "会话1")
        XCTAssertEqual(all.first?.isPinned, true)
        XCTAssertEqual(all.first?.unreadCount, 2)
        XCTAssertEqual(all.first?.order, 1)
    }

    func testFetchAllSortedByCreatedAtDesc() async throws {
        let old = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        try await repo.save(ConversationDTO(id: UUID(), title: "旧", createdAt: old, updatedAt: old))
        try await repo.save(ConversationDTO(id: UUID(), title: "新", createdAt: newer, updatedAt: newer))

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.map(\.title), ["新", "旧"], "应按 createdAt 降序")
    }

    func testFetchById() async throws {
        let id = UUID()
        let now = Date()
        try await repo.save(ConversationDTO(id: id, title: "查找", createdAt: now, updatedAt: now))

        let found = try await repo.fetch(id: id)
        XCTAssertEqual(found?.title, "查找")
        let notFound = try await repo.fetch(id: UUID())
        XCTAssertNil(notFound, "不存在的 id 应返回 nil")
    }

    func testSaveUpdatesExisting() async throws {
        let id = UUID()
        let now = Date()
        try await repo.save(ConversationDTO(id: id, title: "原标题", createdAt: now, updatedAt: now))

        try await repo.save(ConversationDTO(
            id: id, title: "新标题", systemPrompt: "自定义提示",
            parentConversationId: UUID(), parentMessageId: UUID(),
            createdAt: now, updatedAt: now, isPinned: true, unreadCount: 5, order: 3
        ))

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.count, 1, "更新不应新增")
        XCTAssertEqual(all.first?.title, "新标题")
        XCTAssertEqual(all.first?.systemPrompt, "自定义提示")
        XCTAssertEqual(all.first?.isPinned, true)
        XCTAssertEqual(all.first?.unreadCount, 5)
        XCTAssertEqual(all.first?.order, 3)
        XCTAssertNotNil(all.first?.parentConversationId)
        XCTAssertNotNil(all.first?.parentMessageId)
    }

    func testDeleteById() async throws {
        let id1 = UUID()
        let id2 = UUID()
        let now = Date()
        try await repo.save(ConversationDTO(id: id1, title: "A", createdAt: now, updatedAt: now))
        try await repo.save(ConversationDTO(id: id2, title: "B", createdAt: now, updatedAt: now))

        try await repo.delete(id: id1)
        let all = try await repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "B")
    }

    func testSearchByQuery() async throws {
        let now = Date()
        try await repo.save(ConversationDTO(id: UUID(), title: "Swift 学习笔记", createdAt: now, updatedAt: now))
        try await repo.save(ConversationDTO(id: UUID(), title: "Python 入门", createdAt: now, updatedAt: now))

        let results = try await repo.search(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Swift 学习笔记")

        // 大小写不敏感
        let upper = try await repo.search(query: "PYTHON")
        XCTAssertEqual(upper.count, 1)
    }

    func testFetchChildren() async throws {
        let parentId = UUID()
        let now = Date()
        try await repo.save(ConversationDTO(id: parentId, title: "父", createdAt: now, updatedAt: now))
        try await repo.save(ConversationDTO(id: UUID(), title: "子1", parentConversationId: parentId, createdAt: now, updatedAt: now))
        try await repo.save(ConversationDTO(id: UUID(), title: "子2", parentConversationId: parentId, createdAt: Date(timeIntervalSince1970: 9999), updatedAt: now))

        let children = try await repo.fetchChildren(parentId: parentId)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.map(\.title), ["子1", "子2"], "应按 createdAt 降序")
    }

    func testConversationToDTOWithMessages() throws {
        let conv = Conversation(title: "带消息")
        conv.id = UUID()
        let msg = ChatMessage(role: "user", content: "预览内容")
        msg.conversation = conv
        conv.messages.append(msg)
        context.insert(conv)
        try context.save()

        let dto = conv.toDTO()
        XCTAssertEqual(dto.lastMessagePreview, "预览内容")
        XCTAssertEqual(dto.updatedAt, msg.timestamp)
    }

    func testConversationToDTOWithoutMessages() throws {
        let conv = Conversation(title: "空会话")
        conv.id = UUID()
        context.insert(conv)
        try context.save()

        let dto = conv.toDTO()
        XCTAssertEqual(dto.lastMessagePreview, "")
        XCTAssertEqual(dto.updatedAt, conv.createdAt)
    }
}

/// SwiftDataMemoryRepository 单元测试
@MainActor
final class SwiftDataMemoryRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: SwiftDataMemoryRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self,
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self,
            Memory.self,
            configurations: config
        )
        context = ModelContext(container)
        repo = SwiftDataMemoryRepository(context: context)
    }

    override func tearDownWithError() throws {
        repo = nil
        context = nil
        container = nil
    }

    func testFetchAllEmpty() async throws {
        let all = try await repo.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testSaveNewAndFetchAllSortedByImportance() async throws {
        let now = Date()
        try await repo.save(MemoryDTO(id: UUID(), content: "低", importance: 0.2, createdAt: now))
        try await repo.save(MemoryDTO(id: UUID(), content: "高", importance: 0.9, createdAt: now))

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.map(\.content), ["高", "低"], "应按 importance 降序")
    }

    func testSaveUpdatesExisting() async throws {
        let id = UUID()
        let now = Date()
        try await repo.save(MemoryDTO(id: id, content: "原内容", category: "context", importance: 0.5, createdAt: now))
        try await repo.save(MemoryDTO(id: id, content: "更新内容", category: "fact", importance: 0.8, embedding: [1.0, 2.0], sourceConversationId: UUID(), createdAt: now))

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "更新内容")
        XCTAssertEqual(all.first?.category, "fact")
        XCTAssertEqual(all.first?.importance ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(all.first?.embedding, [1.0, 2.0])
        XCTAssertNotNil(all.first?.sourceConversationId)
    }

    func testSearchRelevant() async throws {
        let now = Date()
        try await repo.save(MemoryDTO(id: UUID(), content: "用户喜欢 Swift", importance: 0.9, createdAt: now))
        try await repo.save(MemoryDTO(id: UUID(), content: "用户住在上海", importance: 0.5, createdAt: now))

        let results = try await repo.searchRelevant(query: "swift", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "用户喜欢 Swift")
    }

    func testSearchRelevantRespectsLimit() async throws {
        let now = Date()
        for i in 0..<5 {
            try await repo.save(MemoryDTO(id: UUID(), content: "记忆 \(i) swift", importance: Double(i) * 0.1, createdAt: now))
        }
        let results = try await repo.searchRelevant(query: "swift", limit: 2)
        XCTAssertEqual(results.count, 2, "应受 fetchLimit 限制")
        XCTAssertEqual(results.first?.content, "记忆 4 swift", "应按 importance 降序取前 2")
    }

    func testDeleteById() async throws {
        let id1 = UUID()
        let id2 = UUID()
        let now = Date()
        try await repo.save(MemoryDTO(id: id1, content: "A", createdAt: now))
        try await repo.save(MemoryDTO(id: id2, content: "B", createdAt: now))

        try await repo.delete(id: id1)
        let all = try await repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "B")
    }

    func testMemoryToDTO() throws {
        let memory = Memory(content: "测试记忆", embedding: [0.1, 0.2], category: "preference", importance: 0.7)
        memory.id = UUID()
        context.insert(memory)
        try context.save()

        let dto = memory.toDTO()
        XCTAssertEqual(dto.content, "测试记忆")
        XCTAssertEqual(dto.category, "preference")
        XCTAssertEqual(dto.importance, 0.7, accuracy: 0.001)
        XCTAssertEqual(dto.embedding, [0.1, 0.2])
    }
}

/// SwiftDataDocumentRepository 单元测试
@MainActor
final class SwiftDataDocumentRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: SwiftDataDocumentRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self,
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self,
            Memory.self,
            configurations: config
        )
        context = ModelContext(container)
        repo = SwiftDataDocumentRepository(context: context)
    }

    override func tearDownWithError() throws {
        repo = nil
        context = nil
        container = nil
    }

    func testIndexDocumentAndSearch() async throws {
        let now = Date()
        let chunks = [
            DocumentChunkDTO(id: UUID(), content: "Swift 是一门语言", embedding: [0.1], source: "doc1.md", chunkIndex: 0, weight: 0.8, createdAt: now),
            DocumentChunkDTO(id: UUID(), content: "Python 也很流行", embedding: [0.2], source: "doc1.md", chunkIndex: 1, weight: 0.5, createdAt: now)
        ]
        try await repo.indexDocument(chunks)

        let results = try await repo.search(query: "swift", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "Swift 是一门语言")
    }

    func testSearchSortedByWeightDesc() async throws {
        let now = Date()
        try await repo.indexDocument([
            DocumentChunkDTO(id: UUID(), content: "低权重 swift", source: "a", weight: 0.3, createdAt: now),
            DocumentChunkDTO(id: UUID(), content: "高权重 swift", source: "b", weight: 0.9, createdAt: now)
        ])
        let results = try await repo.search(query: "swift", limit: 10)
        XCTAssertEqual(results.map(\.content), ["高权重 swift", "低权重 swift"], "应按 weight 降序")
    }

    func testSearchRespectsLimit() async throws {
        let now = Date()
        var chunks: [DocumentChunkDTO] = []
        for i in 0..<5 {
            chunks.append(DocumentChunkDTO(id: UUID(), content: "chunk \(i) keyword", source: "s", weight: Float(i) * 0.1, createdAt: now))
        }
        try await repo.indexDocument(chunks)
        let results = try await repo.search(query: "keyword", limit: 2)
        XCTAssertEqual(results.count, 2)
    }

    func testUpdateWeight() async throws {
        let now = Date()
        let chunkId = UUID()
        try await repo.indexDocument([
            DocumentChunkDTO(id: chunkId, content: "测试 keyword", source: "s", weight: 0.5, createdAt: now)
        ])
        // weight = min(1.0, 0.5 * 1.5) = 0.75
        try await repo.updateWeight(chunkId: chunkId, factor: 1.5)
        let results = try await repo.search(query: "keyword", limit: 10)
        XCTAssertEqual(results.first?.weight ?? 0, 0.75, accuracy: 0.01)
    }

    func testUpdateWeightCappedAtOne() async throws {
        let now = Date()
        let chunkId = UUID()
        try await repo.indexDocument([
            DocumentChunkDTO(id: chunkId, content: "上限 keyword", source: "s", weight: 0.9, createdAt: now)
        ])
        // weight = min(1.0, 0.9 * 2.0) = 1.0
        try await repo.updateWeight(chunkId: chunkId, factor: 2.0)
        let results = try await repo.search(query: "keyword", limit: 10)
        XCTAssertEqual(results.first?.weight ?? 0, 1.0, accuracy: 0.01)
    }

    func testUpdateWeightNonExistentChunk() async throws {
        // 不存在的 chunk 应安全返回
        try await repo.updateWeight(chunkId: UUID(), factor: 2.0)
    }

    func testDeleteBySource() async throws {
        let now = Date()
        try await repo.indexDocument([
            DocumentChunkDTO(id: UUID(), content: "A keyword", source: "keep.md", createdAt: now),
            DocumentChunkDTO(id: UUID(), content: "B keyword", source: "delete.md", createdAt: now),
            DocumentChunkDTO(id: UUID(), content: "C keyword", source: "delete.md", createdAt: now)
        ])
        try await repo.deleteBySource("delete.md")
        let results = try await repo.search(query: "keyword", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "keep.md")
    }

    func testDocumentChunkToDTO() throws {
        let chunk = DocumentChunk(content: "分块内容", embedding: [0.5], source: "src.md", chunkIndex: 3)
        chunk.id = UUID()
        chunk.weight = 0.6
        context.insert(chunk)
        try context.save()

        let dto = chunk.toDTO()
        XCTAssertEqual(dto.content, "分块内容")
        XCTAssertEqual(dto.source, "src.md")
        XCTAssertEqual(dto.chunkIndex, 3)
        XCTAssertEqual(dto.weight, 0.6, accuracy: 0.01)
        XCTAssertEqual(dto.embedding, [0.5])
    }
}
