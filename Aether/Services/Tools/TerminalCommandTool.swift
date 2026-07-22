/// 终端命令执行工具（macOS only）
///
/// 通过 Process 直接执行白名单内的系统命令，不再使用 /bin/bash -c。
/// 内置命令解析器：按空格分词、支持简单引号、拒绝 shell 元字符与路径遍历。
/// 调用方式：execute(arguments: ["command": "..."])，command 为必填参数。
import Foundation
import AetherFoundation

/// macOS 命令行执行工具，仅执行白名单内的命令并返回输出
final class TerminalCommandTool: ToolProtocol, @unchecked Sendable {
    /// 允许执行的命令白名单（仅基础命令名，不含路径）。
    /// 注：已移除 `cat`，因其可读取任意文件（如 ~/.ssh/id_rsa），造成敏感信息泄露。
    private static let allowedCommands: Set<String> = [
        "ls", "pwd", "which", "echo", "ps", "top", "df", "du"
    ]

    /// 敏感路径黑名单前缀：禁止通过命令参数访问这些目录下的文件。
    private static let sensitivePathPrefixes: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/.config",
            "\(home)/.aws",
            "\(home)/.docker",
            "\(home)/Library/Keychains",
            "\(home)/Library/Cookies"
        ]
    }()

    /// 危险命令模式列表（作用于规范化后的命令）。
    /// 包含常见绕过形式：多余空格、$HOME 引用、--no-preserve-root、引号包裹等。
    private static let dangerousPatterns = [
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

    /// 拒绝的 shell 元字符集合。
    private static let forbiddenCharacters = CharacterSet(charactersIn: "|><;&\\`$*?(){}[]!#\n\r")

    /// 最小环境变量 PATH（系统标准目录，非硬编码 URI）。
    private static let path = "/usr/bin:/bin:/usr/sbin:/sbin" // NOSONAR: 系统标准 PATH 目录，安全可控

    /// 解析后的命令描述
    internal struct ParsedCommand: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    /// 命令校验错误
    internal enum ValidationError: Error, Equatable {
        case emptyCommand
        case dangerousCommand
        case base64Bypass
        case shellMetacharacter
        case pathTraversal
        case notInWhitelist
        case executableNotFound
        case unterminatedQuote
        case parseError(String)
    }

    /// 工具定义
    /// - name: `run_terminal_command`
    /// - parameters: `command`（必填，String）— 要执行的命令
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_terminal_command",
            description: "在 macOS 上执行白名单内的 shell 命令，返回 stdout 和 stderr，超时 30 秒",
            parameters: [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "要执行的命令"]
                ],
                "required": ["command"]
            ]
        )
    }

    /// Process 工厂，生产代码默认使用 Process()，测试可注入以验证拒绝路径。
    internal var processFactory: () -> Process = { Process() }

    /// 执行 shell 命令
    ///
    /// - Parameter arguments: 含 `command` 键的参数字典
    /// - Returns: 命令的 stdout + stderr 输出，或错误信息字符串
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return ValidationError.emptyCommand.localizedDescription
        }

        // 第一层防护：危险命令模式拦截。
        let normalized = Self.normalizeCommand(command)
        for pattern in Self.dangerousPatterns where normalized.contains(pattern) {
            return ValidationError.dangerousCommand.localizedDescription
        }

        // 第二层防护：白名单解析与元字符校验。
        do {
            let parsed = try Self.parseCommand(command)
            return try await run(parsed)
        } catch let error as ValidationError {
            return error.localizedDescription
        } catch {
            return "错误：\(error.localizedDescription)"
        }
    }

    /// 解析并校验命令字符串，返回可直接交给 Process 的结构。
    internal static func parseCommand(_ command: String) throws -> ParsedCommand {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyCommand }

        try rejectShellMetacharacters(in: trimmed)

        let tokens = try tokenize(trimmed)
        guard let executable = tokens.first, !executable.isEmpty else {
            throw ValidationError.parseError("无法解析命令")
        }

        try validateExecutable(executable)

        let arguments = Array(tokens.dropFirst())
        for argument in arguments {
            if argument.contains("..") { throw ValidationError.pathTraversal }
            // 检查参数是否指向敏感路径（大小写不敏感比较，防止 APFS 大小写绕过）
            let standardized = (argument as NSString).standardizingPath
            let lowercased = standardized.lowercased()
            for prefix in sensitivePathPrefixes {
                let prefixLower = prefix.lowercased()
                if lowercased == prefixLower || lowercased.hasPrefix(prefixLower + "/") {
                    throw ValidationError.pathTraversal
                }
            }
        }

        guard let executableURL = resolveExecutable(named: executable) else {
            throw ValidationError.executableNotFound
        }

        return ParsedCommand(executableURL: executableURL, arguments: arguments)
    }

    // MARK: - 运行

    private func run(_ parsed: ParsedCommand) async throws -> String {
        let process = processFactory()
        process.executableURL = parsed.executableURL
        process.arguments = parsed.arguments
        process.environment = ["PATH": Self.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ValidationError.executableNotFound.localizedDescription)
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

    // MARK: - 校验与分词

    private static func validateExecutable(_ executable: String) throws {
        // 拒绝以路径形式指定可执行文件，防止绕过白名单。
        if executable.contains("/") || executable.hasPrefix(".") {
            throw ValidationError.pathTraversal
        }

        // 拒绝 Base64 解码工具作为入口。
        if executable.lowercased() == "base64" {
            throw ValidationError.base64Bypass
        }

        guard allowedCommands.contains(executable) else {
            throw ValidationError.notInWhitelist
        }
    }

    private static func rejectShellMetacharacters(in command: String) throws {
        if command.rangeOfCharacter(from: forbiddenCharacters) != nil {
            throw ValidationError.shellMetacharacter
        }
    }

    private static func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character?

        for char in input {
            if let quote = inQuote {
                if char == quote {
                    inQuote = nil
                    tokens.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" || char == "'" {
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                    inQuote = char
                } else if char.isWhitespace {
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                } else {
                    current.append(char)
                }
            }
        }

        guard inQuote == nil else { throw ValidationError.unterminatedQuote }
        if !current.isEmpty { tokens.append(current) }

        return tokens
    }

    private static func resolveExecutable(named name: String) -> URL? {
        for directory in path.split(separator: ":") {
            let fullPath = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }
        return nil
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

extension TerminalCommandTool.ValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "错误：请提供要执行的命令"
        case .dangerousCommand:
            return "错误：禁止执行危险命令"
        case .base64Bypass:
            return "错误：禁止执行 Base64 解码绕过"
        case .shellMetacharacter:
            return "错误：命令包含非法 shell 元字符"
        case .pathTraversal:
            return "错误：命令包含路径遍历"
        case .notInWhitelist:
            return "错误：命令不在白名单"
        case .executableNotFound:
            return "错误：未找到可执行文件"
        case .unterminatedQuote:
            return "错误：引号未闭合"
        case .parseError(let message):
            return "错误：\(message)"
        }
    }
}
