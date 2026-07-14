import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Day 11: SemanticCache 单元测试
@MainActor
final class SemanticCacheTests: XCTestCase {
    func testMissOnEmptyCache() {
        let cache = SemanticCache()
        let result = cache.get(query: "你好", embedding: [1.0, 0.0, 0.0])
        XCTAssertNil(result, "空缓存应未命中")
    }

    func testHitOnExactMatch() {
        let cache = SemanticCache()
        let embedding: [Float] = [1.0, 0.0, 0.0]
        cache.set(query: "你好", embedding: embedding, response: "你好啊")
        let result = cache.get(query: "你好", embedding: embedding)
        XCTAssertEqual(result, "你好啊", "完全相同的 embedding 应命中")
    }

    func testMissOnLowSimilarity() {
        let cache = SemanticCache()
        cache.set(query: "你好", embedding: [1.0, 0.0, 0.0], response: "你好啊")
        // 几乎正交的 embedding 应未命中
        let result = cache.get(query: "天气", embedding: [0.0, 1.0, 0.0])
        XCTAssertNil(result, "低相似度应未命中")
    }

    func testHitOnHighSimilarity() {
        let cache = SemanticCache()
        cache.set(query: "你好", embedding: [1.0, 0.0, 0.0], response: "你好啊")
        // 相似度 > 0.92 应命中
        let result = cache.get(query: "你好啊", embedding: [0.99, 0.01, 0.0])
        XCTAssertEqual(result, "你好啊", "高相似度应命中")
    }

    func testCapacityEviction() {
        let cache = SemanticCache()
        // 用 101 维正交单位向量：entry i 仅在位置 i 为 1
        // 这样任意两条 embedding 余弦相似度为 0，不会误命中
        let dim = 101
        func makeEmb(_ i: Int) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[i] = 1.0
            return v
        }
        // 写入 101 条，第一条应被驱逐
        for i in 0..<101 {
            cache.set(query: "q\(i)", embedding: makeEmb(i), response: "r\(i)")
        }
        // 第一条（i=0）应被驱逐，未命中
        let result0 = cache.get(query: "q0", embedding: makeEmb(0))
        XCTAssertNil(result0, "超过容量应驱逐最早的条目")
        // 最后一条应仍在
        let result100 = cache.get(query: "q100", embedding: makeEmb(100))
        XCTAssertEqual(result100, "r100", "最新条目应保留")
    }
}
