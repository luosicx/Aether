import Foundation

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
