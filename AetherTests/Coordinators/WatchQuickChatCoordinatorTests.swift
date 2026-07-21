import XCTest
@testable import Aether

/// P2-6 Task 4: WatchQuickChatCoordinator 单元测试
///
/// 验证 WatchQuickChatCoordinator 正确封装 `.wcQuickChatReceived` 通知监听：
/// 收到消息后通过 @MainActor 闭包回调通知上层，空 payload 静默忽略，
/// init 后观察者已注册，deinit 后观察者已移除。
@MainActor
final class WatchQuickChatCoordinatorTests: XCTestCase {

    // MARK: - testWatchQuickChatReceivedSetsPendingMessage

    /// 收到 .wcQuickChatReceived 通知（object 为 String）时，应通过 @MainActor 闭包回调通知上层。
    /// 行为等价于原 ChatViewModel 中 quickChatObserver 回调设置 pendingWatchMessage。
    func testWatchQuickChatReceivedSetsPendingMessage() async throws {
        let receivedBox = NonIsolatedBox<String?>(nil)
        let coordinator = WatchQuickChatCoordinator { msg in
            receivedBox.value = msg
        }

        NotificationCenter.default.post(
            name: .wcQuickChatReceived,
            object: "hello from watch"
        )

        // 回调通过 Task { @MainActor } 派发，轮询等待执行完成
        for _ in 0..<20 {
            if receivedBox.value != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        }

        XCTAssertEqual(receivedBox.value, "hello from watch",
                       "收到 Watch 快速对话消息应通过闭包回调通知上层")
    }

    // MARK: - testWatchQuickChatReceivedWithEmptyPayloadNoOp

    /// 收到 .wcQuickChatReceived 通知但 object 非 String 时，应静默忽略（不触发闭包回调）。
    /// 与原 ChatViewModel 行为一致：`if let msg = notification.object as? String` 守卫失败时直接返回。
    func testWatchQuickChatReceivedWithEmptyPayloadNoOp() async throws {
        let receivedBox = NonIsolatedBox<String?>(nil)
        let coordinator = WatchQuickChatCoordinator { msg in
            receivedBox.value = msg
        }

        // object 为非 String 类型（Int），应被忽略
        NotificationCenter.default.post(
            name: .wcQuickChatReceived,
            object: 42
        )
        // object 为 nil，也应被忽略
        NotificationCenter.default.post(
            name: .wcQuickChatReceived,
            object: nil
        )

        // 等待一段时间确保回调不会被触发
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        XCTAssertNil(receivedBox.value,
                     "object 非 String 时应静默忽略，不触发闭包回调")
    }

    // MARK: - testWatchQuickChatObserverRegisteredOnInit

    /// init 后应立即注册通知观察者（token 非 nil）。
    func testWatchQuickChatObserverRegisteredOnInit() {
        let coordinator = WatchQuickChatCoordinator { _ in }

        XCTAssertNotNil(coordinator.token,
                        "init 后应注册 .wcQuickChatReceived 观察者，token 非 nil")
    }

    // MARK: - testDeinitRemovesObserver

    /// deinit 后应移除通知观察者，后续通知不再触发闭包回调。
    func testDeinitRemovesObserver() async throws {
        let receivedBox = NonIsolatedBox<String?>(nil)
        weak var weakCoordinator: WatchQuickChatCoordinator?

        do {
            let coordinator = WatchQuickChatCoordinator { msg in
                receivedBox.value = msg
            }
            weakCoordinator = coordinator
            XCTAssertNotNil(coordinator.token, "前置：init 后 token 应非 nil")
        }

        // 让出主线程，确保 ARC 释放与 deinit 执行
        await Task.yield()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(weakCoordinator, "WatchQuickChatCoordinator 应被正确释放")

        // 释放后发送通知不应触发回调
        NotificationCenter.default.post(
            name: .wcQuickChatReceived,
            object: "after deinit"
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(receivedBox.value,
                     "deinit 后观察者应已移除，通知不再触发闭包回调")
    }
}
