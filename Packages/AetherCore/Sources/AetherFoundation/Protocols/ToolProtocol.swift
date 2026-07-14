import Foundation

/// 工具的元信息（name + description + parameters JSON Schema），用于告知 LLM 可调用的工具。
public struct ToolDefinition: @unchecked Sendable {
    /// 工具名，需唯一。
    public let name: String
    /// 工具描述，供 LLM 判断是否调用。
    public let description: String
    /// JSON Schema 字典，符合 OpenAI function calling 规范。
    public let parameters: [String: Any]

    public init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// 工具定义与执行契约：`definition` 暴露给 LLM，`execute` 接收参数执行实际逻辑。
public protocol ToolProtocol: Sendable {
    /// 暴露给 LLM 的工具元信息。
    var definition: ToolDefinition { get }
    /// 执行工具。
    ///
    /// - Parameters:
    ///   - arguments: JSON 反序列化后的参数字典。
    /// - Returns: 字符串形式的结果（成功或错误描述）。
    /// - Throws: 执行过程中可能抛出的错误。
    func execute(arguments: [String: Any]) async throws -> String
}
