import Foundation
import AetherFoundation

/// MCP Server 连接状态枚举。
///
/// 用于 `MCPServerInfo.status` 字段，UI 通过此状态显示连接状态。
public enum MCPServerStatus: Sendable, Equatable {
    case connecting
    case connected
    case disconnected
    case error(String)
}

/// MCP Server 信息快照。
///
/// 供 `MCPClientManager.serverInfos` 存储与 UI 绑定，
/// 包含 Server 元信息、连接状态、已注册工具/资源/提示列表。
public struct MCPServerInfo: Sendable, Equatable, Identifiable {
    /// Server 唯一标识
    public let id: String
    /// Server 显示名称
    public let name: String
    /// 连接状态
    public let status: MCPServerStatus
    /// 已注册工具列表
    public let tools: [MCPTool]
    /// 已注册资源列表
    public let resources: [MCPResource]
    /// 已注册提示列表
    public let prompts: [MCPPrompt]

    public init(
        id: String,
        name: String,
        status: MCPServerStatus,
        tools: [MCPTool] = [],
        resources: [MCPResource] = [],
        prompts: [MCPPrompt] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
    }
}

/// MCP Server 三组分类辅助类型，从 MCPClientManager 提取分组数据。
///
/// 供 `MCPSettingsView` 与单元测试共用，将 manager 的三类状态
/// （已连接 / 候选 / 已拒绝）提取为不可变快照。
struct MCPServerGrouping {
    /// 已连接 Server 信息列表（按名称排序）
    let connected: [MCPServerInfo]
    /// 候选 Server 配置列表（待审批，按名称排序）
    let candidates: [MCPConfigFile.Server]
    /// 已拒绝 Server ID 列表（按字母排序）
    let rejected: [String]

    /// 从 MCPClientManager 提取三组分类
    /// - Parameter manager: MCPClientManager
    /// - Returns: 三组分类结果快照
    @MainActor
    static func classify(manager: MCPClientManager) -> MCPServerGrouping {
        MCPServerGrouping(
            connected: manager.getConnectedServers(),
            candidates: manager.getCandidateServers(),
            rejected: manager.getRejectedServerIDs()
        )
    }
}
