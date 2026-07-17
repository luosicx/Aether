import Foundation

/// Task 24 阶段 3: Aether SDK 工具定义。
///
/// 描述工具的 name / description / parameters JSON Schema，用于告知 LLM 可调用的工具。
/// 与内部 `ToolDefinition` 解耦，避免 `[String: Any]` 的非 Sendable 限制。
public struct AetherToolDefinition: Sendable, Equatable {
    /// 工具名，需唯一
    public let name: String
    /// 工具描述，供 LLM 判断是否调用
    public let description: String
    /// JSON Schema 字符串（OpenAI function calling 规范）
    /// 使用字符串避免 `[String: Any]` 的 Sendable 限制，运行时由 SDK 解析
    public let parametersJSON: String

    /// 创建工具定义
    /// - Parameters:
    ///   - name: 工具名
    ///   - description: 工具描述
    ///   - parametersJSON: JSON Schema 字符串
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }

    /// 便捷构造：从字典创建（运行时序列化为 JSON 字符串）
    public init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        if let data = try? JSONSerialization.data(withJSONObject: parameters),
           let json = String(data: data, encoding: .utf8) {
            self.parametersJSON = json
        } else {
            self.parametersJSON = "{}"
        }
    }

    /// 解析 parametersJSON 为字典；解析失败返回空字典
    public func parameters() -> [String: Any] {
        guard let data = parametersJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

/// Task 24 阶段 3: Aether SDK 工具协议。
///
/// 第三方实现此协议后通过 `AetherClient.register(tool:)` 注册，LLM 可在对话中调用。
public protocol AetherTool: Sendable {
    /// 暴露给 LLM 的工具元信息
    var definition: AetherToolDefinition { get }
    /// 执行工具
    /// - Parameter arguments: JSON 反序列化后的参数字典
    /// - Returns: 字符串形式的结果（成功或错误描述）
    /// - Throws: 执行过程中可能抛出的错误
    func execute(arguments: [String: Any]) async throws -> String
}

/// 工具调用权限
public enum ToolPermission: String, Sendable, Equatable {
    /// 始终允许（无需用户确认）
    case alwaysAllow
    /// 需要用户确认（敏感工具默认）
    case requireApproval
    /// 拒绝（禁用工具）
    case deny
}
