import Foundation

/// 工具的元信息（name + description + parameters JSON Schema），用于告知 LLM 可调用的工具。
///
/// 线程安全契约：`parameters` 类型为 `[String: Any]`，编译器无法验证 Sendable。
/// 实际使用中 `parameters` 仅承载 JSON Schema 兼容的值类型（`Int / Double / Bool /
/// String / [Any] / [String: Any]` 嵌套字典），均 Sendable。**禁止**注入非 Sendable
/// 引用类型（如 `NSObject`、闭包、`DispatchQueue`），否则跨 actor 传递存在数据竞争。
/// 长期重构方向：用 `JSONValue` enum 替代 `[String: Any]`，让编译器静态验证 Sendable，
/// 并与 `AnyCodable` 的长期迁移方向保持一致。
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
