import Foundation
import AetherFoundation

/// MCP 客户端管理器，管理多个 MCP Server 连接。
///
/// 职责：
/// - 维护 serverID → MCPClient 映射
/// - 连接/断开指定 Server 或全部 Server
/// - 获取已连接 Server 列表及其 tools/resources/prompts
/// - 连接成功后将 MCP 工具自动注册到 ToolRegistry，断开时按名注销
/// - 连接状态变化时通过 @Observable 自动通知 UI 更新
///
/// 使用 @Observable + @MainActor 隔离，与 SwiftUI 视图直接绑定。
@Observable
@MainActor
final class MCPClientManager {
    /// 客户端映射（serverID → MCPClientProtocol）
    private var clients: [String: any MCPClientProtocol] = [:]
    /// Server 信息快照（serverID → MCPServerInfo），UI 绑定用
    private(set) var serverInfos: [String: MCPServerInfo] = [:]
    /// Server 注册到 ToolRegistry 的工具名映射（serverID → [toolName]），断开时按名注销
    private var serverToolMap: [String: [String]] = [:]
    /// 客户端工厂（nil 时默认创建 MCPClient，测试可注入 Mock）
    private let clientFactory: ((MCPConfig) -> any MCPClientProtocol)?

    /// 构造管理器
    /// - Parameter clientFactory: 客户端工厂闭包（nil 时使用默认 MCPClient 构造）
    init(clientFactory: ((MCPConfig) -> any MCPClientProtocol)? = nil) {
        self.clientFactory = clientFactory
    }

    // MARK: - 连接管理

    /// 连接到新 MCP Server。
    /// 流程：创建客户端 → 标记 connecting → connect() → 拉取 tools/resources/prompts → 标记 connected
    /// - Parameter config: MCP Server 配置
    /// - Throws: 连接失败抛出错误，serverInfos 更新为 error 状态
    func connect(config: MCPConfig) async throws {
        // 避免重复连接
        if clients[config.id] != nil {
            return
        }

        // 创建客户端（注入或默认）
        let client: any MCPClientProtocol
        if let factory = clientFactory {
            client = factory(config)
        } else {
            client = try MCPClient(config: config)
        }

        // 标记为 connecting
        serverInfos[config.id] = MCPServerInfo(
            id: config.id,
            name: config.name,
            status: .connecting,
            tools: [],
            resources: [],
            prompts: []
        )

        do {
            // 连接 + 握手
            try await client.connect()

            // 拉取 tools / resources / prompts（单个失败不中断整体连接）
            let tools = (try? await client.listTools()) ?? []
            let resources = (try? await client.listResources()) ?? []
            let prompts = (try? await client.listPrompts()) ?? []

            // 存储客户端，更新状态为 connected
            clients[config.id] = client
            serverInfos[config.id] = MCPServerInfo(
                id: config.id,
                name: config.name,
                status: .connected,
                tools: tools,
                resources: resources,
                prompts: prompts
            )

            // 自动注册 MCP 工具到 ToolRegistry（每个 MCPTool 适配为 MCPToolAdapter）
            let adapters = tools.map { MCPToolAdapter(tool: $0, client: client) }
            ToolRegistry.shared.registerBatch(tools: adapters)
            serverToolMap[config.id] = tools.map { $0.name }
        } catch {
            // 连接失败：更新状态为 error，不存储客户端
            serverInfos[config.id] = MCPServerInfo(
                id: config.id,
                name: config.name,
                status: .error(error.localizedDescription),
                tools: [],
                resources: [],
                prompts: []
            )
            throw error
        }
    }

    /// 断开指定 Server。
    /// - Parameter serverID: Server 唯一标识
    func disconnect(serverID: String) async {
        if let client = clients.removeValue(forKey: serverID) {
            await client.disconnect()
        }
        // 注销该 Server 注册到 ToolRegistry 的所有工具
        if let toolNames = serverToolMap.removeValue(forKey: serverID) {
            for name in toolNames {
                ToolRegistry.shared.unregister(name: name)
            }
        }
        // 更新状态为 disconnected
        if let info = serverInfos[serverID] {
            serverInfos[serverID] = MCPServerInfo(
                id: info.id,
                name: info.name,
                status: .disconnected,
                tools: [],
                resources: [],
                prompts: []
            )
        }
    }

    /// 断开所有已连接 Server
    func disconnectAll() async {
        let allClients = clients
        clients.removeAll()
        for (_, client) in allClients {
            await client.disconnect()
        }
        // 注销所有 Server 注册到 ToolRegistry 的工具
        for (_, toolNames) in serverToolMap {
            for name in toolNames {
                ToolRegistry.shared.unregister(name: name)
            }
        }
        serverToolMap.removeAll()
        // 更新所有状态为 disconnected
        for (id, info) in serverInfos {
            serverInfos[id] = MCPServerInfo(
                id: info.id,
                name: info.name,
                status: .disconnected,
                tools: [],
                resources: [],
                prompts: []
            )
        }
    }

    // MARK: - 查询

    /// 获取所有已连接（status == .connected）的 Server 信息
    /// - Returns: 已连接 Server 列表，按名称排序
    func getConnectedServers() -> [MCPServerInfo] {
        serverInfos.values.filter { info in
            if case .connected = info.status {
                return true
            }
            return false
        }.sorted { $0.name < $1.name }
    }

    /// 获取指定 Server 的客户端（供工具调用等操作）
    /// - Parameter serverID: Server 唯一标识
    /// - Returns: 客户端实例（未连接返回 nil）
    func getClient(serverID: String) -> (any MCPClientProtocol)? {
        clients[serverID]
    }
}
