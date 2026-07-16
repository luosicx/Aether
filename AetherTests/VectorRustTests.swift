import XCTest
import AetherRust

/// Rust 向量数学包装器单元测试。
/// 验证 AetherRustVector.cosine (f32/f64) 和 topK 检索。
final class VectorRustTests: XCTestCase {

    // MARK: - f32 cosine

    func testCosineF32IdenticalVectors() {
        let a: [Float] = [1.0, 2.0, 3.0]
        let b: [Float] = [1.0, 2.0, 3.0]
        let sim = AetherRustVector.cosine(a, b)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "相同向量余弦相似度应为 1.0")
    }

    func testCosineF32OrthogonalVectors() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [0.0, 1.0, 0.0]
        let sim = AetherRustVector.cosine(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 0.0001, "正交向量余弦相似度应为 0.0")
    }

    func testCosineF32OppositeVectors() {
        let a: [Float] = [1.0, 2.0, 3.0]
        let b: [Float] = [-1.0, -2.0, -3.0]
        let sim = AetherRustVector.cosine(a, b)
        XCTAssertEqual(sim, -1.0, accuracy: 0.0001, "相反向量余弦相似度应为 -1.0")
    }

    func testCosineF32EmptyVectors() {
        let sim = AetherRustVector.cosine([], [1.0])
        XCTAssertEqual(sim, 0.0, "空向量应返回 0")
    }

    func testCosineF32DifferentLengths() {
        let sim = AetherRustVector.cosine([1.0, 2.0], [1.0])
        XCTAssertEqual(sim, 0.0, "长度不等应返回 0")
    }

    // MARK: - f64 cosine

    func testCosineF64IdenticalVectors() {
        let a: [Double] = [1.0, 2.0, 3.0]
        let b: [Double] = [1.0, 2.0, 3.0]
        let sim = AetherRustVector.cosine(a, b)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "相同向量余弦相似度应为 1.0")
    }

    func testCosineF64EmptyVectors() {
        let sim = AetherRustVector.cosine([Double](), [1.0])
        XCTAssertEqual(sim, 0.0, "空向量应返回 0")
    }

    func testCosineF64DifferentLengths() {
        let sim = AetherRustVector.cosine([1.0, 2.0], [1.0])
        XCTAssertEqual(sim, 0.0, "长度不等应返回 0")
    }

    // MARK: - topK

    func testTopKBasic() {
        let query: [Float] = [1.0, 0.0, 0.0]
        let corpus: [[Float]] = [
            [1.0, 0.0, 0.0],  // index 0: 最相似
            [0.0, 1.0, 0.0],  // index 1: 正交
            [0.5, 0.5, 0.0],  // index 2: 部分相似
        ]
        let results = AetherRustVector.topK(query: query, corpus: corpus, k: 2)
        XCTAssertEqual(results.count, 2, "应返回 top 2 结果")
        XCTAssertEqual(results[0].index, 0, "最相似应为 index 0")
        XCTAssertEqual(results[0].score, 1.0, accuracy: 0.0001)
    }

    func testTopKEmptyCorpus() {
        let results = AetherRustVector.topK(query: [1.0], corpus: [], k: 5)
        XCTAssertTrue(results.isEmpty, "空语料库应返回空结果")
    }

    func testTopKZero() {
        let query: [Float] = [1.0, 0.0]
        let corpus: [[Float]] = [[1.0, 0.0]]
        let results = AetherRustVector.topK(query: query, corpus: corpus, k: 0)
        XCTAssertTrue(results.isEmpty, "k=0 应返回空结果")
    }

    func testTopKReturnsAtMostK() {
        let query: [Float] = [1.0, 0.0]
        let corpus: [[Float]] = [
            [1.0, 0.0],
            [0.9, 0.1],
            [0.8, 0.2],
            [0.7, 0.3],
            [0.6, 0.4],
        ]
        let results = AetherRustVector.topK(query: query, corpus: corpus, k: 3)
        XCTAssertLessThanOrEqual(results.count, 3, "结果数不应超过 k")
    }

    func testTopKSortedByScoreDescending() {
        let query: [Float] = [1.0, 0.0]
        let corpus: [[Float]] = [
            [0.0, 1.0],  // 最不相似
            [0.5, 0.5],  // 中等
            [1.0, 0.0],  // 最相似
        ]
        let results = AetherRustVector.topK(query: query, corpus: corpus, k: 3)
        // 验证按分数降序排列
        for i in 0..<(results.count - 1) {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i + 1].score,
                                       "结果应按分数降序排列")
        }
    }

    // MARK: - 边界情况

    func testCosineF32SingleElement() {
        let sim = AetherRustVector.cosine([5.0], [5.0])
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "单元素相同向量应返回 1.0")
    }

    func testCosineF64SingleElement() {
        let sim = AetherRustVector.cosine([3.0], [3.0])
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "单元素相同向量应返回 1.0")
    }
}