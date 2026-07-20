import Foundation

// MARK: - MCP 传输层协议

/// MCP 传输层抽象，定义连接、断开、发送、接收四个核心能力。
/// 用于解耦 MCPClient 与具体传输实现（stdio / SSE），便于测试注入 Mock。
protocol MCPTransport: Sendable {
    /// 建立传输连接
    func connect() async throws
    /// 断开传输连接
    func disconnect() async
    /// 发送数据（一行 JSON-RPC 消息）
    func send(_ data: Data) async throws
    /// 获取消息接收流（每条消息一个 Data）
    func messages() -> AsyncStream<Data>
}
