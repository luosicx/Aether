import Foundation
import AetherFoundation
import AetherRust

/// 遥测日志脱敏工具：在事件入队/上传前移除用户敏感上下文。
/// 使用正则表达式顺序替换，覆盖常见敏感模式（路径、URL、UUID、邮箱、Token、密码字段等）。
///
/// 正则匹配已迁移至 Rust（aether-core，regex crate 线性时间 NFA + SIMD），
/// 统一 Apple/Workers/Android 三端脱敏算法。
/// 如需回退到纯 Swift 实现，将 `useRust` 置为 false 即可。
public enum TelemetrySanitizer {
    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true

    /// 对输入字符串进行脱敏处理，返回替换后的字符串。
    /// 普通错误信息（如 "Network timeout"）不会被修改。
    public static func redact(_ input: String) -> String {
        if Self.useRust {
            return AetherRustRedactor.redact(input)
        }
        return redactSwift(input)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    /// 脱敏规则列表。顺序影响结果：URL 先于路径处理，避免路径规则误伤 URL 的 path 部分。
    /// 使用 try? 配合 guard let 安全创建正则表达式，避免语法错误导致 crash
    private static let patterns: [(NSRegularExpression, String)] = [
        // UUID，如 550e8400-e29b-41d4-a716-446655440000
        (try? NSRegularExpression(
            pattern: #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        ), "[REDACTED_UUID]"),

        // 邮箱地址
        (try? NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        ), "[REDACTED_EMAIL]"),

        // URL（http / https）
        (try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#
        ), "[REDACTED_URL]"),

        // API Token：OpenAI 风格 sk-...、Bearer ...
        (try? NSRegularExpression(
            pattern: #"\bsk-[A-Za-z0-9_-]+\b"#
        ), "[REDACTED_TOKEN]"),
        (try? NSRegularExpression(
            pattern: #"\bBearer\s+[A-Za-z0-9_\-\.]+\b"#
        ), "[REDACTED_TOKEN]"),

        // 密码 / 密钥 / Token 字段：password=...、token: ...、api_key=... 等
        (try? NSRegularExpression(
            pattern: #"(?i)(password|token|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*[^\s&]+"#,
            options: .caseInsensitive
        ), "[REDACTED_CREDENTIAL]"),

        // Unix/macOS 绝对路径，如 /Users/xxx/.ssh/id_rsa、/var/xxx
        // 负向回顾 (?<![:\w]) 避免匹配 URL scheme 后的 // 以及普通单词内部
        (try? NSRegularExpression(
            pattern: #"(?<![:\w])/(?:[\w\-\. ]+/)+[\w\-\. ]+"#
        ), "[REDACTED_PATH]")
    ].compactMap { (maybeRegex, replacement) in
        guard let regex = maybeRegex else { return nil }
        return (regex, replacement)
    }

    /// 纯 Swift 脱敏实现（保留以便回退）。
    private static func redactSwift(_ input: String) -> String {
        var result = input
        for (regex, replacement) in patterns {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: replacement
            )
        }
        return result
    }
}
