import Foundation

public extension String {
    /// 粗略估算字符串的 token 数。
    ///
    /// 算法：英文按空格分词乘 1.3，非 ASCII 字符（中日韩等）每字约 1.5 token。
    /// 综合两者给出估算值，用于 tokenLimit 截断和文档分块。
    ///
    /// - Note: 本实现与 Rust `aether_core::estimate_tokens`（aether-core/src/token.rs）算法完全一致，
    ///   确保 Apple 端与 CloudflareWorkers 端（走 WASM）输出相同。
    ///   Apple 端保留纯 Swift 实现是因为算法极简（FFI 跨界开销不划算），
    ///   且 AetherFoundation 为基础模块不依赖 AetherRust 二进制。
    ///   后续若引入 `tiktoken-rs` 精确 BPE，两端可同步切换。
    var estimatedTokens: Int {
        let asciiWords = self.split(separator: " ").count
        let nonASCIICount = self.filter { $0.isASCII == false }.count
        let asciiTokenEstimate = Double(asciiWords) * 1.3
        let nonASCIITokenEstimate = Double(nonASCIICount) * 1.5
        return Int(asciiTokenEstimate + nonASCIITokenEstimate)
    }
}
