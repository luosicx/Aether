import Foundation
import AetherRustC

/// Swift 友好的 Rust SHA-256 流式哈希包装。
///
/// 将 `MLXInferenceEngine` 与 `OnDeviceModelDownloader` 中两处重复的
/// CryptoKit `SHA256` 实现统一迁移至 Rust `sha2` crate，
/// 去除 CryptoKit 依赖。保持分块读取特性，避免大文件一次性载入内存。
public final class AetherRustSha256: @unchecked Sendable {
    private let state: OpaquePointer

    public init() {
        state = aether_sha256_new()
    }

    deinit {
        aether_sha256_free(state)
    }

    /// 追加数据到哈希。可多次调用以流式处理大文件。
    public func update(_ data: Data) {
        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let base = rawBuffer.baseAddress, rawBuffer.count > 0 else { return }
            aether_sha256_update(state, base.assumingMemoryBound(to: UInt8.self), UInt(rawBuffer.count))
        }
    }

    /// 完成哈希，返回小写十六进制字符串（64 字符）。
    /// 不消费 state，调用后仍可继续 update（与 Rust finalize 行为一致）。
    public func finalize() -> String {
        guard let raw = aether_sha256_finalize(state) else { return "" }
        defer { aether_free_string(raw) }
        return String(cString: raw)
    }
}

/// 便捷工具：计算文件的 SHA-256（分块 4MB 读取，避免大文件内存问题）。
/// 返回小写十六进制摘要，读取失败返回空串。
public func aetherSha256(of path: URL) -> String {
    guard let fileHandle = try? FileHandle(forReadingFrom: path) else { return "" }
    let hasher = AetherRustSha256()
    let chunkSize = 4 * 1024 * 1024
    while true {
        if let data = try? fileHandle.read(upToCount: chunkSize), !data.isEmpty {
            hasher.update(data)
        } else {
            break
        }
    }
    try? fileHandle.close()
    return hasher.finalize()
}
