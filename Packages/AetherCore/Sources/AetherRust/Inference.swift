import Foundation
import AetherRustC

/// Swift 友好的 Rust candle 推理引擎包装。
///
/// 将 `MLXInferenceEngine.swift`（Apple MLX，仅 Apple 端）迁移为 candle，
/// 赋能 Android/Windows。复用 safetensors 模型格式，跨端共享。
///
/// 架构：
/// - Rust 侧 aether-core（纯逻辑）+ aether-core-ffi（unsafe mmap）
/// - 本 wrapper 提供 Swift 友好的 API，与 MLXInferenceEngine 对齐
///
/// 使用：
/// ```swift
/// let engine = AetherRustInferenceEngine()
/// try engine.loadModel(at: modelDir, config: .init(temperature: 0.7))
/// for token in try engine.generate(prompt: "你好") { print(token.text) }
/// ```
///
/// 线程安全契约：实例应仅在单一 actor 中使用（如 `MLXInferenceEngine` actor
/// 持有 `rustEngine`）。跨 actor 共享需在调用点加 NSLock，否则并发 `generate`
/// 会破坏 KV cache 导致输出错乱。Rust FFI 层（`aether_inference_generate`）
/// 仅对 `Option<LoadedModel>` 加 Mutex 保护加载状态，推理过程本身未加锁。
public final class AetherRustInferenceEngine: @unchecked Sendable {
    private let handle: OpaquePointer

    /// 创建推理引擎（未加载模型）。
    public init() {
        self.handle = aether_inference_new()
    }

    deinit {
        aether_inference_free(handle)
    }

    /// 加载本地 safetensors 模型目录。
    ///
    /// modelDir 应包含：config.json / tokenizer.json / model.safetensors
    /// - Parameters:
    ///   - modelDir: 模型目录路径
    ///   - config: 推理参数（温度、maxTokens 等）
    /// - Throws: 加载失败时抛 `AetherRustInferenceError.loadFailed`
    public func loadModel(at modelDir: String, config: AetherRustInferenceConfig) throws {
        let paramsJson = config.encodeJSON()
        let result = modelDir.withCString { dirCStr -> Int32 in
            paramsJson.withCString { paramsCStr in
                aether_inference_load_model(handle, dirCStr, paramsCStr)
            }
        }
        guard result == 0 else {
            throw AetherRustInferenceError.loadFailed
        }
    }

    /// 模型是否已加载。
    public var isLoaded: Bool {
        aether_inference_is_loaded(handle)
    }

    /// 卸载模型，释放内存。
    public func unload() {
        aether_inference_unload(handle)
    }

    /// 流式生成文本，返回所有 token（一次性返回）。
    ///
    /// 对应 MLXInferenceEngine.generate 的流式生成。
    /// Swift 侧可逐个 yield 实现流式效果。
    /// - Parameter prompt: 已按 chat template 拼接好的完整提示词
    /// - Returns: 生成的 token 数组（最后一个可能 isEnd=true 表示 EOS）
    /// - Throws: 推理失败时抛对应错误
    public func generate(prompt: String) throws -> [AetherRustGeneratedToken] {
        guard let cResult = prompt.withCString({ cstr in
            aether_inference_generate(handle, cstr)
        }) else {
            throw AetherRustInferenceError.inferenceFailed
        }
        defer { aether_free_string(cResult) }
        let json = String(cString: cResult)
        return try AetherRustGeneratedToken.decodeArray(from: json)
    }

    /// 一次性生成完整文本（非流式）。
    /// - Parameter prompt: 提示词
    /// - Returns: 拼接后的完整文本
    /// - Throws: 推理失败时抛对应错误
    public func generateText(prompt: String) throws -> String {
        guard let cResult = prompt.withCString({ cstr in
            aether_inference_generate_text(handle, cstr)
        }) else {
            throw AetherRustInferenceError.inferenceFailed
        }
        defer { aether_free_string(cResult) }
        return String(cString: cResult)
    }
}

/// 推理参数。对应 Rust 侧 InferenceConfig。
public struct AetherRustInferenceConfig {
    /// 采样温度（0.0-1.0，0 表示贪婪）。
    public var temperature: Double
    /// 单次生成最大 token 数。
    public var maxTokens: Int
    /// 重复惩罚（1.0-1.5，默认 1.1）。
    public var repeatPenalty: Float
    /// 重复惩罚窗口（默认 64）。
    public var repeatLastN: Int
    /// top-p 采样阈值（默认 0.9）。
    public var topP: Double
    /// 随机种子（nil 表示随机）。
    public var seed: UInt64?
    /// EOS token id（nil 时从 config.json 读取）。
    public var eosTokenId: UInt32?

    public init(
        temperature: Double = 0.7,
        maxTokens: Int = 1024,
        repeatPenalty: Float = 1.1,
        repeatLastN: Int = 64,
        topP: Double = 0.9,
        seed: UInt64? = nil,
        eosTokenId: UInt32? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.topP = topP
        self.seed = seed
        self.eosTokenId = eosTokenId
    }

    /// 编码为 Rust 侧期望的 JSON 格式。
    fileprivate func encodeJSON() -> String {
        var dict: [String: Any] = [
            "temperature": temperature,
            "maxTokens": maxTokens,
            "repeatPenalty": repeatPenalty,
            "repeatLastN": repeatLastN,
            "topP": topP,
        ]
        if let seed = seed { dict["seed"] = seed }
        if let eosTokenId = eosTokenId { dict["eosTokenId"] = eosTokenId }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

/// 生成的单个 token。
public struct AetherRustGeneratedToken: Equatable {
    /// token 对应的文本片段。
    public let text: String
    /// 是否为生成结束 token（EOS）。
    public let isEnd: Bool

    /// 从 Rust 侧返回的 JSON 数组解析。
    /// 格式：`[{"text":"hello","isEnd":false},...]`
    static func decodeArray(from json: String) throws -> [AetherRustGeneratedToken] {
        struct ErrorWrapper: Decodable {
            let error: String?
        }
        struct TokenView: Decodable {
            let text: String
            let isEnd: Bool
        }
        guard let data = json.data(using: .utf8) else {
            throw AetherRustInferenceError.invalidJson
        }
        // 先检查是否为错误响应
        if let err = try? JSONDecoder().decode(ErrorWrapper.self, from: data), let msg = err.error {
            throw AetherRustInferenceError.inferenceFailed
        }
        let views = try JSONDecoder().decode([TokenView].self, from: data)
        return views.map { AetherRustGeneratedToken(text: $0.text, isEnd: $0.isEnd) }
    }
}

/// 推理错误。
public enum AetherRustInferenceError: Error, LocalizedError {
    case loadFailed
    case inferenceFailed
    case invalidJson
    case notLoaded

    /// 用户可见的错误描述（中文本地化）。
    public var errorDescription: String? {
        switch self {
        case .loadFailed:
            return NSLocalizedString("端侧模型加载失败", comment: "")
        case .inferenceFailed:
            return NSLocalizedString("端侧推理执行失败", comment: "")
        case .invalidJson:
            return NSLocalizedString("Rust 推理返回数据 JSON 解析失败", comment: "")
        case .notLoaded:
            return NSLocalizedString("端侧模型未加载，请先加载模型", comment: "")
        }
    }
}
