import Foundation

/// 工具注册中心协议，定义工具的注册、注销与查询能力。
///
/// 用于解耦 AetherServices（PluginManager）与 Aether App（ToolRegistry）：
/// PluginManager 持有一个 `ToolRegistering?` 实例，由 App 启动时注入 ToolRegistry.shared，
/// 避免 SPM 包对 App 层的循环依赖。
///
/// 不要求 Sendable：App 侧实现（ToolRegistry）是 @MainActor 隔离的类，
/// 对 Sendable 协议只能做 isolated conformance，而 Swift 6.2 禁止对继承 Sendable
/// 的协议形成 actor 隔离遵循；注入与调用都发生在 PluginManager 的 @MainActor 内。
public protocol ToolRegistering: AnyObject {
    /// 注册工具，同名覆盖
    /// - Parameter tool: 待注册的工具
    func register(tool: ToolProtocol)
    /// 按名注销工具。工具不存在时不报错（no-op）。
    /// - Parameter name: 工具名
    func unregister(name: String)
    /// 按名获取工具，未命中返回 nil
    /// - Parameter name: 工具名
    /// - Returns: 工具实例，未注册返回 nil
    func getTool(named name: String) -> ToolProtocol?
}
