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
    /// 未读消息数。大于 0 时在会话行末尾显示胶囊徽标。
    var unreadCount: Int = 0
    /// Day 23: 手动排序字段。默认 0，拖拽排序后按列表顺序赋值 0,1,2…
    /// 排序优先级：isPinned > order > createdAt
    var order: Int = 0
    /// Task 21: 父对话 ID（分叉来源），nil 表示非分叉对话
    var parentConversationID: UUID?
    /// Task 21: 分叉点的消息 ID（在父对话中的哪条消息处分叉），nil 表示非分叉对话
    var parentMessageID: UUID?
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
        self.unreadCount = 0
        self.messages = []
    }

    // MARK: - Day 18: NSUserActivity (Handoff / 搜索延续)
    /// 构造 NSUserActivity，用于 Handoff 与 Spotlight 搜索延续。
    /// userInfo 携带 conversationId / title / lastMessage，供 ChatView 接收后切换到对应会话。
    var userActivity: NSUserActivity {
        let activity = NSUserActivity(activityType: "com.aether.conversation")
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
    /// 唯一标识
    @Attribute(.unique) var id: UUID = UUID()
    /// 偏好语气："正式" / "轻松" / "默认"
    var preferredTone: String = "默认"
    /// 偏好工具名数组（来自 ToolRegistry.allToolDefs 的 function.name）
    var preferredTools: [String] = []
    /// 用户自定义事实（如"我是素食者"）
    var customFact: String = ""
    /// Task 6: AI 人设名称，如"小以太"
    var aiPersona: String = ""
    /// Task 6: AI 性格描述
    var aiPersonaDescription: String = ""
    /// Task 6: 自定义头像二进制数据（可选）
    var avatarData: Data? = nil
    /// Task 6: 主题名称：deepSpace / dawn / aurora
    var themeName: String = "deepSpace"
    /// Task 6: 气泡样式：liquidGlass / minimal / card
    var bubbleStyle: String = "liquidGlass"
    /// Task 6: 字体大小（pt）
    var fontSize: Double = 16.0
    /// Task 6: 行距倍数
    var lineHeight: Double = 1.5

    /// 创建 UserPreference 实例，所有字段均初始化为默认值
    /// - Parameters:
    ///   - preferredTone: 偏好语气，默认 "默认"
    ///   - preferredTools: 偏好工具名数组，默认 []
    ///   - customFact: 自定义事实，默认 ""
    ///   - aiPersona: AI 人设名称，默认 ""
    ///   - aiPersonaDescription: AI 性格描述，默认 ""
    ///   - avatarData: 自定义头像数据，默认 nil
    ///   - themeName: 主题名称，默认 "deepSpace"
    ///   - bubbleStyle: 气泡样式，默认 "liquidGlass"
    ///   - fontSize: 字体大小，默认 16.0
    ///   - lineHeight: 行距倍数，默认 1.5
    // NOSONAR: Swift @Model 需显式 init；10 个字段均有默认值，调用方多用默认值或部分参数
    init(
        preferredTone: String = "默认",
        preferredTools: [String] = [],
        customFact: String = "",
        aiPersona: String = "",
        aiPersonaDescription: String = "",
        avatarData: Data? = nil,
        themeName: String = "deepSpace",
        bubbleStyle: String = "liquidGlass",
        fontSize: Double = 16.0,
        lineHeight: Double = 1.5
    ) {
        self.preferredTone = preferredTone
        self.preferredTools = preferredTools
        self.customFact = customFact
        self.aiPersona = aiPersona
        self.aiPersonaDescription = aiPersonaDescription
        self.avatarData = avatarData
        self.themeName = themeName
        self.bubbleStyle = bubbleStyle
        self.fontSize = fontSize
        self.lineHeight = lineHeight
    }
}
