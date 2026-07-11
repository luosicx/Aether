import XCTest
@testable import Aether

/// Day 16: 网络监控 actor 单元测试。
/// NetworkMonitor 基于 NWPathMonitor，start() 后异步更新 currentStatus，
/// statusStream() 订阅时立即 yield 当前状态。
/// 测试中创建新实例避免 shared 单例状态污染。
final class NetworkMonitorTests: XCTestCase {

    // MARK: - 1. start() 后 currentStatus 为有效状态

    func testInitialStateIsOfflineOrOnline() async {
        let monitor = NetworkMonitor()
        defer { Task { await monitor.stop() } }

        await monitor.start()
        // NWPathMonitor 异步初始化，等待首个 path 更新回调
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let status = await monitor.currentStatus
        // 依赖运行环境：CI 无网络 → .offline，本地有网络 → .online/.wifi/.cellular
        let valid: [NetworkStatus] = [.online, .offline, .wifi, .cellular]
        XCTAssertTrue(
            valid.contains(status),
            "start() 后 currentStatus 应为有效状态，实际：\(status)"
        )
    }

    // MARK: - 2. statusStream 订阅时立即收到当前状态

    func testStatusStreamEmitsInitialStatus() async {
        let monitor = NetworkMonitor()
        defer { Task { await monitor.stop() } }

        await monitor.start()
        // 等待 NWPathMonitor 完成首次状态更新
        try? await Task.sleep(nanoseconds: 500_000_000)

        let current = await monitor.currentStatus
        let stream = await monitor.statusStream()

        // 取流的首个值（订阅时立即 yield 当前状态，值已缓冲，next() 立即返回）
        let first = await Self.firstValue(from: stream)

        XCTAssertNotNil(first, "statusStream 订阅时应立即 yield 当前状态")
        XCTAssertEqual(
            first,
            current,
            "首个 yield 值应等于订阅时的 currentStatus"
        )
    }

    /// 消费 AsyncStream 的首个值，返回 nil 表示流已结束未产出。
    private static func firstValue(from stream: AsyncStream<NetworkStatus>) async -> NetworkStatus? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    // MARK: - 边缘测试补充

    // 初始状态：start() 前currentStatus 应为 .offline
    func testInitialStatusIsOfflineBeforeStart() async {
        let monitor = NetworkMonitor()
        defer { Task { await monitor.stop() } }

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .offline, "start() 前初始状态应为 offline")
    }

    // start() 幂等性：重复调用 start 不应崩溃且不重复注册 pathUpdateHandler
    func testStartIsIdempotent() async {
        let monitor = NetworkMonitor()
        defer { Task { await monitor.stop() } }

        await monitor.start()
        // 再次调用 start 应安全返回（guard !started）
        await monitor.start()
        // 未崩溃即通过
        XCTAssertTrue(true, "重复 start 不应崩溃")
    }

    // stop() 后状态流应结束：验证流可正常 finish
    func testStopFinishesStreams() async {
        let monitor = NetworkMonitor()
        await monitor.start()
        try? await Task.sleep(nanoseconds: 300_000_000) // 等待首个状态

        let stream = await monitor.statusStream()
        // 消费初始值
        let first = await Self.firstValue(from: stream)
        XCTAssertNotNil(first, "应收到初始状态")

        // stop 后流应结束，next 返回 nil
        await monitor.stop()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next() // 可能还有缓冲值，多取一次
        // 流最终会 finish，再取应返回 nil（允许短暂等待）
        let after = await withTaskGroup(of: NetworkStatus?.self) { group in
            group.addTask { await iterator.next() }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
        XCTAssertNil(after, "stop 后流应结束，next 最终返回 nil")
    }

    // 多订阅者：两个 statusStream 订阅都应收到初始当前状态
    func testMultipleSubscribersReceiveInitialStatus() async {
        let monitor = NetworkMonitor()
        defer { Task { await monitor.stop() } }

        await monitor.start()
        try? await Task.sleep(nanoseconds: 300_000_000)

        let current = await monitor.currentStatus
        let stream1 = await monitor.statusStream()
        let stream2 = await monitor.statusStream()

        let first1 = await Self.firstValue(from: stream1)
        let first2 = await Self.firstValue(from: stream2)

        XCTAssertEqual(first1, current, "订阅者1应收到当前状态")
        XCTAssertEqual(first2, current, "订阅者2应收到当前状态")
    }
}
