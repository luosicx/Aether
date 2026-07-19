import Foundation
import AetherFoundation

/// Task 24 阶段 3: Aether SDK 工具注册中心。
///
/// 内部管理第三方注册的 `AetherTool` 实例与权限。
/// 使用 NSLock 串行化保证线程安全（避免 actor 的 async API 传染调用方）。
public final class AetherToolRegistry: @unchecked Sendable {

    /// 锁，保护 tools / permissions
    private let lock = NSLock()
    /// 已注册工具（name → tool）
    private var tools: [String: AetherTool] = [:]
    /// 工具权限（name → permission）
    private var permissions: [String: ToolPermission] = [:]

    public init() {
        // 空初始化器：使用默认空 tools/permissions 字典
    }

    /// 注册工具（同名覆盖）
    public func register(tool: AetherTool) {
        lock.lock()
        defer { lock.unlock() }
        let name = tool.definition.name
        tools[name] = tool
        // 默认权限：alwaysAllow（第三方工具默认信任）
        if permissions[name] == nil {
            permissions[name] = .alwaysAllow
        }
    }

    /// 按名注销工具
    public func unregister(name: String) {
        lock.lock()
        defer { lock.unlock() }
        tools.removeValue(forKey: name)
        permissions.removeValue(forKey: name)
    }

    /// 设置工具权限
    public func setPermission(name: String, _ perm: ToolPermission) {
        lock.lock()
        defer { lock.unlock() }
        permissions[name] = perm
    }

    /// 获取工具
    public func getTool(named name: String) -> AetherTool? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    /// 当前权限
    public func permission(for name: String) -> ToolPermission {
        lock.lock()
        defer { lock.unlock() }
        return permissions[name] ?? .alwaysAllow
    }

    /// 已注册工具数量
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return tools.count
    }

    /// 所有已注册工具名
    public var toolNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.keys)
    }

    /// 获取所有非 deny 工具定义（供 LLM 调用）
    public func availableDefinitions() -> [AetherToolDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values
            .filter { permissions[$0.definition.name] != .deny }
            .map { $0.definition }
    }

    /// 执行工具
    /// - Parameters:
    ///   - name: 工具名
    ///   - arguments: 参数字典
    /// - Returns: 工具执行结果字符串
    /// - Throws: 工具未注册 / 权限拒绝 / 执行失败
    public func execute(name: String, arguments: [String: Any]) async throws -> String {
        // 先在锁内取出 tool，避免执行期间持锁
        let tool: AetherTool?
        let perm: ToolPermission
        lock.lock()
        tool = tools[name]
        perm = permissions[name] ?? .alwaysAllow
        lock.unlock()

        guard let tool = tool else {
            throw AetherError.toolExecutionFailed(name: name, errorDescription: "工具未注册")
        }
        guard perm != .deny else {
            throw AetherError.toolExecutionFailed(name: name, errorDescription: "工具已被禁用")
        }
        do {
            return try await tool.execute(arguments: arguments)
        } catch {
            let desc: String
            if let localized = error as? LocalizedError, let msg = localized.errorDescription {
                desc = msg
            } else {
                desc = error.localizedDescription
            }
            throw AetherError.toolExecutionFailed(name: name, errorDescription: desc)
        }
    }

    /// 批量注册工具
    public func registerBatch(tools: [AetherTool]) {
        for tool in tools {
            register(tool: tool)
        }
    }

    /// 清空所有工具
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        tools.removeAll()
        permissions.removeAll()
    }
}
