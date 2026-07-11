import XCTest
@testable import Aether

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

    // MARK: - 边缘测试补充

    // clear 应清除所有已记录指标
    func testClearRemovesAllMetrics() async {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        _ = await monitor.measure("metric_a") { return 1 }
        _ = await monitor.measure("metric_b") { return 2 }
        // 确认有 2 条指标
        let before = await monitor.getMetrics()
        XCTAssertEqual(before.count, 2)
        // clear 后应清空
        await monitor.clear()
        let after = await monitor.getMetrics()
        XCTAssertTrue(after.isEmpty, "clear 后指标应全部清除")
    }

    // 同名 measure 应覆盖前一次记录的耗时值
    func testMeasureOverwritesSameName() async {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        // 第一次记录（短耗时）
        _ = await monitor.measure("same_op") { return 1 }
        let first = await monitor.getMetrics()
        let firstElapsed = first["same_op"]
        // 第二次同名记录（长耗时），应覆盖
        _ = try? await monitor.measure("same_op") {
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
            return 2
        }
        let second = await monitor.getMetrics()
        XCTAssertEqual(second.count, 1, "同名指标应覆盖而非新增")
        XCTAssertNotNil(second["same_op"])
        XCTAssertGreaterThan(second["same_op"] ?? 0, firstElapsed ?? 0, "第二次耗时应大于第一次")
    }

    // measure 返回值应正确透传 block 的返回值
    func testMeasureReturnsCorrectResult() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        // 测试 String 返回值
        let strResult = try await monitor.measure("string_op") {
            return "hello"
        }
        XCTAssertEqual(strResult, "hello")
        // 测试 Int 返回值
        let intResult = try await monitor.measure("int_op") {
            return 100
        }
        XCTAssertEqual(intResult, 100)
        // 测试 Optional 返回值
        let optResult = try await monitor.measure("opt_op") {
            return Optional<String>.none
        }
        XCTAssertNil(optResult)
    }

    // 空指标时 getMetrics 应返回空字典
    func testGetMetricsEmptyWhenCleared() async {
        let monitor = PerformanceMonitor.shared
        await monitor.clear()
        let metrics = await monitor.getMetrics()
        XCTAssertTrue(metrics.isEmpty, "clear 后 getMetrics 应返回空字典")
    }
}
