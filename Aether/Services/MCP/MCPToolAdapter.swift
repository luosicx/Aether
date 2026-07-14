import Foundation
import AetherFoundation

/// MCP 工具适配器：将 MCP Server 暴露的工具适配为本地 ToolProtocol。
///
/// 把 MCPTool 的元信息映射为 ToolDefinition，execute 时委托关联的 MCPClient
/// 发起 tools/call 请求，并将返回的 content 文本块拼接为字符串结果。
///
/// - Note: client 类型使用 `any MCPClientProtocol`（而非具体 `MCPClient`），
///   与 MCPClientManager 的客户端抽象保持一致，便于注入 Mock 进行单元测试。
final class MCPToolAdapter: ToolProtocol, @unchecked Sendable {
    /// 暴露给 LLM 的工具元信息（由 MCPTool 转换而来）
    let definition: ToolDefinition
    /// 关联的 MCP 客户端，execute 时调用其 callTool
    private let mcpClient: any MCPClientProtocol
    /// MCP 工具名（与 definition.name 一致，execute 时透传给 client）
    private let toolName: String

    /// 构造适配器
    /// - Parameters:
    ///   - tool: MCP Server 暴露的工具定义
    ///   - client: 关联的 MCP 客户端（用于发起 tools/call）
    init(tool: MCPTool, client: any MCPClientProtocol) {
        self.toolName = tool.name
        self.mcpClient = client
        self.definition = ToolDefinition(
            name: tool.name,
            description: tool.description,
            parameters: tool.inputSchema
        )
    }

    /// 执行 MCP 工具：委托 mcpClient.callTool，拼接返回的文本内容块。
    /// 多个 text 块以换行连接；若无 text 块则返回空字符串。
    /// - Parameter arguments: 工具参数
    /// - Returns: 拼接后的文本结果
    func execute(arguments: [String: Any]) async throws -> String {
        let result = try await mcpClient.callTool(name: toolName, arguments: arguments)
        let texts = result.content.compactMap { $0.text }
        return texts.joined(separator: "\n")
    }
}
