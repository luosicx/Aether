import Foundation

/// Task 24: Aether SDK 消息类型。
///
/// 第三方调用方传入 `AetherClient.chat(messages:)` 的消息结构。
/// `Sendable` 安全，可与 LLMProvider 的 `APIMessage` 互转。
public struct AetherMessage: Sendable, Equatable {
    /// 消息角色
    public enum Role: String, Sendable, Equatable {
        case system
        case user
        case assistant
        case tool
    }

    /// 消息角色
    public let role: Role
    /// 文本内容
    public var content: String
    /// base64 编码图片数组（多模态用，可选）
    public let images: [String]?
    /// 工具调用 ID（`tool` 角色消息必填）
    public let toolCallId: String?
    /// 工具名（`tool` 角色消息必填）
    public let toolName: String?
    /// `assistant` 触发的工具调用列表（可选）
    public let toolCalls: [AetherToolCall]?

    /// 创建一条消息
    /// - Parameters:
    ///   - role: 角色
    ///   - content: 文本内容
    ///   - images: base64 图片数组，多模态用
    ///   - toolCallId: 工具调用 ID
    ///   - toolName: 工具名
    ///   - toolCalls: assistant 触发的工具调用列表
    public init(
        role: Role,
        content: String,
        images: [String]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        toolCalls: [AetherToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.images = images
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.toolCalls = toolCalls
    }

    /// 便捷构造：system 消息
    public static func system(_ content: String) -> AetherMessage {
        AetherMessage(role: .system, content: content)
    }

    /// 便捷构造：user 消息
    public static func user(_ content: String) -> AetherMessage {
        AetherMessage(role: .user, content: content)
    }

    /// 便捷构造：assistant 消息
    public static func assistant(_ content: String) -> AetherMessage {
        AetherMessage(role: .assistant, content: content)
    }

    /// 便捷构造：tool 结果消息
    public static func tool(name: String, callId: String, content: String) -> AetherMessage {
        AetherMessage(role: .tool, content: content, toolCallId: callId, toolName: name)
    }
}

/// 一次工具调用的完整参数
public struct AetherToolCall: Sendable, Equatable {
    /// 工具调用唯一 ID
    public let id: String
    /// 调用类型，通常为 `function`
    public let type: String
    /// 函数名
    public let name: String
    /// JSON 字符串形式的参数
    public let arguments: String

    public init(id: String, type: String = "function", name: String, arguments: String) {
        self.id = id
        self.type = type
        self.name = name
        self.arguments = arguments
    }
}
