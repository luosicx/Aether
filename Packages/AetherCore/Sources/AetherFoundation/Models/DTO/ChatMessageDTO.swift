import Foundation

/// 平台无关的工具调用 DTO
///
/// 表示助手消息触发的工具调用，独立于具体 LLM provider 的 ToolCallParam。
/// arguments 使用 AnyCodable 处理 JSON 动态类型。
public struct ToolCallDTO: Sendable, Codable {
    public let id: String
    public let name: String
    public let arguments: String  // JSON 字符串，保持跨平台兼容

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// 平台无关的聊天消息 DTO
///
/// 跨平台统一的消息契约。toolCalls 为可选数组，仅 assistant 角色消息可能携带。
/// imageData/attachedImage 用 base64 字符串表示，便于跨平台传输。
public struct ChatMessageDTO: Sendable, Codable, Identifiable {
    public let id: UUID
    public var conversationId: UUID
    public var role: String  // "user" | "assistant" | "system" | "tool"
    public var content: String
    public var toolCalls: [ToolCallDTO]?
    public var toolCallId: String?
    public var toolName: String?
    public var imageData: String?      // base64 编码
    public var attachedImage: String?   // base64 编码
    public var feedback: Int?           // -1 | 0 | 1
    public var injectionChecked: Bool?
    public var createdAt: Date

    public init(
        id: UUID,
        conversationId: UUID,
        role: String,
        content: String,
        toolCalls: [ToolCallDTO]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        imageData: String? = nil,
        attachedImage: String? = nil,
        feedback: Int? = nil,
        injectionChecked: Bool? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.imageData = imageData
        self.attachedImage = attachedImage
        self.feedback = feedback
        self.injectionChecked = injectionChecked
        self.createdAt = createdAt
    }
}
