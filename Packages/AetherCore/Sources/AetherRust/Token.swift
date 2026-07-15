import Foundation
import AetherRustC

/// Swift 友好的 Rust token 计数包装。
///
/// 将 `String.estimatedTokens` 的粗估公式迁移至 Rust（aether-core），
/// 统一 Apple/Workers 两端算法。后续可替换为 `tiktoken-rs` 精确 BPE，
/// 调用方无感升级。
public enum AetherRustToken {
    /// 粗略估算字符串的 token 数（与 Swift `String.estimatedTokens` 算法一致）。
    /// 空字符串返回 0。
    public static func estimateTokens(_ s: String) -> Int {
        return s.withCString { ptr in
            aether_estimate_tokens(ptr)
        }
    }
}
