import Foundation

/// 插件生命周期钩子。
///
/// 声明插件关心的事件，PluginManager 在对应事件发生时触发插件 JS 入口的同名函数。
public enum PluginHook: String, Codable, Hashable, Sendable, CaseIterable {
    /// 收到新消息时触发
    case onMessageReceived
    /// 工具调用前后触发
    case onToolCall
    /// 新会话创建时触发
    case onConversationCreated
}
