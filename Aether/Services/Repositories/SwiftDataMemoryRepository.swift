import Foundation
import SwiftData
import AetherFoundation
import AetherServices

/// SwiftData 实现的 MemoryRepository
///
/// 将 SwiftData @Model Memory 与平台无关 MemoryDTO 桥接。
/// @MainActor 隔离，因为 ModelContext 访问需在主线程。
@MainActor
final class SwiftDataMemoryRepository: MemoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [MemoryDTO] {
        let descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.importance, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDTO() }
    }

    func save(_ memory: MemoryDTO) async throws {
        let id = memory.id
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.content = memory.content
            existing.category = memory.category
            existing.importance = memory.importance
            existing.embedding = memory.embedding
            existing.sourceConversationID = memory.sourceConversationId
        } else {
            let newMemory = Memory(
                content: memory.content,
                embedding: memory.embedding,
                category: memory.category,
                importance: memory.importance,
                sourceConversationID: memory.sourceConversationId
            )
            newMemory.id = memory.id
            newMemory.createdAt = memory.createdAt
            context.insert(newMemory)
        }
        try context.save()
    }

    func searchRelevant(query: String, limit: Int) async throws -> [MemoryDTO] {
        let lowercaseQuery = query.lowercased()
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { $0.content.localizedStandardContains(lowercaseQuery) },
            sortBy: [SortDescriptor(\.importance, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map { $0.toDTO() }
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { $0.id == id }
        )
        for memory in try context.fetch(descriptor) {
            context.delete(memory)
        }
        try context.save()
    }
}

// MARK: - Memory -> DTO 转换扩展

extension Memory {
    /// 将 SwiftData @Model Memory 转为平台无关 MemoryDTO
    func toDTO() -> MemoryDTO {
        MemoryDTO(
            id: id,
            content: content,
            category: category,
            importance: importance,
            embedding: embedding,
            sourceConversationId: sourceConversationID,
            createdAt: createdAt
        )
    }
}
