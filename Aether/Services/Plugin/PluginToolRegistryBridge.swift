import Foundation
import AetherFoundation
import AetherServices

/// ToolRegistry 桥接：让 ToolRegistry 遵循 ToolRegistering 协议，
/// 供 PluginManager 通过依赖注入调用，避免 SPM 包对 App 层的循环依赖。
///
/// ToolRegistry 已有 register/unregister/getTool 方法，此处仅需声明协议遵循。
/// 遵循关系隔离到主 actor：PluginManager 本身也是 @MainActor，调用方不会跨隔离访问。
/// ToolRegistering 因此不继承 Sendable（Swift 6.2 禁止对继承 Sendable 的协议做隔离遵循）。
extension ToolRegistry: @MainActor ToolRegistering {}

/// 插件工具注册桥接：在 App 启动时调用，将 ToolRegistry.shared 注入到 PluginManager。
///
/// 调用时机：AetherApp.sharedInit() 中调用一次。
@MainActor
enum PluginToolRegistryBridge {
    /// 注入 ToolRegistry.shared 到 PluginManager.toolRegistry。
    /// 幂等操作，多次调用安全。
    static func setup() {
        PluginManager.toolRegistry = ToolRegistry.shared
    }
}
