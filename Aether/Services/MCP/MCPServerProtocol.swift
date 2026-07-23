import AetherFoundation
import Foundation

// MARK: - MCP Server 协议（v1.1 Phase A: 反向暴露）

/// MCP Server 契约，抽象 Aether 作为 MCP Server 对外暴露工具/资源/Prompts 的能力。
///
/// 与 `MCPClientProtocol` 方向相反：MCPClient 调用外部 MCP Server，
/// MCPServer 则将 Aether 自身的工具暴露给 Claude Desktop 等外部 MCP 客户端。
///
/// `MCPServer` actor 遵循此协议，测试可注入 Mock 实现。
protocol MCPServerProtocol {
    /// 启动 Server：连接 transport 并开始监听 JSON-RPC 请求
    func start() async throws
    /// 停止 Server：取消监听并断开 transport
    func stop() async
    /// 注册工具白名单（仅暴露白名单中的工具；传空数组表示不暴露任何工具）
    /// - Parameter tools: 工具名数组（对应 ToolRegistry 中已注册的工具名）
    func registerTools(_ tools: [String]) async
    /// 注册暴露给外部客户端的资源列表
    /// - Parameter resources: 资源定义数组
    func registerResources(_ resources: [MCPResource]) async
    /// 注册暴露给外部客户端的 Prompts 列表
    /// - Parameter prompts: Prompts 定义数组
    func registerPrompts(_ prompts: [MCPPrompt]) async
}
