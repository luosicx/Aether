import XCTest
@testable import Aether

#if os(macOS)
/// StdioTransport 单元测试
///
/// 覆盖范围：
/// 1. init：使用 /bin/echo 与 /bin/cat 命令构造
/// 2. connect：成功启动子进程；无效命令路径抛出 connectionFailedWithCause
/// 3. send：向 /bin/cat 的 stdin 写入数据，通过 messages() 流接收回显
/// 4. disconnect：终止子进程并清理（幂等性）
/// 5. messages：返回 AsyncStream<Data>
/// 6. processStdoutData：多行输出按换行符分割 yield 多条消息
final class StdioTransportTests: XCTestCase {

    // MARK: - 线程安全的消息缓冲区

    /// 线程安全的消息缓冲区，用于在 Task 间共享收集到的消息。
    private final class MessageBuffer: @unchecked Sendable {
        private var messages: [Data] = []
        private let lock = NSLock()

        func append(_ data: Data) {
            lock.lock()
            messages.append(data)
            lock.unlock()
        }

        var allMessages: [Data] {
            lock.lock()
            defer { lock.unlock() }
            return messages
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return messages.count
        }
    }

    // MARK: - 辅助方法

    /// 从 AsyncStream 收集指定数量的消息，带超时保护（防止测试挂起）。
    /// 收集到指定数量后返回；超时则返回已收集的消息。
    private func collectMessages(
        from stream: AsyncStream<Data>,
        count: Int,
        timeoutSeconds: TimeInterval = 5
    ) async -> [Data] {
        let buffer = MessageBuffer()
        await withTaskGroup(of: Void.self) { group in
            // 消息收集任务：收集到指定数量后返回
            group.addTask {
                for await data in stream {
                    buffer.append(data)
                    if buffer.count >= count { break }
                }
            }
            // 超时看门狗任务：到达超时时间返回
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            }
            // 等待任一任务完成，取消另一个
            await group.next()
            group.cancelAll()
        }
        return buffer.allMessages
    }

    // MARK: - 1. init 测试

    /// 使用 /bin/echo 命令构造 StdioTransport，应成功创建对象
    func testInitWithEchoCommand() async {
        let transport = StdioTransport(command: "/bin/echo", args: ["hello"], env: nil)
        // messages() 可调用证明对象已正确初始化
        _ = transport.messages()
        await transport.disconnect()
    }

    /// 使用 /bin/cat 命令构造 StdioTransport（交互式，用于 send/messages 测试）
    func testInitWithCatCommand() async {
        let transport = StdioTransport(command: "/bin/cat", args: [], env: nil)
        _ = transport.messages()
        await transport.disconnect()
    }

    // MARK: - 2. connect 测试

    /// connect 成功启动子进程（/bin/echo hello），通过 messages() 接收到 "hello" 消息
    func testConnectSucceeds() async throws {
        let transport = StdioTransport(command: "/bin/echo", args: ["hello"], env: nil)

        // 先启动消息流（设置 continuation），再连接
        let stream = transport.messages()
        try await transport.connect()

        // echo 输出 "hello\n"，应收到一条 "hello" 消息
        let messages = await collectMessages(from: stream, count: 1, timeoutSeconds: 5)
        XCTAssertEqual(messages.count, 1, "应收到 1 条消息")
        XCTAssertEqual(messages.first, Data("hello".utf8), "消息内容应为 'hello'")

        await transport.disconnect()
    }

    /// connect 使用无效命令路径时，应抛出 connectionFailedWithCause
    func testConnectWithInvalidCommandThrowsConnectionFailedWithCause() async {
        let transport = StdioTransport(command: "/nonexistent/path/to/binary", args: [], env: nil)

        do {
            try await transport.connect()
            XCTFail("无效命令路径应抛出 connectionFailedWithCause 错误")
        } catch let error as MCPError {
            if case .connectionFailedWithCause = error {
                // 预期：子进程启动失败
            } else {
                XCTFail("应为 connectionFailedWithCause 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }
    }

    // MARK: - 3. send 测试

    /// send 向 /bin/cat 的 stdin 写入数据，通过 messages() 流接收回显
    func testSendReceivesEcho() async throws {
        let transport = StdioTransport(command: "/bin/cat", args: [], env: nil)

        // 先启动消息流，再连接
        let stream = transport.messages()
        try await transport.connect()

        // 发送数据（send 会自动追加换行符），cat 回显到 stdout
        try await transport.send(Data("hello".utf8))

        // 应收到一条回显消息 "hello"
        let messages = await collectMessages(from: stream, count: 1, timeoutSeconds: 5)
        XCTAssertEqual(messages.count, 1, "应收到 1 条回显消息")
        XCTAssertEqual(messages.first, Data("hello".utf8), "回显内容应为 'hello'")

        await transport.disconnect()
    }

    // MARK: - 4. disconnect 测试

    /// disconnect 终止子进程并清理（幂等性：多次调用无副作用）
    func testDisconnectTerminatesAndCleansUp() async throws {
        let transport = StdioTransport(command: "/bin/cat", args: [], env: nil)

        let stream = transport.messages()
        try await transport.connect()

        // 断开连接，终止 cat 子进程
        await transport.disconnect()

        // 断开后流应立即结束（continuation 已 finish），不产生消息
        let messages = await collectMessages(from: stream, count: 1, timeoutSeconds: 1)
        XCTAssertTrue(messages.isEmpty, "disconnect 后流应立即结束")

        // 再次调用 disconnect 应是幂等的，不崩溃
        await transport.disconnect()
    }

    // MARK: - 5. messages 测试

    /// messages 返回 AsyncStream<Data>，可被迭代
    func testMessagesReturnsAsyncStream() async {
        let transport = StdioTransport(command: "/bin/cat", args: [], env: nil)
        let stream = transport.messages()

        // disconnect 会 finish continuation，使流结束
        await transport.disconnect()

        // 流应在 disconnect 后立即结束，不产生消息
        let messages = await collectMessages(from: stream, count: 1, timeoutSeconds: 1)
        XCTAssertTrue(messages.isEmpty, "未连接的流不应产生消息")
    }

    // MARK: - 6. processStdoutData 测试

    /// processStdoutData 将多行输出按换行符分割，yield 多条消息
    func testProcessStdoutDataSplitsMultipleLines() async throws {
        let transport = StdioTransport(command: "/bin/cat", args: [], env: nil)

        let stream = transport.messages()
        try await transport.connect()

        // 发送包含多行的数据（send 会追加换行符），cat 回显后按换行分割
        try await transport.send(Data("line1\nline2\nline3".utf8))

        // 应收到 3 条消息：line1、line2、line3
        let messages = await collectMessages(from: stream, count: 3, timeoutSeconds: 5)
        XCTAssertEqual(messages.count, 3, "应收到 3 条消息（按换行符分割）")
        XCTAssertEqual(messages.first, Data("line1".utf8), "第一条消息应为 'line1'")
        XCTAssertEqual(messages.last, Data("line3".utf8), "最后一条消息应为 'line3'")

        await transport.disconnect()
    }
}
#endif
