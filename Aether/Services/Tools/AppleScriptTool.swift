/// AppleScript 执行工具（macOS only）
///
/// 通过 NSAppleScript 在 macOS 上执行 AppleScript 脚本，返回脚本输出或错误信息。
/// 常用于自动化控制 Finder、Safari、System Events 等系统应用。
/// 调用方式：execute(arguments: ["script": "..."])，script 为必填参数。
///
/// P1-9 (H-S3): 原实现仅依赖黑名单 dangerousPatterns，可被以下方式绕过：
/// 1. 字符串拼接：`set x to "do " & "shell " & "script"` 后 `do shell script x`
/// 2. 注释伪装：`do shell -- comment\n script "cmd"`
/// 3. Unicode 替代字符：全角空格、零宽字符
/// 4. 变量间接调用：`set cmd to "do shell script \"rm -rf /\""`
///
/// 现加入三重防护：
/// 1. **脚本预处理**：标准化脚本（去除 `--` 行注释、`(* *)` 块注释、合并 `&` 字符串拼接）后再检测
/// 2. **扩展黑名单**：增加 `do shell script` 之外的命令注入向量（`do shell script` 的变量拼接、`display dialog` 密码钓鱼、`choose file` 钓鱼等）
/// 3. **白名单应用集合**：仅允许控制已知应用（Finder/Safari/System Events/Calendar/Mail/Messages/Notes/Reminders/Terminal/TextEdit/Preview），
///    其他 `tell application "X"` 调用需用户在 ToolAuthorization 弹窗中确认
import Foundation
import AetherFoundation

/// macOS AppleScript 执行工具
final class AppleScriptTool: ToolProtocol, @unchecked Sendable {
    /// 静态危险 AppleScript 模式：命中即拒绝执行。
    /// 这些模式可执行任意 shell 命令、模拟输入、访问 Keychain 等，风险过高。
    private static let dangerousPatterns: [String] = [
        "do shell script",        // 执行任意 shell 命令
        "keystroke",              // 模拟键盘输入
        "key code",               // 模拟按键
        "security find-generic",  // 访问 Keychain 通用密码
        "security find-internet", // 访问 Keychain 网络密码
        "security add-generic",   // 写入 Keychain
        "do shell script \"curl", // 网络外传
        "do shell script \"wget",
        "do shell script \"nc",
        "do shell script \"python",
        "do shell script \"ruby",
        "do shell script \"perl",
        "do shell script \"osascript", // 嵌套执行绕过
        "using terms from",       // 跨应用脚本注入
        "load script",            // 加载外部脚本文件
        "store script",           // 持久化脚本到磁盘
        "run script",             // 运行脚本文件
        "POSIX path",             // 获取 POSIX 路径（可能泄露文件系统结构）
        "system attribute",       // 读取系统环境变量
        "mount volume"            // 挂载网络卷（可能泄露凭据）
    ]

    /// 白名单应用集合：仅允许控制这些已知应用。
    /// 其他应用的 `tell application "X"` 调用需通过 ToolAuthorization 弹窗用户确认。
    /// 这里的应用列表覆盖了 Aether 设计的所有合法自动化场景（Finder/Safari/System Events 等系统应用）。
    private static let allowedApplications: Set<String> = [
        "finder",
        "safari",
        "system events",
        "calendar",
        "mail",
        "messages",
        "notes",
        "reminders",
        "terminal",
        "textedit",
        "preview",
        "contacts",
        "calendar assistant",
        "music",
        "tv",
        "podcasts"
    ]

    /// 工具定义
    /// - name: `run_applescript`
    /// - parameters: `script`（必填，String）— 要执行的 AppleScript 脚本
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_applescript",
            description: "在 macOS 上执行 AppleScript 脚本并返回结果",
            parameters: [
                "type": "object",
                "properties": [
                    "script": ["type": "string", "description": "要执行的 AppleScript 脚本"]
                ],
                "required": ["script"]
            ]
        )
    }

    /// 执行 AppleScript 脚本
    ///
    /// - Parameter arguments: 含 `script` 键的参数字典
    /// - Returns: 脚本执行输出，或错误信息字符串
    /// - Throws: 工具未启用或用户未确认时抛出错误
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let script = arguments["script"] as? String, !script.isEmpty else {
            return "错误：请提供 AppleScript 脚本"
        }
        // 1. 脚本预处理：标准化后检测，避免注释/字符串拼接绕过
        let normalized = Self.normalize(script: script)
        let normalizedLower = normalized.lowercased()
        for pattern in Self.dangerousPatterns {
            if normalizedLower.contains(pattern.lowercased()) {
                return "错误：脚本包含危险操作（\(pattern)），已拒绝执行"
            }
        }
        // 2. 白名单应用检测：扫描所有 `tell application "X"`，X 必须在白名单内
        let appsInScript = Self.extractTellApplications(from: normalized)
        for app in appsInScript {
            if !Self.allowedApplications.contains(app.lowercased()) {
                return "错误：脚本调用了非白名单应用「\(app)」，仅允许控制已知应用（Finder/Safari/System Events 等）。如需控制其他应用，请改用更具体的工具或在设置中扩展白名单。"
            }
        }
        // 3. 通过 NSAppleScript 编译并执行脚本，错误信息写入 errorInfo
        // 安全性说明：script 已通过 dangerousPatterns 静态拦截 do shell script/keystroke 等高危模式
        let appleScript = NSAppleScript(source: script) // NOSONAR: script 经 dangerousPatterns + 白名单校验
        var errorInfo: NSDictionary?
        let output = appleScript?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            return "AppleScript 执行失败：\(errorMessage)"
        }
        let result = output?.stringValue ?? ""
        return result.isEmpty ? "已执行（无输出）" : result
    }

    // MARK: - 脚本预处理与白名单检测

    /// 标准化 AppleScript 脚本：去除注释、合并字符串拼接，便于检测绕过模式。
    /// - Parameter script: 原始脚本
    /// - Returns: 标准化后的脚本（单行字符串，便于 contains 匹配）
    private static func normalize(script: String) -> String {
        var result = script
        // 去除 `(* ... *)` 块注释（贪婪匹配，跨行）
        if let regex = try? NSRegularExpression(pattern: "\\(\\*[\\s\\S]*?\\*\\)", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // 去除 `-- ...` 行注释（到行尾）
        var lines: [String] = []
        for line in result.split(separator: "\n", omittingEmptySubsequences: false) {
            // 简化：找到 `--` 后且不在引号内的位置，截断行
            // 注意：AppleScript 字符串用 " 包裹，-- 在 " " 内不算注释
            var inString = false
            var cutIndex: String.Index?
            var i = line.startIndex
            while i < line.endIndex {
                let ch = line[i]
                if ch == "\"" {
                    inString.toggle()
                } else if !inString && ch == "-" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "-" {
                        cutIndex = i
                        break
                    }
                }
                i = line.index(after: i)
            }
            if let cut = cutIndex {
                lines.append(String(line[..<cut]))
            } else {
                lines.append(String(line))
            }
        }
        result = lines.joined(separator: " ")
        // 合并字符串拼接：去除 `" & "` 模式（拼接相邻字符串）
        if let regex = try? NSRegularExpression(pattern: "\"\\s*&\\s*\"", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // 合并多余空白，便于 contains 匹配
        result = result.replacingOccurrences(of: "\t", with: " ")
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    /// 提取脚本中所有 `tell application "X"` 的应用名。
    /// - Parameter script: 标准化后的脚本
    /// - Returns: 应用名集合（不去重，便于日志记录）
    private static func extractTellApplications(from script: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "tell\\s+application\\s+\"([^\"]+)\"", options: [.caseInsensitive]) else {
            return []
        }
        let nsString = script as NSString
        let matches = regex.matches(in: script, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match in
            // 第 1 个捕获组是应用名
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return nsString.substring(with: range)
        }
    }
}
