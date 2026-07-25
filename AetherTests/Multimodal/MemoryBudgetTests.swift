import XCTest
@testable import Aether

/// v1.3: MemoryBudget 全局内存预算器测试
final class MemoryBudgetTests: XCTestCase {

    // MARK: - 基本属性

    func testInitWithTotalBudget() async {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.totalMB, 3000)
        XCTAssertEqual(snapshot.usedMB, 0)
        XCTAssertEqual(snapshot.availableMB, 3000)
        XCTAssertEqual(snapshot.peakMB, 0)
        XCTAssertEqual(snapshot.utilization, 0.0)
    }

    func testAvailableComputation() async {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try? await budget.reserve(mb: 1000)
        let available = await budget.available
        XCTAssertEqual(available, 2000)
    }

    // MARK: - reserve / release

    func testReserveSuccess() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        let remaining = try await budget.reserve(mb: 1000)
        XCTAssertEqual(remaining, 2000)
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.usedMB, 1000)
        XCTAssertEqual(snapshot.availableMB, 2000)
    }

    func testReserveExceedsBudget() async {
        let budget = MemoryBudget(totalBudgetMB: 1000)
        do {
            _ = try await budget.reserve(mb: 2000)
            XCTFail("应抛出 memoryBudgetExceeded")
        } catch let error as MultimodalError {
            if case .memoryBudgetExceeded(let requested, let available) = error {
                XCTAssertEqual(requested, 2000)
                XCTAssertEqual(available, 1000)
            } else {
                XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testReserveZeroThrows() async {
        let budget = MemoryBudget(totalBudgetMB: 1000)
        do {
            _ = try await budget.reserve(mb: 0)
            XCTFail("应抛出 memoryBudgetExceeded（mb > 0 检查）")
        } catch let error as MultimodalError {
            if case .memoryBudgetExceeded = error {
                // 符合预期
            } else {
                XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testReserveNegativeThrows() async {
        let budget = MemoryBudget(totalBudgetMB: 1000)
        do {
            _ = try await budget.reserve(mb: -100)
            XCTFail("应抛出 memoryBudgetExceeded（mb > 0 检查）")
        } catch let error as MultimodalError {
            if case .memoryBudgetExceeded = error {
                // 符合预期
            } else {
                XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testReleaseSuccess() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try await budget.reserve(mb: 1500)
        let remaining = await budget.release(mb: 500)
        XCTAssertEqual(remaining, 2000)
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.usedMB, 1000)
    }

    func testReleaseMoreThanUsed() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try await budget.reserve(mb: 500)
        let remaining = await budget.release(mb: 1000)  // 释放超过已用
        XCTAssertEqual(remaining, 3000)
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.usedMB, 0, "释放超过已用时应归零")
    }

    func testReserveReleaseReserve() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try await budget.reserve(mb: 1000)
        _ = await budget.release(mb: 500)
        let remaining = try await budget.reserve(mb: 2500)
        XCTAssertEqual(remaining, 0, "3000 - 500 + 2500 = 0")
    }

    // MARK: - peak 追踪

    func testPeakTracking() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try await budget.reserve(mb: 1500)
        _ = await budget.release(mb: 500)
        _ = try await budget.reserve(mb: 1000)
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.peakMB, 2000, "峰值应为 1500 + 1000 - 500 = 2000... 实际为 2000")
    }

    func testPeakNotExceededByLowerUsage() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try await budget.reserve(mb: 2000)  // 峰值 2000
        _ = await budget.release(mb: 1500)       // used=500, peak=2000
        _ = try await budget.reserve(mb: 500)     // used=1000, peak=2000
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.peakMB, 2000, "峰值不应被低于峰值的使用量刷新")
    }

    // MARK: - reset

    func testReset() async throws {
        let budget = MemoryBudget(totalBudgetMB: 3000)
        _ = try await budget.reserve(mb: 1500)
        await budget.reset()
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.usedMB, 0)
        XCTAssertEqual(snapshot.peakMB, 0)
        XCTAssertEqual(snapshot.availableMB, 3000)
    }

    // MARK: - snapshot

    func testSnapshotUtilization() async throws {
        let budget = MemoryBudget(totalBudgetMB: 4000)
        _ = try await budget.reserve(mb: 1000)
        let snapshot = await budget.snapshot()
        XCTAssertEqual(snapshot.utilization, 0.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.utilizationPercentage, 25.0, accuracy: 0.1)
    }

    func testSnapshotEquatable() {
        let snapshot1 = BudgetSnapshot(totalMB: 3000, usedMB: 1000, availableMB: 2000, peakMB: 1500, utilization: 0.333)
        let snapshot2 = BudgetSnapshot(totalMB: 3000, usedMB: 1000, availableMB: 2000, peakMB: 1500, utilization: 0.333)
        XCTAssertEqual(snapshot1, snapshot2)
    }

    // MARK: - 边界用例

    func testReserveExactAvailable() async throws {
        let budget = MemoryBudget(totalBudgetMB: 1000)
        let remaining = try await budget.reserve(mb: 1000)
        XCTAssertEqual(remaining, 0, "恰好用完预算应返回 0")
    }

    func testReserveAfterFullUsage() async throws {
        let budget = MemoryBudget(totalBudgetMB: 1000)
        _ = try await budget.reserve(mb: 1000)
        do {
            _ = try await budget.reserve(mb: 1)
            XCTFail("预算用完后应无法再 reserve")
        } catch {
            // 符合预期
        }
    }
}
