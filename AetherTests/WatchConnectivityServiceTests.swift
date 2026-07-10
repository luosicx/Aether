#if os(iOS)
import XCTest
import WatchConnectivity
@testable import Aether

/// Day 17: WatchConnectivityService 单元测试
///
/// 注意：WCSession 在模拟器上可能不可用（!WCSession.isSupported()），
/// 测试设计为不依赖 WCSession 激活状态，避免环境差异导致跳过。
/// WatchConnectivityService 是 nonisolated class，不需 await。
final class WatchConnectivityServiceTests: XCTestCase {

    /// 测试 1: sendActiveConversation 后 activeConversationId 更新
    func testSendActiveConversationUpdatesProperty() {
        let service = WatchConnectivityService.shared
        let testId = UUID()
        // sendActiveConversation 会更新 activeConversationId 属性（即使 WCSession 未激活也不影响属性更新）
        service.sendActiveConversation(testId)
        XCTAssertEqual(service.activeConversationId, testId, "sendActiveConversation 后 activeConversationId 应更新")
    }

    /// 测试 2: activate() 在 WCSession 不支持时也安全返回不崩溃，
    /// 支持时 delegate 应已设置
    func testActivateIsSafeWhenUnsupported() throws {
        // 无论 WCSession 是否支持，activate() 都应安全返回不崩溃
        let service = WatchConnectivityService.shared
        service.activate()
        if WCSession.isSupported() {
            XCTAssertNotNil(WCSession.default.delegate, "支持时 activate 后 delegate 应已设置")
        } else {
            // 不支持时无副作用，不崩溃即通过
            XCTAssertTrue(true, "WCSession 不支持时 activate 安全返回")
        }
    }

    /// 测试 3: 调用 didReceiveMessage 后 NotificationCenter 收到 .wcQuickChatReceived
    /// 注意：session(_:didReceiveMessage:) 只调用 NotificationCenter.post，
    /// 不依赖 WCSession 是否激活/支持，故无需 guard WCSession.isSupported()
    func testReceiveMessagePostsNotification() throws {
        let service = WatchConnectivityService.shared
        let expectation = XCTNSNotificationExpectation(name: .wcQuickChatReceived, object: nil)
        expectation.handler = { note in
            // 验证通知 object 为消息文本
            return note.object as? String == "test message"
        }

        // 直接调用 delegate 方法，传入 WCSession.default（即使未激活也能触发通知）
        service.session(WCSession.default, didReceiveMessage: ["action": "quickChat", "message": "test message"])

        // 等待通知（超时 2 秒）
        wait(for: [expectation], timeout: 2.0)
    }
}
#endif
