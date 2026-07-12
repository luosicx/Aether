import Foundation

/// 工具参数脱敏器。
///
/// 审计日志与确认弹窗摘要不应暴露命令、脚本、URL、路径等敏感内容。
/// 对已知敏感键替换为 `***`，其余键保留字符串描述。
enum ToolParameterRedactor {
    /// 需要脱敏的参数键集合。
    static let sensitiveKeys: Set<String> = [
        "command",
        "script",
        "url",
        "text",
        "input",
        "path",
        "src",
        "dst",
        "name",
        "app",
        "image_path"
    ]

    /// 对参数字典进行脱敏，返回可读的 JSON 字符串。
    static func redact(parameters: [String: Any]) -> String {
        var sanitized: [String: String] = [:]
        for (key, value) in parameters {
            if sensitiveKeys.contains(key) {
                sanitized[key] = "***"
            } else {
                sanitized[key] = String(describing: value)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: sanitized, options: .sortedKeys),
              let json = String(data: data, encoding: .utf8) else {
            return sanitized.description
        }
        return json
    }

    /// 生成一行简短摘要，用于弹窗展示。
    ///
    /// 仅展示非敏感键；敏感内容用 `***` 代替。
    static func summary(for toolName: String, parameters: [String: Any]) -> String {
        let redacted = redact(parameters: parameters)
        return "操作：\(toolName)\n参数：\(redacted)"
    }
}
