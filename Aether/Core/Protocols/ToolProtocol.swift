import Foundation

/// 工具的元信息（name + description + parameters JSON Schema），用于告知 LLM 可调用的工具。
struct ToolDefinition {
    /// 工具名，需唯一。
    let name: String
    /// 工具描述，供 LLM 判断是否调用。
    let description: String
    /// JSON Schema 字典，符合 OpenAI function calling 规范。
    let parameters: [String: Any]
}

/// 工具风险等级。
enum ToolRiskLevel: String {
    /// 普通工具，无需额外确认。
    case normal
    /// 敏感工具，涉及隐私或用户数据，需要确认。
    case sensitive
    /// 危险工具，可执行系统命令或修改系统状态，需要确认。
    case dangerous
}

/// 工具定义与执行契约：`definition` 暴露给 LLM，`execute` 接收参数执行实际逻辑。
protocol ToolProtocol {
    /// 暴露给 LLM 的工具元信息。
    var definition: ToolDefinition { get }
    /// 工具风险等级，默认普通。
    var riskLevel: ToolRiskLevel { get }
    /// 执行工具。
    ///
    /// - Parameters:
    ///   - arguments: JSON 反序列化后的参数字典。
    /// - Returns: 字符串形式的结果（成功或错误描述）。
    /// - Throws: 执行过程中可能抛出的错误。
    func execute(arguments: [String: Any]) async throws -> String
}

extension ToolProtocol {
    var riskLevel: ToolRiskLevel { .normal }

    /// 确认对话框标题（按风险等级）。
    var confirmationTitle: String {
        switch riskLevel {
        case .dangerous: return "确认执行危险操作"
        case .sensitive: return "确认访问敏感信息"
        default: return "确认执行"
        }
    }

    /// 确认对话框消息（按风险等级）。
    var confirmationMessage: String {
        switch riskLevel {
        case .dangerous: return "工具 \(definition.name) 可能对系统造成不可逆修改，是否继续？"
        case .sensitive: return "工具 \(definition.name) 将访问敏感信息，是否继续？"
        default: return "是否执行工具 \(definition.name)？"
        }
    }
}
