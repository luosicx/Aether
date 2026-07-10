import XCTest
@testable import Aether

/// Day 18 Task 13: Conversation.userActivity 计算属性单元测试
/// 验证 NSUserActivity 的 activityType / userInfo / Handoff & Search 资格配置正确。
final class ConversationActivityTests: XCTestCase {

    // 1. userActivity.activityType 应为 "com.aether.conversation"
    func testUserActivityTypeIsCorrect() {
        let conversation = Conversation(title: "测试会话", systemPrompt: "你是助手")
        let activity = conversation.userActivity
        XCTAssertEqual(activity.activityType, "com.aether.conversation")
    }

    // 2. userActivity.userInfo 应包含 conversationId，值等于 conversation.id.uuidString
    func testUserActivityUserInfoContainsConversationId() {
        let conversation = Conversation(title: "测试会话", systemPrompt: "你是助手")
        let activity = conversation.userActivity
        let userInfo = activity.userInfo
        let conversationId = userInfo?["conversationId"] as? String
        XCTAssertEqual(conversationId, conversation.id.uuidString,
                       "userInfo[conversationId] 应等于 conversation.id.uuidString")
    }

    // 3. userActivity 应同时具备 Handoff 与 Search 资格
    func testUserActivityIsEligibleForHandoff() {
        let conversation = Conversation(title: "测试会话", systemPrompt: "你是助手")
        let activity = conversation.userActivity
        XCTAssertTrue(activity.isEligibleForHandoff, "isEligibleForHandoff 应为 true")
        XCTAssertTrue(activity.isEligibleForSearch, "isEligibleForSearch 应为 true")
    }
}
