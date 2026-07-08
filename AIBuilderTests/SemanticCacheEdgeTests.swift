import XCTest
@testable import AIBuilder

/// SemanticCache 边界用例补充（不重复 SemanticCacheTests 已覆盖的命中/未命中/容量 101 驱逐）
@MainActor
final class SemanticCacheEdgeTests: XCTestCase {

    /// 空向量：cosineSimilarity 内部 guard `!a.isEmpty` 返回 0，应不命中
    func testCosineSimilarityEmptyVectors() {
        let cache = SemanticCache()
        cache.set(query: "q", embedding: [], response: "r")
        let result = cache.get(query: "q", embedding: [])
        XCTAssertNil(result, "空向量的相似度返回 0，不应命中")
    }

    /// 长度不等：cosineSimilarity 内部 guard `a.count == b.count` 返回 0，应不命中
    func testCosineSimilarityUnequalLength() {
        let cache = SemanticCache()
        cache.set(query: "q", embedding: [1.0, 0.0, 0.0], response: "r")
        let result = cache.get(query: "q", embedding: [1.0, 0.0])
        XCTAssertNil(result, "长度不等的向量相似度返回 0，不应命中")
    }

    /// 零范数：normA == 0 时 guard `normA > 0` 返回 0，避免除零
    func testCosineSimilarityZeroNorm() {
        let cache = SemanticCache()
        cache.set(query: "q", embedding: [0.0, 0.0, 0.0], response: "r")
        // 零向量 vs 零向量
        XCTAssertNil(cache.get(query: "q", embedding: [0.0, 0.0, 0.0]),
                     "零范数向量相似度返回 0，不应命中")
        // 零向量 vs 非零向量
        cache.set(query: "q2", embedding: [1.0, 0.0, 0.0], response: "r2")
        XCTAssertNil(cache.get(query: "q2", embedding: [0.0, 0.0, 0.0]),
                     "查询向量为零范数时相似度返回 0，不应命中")
    }

    /// 阈值恰等 0.92：实现使用 `>` 严格大于，等于阈值应不命中
    /// 构造 a=[1,0,0]，b=[0.92, sqrt(1-0.92²), 0]，数学上余弦相似度恰为 0.92
    func testThresholdExactlyEquals() {
        let cache = SemanticCache()
        let a: [Float] = [1.0, 0.0, 0.0]
        let t: Float = 0.92
        let b: [Float] = [t, (1 - t * t).squareRoot(), 0.0]
        cache.set(query: "q", embedding: a, response: "r")
        let result = cache.get(query: "q", embedding: b)
        XCTAssertNil(result, "相似度恰等于阈值 0.92 时，因 `>` 严格大于应不命中")
    }

    /// 容量恰好 100：驱逐条件为 `count >= 100`，第 100 次写入时 count 为 99，不触发驱逐
    func testCapacityExactly100NotEvicted() {
        let cache = SemanticCache()
        let dim = 100
        func makeEmb(_ i: Int) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[i] = 1.0
            return v
        }
        // 写入 100 条（i = 0..<100），第一条不应被驱逐
        for i in 0..<100 {
            cache.set(query: "q\(i)", embedding: makeEmb(i), response: "r\(i)")
        }
        XCTAssertEqual(cache.get(query: "q0", embedding: makeEmb(0)), "r0",
                       "容量恰好为 100 时不应驱逐最早条目")
        XCTAssertEqual(cache.get(query: "q99", embedding: makeEmb(99)), "r99",
                       "最新条目应保留")
    }

    /// 同 query 重复 set：当前实现不去重（按 embedding 分别存储），cache.count 应增加
    /// cache 为 private 无法直接断言 count，故通过两条正交 embedding 各自命中来验证两条记录共存
    func testSameQueryDuplicateSet() {
        let cache = SemanticCache()
        cache.set(query: "dup", embedding: [1.0, 0.0, 0.0], response: "r1")
        cache.set(query: "dup", embedding: [0.0, 1.0, 0.0], response: "r2")
        // 若去重则第一条会被替换，[1,0,0] 将不命中；此处断言两条记录共存（count 增加）
        XCTAssertEqual(cache.get(query: "dup", embedding: [1.0, 0.0, 0.0]), "r1",
                       "不去重：第一条记录仍存在")
        XCTAssertEqual(cache.get(query: "dup", embedding: [0.0, 1.0, 0.0]), "r2",
                       "不去重：第二条记录可命中")
    }
}
