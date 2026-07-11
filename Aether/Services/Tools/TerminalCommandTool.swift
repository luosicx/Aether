/// 终端命令执行工具（macOS only）
///
/// 通过 Process 在 macOS 上执行白名单内的命令，返回 stdout 和 stderr 合并输出。
/// 不再通过 /bin/bash -c 执行任意字符串，从而避免命令注入。
/// 内置 30 秒超时保护。
/// 调用方式：execute(arguments: ["command": "..."])，command 为必填参数。
#if os(macOS)
import Foundation

/// macOS 命令行执行工具，执行白名单命令并返回输出
final class TerminalCommandTool: ToolProtocol {
    var riskLevel: ToolRiskLevel { .dangerous }

    /// 允许执行的命令白名单。
    /// key 为命令名（输入字符串中的第一个 token），value 为可能的可执行文件绝对路径列表，
    /// 按顺序查找第一个存在且可执行的文件。
    private let allowedCommands: [String: [String]] = [
        "ls": ["/bin/ls"],
        "pwd": ["/bin/pwd"],
        "git": ["/usr/bin/git"],
        "brew": ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    ]

    /// 工具定义
    /// - name: `run_terminal_command`
    /// - parameters: `command`（必填，String）— 要执行的命令
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_terminal_command",
            description: "在 macOS 上执行白名单内的终端命令，返回 stdout 和 stderr，超时 30 秒",
            parameters: [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "要执行的 shell 命令"]
                ],
                "required": ["command"]
            ]
        )
    }

    /// 执行白名单内的命令
    ///
    /// - Parameter arguments: 含 `command` 键的参数字典
    /// - Returns: 命令的 stdout + stderr 输出，或错误信息字符串
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return "错误：请提供要执行的命令"
        }

        let tokens = splitCommand(command)
        guard let baseCommand = tokens.first else {
            return "错误：请提供要执行的命令"
        }

        guard let candidatePaths = allowedCommands[baseCommand] else {
            return "错误：不允许执行的命令: \(command)"
        }

        guard let executablePath = candidatePaths.first(where: {
            FileManager.default.fileExists(atPath: $0) && FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return "错误：命令未安装: \(baseCommand)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = Array(tokens.dropFirst())
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

    /// 将命令字符串按空白拆分为 token，并尊重单引号和双引号。
    private func splitCommand(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false

        for character in command {
            switch character {
            case "'":
                if inDoubleQuote {
                    current.append(character)
                } else {
                    inSingleQuote.toggle()
                }
            case "\"":
                if inSingleQuote {
                    current.append(character)
                } else {
                    inDoubleQuote.toggle()
                }
            case " ", "\t", "\n", "\r":
                if inSingleQuote || inDoubleQuote {
                    current.append(character)
                } else if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
#endif
