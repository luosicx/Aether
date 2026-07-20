import Foundation

/// Rust FFI 调用错误。
public enum AetherRustError: Error, Equatable, LocalizedError {
    case nullResult
    case invalidUTF8
    case decodeFailed(String)

    /// 用户可见的错误描述（中文本地化）。
    /// 用于 UI 层展示，避免暴露原始 FFI 错误细节。
    public var errorDescription: String? {
        switch self {
        case .nullResult:
            return NSLocalizedString("Rust 核心返回空指针", comment: "")
        case .invalidUTF8:
            return NSLocalizedString("Rust 核心返回数据非 UTF-8 编码", comment: "")
        case .decodeFailed(let reason):
            return String(format: NSLocalizedString("Rust 核心返回数据解码失败：%@", comment: ""), reason)
        }
    }
}
