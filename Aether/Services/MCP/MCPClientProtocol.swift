import AetherFoundation
import Foundation

// MARK: - MCP 客户端协议（用于 MCPClientManager 测试注入）

/// MCP 客户端契约，抽象连接与 MCP 方法调用。
/// MCPClient actor 遵循此协议，测试可注入 Mock 实现。
protocol MCPClientProtocol {
    /// 关联的配置
    var config: MCPConfig { get }
    /// 连接并完成 MCP 握手
    func connect() async throws
    /// 断开连接
    func disconnect() async
    /// 列出工具
    func listTools() async throws -> [MCPTool]
    /// 列出资源
    func listResources() async throws -> [MCPResource]
    /// 列出提示模板
    func listPrompts() async throws -> [MCPPrompt]
    /// 调用工具
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult
    /// 读取资源
    func readResource(uri: String) async throws -> [MCPResourceContent]
    /// 获取提示模板内容
    func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult
}
