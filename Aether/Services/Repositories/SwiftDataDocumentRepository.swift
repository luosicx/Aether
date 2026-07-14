import Foundation
import SwiftData
import AetherFoundation
import AetherServices

/// SwiftData 实现的 DocumentRepository
///
/// 将 SwiftData @Model DocumentChunk 与平台无关 DocumentChunkDTO 桥接。
/// @MainActor 隔离，因为 ModelContext 访问需在主线程。
@MainActor
final class SwiftDataDocumentRepository: DocumentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func indexDocument(_ chunks: [DocumentChunkDTO]) async throws {
        for chunkDTO in chunks {
            let chunk = DocumentChunk(
                content: chunkDTO.content,
                embedding: chunkDTO.embedding,
                source: chunkDTO.source,
                chunkIndex: chunkDTO.chunkIndex
            )
            chunk.id = chunkDTO.id
            chunk.createdAt = chunkDTO.createdAt
            chunk.weight = chunkDTO.weight
            context.insert(chunk)
        }
        try context.save()
    }

    func search(query: String, limit: Int) async throws -> [DocumentChunkDTO] {
        let lowercaseQuery = query.lowercased()
        let descriptor = FetchDescriptor<DocumentChunk>(
            predicate: #Predicate { $0.content.localizedStandardContains(lowercaseQuery) },
            sortBy: [SortDescriptor(\.weight, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map { $0.toDTO() }
    }

    func updateWeight(chunkId: UUID, factor: Float) async throws {
        let descriptor = FetchDescriptor<DocumentChunk>(
            predicate: #Predicate { $0.id == chunkId }
        )
        if let chunk = try context.fetch(descriptor).first {
            chunk.weight = min(1.0, chunk.weight * factor)
        }
        try context.save()
    }

    func deleteBySource(_ source: String) async throws {
        let descriptor = FetchDescriptor<DocumentChunk>(
            predicate: #Predicate { $0.source == source }
        )
        for chunk in try context.fetch(descriptor) {
            context.delete(chunk)
        }
        try context.save()
    }
}

// MARK: - DocumentChunk -> DTO 转换扩展

extension DocumentChunk {
    /// 将 SwiftData @Model DocumentChunk 转为平台无关 DocumentChunkDTO
    func toDTO() -> DocumentChunkDTO {
        DocumentChunkDTO(
            id: id,
            content: content,
            embedding: embedding,
            source: source,
            chunkIndex: chunkIndex,
            weight: weight,
            createdAt: createdAt
        )
    }
}
