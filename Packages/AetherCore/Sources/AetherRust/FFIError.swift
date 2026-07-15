import Foundation

/// Rust FFI 调用错误。
public enum AetherRustError: Error, Equatable {
    case nullResult
    case invalidUTF8
    case decodeFailed(String)
}
