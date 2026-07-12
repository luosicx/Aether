import Foundation

/// MCP 提示词模板管理服务。
///
/// 聚合所有已连接 MCP Server 的提示词模板列表，提供统一的模板获取入口。
/// 通过 MCPClientManager 获取已连接的客户端，委托其完成 prompts/list 与 prompts/get 调用。
///
/// - Note: 使用 @Observable + @MainActor，与 MCPClientManager 隔离保持一致，
///   可直接绑定到 SwiftUI 视图。
@MainActor
@Observable
final class MCPPromptService {
    /// 关联的客户端管理器，用于获取已连接 Server 的客户端
    private let clientManager: MCPClientManager

    /// 构造提示词服务
    /// - Parameter clientManager: MCP 客户端管理器
    init(clientManager: MCPClientManager) {
        self.clientManager = clientManager
    }

    /// 获取所有已连接 Server 的提示词模板列表。
    ///
    /// 遍历已连接的 Server，逐一调用 listPrompts() 拉取最新模板列表，
    /// 按 (serverID, prompt) 元组聚合返回。单个 Server 拉取失败不中断整体流程。
    /// - Returns: 提示词元组列表（serverID + 模板定义）
    func getAllPrompts() async -> [(serverID: String, prompt: MCPPrompt)] {
        var result: [(serverID: String, prompt: MCPPrompt)] = []
        let servers = clientManager.getConnectedServers()
        for server in servers {
            guard let client = clientManager.getClient(serverID: server.id) else { continue }
            // 单个 Server 拉取失败时跳过，不中断整体聚合
            guard let prompts = try? await client.listPrompts() else { continue }
            for prompt in prompts {
                result.append((serverID: server.id, prompt: prompt))
            }
        }
        return result
    }

    /// 获取指定 Server 的提示词模板内容。
    ///
    /// 委托目标客户端发起 prompts/get 请求，拼接返回消息中的文本内容。
    /// 多个消息的文本块以换行符连接；无文本块时返回空字符串。
    /// - Parameters:
    ///   - serverID: Server 唯一标识
    ///   - name: 提示模板名
    ///   - arguments: 模板参数（字符串键值对）
    /// - Returns: 拼接后的文本内容
    /// - Throws: serverID 未连接时抛出 MCPError.notConnected；获取失败透传底层错误
    func getPrompt(serverID: String, name: String, arguments: [String: String]) async throws -> String {
        guard let client = clientManager.getClient(serverID: serverID) else {
            throw MCPError.notConnected
        }
        // [String: String] 转换为 [String: Any] 以匹配 MCPClientProtocol.getPrompt 签名
        let anyArguments: [String: Any] = arguments
        let result = try await client.getPrompt(name: name, arguments: anyArguments)
        return result.messages.compactMap { $0.content.text }.joined(separator: "\n")
    }
}
