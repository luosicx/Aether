import Foundation
import SwiftData

/// 持久化聊天消息，关联 Conversation，支持文本/图片/工具调用
@Model
final class ChatMessage {
    /// 消息唯一标识
    var id: UUID
    /// 消息角色：system / user / assistant / tool
    var role: String
    /// 文本内容
    var content: String
    /// 消息创建时间
    var timestamp: Date
    /// Day 5 补充A 之前的图片数据，base64 编码后随请求下发
    var imageData: Data?
    /// Day 5 补充A：用户从相册选择的附带图片（SwiftData @Model 自动迁移）
    var attachedImage: Data?
    /// assistant 触发的工具调用列表 JSON 数据，用于 ReAct 多轮上下文
    var toolCallData: Data?
    /// tool 角色消息对应的工具调用 ID
    var toolCallId: String?
    /// tool 角色消息对应的工具名
    var toolName: String?
    /// Task 7: 标记该消息是否已通过提示注入检测并继续发送
    var injectionChecked: Bool?
    /// 反向关联所属 Conversation
    var conversation: Conversation?

    /// 创建 ChatMessage 实例
    /// - Parameters:
    ///   - role: 消息角色（必填），system / user / assistant / tool
    ///   - content: 文本内容（必填）
    ///   - imageData: Day 5 补充A 之前的图片数据，可选
    ///   - attachedImage: 用户从相册选择的附带图片，可选
    ///   - toolCallData: assistant 触发的工具调用列表 JSON 数据，可选
    ///   - toolCallId: tool 角色消息对应的工具调用 ID，可选
    ///   - toolName: tool 角色消息对应的工具名，可选
    init(role: String, content: String, imageData: Data? = nil, attachedImage: Data? = nil, toolCallData: Data? = nil, toolCallId: String? = nil, toolName: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.imageData = imageData
        self.attachedImage = attachedImage
        self.toolCallData = toolCallData
        self.toolCallId = toolCallId
        self.toolName = toolName
    }

    /// 转换为发往 LLM 的 APIMessage
    /// 合并 imageData 与 attachedImage 的 base64 到 images 字段，从 toolCallData 反序列化 toolCalls
    /// - Returns: 与 LLM API 直接对应的 APIMessage
    func toAPIMessage() -> APIMessage {
        // 合并 imageData 与 attachedImage 的 base64，统一通过 images 字段下发
        var base64Images: [String] = []
        if let data = imageData { base64Images.append(data.base64EncodedString()) }
        if let data = attachedImage { base64Images.append(data.base64EncodedString()) }
        let images: [String]? = base64Images.isEmpty ? nil : base64Images
        let toolCalls: [ToolCallParam]? = decodedToolCalls
        return APIMessage(role: role, content: content, images: images, toolCallId: toolCallId, toolName: toolName, toolCalls: toolCalls)
    }

    /// 从 toolCallData 反序列化出 ToolCallParam 数组，失败或无数据返回 nil
    private var decodedToolCalls: [ToolCallParam]? {
        guard let data = toolCallData else { return nil }
        struct StoredToolCall: Codable {
            let id: String
            let type: String
            let name: String
            let arguments: String
        }
        guard let calls = try? JSONDecoder().decode([StoredToolCall].self, from: data) else { return nil }
        return calls.map { ToolCallParam(id: $0.id, type: $0.type, function: FunctionCall(name: $0.name, arguments: $0.arguments)) }
    }
}
