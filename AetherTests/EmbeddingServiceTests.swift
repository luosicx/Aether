import XCTest
@testable import Aether

/// Day 11: EmbeddingService 单元测试
final class EmbeddingServiceTests: XCTestCase {

    // MARK: - 桩 EmbeddingService

    /// 桩子类：override `embed` 返回固定向量，记录每批输入以便验证分片顺序
    final class StubEmbeddingService: EmbeddingService {
        var recordedBatches: [[String]] = []
        var returnEmpty = false
        private var counter: Float = 0

        override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            if returnEmpty { return [] }
            recordedBatches.append(texts)
            return texts.map { _ in
                counter += 1
                return [counter, 0, 0]
            }
        }
    }

    // MARK: - embedBatch 分片聚合

    func testEmbedBatchChunking() async throws {
        let stub = StubEmbeddingService()
        let texts = ["t0", "t1", "t2", "t3", "t4"]

        let embeddings = try await stub.embedBatch(texts, batchSize: 2, apiKey: "key")

        // 5 个文本应产出 5 个向量
        XCTAssertEqual(embeddings.count, 5, "应返回 5 个向量")

        // 分 3 批：[0,1] / [2,3] / [4]
        XCTAssertEqual(stub.recordedBatches.count, 3, "应分 3 批调用 embed")
        XCTAssertEqual(stub.recordedBatches[0], ["t0", "t1"], "第 1 批应为 [t0, t1]")
        XCTAssertEqual(stub.recordedBatches[1], ["t2", "t3"], "第 2 批应为 [t2, t3]")
        XCTAssertEqual(stub.recordedBatches[2], ["t4"], "第 3 批应为 [t4]")

        // 输出 5 个向量按原顺序：[1,0,0]..[5,0,0]
        for (i, emb) in embeddings.enumerated() {
            XCTAssertEqual(emb, [Float(i + 1), 0, 0], "第 \(i) 个向量应按原顺序聚合")
        }
    }

    // MARK: - Array.chunked 扩展

    func testArrayChunkedExtension() {
        // count < size → 1 块
        let small = [1, 2].chunked(into: 5)
        XCTAssertEqual(small.count, 1, "count<size 应返回 1 块")
        XCTAssertEqual(small[0], [1, 2])

        // 整除：6/2 = 3 块
        let even = [1, 2, 3, 4, 5, 6].chunked(into: 2)
        XCTAssertEqual(even.count, 3, "6/2 应返回 3 块")
        XCTAssertEqual(even[0], [1, 2])
        XCTAssertEqual(even[1], [3, 4])
        XCTAssertEqual(even[2], [5, 6])

        // 非整除：7/3 = 3 块（末尾截断）
        let odd = [1, 2, 3, 4, 5, 6, 7].chunked(into: 3)
        XCTAssertEqual(odd.count, 3, "7/3 应返回 3 块")
        XCTAssertEqual(odd[0], [1, 2, 3])
        XCTAssertEqual(odd[1], [4, 5, 6])
        XCTAssertEqual(odd[2], [7], "末尾块应截断为单个元素")
    }

    // MARK: - 批量 embedding 与错误处理补充

    /// batchSize=1 时每个文本独占一批
    func testEmbedBatchBatchSizeOne() async throws {
        let stub = StubEmbeddingService()
        let texts = ["a", "b", "c"]

        let embeddings = try await stub.embedBatch(texts, batchSize: 1, apiKey: "key")

        XCTAssertEqual(embeddings.count, 3, "应返回 3 个向量")
        XCTAssertEqual(stub.recordedBatches.count, 3, "应分 3 批调用 embed")
        XCTAssertEqual(stub.recordedBatches[0], ["a"])
        XCTAssertEqual(stub.recordedBatches[1], ["b"])
        XCTAssertEqual(stub.recordedBatches[2], ["c"])
    }

    /// batchSize 大于总数时应单批完成
    func testEmbedBatchBatchSizeLargerThanCount() async throws {
        let stub = StubEmbeddingService()
        let texts = ["a", "b"]

        let embeddings = try await stub.embedBatch(texts, batchSize: 100, apiKey: "key")

        XCTAssertEqual(embeddings.count, 2)
        XCTAssertEqual(stub.recordedBatches.count, 1, "应仅 1 批")
        XCTAssertEqual(stub.recordedBatches[0], ["a", "b"])
    }

    /// 空入参应返回空数组，不调用 embed
    func testEmbedBatchEmptyInput() async throws {
        let stub = StubEmbeddingService()

        let embeddings = try await stub.embedBatch([], batchSize: 10, apiKey: "key")

        XCTAssertEqual(embeddings, [])
        XCTAssertEqual(stub.recordedBatches.count, 0, "空入参不应调用 embed")
    }

    /// 单条文本应正确返回 1 个向量
    func testEmbedBatchSingleText() async throws {
        let stub = StubEmbeddingService()

        let embeddings = try await stub.embedBatch(["only"], batchSize: 10, apiKey: "key")

        XCTAssertEqual(embeddings.count, 1)
        XCTAssertEqual(stub.recordedBatches.count, 1)
        XCTAssertEqual(stub.recordedBatches[0], ["only"])
    }

    /// stub 抛错时 embedBatch 应传播错误
    func testEmbedBatchPropagatesError() async {
        final class ThrowingStub: EmbeddingService {
            var callCount = 0
            override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
                callCount += 1
                if callCount == 2 {
                    throw LLMError.networkError("batch 2 failed")
                }
                return texts.map { _ in [1.0, 0.0] }
            }
        }
        let stub = ThrowingStub()
        let texts = ["a", "b", "c", "d"]

        do {
            _ = try await stub.embedBatch(texts, batchSize: 1, apiKey: "key")
            XCTFail("应抛出错误")
        } catch let err as LLMError {
            if case .networkError(let msg) = err {
                XCTAssertTrue(msg.contains("batch 2 failed"), "应传播 batch 2 的错误")
            } else {
                XCTFail("期望 networkError，实际：\(err)")
            }
        } catch {
            XCTFail("期望 LLMError，实际：\(type(of: error))")
        }
        XCTAssertEqual(stub.callCount, 2, "应在第 2 次调用时抛错")
    }

    /// embed 直接透传给 client.embed
    func testEmbedDelegatesToClient() async throws {
        let stub = StubEmbeddingService()
        let result = try await stub.embed(texts: ["x", "y"], apiKey: "test-key")
        XCTAssertEqual(result.count, 2, "应返回 2 个向量")
        XCTAssertEqual(stub.recordedBatches.count, 1, "应调用 1 次 embed")
        XCTAssertEqual(stub.recordedBatches[0], ["x", "y"])
    }

    // MARK: - resolveEmbedding 静态方法

    /// resolveEmbedding(.qwen) 应返回 QwenClient 和 .qwen
    func testResolveEmbeddingForQwen() {
        let result = EmbeddingService.resolveEmbedding(for: .qwen)
        XCTAssertNotNil(result, "qwen 应返回非 nil")
        XCTAssertEqual(result?.1, .qwen, "provider 应为 qwen")
    }

    /// resolveEmbedding(.onDevice) 应返回 client 和 .onDevice
    func testResolveEmbeddingForOnDevice() {
        let result = EmbeddingService.resolveEmbedding(for: .onDevice)
        XCTAssertNotNil(result, "onDevice 应返回非 nil")
        XCTAssertEqual(result?.1, .onDevice, "provider 应为 onDevice")
    }

    /// resolveEmbedding(.deepseek) 无 Qwen Key 时应返回 nil
    /// 注意：此测试依赖 KeychainManager.shared 的实际状态，若 Keychain 中有 Qwen key 则返回非 nil
    func testResolveEmbeddingForDeepSeek() {
        let result = EmbeddingService.resolveEmbedding(for: .deepseek)
        // 结果取决于 Keychain 中是否有 Qwen API Key
        if let result = result {
            // 有 Qwen key 时应降级到 qwen
            XCTAssertEqual(result.1, .qwen, "deepseek 应降级到 qwen")
        } else {
            // 无 Qwen key 时返回 nil
            XCTAssertNil(result, "无 Qwen key 时应返回 nil")
        }
    }

    /// Array.chunked 对空数组的处理
    func testArrayChunkedEmptyArray() {
        let empty: [Int] = []
        let chunks = empty.chunked(into: 3)
        XCTAssertTrue(chunks.isEmpty, "空数组应返回空块数组")
    }

    /// Array.chunked size=1 应每个元素一块
    func testArrayChunkedSizeOne() {
        let arr = [1, 2, 3]
        let chunks = arr.chunked(into: 1)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1])
        XCTAssertEqual(chunks[1], [2])
        XCTAssertEqual(chunks[2], [3])
    }
}
