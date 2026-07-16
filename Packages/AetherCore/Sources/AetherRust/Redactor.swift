import Foundation
import AetherRustC

/// Swift 友好的 Rust 脱敏包装。
///
/// 将 `TelemetrySanitizer` 的 7 个 NSRegularExpression 模式迁移至 Rust `regex` crate，
/// 统一 Apple/Workers/Android 三端脱敏算法。Rust regex 基于 RE2 语法（线性时间 NFA + SIMD），
/// 批量替换性能优于 NSRegularExpression（ICU 引擎，单线程）。
public enum AetherRustRedactor {
    /// 对输入字符串脱敏（UUID/邮箱/URL/Token/密码字段/路径）。
    /// 返回脱敏后的新字符串，原字符串不变。普通错误信息（如 "Network timeout"）不会被修改。
    public static func redact(_ input: String) -> String {
        return input.withCString { ptr in
            guard let raw = aether_redact(ptr) else { return input }
            defer { aether_free_string(raw) }
            return String(cString: raw)
        }
    }
}
