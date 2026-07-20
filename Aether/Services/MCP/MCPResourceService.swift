import Foundation
import AetherFoundation
import os

/// MCP 资源管理服务。
///
/// 聚合所有已连接 MCP Server 的资源列表，提供统一的资源读取入口。
/// 通过 MCPClientManager 获取已连接的客户端，委托其完成 resources/list 与 resources/read 调用。
///
/// - Note: 使用 @Observable + @MainActor，与 MCPClientManager 隔离保持一致，
///   可直接绑定到 SwiftUI 视图。
@MainActor
@Observable
final class MCPResourceService {
    /// 关联的客户端管理器，用于获取已连接 Server 的客户端
    private let clientManager: MCPClientManager

    /// 构造资源服务
    /// - Parameter clientManager: MCP 客户端管理器
    init(clientManager: MCPClientManager) {
        self.clientManager = clientManager
    }

    /// 获取所有已连接 Server 的资源列表。
    ///
    /// 遍历已连接的 Server，逐一调用 listResources() 拉取最新资源列表，
    /// 按 (serverID, resource) 元组聚合返回。单个 Server 拉取失败不中断整体流程。
    /// - Returns: 资源元组列表（serverID + 资源定义）
    func getAllResources() async -> [(serverID: String, resource: MCPResource)] {
        var result: [(serverID: String, resource: MCPResource)] = []
        let servers = clientManager.getConnectedServers()
        for server in servers {
            guard let client = clientManager.getClient(serverID: server.id) else { continue }
            // 单个 Server 拉取失败时跳过，不中断整体聚合
            // P2-2: 将 try? 改为 do/catch + Logger.warning，便于诊断拉取失败原因
            let resources: [MCPResource]
            do {
                resources = try await client.listResources()
            } catch {
                Logger.mcp.warning("getAllResources: listResources 失败 (server=\(server.id, privacy: .public))，已跳过：\(error.localizedDescription, privacy: .public)")
                continue
            }
            for resource in resources {
                result.append((serverID: server.id, resource: resource))
            }
        }
        return result
    }

    /// 读取指定 Server 的资源内容。
    ///
    /// 委托目标客户端发起 resources/read 请求，拼接返回的文本内容块。
    /// 多个 text 块以换行符连接；无 text 块时返回空字符串。
    /// - Parameters:
    ///   - serverID: Server 唯一标识
    ///   - uri: 资源 URI
    /// - Returns: 拼接后的文本内容
    /// - Throws: serverID 未连接时抛出 MCPError.notConnected；读取失败透传底层错误
    func readResource(serverID: String, uri: String) async throws -> String {
        guard let client = clientManager.getClient(serverID: serverID) else {
            throw MCPError.notConnected
        }
        let contents = try await client.readResource(uri: uri)
        return contents.compactMap { $0.text }.joined(separator: "\n")
    }
}
