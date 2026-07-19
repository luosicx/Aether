import XCTest
@testable import AetherSDK
import AetherFoundation
import AetherServices

/// Task 24 阶段 2: AetherClient 核心 API 测试
///
/// 使用 MockLLMProvider / MockRAGProvider / MockEmbeddingProvider 验证
/// chat / stream / embed / retrieve 四个核心 API 的行为。
final class AetherClientAPITests: XCTestCase {

    // MARK: - chat

    func testChatReturnsAccumulatedResponse() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["Hello", ", ", "world!"]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        let response = try await client.chat(messages: [.user("hi")])
        XCTAssertEqual(response, "Hello, world!")
    }

    func testChatEmptyResponseThrows() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = []
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        do {
            _ = try await client.chat(messages: [.user("hi")])
            XCTFail("应抛出 networkUnreachable")
        } catch let error as AetherError {
            // 空响应表示网络故障/流提前结束，源码按可重试的 networkUnreachable 抛出
            if case .networkUnreachable = error {
                // 预期
            } else {
                XCTFail("期望 networkUnreachable，实际：\(error)")
            }
        }
    }

    func testChatWithCacheReturnsCachedResponse() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["first response"]
        mock.embedResponses = [[0.5, 0.5, 0.5]]
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            cache: CacheConfig(enabled: true, ttl: 3600, similarityThreshold: 0.92, maxCapacity: 100)
        )
        let client = try AetherClient(config: config, provider: mock)

        // 第一次调用：缓存未命中，调用 LLM
        let r1 = try await client.chat(messages: [.user("hello")])
        XCTAssertEqual(r1, "first response")

        // 第二次相同调用：应命中缓存（embed 返回相同向量）
        mock.chatResponses = ["second response"] // LLM 不会被调用，但若被调用会返回不同结果
        let r2 = try await client.chat(messages: [.user("hello")])
        XCTAssertEqual(r2, "first response", "第二次应返回缓存结果")
    }

    // MARK: - stream

    func testStreamYieldsChunks() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["chunk1", "chunk2", "chunk3"]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        var chunks: [AetherChunk] = []
        for await chunk in client.stream(messages: [.user("hi")]) {
            chunks.append(chunk)
        }
        // 应有 3 个内容 chunk + 1 个 final chunk
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks[0].content, "chunk1")
        XCTAssertEqual(chunks[1].content, "chunk2")
        XCTAssertEqual(chunks[2].content, "chunk3")
        XCTAssertTrue(chunks[3].isFinal)
    }

    func testStreamWithEmptyResponse() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = []
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        var chunks: [AetherChunk] = []
        for await chunk in client.stream(messages: [.user("hi")]) {
            chunks.append(chunk)
        }
        // 空响应也应 yield final
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].isFinal)
    }

    // MARK: - embed

    func testEmbedReturnsVectors() async throws {
        let mock = MockLLMProvider()
        mock.embedResponses = [[0.1, 0.2], [0.3, 0.4]]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        let vectors = try await client.embed(texts: ["hello", "world"])
        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0], [0.1, 0.2])
        XCTAssertEqual(vectors[1], [0.3, 0.4])
    }

    func testEmbedUsesInjectedProvider() async throws {
        let mock = MockLLMProvider()
        let embedProvider = MockEmbeddingProvider(vectors: [[0.9, 0.8]])
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock,
            embeddingProvider: embedProvider
        )
        let vectors = try await client.embed(texts: ["test"])
        XCTAssertEqual(vectors, [[0.9, 0.8]])
    }

    func testEmbedPropagatesError() async throws {
        let mock = MockLLMProvider()
        mock.shouldThrowEmbed = true
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        do {
            _ = try await client.embed(texts: ["test"])
            XCTFail("应抛出错误")
        } catch let error as AetherError {
            if case .authFailed = error {
                // 预期：401 → authFailed
            } else {
                XCTFail("期望 authFailed，实际：\(error)")
            }
        }
    }

    // MARK: - retrieve

    func testRetrieveWithoutRAGProviderThrows() async throws {
        let mock = MockLLMProvider()
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            rag: RAGConfig(knowledgeBaseID: "kb-1")
        )
        let client = try AetherClient(config: config, provider: mock)
        do {
            _ = try await client.retrieve(query: "test")
            XCTFail("应抛出 ragRetrievalFailed")
        } catch let error as AetherError {
            if case .ragRetrievalFailed = error {
                // 预期
            } else {
                XCTFail("期望 ragRetrievalFailed，实际：\(error)")
            }
        }
    }

    func testRetrieveWithoutRAGConfigThrows() async throws {
        let mock = MockLLMProvider()
        let ragProvider = MockRAGProvider(documents: [])
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock,
            ragProvider: ragProvider
        )
        do {
            _ = try await client.retrieve(query: "test")
            XCTFail("应抛出 ragRetrievalFailed")
        } catch let error as AetherError {
            if case .ragRetrievalFailed = error {
                // 预期
            } else {
                XCTFail("期望 ragRetrievalFailed，实际：\(error)")
            }
        }
    }

    func testRetrieveReturnsDocuments() async throws {
        let mock = MockLLMProvider()
        let docs = [
            AetherDocument(content: "doc1", source: "src1", score: 0.9),
            AetherDocument(content: "doc2", source: "src2", score: 0.7)
        ]
        let ragProvider = MockRAGProvider(documents: docs)
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            rag: RAGConfig(knowledgeBaseID: "kb-1", topK: 5)
        )
        let client = try AetherClient(config: config, provider: mock, ragProvider: ragProvider)
        let result = try await client.retrieve(query: "question", topK: 5)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].content, "doc1")
        XCTAssertEqual(result[1].content, "doc2")
        XCTAssertEqual(ragProvider.lastQuery, "question")
        XCTAssertEqual(ragProvider.lastTopK, 5)
        XCTAssertEqual(ragProvider.lastKnowledgeBaseID, "kb-1")
    }
}

// MARK: - Mock Embedding Provider

final class MockEmbeddingProvider: AetherEmbeddingProvider, @unchecked Sendable {
    let vectors: [[Float]]
    var shouldThrow = false

    init(vectors: [[Float]]) {
        self.vectors = vectors
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        if shouldThrow {
            throw LLMError.apiError(code: 500, message: "embed failed")
        }
        return vectors
    }
}

// MARK: - Mock RAG Provider

final class MockRAGProvider: AetherRAGProvider, @unchecked Sendable {
    let documents: [AetherDocument]
    var lastQuery: String?
    var lastTopK: Int?
    var lastKnowledgeBaseID: String?
    var shouldThrow = false

    init(documents: [AetherDocument]) {
        self.documents = documents
    }

    func retrieve(query: String, topK: Int, knowledgeBaseID: String) async throws -> [AetherDocument] {
        lastQuery = query
        lastTopK = topK
        lastKnowledgeBaseID = knowledgeBaseID
        if shouldThrow {
            throw AetherError.ragRetrievalFailed(reason: "mock error")
        }
        return documents
    }
}
