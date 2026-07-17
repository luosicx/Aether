import os

/// Task 7.1: 统一日志系统分类扩展。
/// 按模块定义 Logger 单例，替换散落各处的 `print()` 调用，
/// 便于在 Console.app 中按 category 过滤查看日志。
extension Logger {
    /// 聊天模块：消息收发、流式输出、工具调用相关日志
    static let chat = Logger(subsystem: "com.aether.app", category: "chat")
    /// App 入口与生命周期：后台任务、启动初始化等
    static let app = Logger(subsystem: "com.aether.app", category: "app")
    /// 存储模块：SwiftData 持久化、Spotlight 索引
    static let storage = Logger(subsystem: "com.aether.app", category: "storage")
    /// 崩溃监控模块：Bugly 初始化与异常上报
    static let crash = Logger(subsystem: "com.aether.app", category: "crash")
    /// 网络与连接模块：WatchConnectivity、网络监控
    static let network = Logger(subsystem: "com.aether.app", category: "network")
    /// 工具模块：ToolRegistry 及各工具执行日志
    static let tools = Logger(subsystem: "com.aether.app", category: "tools")
}
