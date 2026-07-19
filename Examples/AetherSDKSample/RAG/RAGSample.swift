// AetherSDKSample — RAG Retrieval Scenario
//
// Demonstrates how to inject a custom RAG provider and retrieve relevant documents.
// In production, bridge this to the App's RAGService backed by SwiftData + sqlite-vec.

import AetherSDK
import Foundation

/// A sample RAG provider that returns mock documents.
/// In production, bridge to your DocumentChunk store (SwiftData, sqlite-vec, etc.)
struct SampleRAGProvider: AetherRAGProvider {
    func retrieve(query: String, topK: Int, knowledgeBaseID: String) async throws -> [AetherDocument] {
        // Mock: return 2 documents
        return [
            AetherDocument(
                content: "Swift is a high-performance systems programming language by Apple.",
                source: "swift-docs.md",
                score: 0.92,
                metadata: ["chapter": "1", "page": "1"]
            ),
            AetherDocument(
                content: "SwiftUI is Apple's declarative UI framework for building apps.",
                source: "swiftui-guide.md",
                score: 0.85,
                metadata: ["chapter": "2", "page": "5"]
            )
        ]
    }
}

@main
struct RAGSample {
    static func main() async throws {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-your-api-key",
            rag: RAGConfig(knowledgeBaseID: "swift-kb", topK: 5)
        )
        let client = try AetherClient(
            config: config,
            provider: ModelProviderFactory.make(.deepseek), // placeholder
            ragProvider: SampleRAGProvider()
        )

        let docs = try await client.retrieve(query: "What is SwiftUI?", topK: 5)
        print("Retrieved \(docs.count) documents:")
        for (i, doc) in docs.enumerated() {
            print("[\(i + 1)] \(doc.source) (score: \(doc.score))")
            print("    \(doc.content)")
        }

        // Augment chat with retrieved context
        let context = docs.map(\.content).joined(separator: "\n\n")
        let messages: [AetherMessage] = [
            .system("Use the following context to answer the user's question:\n\n\(context)"),
            .user("What is SwiftUI?")
        ]
        let response = try await client.chat(messages: messages)
        print("Assistant: \(response)")
    }
}
