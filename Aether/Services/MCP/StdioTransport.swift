import Foundation

// MARK: - stdio 传输（仅 macOS，Process + Pipe）

#if os(macOS)
/// stdio 传输实现：通过 Process 启动子进程，经 stdin/stdout 通信。
/// 使用 readabilityHandler 异步读取 stdout，按换行符分割 JSON-RPC 消息。
final class StdioTransport: @unchecked Sendable, MCPTransport {
    /// 子进程
    private let process: Process
    /// stdin 管道（写入请求）
    private let stdinPipe: Pipe
    /// stdout 管道（读取响应）
    private let stdoutPipe: Pipe
    /// stderr 管道（捕获错误输出，不解析）
    private let stderrPipe: Pipe
    /// 消息流 continuation（由 messages() 设置）
    private var continuation: AsyncStream<Data>.Continuation?
    /// 行缓冲（readabilityHandler 可能返回不完整行，需按 \n 分割）
    private var lineBuffer = ""
    /// 线程安全锁（readabilityHandler 在后台队列回调）
    private let lock = NSLock()

    /// 构造 stdio 传输
    /// - Parameters:
    ///   - command: 可执行文件路径
    ///   - args: 启动参数
    ///   - env: 环境变量（nil 表示继承当前进程环境）
    init(command: String, args: [String], env: [String: String]?) {
        process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        if let env = env {
            process.environment = env
        }
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    // MARK: - MCPTransport 实现

    /// 启动子进程并设置 stdout readabilityHandler
    func connect() async throws {
        do {
            try process.run()
        } catch {
            // P2-3: 携带 underlying 保留原始 Error 上下文
            throw MCPError.connectionFailedWithCause(message: "子进程启动失败: \(error.localizedDescription)", underlying: error)
        }
        // 设置 readabilityHandler 异步读取 stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.processStdoutData(data)
        }
    }

    /// 终止子进程并清理 readabilityHandler
    func disconnect() async {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        // 持锁访问 continuation，与 messages() / processStdoutData() 串行化
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    /// 写入 stdin（JSON-RPC 消息 + 换行符）
    func send(_ data: Data) async throws {
        var message = data
        message.append(0x0A) // 追加换行符 \n
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: message)
        } catch {
            // P2-3: 携带 underlying 保留原始 Error 上下文
            throw MCPError.transportErrorWithCause(message: "stdin 写入失败: \(error.localizedDescription)", underlying: error)
        }
    }

    /// 创建消息接收流，存储 continuation 供 readabilityHandler 回调时 yield
    /// - Note: 持锁设置 continuation，与 disconnect() / processStdoutData() 串行化
    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    // MARK: - 私有方法

    /// 处理 stdout 数据：按换行符分割，逐行 yield 给消息流
    private func processStdoutData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        lineBuffer += string
        // 按换行符分割完整行
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // 非空行解析为 JSON-RPC 消息
            if !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) {
                continuation?.yield(lineData)
            }
        }
        lock.unlock()
    }
}
#endif
