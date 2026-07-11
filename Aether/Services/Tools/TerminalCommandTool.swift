/// 终端命令执行工具（macOS only）
///
/// 通过 Process 在 macOS 上执行 shell 命令（/bin/bash -c），返回 stdout 和 stderr 合并输出。
/// 内置危险命令防护（rm -rf /、mkfs、dd if=、shutdown 等）和 30 秒超时保护。
/// 调用方式：execute(arguments: ["command": "..."])，command 为必填参数。
#if os(macOS)
import Foundation

/// macOS 命令行执行工具，执行 shell 命令并返回输出
final class TerminalCommandTool: ToolProtocol {
    /// 危险命令模式列表（作用于规范化后的命令）。
    /// 包含常见绕过形式：多余空格、$HOME 引用、--no-preserve-root、引号包裹等。
    private let dangerousPatterns = [
        "rm -rf /",
        "rm -rf /*",
        "rm -rf --no-preserve-root /",
        "rm -rf ~",
        "rm -rf ~/",
        "rm -rf ~/*",
        "rm -rf $HOME",
        "rm -rf $HOME/",
        "rm -rf $HOME/*",
        "mkfs",
        "dd if=",
        "shutdown",
        "reboot",
        "halt",
        ":(){:|:&};:"
    ]

    /// 工具定义
    /// - name: `run_terminal_command`
    /// - parameters: `command`（必填，String）— 要执行的 shell 命令
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_terminal_command",
            description: "在 macOS 上执行 shell 命令，返回 stdout 和 stderr，超时 30 秒",
            parameters: [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "要执行的 shell 命令"]
                ],
                "required": ["command"]
            ]
        )
    }

    /// 执行 shell 命令
    ///
    /// - Parameter arguments: 含 `command` 键的参数字典
    /// - Returns: 命令的 stdout + stderr 输出，或错误信息字符串
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return "错误：请提供要执行的命令"
        }
        // 危险命令防护：检测 rm -rf / / mkfs / dd if= / shutdown / reboot 等
        // 先对命令做规范化（折叠空白、去除引号），再匹配，防止简单绕过。
        let normalized = Self.normalizeCommand(command)
        for pattern in dangerousPatterns where normalized.contains(pattern) {
            return "错误：禁止执行危险命令"
        }

        // 用 Process 启动 /bin/bash 执行命令，stdout/stderr 分别接 Pipe
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            do {
                try process.run()
            } catch {
                continuation.resume(returning: "错误：无法启动进程：\(error.localizedDescription)")
                return
            }
            // 超时 30 秒：超时后终止进程
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutWorkItem)

            // 等待进程结束，读取 stdout/stderr 并合并
            DispatchQueue.global().async {
                process.waitUntilExit()
                timeoutWorkItem.cancel()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                var output = ""
                if let stdout = String(data: stdoutData, encoding: .utf8), !stdout.isEmpty {
                    output += stdout
                }
                if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                    if !output.isEmpty { output += "\n" }
                    output += stderr
                }
                if process.terminationStatus != 0 && output.isEmpty {
                    output = "命令退出码：\(process.terminationStatus)"
                }
                if output.isEmpty {
                    output = "已执行（无输出）"
                }
                continuation.resume(returning: output)
            }
        }
    }

    /// 规范化命令字符串：折叠连续空白并移除引号，便于统一匹配危险模式。
    private static func normalizeCommand(_ command: String) -> String {
        var normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }
        normalized = normalized.replacingOccurrences(of: "\"", with: "")
        normalized = normalized.replacingOccurrences(of: "'", with: "")
        return normalized
    }
}
#endif
