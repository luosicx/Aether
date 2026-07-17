import Foundation
import AetherFoundation

/// MCP 工具适配器：将 MCP Server 暴露的工具适配为本地 ToolProtocol。
///
/// 把 MCPTool 的元信息映射为 ToolDefinition，execute 时委托关联的 MCPClient
/// 发起 tools/call 请求，并将返回的 content 文本块拼接为字符串结果。
///
/// **安全加固（Stage 4）**：
/// - 工具名加 `serverID__toolName` 前缀注册到 `ToolRegistry`，防止诱导调用
/// - execute 时调用 `MCPAuditLogger` 记录审计日志（Server ID + 工具名 + 参数摘要 + 结果摘要）
///
/// - Note: client 类型使用 `any MCPClientProtocol`（而非具体 `MCPClient`），
///   与 MCPClientManager 的客户端抽象保持一致，便于注入 Mock 进行单元测试。
final class MCPToolAdapter: ToolProtocol, @unchecked Sendable {
    /// 暴露给 LLM 的工具元信息（由 MCPTool 转换而来，name 已加 Server 前缀）
    let definition: ToolDefinition
    /// 关联的 MCP 客户端，execute 时调用其 callTool
    private let mcpClient: any MCPClientProtocol
    /// MCP 工具原名（不含 Server 前缀，execute 时透传给 client）
    private let originalToolName: String
    /// 关联的 Server ID（审计日志与已注册工具名映射用）
    private let serverID: String
    /// 注册到 ToolRegistry 的带前缀工具名
    private let prefixedToolName: String

    /// 构造适配器
    /// - Parameters:
    ///   - tool: MCP Server 暴露的工具定义
    ///   - client: 关联的 MCP 客户端（用于发起 tools/call）
    ///   - serverID: 关联的 Server ID（用于工具名前缀与审计日志）
    init(tool: MCPTool, client: any MCPClientProtocol, serverID: String) {
        self.originalToolName = tool.name
        self.serverID = serverID
        self.prefixedToolName = ToolNamePrefixer.prefix(serverID: serverID, toolName: tool.name)
        self.mcpClient = client
        self.definition = ToolDefinition(
            name: prefixedToolName,
            description: tool.description,
            parameters: tool.inputSchema
        )
    }

    /// 执行 MCP 工具：委托 mcpClient.callTool，拼接返回的文本内容块。
    /// 多个 text 块以换行连接；若无 text 块则返回空字符串。
    /// 执行前后记录审计日志（含 Server ID、工具名、参数摘要、结果摘要）。
    /// - Parameter arguments: 工具参数
    /// - Returns: 拼接后的文本结果
    func execute(arguments: [String: Any]) async throws -> String {
        // 参数摘要（仅记录键名，不记录敏感值）
        let argSummary = arguments.keys.sorted().joined(separator: ",")

        do {
            let result = try await mcpClient.callTool(name: originalToolName, arguments: arguments)
            let texts = result.content.compactMap { $0.text }
            let output = texts.joined(separator: "\n")

            // 记录成功调用审计
            MCPAuditLogger.shared.logToolCall(
                serverID: serverID,
                toolName: originalToolName,
                argumentsSummary: argSummary,
                resultSummary: String(output.prefix(200)),
                authorized: true
            )

            return output
        } catch {
            // 记录失败调用审计
            MCPAuditLogger.shared.logToolCall(
                serverID: serverID,
                toolName: originalToolName,
                argumentsSummary: argSummary,
                resultSummary: "error: \(error.localizedDescription)",
                authorized: true
            )
            throw error
        }
    }

    /// 返回工具原名（不含 Server 前缀，内部使用）
    var originalName: String { originalToolName }

    /// 返回带前缀的注册名（与 definition.name 一致）
    var registeredName: String { prefixedToolName }
}
