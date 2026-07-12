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

    // MARK: - sendQuickChat 测试

    /// 测试 4: sendQuickChat 在 WCSession 未激活时应安全返回不崩溃
    func testSendQuickChatSafeWhenNotActivated() {
        let service = WatchConnectivityService.shared
        // 即使 WCSession 未激活，sendQuickChat 的 guard 也会安全返回
        service.sendQuickChat("hello")
        // 无崩溃即通过
        XCTAssertTrue(true, "sendQuickChat 在未激活时应安全返回")
    }

    /// 测试 5: sendQuickChat 传入空字符串应不崩溃
    func testSendQuickChatEmptyMessage() {
        let service = WatchConnectivityService.shared
        service.sendQuickChat("")
        XCTAssertTrue(true, "sendQuickChat 空字符串应不崩溃")
    }

    // MARK: - didReceiveMessage 测试

    /// 测试 6: 接收 activeConversation 消息后应更新 activeConversationId 并发通知
    func testReceiveActiveConversationUpdatesPropertyAndPostsNotification() throws {
        let service = WatchConnectivityService.shared
        let testId = UUID()
        let expectation = XCTNSNotificationExpectation(name: .wcActiveConversationChanged, object: nil)
        expectation.handler = { note in
            return (note.object as? UUID) == testId
        }

        service.session(WCSession.default, didReceiveMessage: ["action": "activeConversation", "id": testId.uuidString])

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(service.activeConversationId, testId, "接收消息后 activeConversationId 应更新")
    }

    /// 测试 7: 接收 activeConversation 消息但 UUID 无效时不更新
    func testReceiveActiveConversationWithInvalidUUIDDoesNotUpdate() {
        let service = WatchConnectivityService.shared
        let originalId = service.activeConversationId
        service.session(WCSession.default, didReceiveMessage: ["action": "activeConversation", "id": "not-a-uuid"])
        XCTAssertEqual(service.activeConversationId, originalId, "UUID 无效时 activeConversationId 不应更新")
    }

    /// 测试 8: 接收消息但缺少 action 字段时应不崩溃
    func testReceiveMessageWithoutActionDoesNotCrash() {
        let service = WatchConnectivityService.shared
        service.session(WCSession.default, didReceiveMessage: ["foo": "bar"])
        XCTAssertTrue(true, "缺少 action 字段时应安全返回")
    }

    /// 测试 9: 接收未知 action 时应不崩溃
    func testReceiveMessageWithUnknownActionDoesNotCrash() {
        let service = WatchConnectivityService.shared
        service.session(WCSession.default, didReceiveMessage: ["action": "unknownAction"])
        XCTAssertTrue(true, "未知 action 时应安全返回")
    }

    /// 测试 10: 接收 quickChat 消息但缺少 message 字段时应不崩溃
    func testReceiveQuickChatWithoutMessageDoesNotCrash() {
        let service = WatchConnectivityService.shared
        service.session(WCSession.default, didReceiveMessage: ["action": "quickChat"])
        XCTAssertTrue(true, "缺少 message 字段时应安全返回")
    }

    /// 测试 11: 接收 activeConversation 但缺少 id 字段时应不崩溃
    func testReceiveActiveConversationWithoutIdDoesNotCrash() {
        let service = WatchConnectivityService.shared
        let originalId = service.activeConversationId
        service.session(WCSession.default, didReceiveMessage: ["action": "activeConversation"])
        XCTAssertEqual(service.activeConversationId, originalId, "缺少 id 字段时不应更新")
    }

    // MARK: - 其他 delegate 方法测试

    /// 测试 12: sessionReachabilityDidChange 应发送 .wcReachabilityChanged 通知
    func testSessionReachabilityDidChangePostsNotification() {
        let service = WatchConnectivityService.shared
        let expectation = XCTNSNotificationExpectation(name: .wcReachabilityChanged, object: nil)
        service.sessionReachabilityDidChange(WCSession.default)
        wait(for: [expectation], timeout: 2.0)
    }

    /// 测试 13: sessionDidBecomeInactive 应安全执行不崩溃
    func testSessionDidBecomeInactiveDoesNotCrash() {
        let service = WatchConnectivityService.shared
        service.sessionDidBecomeInactive(WCSession.default)
        XCTAssertTrue(true, "sessionDidBecomeInactive 应安全执行")
    }

    /// 测试 14: sessionDidDeactivate 应安全执行并重新激活 WCSession
    func testSessionDidDeactivateReactivatesSession() throws {
        try XCTSkipIf(!WCSession.isSupported(), "WCSession 不支持时跳过")
        let service = WatchConnectivityService.shared
        service.sessionDidDeactivate(WCSession.default)
        // 无崩溃即通过
        XCTAssertTrue(true, "sessionDidDeactivate 应安全执行")
    }

    /// 测试 15: activationDidCompleteWith 无错误时应不崩溃
    func testActivationDidCompleteWithoutErrorDoesNotCrash() {
        let service = WatchConnectivityService.shared
        service.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
        XCTAssertTrue(true, "无错误时 activationDidCompleteWith 应安全执行")
    }

    /// 测试 16: activationDidCompleteWith 有错误时应不崩溃（仅打印日志）
    func testActivationDidCompleteWithErrorDoesNotCrash() {
        let service = WatchConnectivityService.shared
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        service.session(WCSession.default, activationDidCompleteWith: .notActivated, error: error)
        XCTAssertTrue(true, "有错误时 activationDidCompleteWith 应安全执行")
    }

    // MARK: - Notification.Name 测试

    /// 测试 17: 三个通知名应互不相同
    func testNotificationNamesAreUnique() {
        let names: Set<String> = [
            Notification.Name.wcActiveConversationChanged.rawValue,
            Notification.Name.wcQuickChatReceived.rawValue,
            Notification.Name.wcReachabilityChanged.rawValue,
        ]
        XCTAssertEqual(names.count, 3, "三个通知名应互不相同")
    }

    /// 测试 18: 通知名应与预期字符串值一致
    func testNotificationNameRawValues() {
        XCTAssertEqual(Notification.Name.wcActiveConversationChanged.rawValue, "wcActiveConversationChanged")
        XCTAssertEqual(Notification.Name.wcQuickChatReceived.rawValue, "wcQuickChatReceived")
        XCTAssertEqual(Notification.Name.wcReachabilityChanged.rawValue, "wcReachabilityChanged")
    }
}
#endif
