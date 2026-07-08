import Foundation
import SwiftData

/// 持久化会话，含标题、系统提示词、置顶状态、消息列表
@Model
final class Conversation {
    /// 会话唯一标识
    var id: UUID
    /// 会话标题，显示在侧边栏
    var title: String
    /// 系统提示词，注入到对话首条 system 消息
    var systemPrompt: String
    /// 会话创建时间
    var createdAt: Date
    /// Day 9: 是否置顶。置顶会话在侧边栏排在最上方。
    var isPinned: Bool = false
    /// 消息列表；cascade 删除规则，删除 Conversation 时级联删除所有 ChatMessage
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]

    /// 创建 Conversation 实例
    /// - Parameters:
    ///   - title: 会话标题，默认 "新对话"
    ///   - systemPrompt: 系统提示词，默认 "你是一个有帮助的AI助手。"
    init(title: String = "新对话", systemPrompt: String = "你是一个有帮助的AI助手。") {
        self.id = UUID()
        self.title = title
        self.systemPrompt = systemPrompt
        self.createdAt = Date()
        self.isPinned = false
        self.messages = []
    }

    // MARK: - Day 18: NSUserActivity (Handoff / 搜索延续)
    /// 构造 NSUserActivity，用于 Handoff 与 Spotlight 搜索延续。
    /// userInfo 携带 conversationId / title / lastMessage，供 ChatView 接收后切换到对应会话。
    var userActivity: NSUserActivity {
        let activity = NSUserActivity(activityType: "com.aibuilder.conversation")
        activity.title = title
        activity.userInfo = [
            "conversationId": id.uuidString,
            "title": title
        ]
        if let lastMsg = messages.last {
            activity.userInfo?["lastMessage"] = lastMsg.content
        }
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        return activity
    }
}

// MARK: - Day 9: 用户偏好记忆
/// 持久化用户的语气偏好、偏好工具与自定义事实，注入系统提示词以个性化 AI 回复
@Model
final class UserPreference {
    /// 偏好语气："正式" / "轻松" / "默认"
    var preferredTone: String = "默认"
    /// 偏好工具名数组（来自 ToolRegistry.allToolDefs 的 function.name）
    var preferredTools: [String] = []
    /// 用户自定义事实（如"我是素食者"）
    var customFact: String = ""

    /// 创建 UserPreference 实例，所有字段均初始化为默认值
    /// （preferredTone = "默认"，preferredTools = []，customFact = ""）
    init() {
        self.preferredTone = "默认"
        self.preferredTools = []
        self.customFact = ""
    }
}
