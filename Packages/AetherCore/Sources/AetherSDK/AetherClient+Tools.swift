import Foundation

/// Task 24 阶段 3: AetherClient 工具扩展 API。
///
/// 提供 register / unregister / setToolPermission 三个工具管理方法。
extension AetherClient {

    /// 注册自定义工具
    /// - Parameter tool: 实现 `AetherTool` 协议的工具实例
    public func register(tool: AetherTool) {
        _toolRegistry.register(tool: tool)
    }

    /// 按名注销工具
    /// - Parameter name: 工具名
    public func unregister(tool name: String) {
        _toolRegistry.unregister(name: name)
    }

    /// 设置工具权限
    /// - Parameters:
    ///   - name: 工具名
    ///   - perm: 权限（.alwaysAllow / .requireApproval / .deny）
    public func setToolPermission(name: String, _ perm: ToolPermission) {
        _toolRegistry.setPermission(name: name, perm)
    }

    /// 当前已注册工具数量
    public var registeredToolCount: Int {
        _toolRegistry.count
    }

    /// 当前已注册工具名列表
    public var registeredToolNames: [String] {
        _toolRegistry.toolNames
    }

    /// 查询工具权限
    /// - Parameter name: 工具名
    /// - Returns: 当前权限
    public func toolPermission(for name: String) -> ToolPermission {
        _toolRegistry.permission(for: name)
    }
}
