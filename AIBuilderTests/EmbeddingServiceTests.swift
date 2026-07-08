import XCTest
@testable import AIBuilder

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
}
