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
}
