#if os(iOS)
import XCTest
import WatchConnectivity
@testable import AIBuilder

/// Day 17: WatchConnectivityService 单元测试
///
/// 注意：WCSession 在模拟器上可能不可用（!WCSession.isSupported()），测试用 XCTSkip 跳过。
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

    /// 测试 2: activate 后 WCSession.default.delegate 已设置（若 WCSession.isSupported()）
    func testActivateSetsDelegate() throws {
        guard WCSession.isSupported() else {
            throw XCTSkip("WCSession 在当前环境不支持，跳过")
        }
        let service = WatchConnectivityService.shared
        service.activate()
        // activate 后 delegate 应已设置
        XCTAssertNotNil(WCSession.default.delegate, "activate 后 WCSession.default.delegate 应已设置")
    }

    /// 测试 3: 调用 didReceiveMessage 后 NotificationCenter 收到 .wcQuickChatReceived
    func testReceiveMessagePostsNotification() throws {
        guard WCSession.isSupported() else {
            throw XCTSkip("WCSession 在当前环境不支持，跳过")
        }
        let service = WatchConnectivityService.shared
        // 激活 session 以确保 delegate 生效
        service.activate()

        let expectation = XCTNSNotificationExpectation(name: .wcQuickChatReceived, object: nil)
        expectation.handler = { note in
            // 验证通知 object 为消息文本
            return note.object as? String == "test message"
        }

        // 模拟接收 quickChat 消息
        service.session(WCSession.default, didReceiveMessage: ["action": "quickChat", "message": "test message"])

        // 等待通知（超时 2 秒）
        wait(for: [expectation], timeout: 2.0)
    }
}
#endif
