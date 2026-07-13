import Foundation

/// 提示注入基础检测器。
/// 在用户输入进入 LLM 前检测常见的提示注入模式，并返回命中原因。
enum PromptInjectionDetector {
    /// 直接子串匹配模式（不区分大小写）。
    /// 顺序影响 `reason(for:)` 返回的原因，较长/更具体的模式放前面，避免被更短模式抢先。
    private static let substringPatterns: [(phrase: String, reason: String)] = [
        ("ignore all previous instructions", "包含 \"ignore all previous instructions\""),
        ("ignore previous instructions", "包含 \"ignore previous instructions\""),
        ("from now on you are", "包含 \"from now on you are\""),
        ("system prompt", "包含 \"system prompt\""),
        ("developer mode", "包含 \"developer mode\""),
        ("jailbreak", "包含 \"jailbreak\""),
        ("you are now", "包含 \"you are now\""),
        ("disregard", "包含 \"disregard\""),
        ("simulate", "包含 \"simulate\"")
    ]

    /// 用于降低 "DAN" 误报的指令性上下文关键词。
    /// 仅当 DAN 作为独立词出现且同时出现这些上下文词之一时才命中。
    private static let danContextIndicators = [
        "ignore", "disregard", "system prompt", "developer mode", "jailbreak",
        "you are now", "from now on you are", "simulate", "do anything",
        "act as", "from now on", "you are"
    ]

    /// 判断输入是否疑似提示注入。
    /// - Parameter input: 用户原始输入。
    /// - Returns: 命中任意规则时返回 `true`。
    static func isSuspicious(_ input: String) -> Bool {
        let lower = input.lowercased()
        for (phrase, _) in substringPatterns where lower.contains(phrase) {
            return true
        }
        if containsStandaloneDAN(lower), hasInstructionContext(lower) {
            return true
        }
        return false
    }

    /// 返回命中原因，未命中返回 `nil`。
    /// - Parameter input: 用户原始输入。
    /// - Returns: 命中规则的描述字符串。
    static func reason(for input: String) -> String? {
        let lower = input.lowercased()
        for (phrase, reason) in substringPatterns where lower.contains(phrase) {
            return reason
        }
        if containsStandaloneDAN(lower), hasInstructionContext(lower) {
            return "包含提示注入关键词 \"DAN\" 且伴有指令性上下文"
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func containsStandaloneDAN(_ lower: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\bDAN\b"#, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(lower.startIndex..., in: lower)
        return regex.firstMatch(in: lower, options: [], range: range) != nil
    }

    private static func hasInstructionContext(_ lower: String) -> Bool {
        danContextIndicators.contains { lower.contains($0) }
    }
}
