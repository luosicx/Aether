import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

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

    /// 无 TTL 驱逐：写入后短暂等待仍应命中（实现无时间戳/TTL 机制）
    func testNoTimeBasedEviction() async {
        let cache = SemanticCache()
        cache.set(query: "q", embedding: [1.0, 0.0, 0.0], response: "r")
        // 短暂等待验证无 TTL 过期
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        let result = cache.get(query: "q", embedding: [1.0, 0.0, 0.0])
        XCTAssertEqual(result, "r", "无 TTL 机制，短暂等待后应仍命中")
    }

    /// 阈值略高于 0.92（0.93）应命中
    func testThresholdSlightlyAbove() {
        let cache = SemanticCache()
        let a: [Float] = [1.0, 0.0, 0.0]
        let cos: Float = 0.93
        let b: [Float] = [cos, (1 - cos * cos).squareRoot(), 0.0]
        cache.set(query: "q", embedding: a, response: "hit")
        let result = cache.get(query: "q", embedding: b)
        XCTAssertEqual(result, "hit", "相似度 0.93 > 0.92 应命中")
    }

    /// 阈值略低于 0.92（0.91）应不命中
    func testThresholdSlightlyBelow() {
        let cache = SemanticCache()
        let a: [Float] = [1.0, 0.0, 0.0]
        let cos: Float = 0.91
        let b: [Float] = [cos, (1 - cos * cos).squareRoot(), 0.0]
        cache.set(query: "q", embedding: a, response: "hit")
        let result = cache.get(query: "q", embedding: b)
        XCTAssertNil(result, "相似度 0.91 < 0.92 应不命中")
    }

    /// 高维向量（1024 维）应正确计算相似度
    func testHighDimensionVectors() {
        let cache = SemanticCache()
        let dim = 1024
        // 构造两个几乎相同的向量（仅最后一维略不同）
        var a = [Float](repeating: 0.01, count: dim)
        var b = [Float](repeating: 0.01, count: dim)
        a[dim - 1] = 1.0
        b[dim - 1] = 0.99
        cache.set(query: "q", embedding: a, response: "high-dim-hit")
        // 两个向量相似度应极高（> 0.92）
        let result = cache.get(query: "q", embedding: b)
        XCTAssertEqual(result, "high-dim-hit", "高维高相似向量应命中")
    }

    /// 负相似度（方向相反）应返回 0 以下，不命中
    func testNegativeSimilarityNotHit() {
        let cache = SemanticCache()
        cache.set(query: "q", embedding: [1.0, 0.0, 0.0], response: "r")
        // b = [-1, 0, 0]，余弦相似度 = -1
        let result = cache.get(query: "q", embedding: [-1.0, 0.0, 0.0])
        XCTAssertNil(result, "负相似度不应命中")
    }

    /// 并发安全：多个 Task 交替 set/get 不应崩溃，最终数据一致
    func testConcurrentSetGetNoCrash() async {
        let cache = SemanticCache()
        let dim = 10
        func makeEmb(_ i: Int) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[i % dim] = 1.0
            return v
        }
        // 并发写入 50 条 + 读取
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    cache.set(query: "q\(i)", embedding: makeEmb(i), response: "r\(i)")
                }
            }
            for i in 0..<50 {
                group.addTask { @MainActor in
                    _ = cache.get(query: "q\(i)", embedding: makeEmb(i))
                }
            }
        }
        // 验证写入的数据可被读出
        // 注：并发操作后部分条目可能因容量驱逐或时序返回不同值，仅验证不 crash + q0 可读
        let result = cache.get(query: "q0", embedding: makeEmb(0))
        XCTAssertEqual(result, "r0", "并发操作后 q0 数据应一致")
        // q49 可能因容量驱逐或并发时序返回不同值，仅验证不 crash
        let _ = cache.get(query: "q49", embedding: makeEmb(49))
    }

    /// 先写入再覆盖：同 query 同 embedding 再次 set 时追加而非替换（实现不去重）
    func testSameQuerySameEmbeddingAppends() {
        let cache = SemanticCache()
        let emb: [Float] = [1.0, 0.0, 0.0]
        cache.set(query: "q", embedding: emb, response: "first")
        cache.set(query: "q", embedding: emb, response: "second")
        // 两条完全相同 embedding 的记录共存，get 返回第一条匹配
        let result = cache.get(query: "q", embedding: emb)
        XCTAssertEqual(result, "first", "两条相同 embedding 共存时返回第一条（迭代顺序）")
    }

    /// 容量驱逐后旧条目不可命中
    func testEvictedEntryNotHit() {
        let cache = SemanticCache()
        let dim = 101
        func makeEmb(_ i: Int) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[i] = 1.0
            return v
        }
        // 写入 101 条，第 0 条被驱逐
        for i in 0..<101 {
            cache.set(query: "q\(i)", embedding: makeEmb(i), response: "r\(i)")
        }
        // 驱逐后尝试读取前 2 条（应都不可命中，因为 i=0 被驱逐，i=1 保留）
        XCTAssertNil(cache.get(query: "q0", embedding: makeEmb(0)), "i=0 应已被驱逐")
        XCTAssertNotNil(cache.get(query: "q1", embedding: makeEmb(1)), "i=1 应保留")
    }
}
