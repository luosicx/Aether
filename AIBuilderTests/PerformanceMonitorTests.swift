import XCTest
@testable import AIBuilder

/// Day 19: PerformanceMonitor 单元测试
final class PerformanceMonitorTests: XCTestCase {

    /// measure 应记录异步操作耗时，且耗时合理（> 50ms）
    func testMeasureRecordsElapsedTime() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        // 测量一个 sleep 0.1s 的 block
        let result = try await monitor.measure("startup") {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            return 42
        }
        XCTAssertEqual(result, 42)
        let metrics = await monitor.getMetrics()
        XCTAssertNotNil(metrics["startup"], "measure 后应记录 startup 指标")
        let elapsed = metrics["startup"] ?? 0
        XCTAssertGreaterThan(elapsed, 50.0, "0.1s 操作耗时应 > 50ms，实际 \(elapsed)ms")
    }

    /// getMetrics 应返回所有已记录指标
    func testGetMetricsReturnsAll() async {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        _ = await monitor.measure("first") { return 1 }
        _ = await monitor.measure("second") { return 2 }
        let metrics = await monitor.getMetrics()
        XCTAssertEqual(metrics.count, 2, "应记录两个指标")
        XCTAssertNotNil(metrics["first"])
        XCTAssertNotNil(metrics["second"])
    }

    /// measure 在 block 抛错时应重新抛出错误，且不记录该指标
    func testMeasureRethrowsOnError() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        struct TestError: Error {}
        do {
            _ = try await monitor.measure("failing") {
                throw TestError()
            }
            XCTFail("应抛出错误")
        } catch {
            // 预期抛错
        }
        let metrics = await monitor.getMetrics()
        XCTAssertTrue(metrics.isEmpty, "block 抛错时不应记录指标，实际 \(metrics)")
    }
}
