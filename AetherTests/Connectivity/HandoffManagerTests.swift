#if os(iOS) || os(macOS)
import XCTest
@testable import Aether

/// v2.0 HandoffManager 单元测试
///
/// 验证：
/// - becomeCurrent 创建正确的 NSUserActivity（activityType / userInfo / 资格）
/// - handleContinueActivity 正确解析 HandoffPayload（含错误处理）
/// - invalidate 清除当前 activity
///
/// HandoffManager 为 @MainActor 隔离，测试类标注 @MainActor 同步访问。
@MainActor
final class HandoffManagerTests: XCTestCase {

    // MARK: - HandoffActivityTypes 常量

    /// 测试 1: chatContinue 常量应为 "com.aether.chat.continue"
    func testChatContinueActivityTypeConstant() {
        XCTAssertEqual(
            HandoffActivityTypes.chatContinue,
            "com.aether.chat.continue",
            "chatContinue 常量应为 com.aether.chat.continue"
        )
    }

    // MARK: - becomeCurrent 测试

    /// 测试 2: becomeCurrent 后 currentActivity 应非 nil
    func testBecomeCurrentSetsCurrentActivity() {
        let manager = HandoffManager.shared
        manager.invalidate()

        manager.becomeCurrent(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.0
        )

        XCTAssertNotNil(manager.currentActivity, "becomeCurrent 后 currentActivity 应非 nil")
        manager.invalidate()
    }

    /// 测试 3: becomeCurrent 创建的 activity 其 activityType 应为 chatContinue
    func testBecomeCurrentCreatesActivityWithCorrectType() throws {
        let manager = HandoffManager.shared
        manager.becomeCurrent(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.5
        )

        let activity = try XCTUnwrap(manager.currentActivity)
        XCTAssertEqual(
            activity.activityType,
            HandoffActivityTypes.chatContinue,
            "activityType 应为 chatContinue"
        )

        manager.invalidate()
    }

    /// 测试 4: becomeCurrent 创建的 activity 应 isEligibleForHandoff
    func testBecomeCurrentActivityIsEligibleForHandoff() throws {
        let manager = HandoffManager.shared
        manager.becomeCurrent(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.0
        )

        let activity = try XCTUnwrap(manager.currentActivity)
        XCTAssertTrue(activity.isEligibleForHandoff, "isEligibleForHandoff 应为 true")

        manager.invalidate()
    }

    /// 测试 5: userInfo 应包含 conversationId 且与传入一致
    func testBecomeCurrentUserInfoContainsConversationId() throws {
        let manager = HandoffManager.shared
        let conversationId = UUID()

        manager.becomeCurrent(
            conversationId: conversationId,
            lastMessageId: nil,
            scrollPosition: 0.0
        )

        let activity = try XCTUnwrap(manager.currentActivity)
        let userInfo = try XCTUnwrap(activity.userInfo)
        let storedId = userInfo["conversationId"] as? String
        XCTAssertEqual(
            storedId,
            conversationId.uuidString,
            "userInfo[conversationId] 应等于传入的 uuidString"
        )

        manager.invalidate()
    }

    /// 测试 6: userInfo 应包含 scrollPosition 且与传入一致
    func testBecomeCurrentUserInfoContainsScrollPosition() throws {
        let manager = HandoffManager.shared
        manager.becomeCurrent(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.75
        )

        let activity = try XCTUnwrap(manager.currentActivity)
        let userInfo = try XCTUnwrap(activity.userInfo)
        let storedScroll = try XCTUnwrap(userInfo["scrollPosition"] as? Double)
        XCTAssertEqual(
            storedScroll,
            0.75,
            accuracy: 0.0001,
            "userInfo[scrollPosition] 应等于传入值"
        )

        manager.invalidate()
    }

    /// 测试 7: 传入 lastMessageId 时 userInfo 应包含 lastMessageId
    func testBecomeCurrentUserInfoContainsLastMessageId() throws {
        let manager = HandoffManager.shared
        let conversationId = UUID()
        let lastMessageId = UUID()

        manager.becomeCurrent(
            conversationId: conversationId,
            lastMessageId: lastMessageId,
            scrollPosition: 0.0
        )

        let activity = try XCTUnwrap(manager.currentActivity)
        let userInfo = try XCTUnwrap(activity.userInfo)
        let storedLastMessageId = userInfo["lastMessageId"] as? String
        XCTAssertEqual(
            storedLastMessageId,
            lastMessageId.uuidString,
            "userInfo[lastMessageId] 应等于传入的 uuidString"
        )

        manager.invalidate()
    }

    /// 测试 8: lastMessageId 为 nil 时 userInfo 不应包含 lastMessageId 键
    func testBecomeCurrentOmitsLastMessageIdWhenNil() throws {
        let manager = HandoffManager.shared
        manager.becomeCurrent(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.0
        )

        let activity = try XCTUnwrap(manager.currentActivity)
        let userInfo = try XCTUnwrap(activity.userInfo)
        XCTAssertNil(
            userInfo["lastMessageId"],
            "lastMessageId 为 nil 时 userInfo 不应包含该键"
        )

        manager.invalidate()
    }

    /// 测试 9: 连续调用 becomeCurrent 应替换当前 activity
    func testBecomeCurrentReplacesPreviousActivity() throws {
        let manager = HandoffManager.shared
        let firstId = UUID()
        let secondId = UUID()

        manager.becomeCurrent(conversationId: firstId, lastMessageId: nil, scrollPosition: 0.0)
        let firstActivity = try XCTUnwrap(manager.currentActivity)

        manager.becomeCurrent(conversationId: secondId, lastMessageId: nil, scrollPosition: 0.0)
        let secondActivity = try XCTUnwrap(manager.currentActivity)

        XCTAssertFalse(secondActivity === firstActivity, "第二次 becomeCurrent 应创建新 activity")
        let userInfo = try XCTUnwrap(secondActivity.userInfo)
        XCTAssertEqual(
            userInfo["conversationId"] as? String,
            secondId.uuidString,
            "替换后 currentActivity 应反映第二次的 conversationId"
        )

        manager.invalidate()
    }

    // MARK: - handleContinueActivity 测试

    /// 测试 10: handleContinueActivity 应正确解析有效的 activity
    func testHandleContinueActivityParsesValidPayload() throws {
        let manager = HandoffManager.shared
        let conversationId = UUID()
        let lastMessageId = UUID()

        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = [
            "conversationId": conversationId.uuidString,
            "lastMessageId": lastMessageId.uuidString,
            "scrollPosition": 0.42,
        ]

        let payload = try XCTUnwrap(manager.handleContinueActivity(activity))
        XCTAssertEqual(payload.conversationId, conversationId)
        XCTAssertEqual(payload.lastMessageId, lastMessageId)
        XCTAssertEqual(payload.scrollPosition, 0.42, accuracy: 0.0001)
    }

    /// 测试 11: activityType 不匹配时应返回 nil
    func testHandleContinueActivityReturnsNilForWrongType() {
        let manager = HandoffManager.shared
        let activity = NSUserActivity(activityType: "com.aether.conversation")
        activity.userInfo = [
            "conversationId": UUID().uuidString,
            "scrollPosition": 0.0,
        ]

        XCTAssertNil(
            manager.handleContinueActivity(activity),
            "activityType 不匹配时应返回 nil"
        )
    }

    /// 测试 12: 缺少 conversationId 时应返回 nil
    func testHandleContinueActivityReturnsNilForMissingConversationId() {
        let manager = HandoffManager.shared
        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = [
            "scrollPosition": 0.0,
        ]

        XCTAssertNil(
            manager.handleContinueActivity(activity),
            "缺少 conversationId 时应返回 nil"
        )
    }

    /// 测试 13: conversationId 为无效 UUID 字符串时应返回 nil
    func testHandleContinueActivityReturnsNilForInvalidConversationId() {
        let manager = HandoffManager.shared
        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = [
            "conversationId": "not-a-uuid",
            "scrollPosition": 0.0,
        ]

        XCTAssertNil(
            manager.handleContinueActivity(activity),
            "conversationId 非法时应返回 nil"
        )
    }

    /// 测试 14: lastMessageId 缺失时 payload.lastMessageId 应为 nil
    func testHandleContinueActivityHandlesMissingLastMessageId() throws {
        let manager = HandoffManager.shared
        let conversationId = UUID()

        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = [
            "conversationId": conversationId.uuidString,
            "scrollPosition": 0.0,
        ]

        let payload = try XCTUnwrap(manager.handleContinueActivity(activity))
        XCTAssertEqual(payload.conversationId, conversationId)
        XCTAssertNil(payload.lastMessageId, "缺少 lastMessageId 时 payload.lastMessageId 应为 nil")
        XCTAssertEqual(payload.scrollPosition, 0.0, accuracy: 0.0001)
    }

    /// 测试 15: 缺少 scrollPosition 时应默认为 0.0
    func testHandleContinueActivityDefaultsScrollPositionToZero() throws {
        let manager = HandoffManager.shared
        let conversationId = UUID()

        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = [
            "conversationId": conversationId.uuidString,
        ]

        let payload = try XCTUnwrap(manager.handleContinueActivity(activity))
        XCTAssertEqual(
            payload.scrollPosition,
            0.0,
            accuracy: 0.0001,
            "缺少 scrollPosition 时应默认 0.0"
        )
    }

    /// 测试 16: lastMessageId 为无效 UUID 时应视为 nil（不阻断解析）
    func testHandleContinueActivityHandlesInvalidLastMessageId() throws {
        let manager = HandoffManager.shared
        let conversationId = UUID()

        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = [
            "conversationId": conversationId.uuidString,
            "lastMessageId": "not-a-uuid",
            "scrollPosition": 0.0,
        ]

        let payload = try XCTUnwrap(manager.handleContinueActivity(activity))
        XCTAssertEqual(payload.conversationId, conversationId)
        XCTAssertNil(payload.lastMessageId, "lastMessageId 非法时应为 nil")
    }

    /// 测试 17: userInfo 为 nil 时应返回 nil
    func testHandleContinueActivityReturnsNilForNilUserInfo() {
        let manager = HandoffManager.shared
        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.userInfo = nil

        XCTAssertNil(
            manager.handleContinueActivity(activity),
            "userInfo 为 nil 时应返回 nil"
        )
    }

    // MARK: - invalidate 测试

    /// 测试 18: invalidate 后 currentActivity 应为 nil
    func testInvalidateClearsCurrentActivity() {
        let manager = HandoffManager.shared
        manager.becomeCurrent(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.0
        )
        XCTAssertNotNil(manager.currentActivity)

        manager.invalidate()
        XCTAssertNil(manager.currentActivity, "invalidate 后 currentActivity 应为 nil")
    }

    /// 测试 19: 无当前 activity 时 invalidate 应安全返回不崩溃
    func testInvalidateWhenNoCurrentActivityIsSafe() {
        let manager = HandoffManager.shared
        manager.invalidate()
        manager.invalidate()
        XCTAssertNil(
            manager.currentActivity,
            "无 activity 时 invalidate 应安全且 currentActivity 仍为 nil"
        )
    }

    // MARK: - HandoffPayload 测试

    /// 测试 20: HandoffPayload 应正确存储字段
    func testHandoffPayloadStoresFields() {
        let conversationId = UUID()
        let lastMessageId = UUID()
        let payload = HandoffPayload(
            conversationId: conversationId,
            lastMessageId: lastMessageId,
            scrollPosition: 0.5
        )
        XCTAssertEqual(payload.conversationId, conversationId)
        XCTAssertEqual(payload.lastMessageId, lastMessageId)
        XCTAssertEqual(payload.scrollPosition, 0.5, accuracy: 0.0001)
    }

    /// 测试 21: HandoffPayload lastMessageId 为 nil 时应可正常构造
    func testHandoffPayloadAcceptsNilLastMessageId() {
        let payload = HandoffPayload(
            conversationId: UUID(),
            lastMessageId: nil,
            scrollPosition: 0.0
        )
        XCTAssertNil(payload.lastMessageId)
    }
}
#endif
