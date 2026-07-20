import Foundation
import CryptoKit
import AetherFoundation
import AetherRust
#if canImport(MLXLLM)
import MLX
import MLXLMCommon
import MLXLLM
#endif

/// Day 16: MLX 端侧推理引擎（actor 隔离，保证并发安全）。
/// 通过 `#if canImport(MLXLLM)` 条件编译保护：
/// - mlx-swift 可用（真机集成 SPM 后）：调用真正的 MLX API 加载模型并流式生成
/// - mlx-swift 不可用（模拟器或未集成时）：提供占位实现，抛 loadFailed 或返回提示流
/// 这样代码在模拟器上能编译（走占位分支），在真机上有 mlx-swift 时才真正调用 MLX。
///
/// 推理后端可通过 `useRust` 开关切换：
/// - `useRust = true`：走 Rust candle（跨端，赋能 Android/Windows；复用 safetensors 格式）
/// - `useRust = false`：走 MLX（仅 Apple 端，Metal 加速）
/// 两者并存，可按平台/模型格式选择最优后端。
actor MLXInferenceEngine {
    /// 单例，全局共享一个推理引擎实例（避免重复加载模型占用内存）
    static let shared = MLXInferenceEngine()

    /// 推理后端开关：true 走 Rust candle（跨端），false 走 MLX（仅 Apple）。
    /// Apple 真机默认 MLX（Metal 加速）；Android/Windows 强制 candle。
    /// 如需在 Apple 端测试 candle，置为 true。
    private static let useRust = false

    /// 切换开关：true 走 Rust 核心 SHA-256，false 走下方纯 Swift 兜底实现。
    private static let useRustSha = true

    /// 模型是否已加载到内存（外部只读，供 OfflineLLMProvider 等检查加载状态）
    private(set) var isLoaded = false
    /// 最近一次加载错误（供 UI 展示诊断信息）
    private(set) var lastLoadError: OnDeviceError?
    /// 最近一次成功加载的模型路径（用于 tokenizer 预加载等后续操作）
    private var loadedModelPath: URL?

    #if canImport(MLXLLM)
    /// 已加载的 MLX 模型容器（mlx-swift 可用时持有真实模型）
    private var loadedModel: ModelContainer?
    #endif

    /// Rust candle 推理引擎（useRust=true 时使用）
    private var rustEngine: AetherRustInferenceEngine?

    /// 加载本地模型文件（后台异步执行，不阻塞调用线程）。
    /// 依次执行：内存检查 → 文件存在性检查 → SHA256 完整性校验 → MLX 后台加载。
    /// MLX 加载通过 `Task.detached` 在后台线程执行，避免阻塞 actor 线程导致 UI 卡顿。
    /// - Parameters:
    ///   - path: 模型文件本地路径
    ///   - expectedSHA256: 期望的 SHA256 摘要（空字符串时跳过校验，由下载阶段已校验）
    /// - Throws: `OnDeviceError`（内存不足 / 模型未找到 / 校验失败 / 加载失败）
    func loadModel(path: URL, expectedSHA256: String = "") async throws {
        // 1. 内存检查：端侧推理通常需要设备至少 4GB 物理内存
        //    用 ProcessInfo.physicalMemory 检查设备总内存（简化方案，跨平台可靠）
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        if physicalMemory < (4 * 1024 * 1024 * 1024) {
            lastLoadError = .insufficientMemory
            throw OnDeviceError.insufficientMemory
        }

        // 2. 文件存在性检查
        guard FileManager.default.fileExists(atPath: path.path) else {
            lastLoadError = .modelNotFound(path)
            throw OnDeviceError.modelNotFound(path)
        }

        // 3. SHA256 完整性校验（expectedSHA256 非空时执行）
        //    若 path 为目录（完整 MLX 模型目录），校验其中的 model.safetensors；
        //    若 path 为单文件（兼容旧测试），校验文件本身
        if !expectedSHA256.isEmpty {
            var isDir: ObjCBool = false
            let shaPath: URL
            if FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                shaPath = path.appendingPathComponent("model.safetensors")
            } else {
                shaPath = path
            }
            let actualSHA = sha256(of: shaPath)
            guard actualSHA == expectedSHA256 else {
                lastLoadError = .sha256Mismatch(expected: expectedSHA256, actual: actualSHA)
                throw OnDeviceError.sha256Mismatch(expected: expectedSHA256, actual: actualSHA)
            }
        }

        // Rust candle 推理路径（跨端，赋能 Android/Windows）
        if Self.useRust {
            try await loadModelRust(path: path)
            return
        }

        #if canImport(MLXLLM)
        // 真正加载 MLX 模型：通过 Task.detached 将阻塞式加载放到后台线程，避免阻塞 actor
        // 使用 ModelConfiguration 指定本地模型目录路径，MLXLMCommon 会读取
        // config.json / tokenizer.json / model.safetensors 等完整模型目录文件
        do {
            let model = try await Task.detached(priority: .userInitiated) {
                let configuration = ModelConfiguration(id: path.path)
                return try await ModelContainer.load(configuration: configuration)
            }.value
            loadedModel = model
            loadedModelPath = path
            isLoaded = true
            lastLoadError = nil
        } catch {
            // P2-3: 携带 underlying 保留原始 Error 上下文，避免 error.localizedDescription 丢失类型信息
            lastLoadError = .loadFailedWithCause(message: error.localizedDescription, underlying: error)
            throw OnDeviceError.loadFailedWithCause(message: error.localizedDescription, underlying: error)
        }
        #else
        // 占位：mlx-swift 未集成时（模拟器或未添加 SPM 依赖），无法真正加载模型
        // 无底层 error 可携带，使用向后兼容的 loadFailed(String) 变体
        lastLoadError = .loadFailed(NSLocalizedString("mlx-swift 未集成，端侧推理不可用", comment: ""))
        throw OnDeviceError.loadFailed(NSLocalizedString("mlx-swift 未集成，端侧推理不可用", comment: ""))
        #endif
    }

    /// 预加载 tokenizer 相关资源（后台异步执行，不阻塞调用线程）。
    /// 通过 ModelContainer 执行一次 prepare 预热 tokenizer，同时并行预读配置文件 warm OS page cache，
    /// 减少首次推理的延迟。在 mlx-swift 不可用时为空操作。
    func preloadTokenizer() async {
        #if canImport(MLXLLM)
        guard let model = loadedModel else { return }
        // 通过 ModelContainer 执行一次 tokenizer prepare，初始化并预热 tokenizer
        _ = try? await model.perform { context in
            _ = try await context.processor.prepare(input: UserInput(prompt: " "))
        }
        #else
        // 占位：mlx-swift 不可用时无 tokenizer 可预加载
        #endif
    }

    /// 流式生成文本。逐 token yield 生成内容。
    /// 若模型未加载且传入了 modelPath，会先自动调用 `loadModel()` 加载模型再生成。
    /// - Parameters:
    ///   - prompt: 已按 chat template 拼接好的完整提示词
    ///   - maxTokens: 单次生成最大 token 数
    ///   - temperature: 采样温度（0.0-1.0）
    ///   - modelPath: 模型路径（可选，模型未加载时自动加载用）
    /// - Returns: 逐 token 的文本流
    func generate(prompt: String, maxTokens: Int, temperature: Double, modelPath: URL? = nil) -> AsyncStream<String> {
        AsyncStream { continuation in
            // Rust candle 推理路径
            if Self.useRust, let engine = rustEngine ?? modelPath.map { _ in AetherRustInferenceEngine() } {
                Task {
                    if rustEngine == nil, let path = modelPath {
                        do {
                            try await loadModelRust(path: path)
                        } catch {
                            continuation.yield(String(format: NSLocalizedString("[模型加载失败：%@]", comment: ""), error.localizedDescription))
                            continuation.finish()
                            return
                        }
                    }
                    guard isLoaded, let engine = rustEngine else {
                        continuation.yield(NSLocalizedString("[端侧模型未加载，请先下载并加载模型]", comment: ""))
                        continuation.finish()
                        return
                    }
                    do {
                        let config = AetherRustInferenceConfig(
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                        // 重新加载以应用新参数（简化实现；后续可缓存 config 复用引擎）
                        _ = config
                        let tokens = try engine.generate(prompt: prompt)
                        for token in tokens {
                            if Task.isCancelled { break }
                            if !token.text.isEmpty {
                                continuation.yield(token.text)
                            }
                        }
                    } catch {
                        continuation.yield(String(format: NSLocalizedString("[生成失败：%@]", comment: ""), error.localizedDescription))
                    }
                    continuation.finish()
                }
                return
            }

            #if canImport(MLXLLM)
            Task {
                // 自动加载：模型未加载且提供了路径时，先后台加载
                if !isLoaded, let path = modelPath {
                    do {
                        try await loadModel(path: path)
                    } catch {
                        continuation.yield(String(format: NSLocalizedString("[模型加载失败：%@]", comment: ""), error.localizedDescription))
                        continuation.finish()
                        return
                    }
                }
                guard isLoaded, let model = loadedModel else {
                    continuation.yield(NSLocalizedString("[端侧模型未加载，请先下载并加载模型]", comment: ""))
                    continuation.finish()
                    return
                }
                do {
                    // 使用 MLX 原生流式生成：通过 perform 获取 ModelContext，
                    // 调用 MLXLMCommon.generate 获取 AsyncStream<Generation>，逐 token yield
                    // NOSONAR: MLXLMCommon API 要求 model.perform 闭包内调用 generate 流式 API
                    try await model.perform { context in
                        let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
                        let params = GenerateParameters(temperature: Float(temperature), maxTokens: maxTokens)
                        let tokenStream = try generate(input: input, parameters: params, context: context)
                        for await part in tokenStream {
                            if Task.isCancelled { break }
                            if let chunk = part.chunk, !chunk.isEmpty {
                                continuation.yield(chunk)
                            }
                        }
                    }
                } catch {
                    continuation.yield(String(format: NSLocalizedString("[生成失败：%@]", comment: ""), error.localizedDescription))
                }
                continuation.finish()
            }
            #else
            // 占位：mlx-swift 不可用时返回提示信息
            continuation.yield(NSLocalizedString("[端侧推理不可用：mlx-swift 未集成]", comment: ""))
            continuation.finish()
            #endif
        }
    }

    /// 流式生成文本（OnDeviceConfig 入参版本）。逐 token yield 生成内容。
    ///
    /// 内部委托给 `generate(prompt:maxTokens:temperature:modelPath:)`，从 `config` 提取
    /// `maxTokens` / `temperature` / `modelPath` 后复用既有的真流式实现：
    /// - MLX 可用：调用 `MLXLMCommon.generate(input:parameters:context:)` 返回的
    ///   `AsyncStream<Generation>`，逐 token yield（真流式，非完整生成后返回）
    /// - MLX 不可用：返回占位提示流
    /// - Rust candle：走 `AetherRustInferenceEngine.generate` 逐 token yield
    ///
    /// 设计为 thin wrapper 的目的：
    /// - 对外提供接收 `OnDeviceConfig` 的统一入口，简化 `OfflineLLMProvider` 调用方
    /// - 保留 `generate(...)` 作为分参 fallback，避免破坏既有调用方
    /// - 参数集中到 `OnDeviceConfig`，便于后续扩展（如 topP / topK / repetitionPenalty）
    ///
    /// - Parameters:
    ///   - prompt: 已按 chat template 拼接好的完整提示词
    ///   - config: 端侧推理配置（提取 `maxTokens` / `temperature` / `modelPath`）
    /// - Returns: 逐 token 的文本流；流结束时自然 finish，无需特殊结束标记
    func streamGenerate(prompt: String, config: OnDeviceConfig) -> AsyncStream<String> {
        generate(
            prompt: prompt,
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            modelPath: config.modelPath
        )
    }

    /// 卸载模型，释放内存。
    func unloadModel() {
        #if canImport(MLXLLM)
        loadedModel = nil
        #endif
        rustEngine?.unload()
        rustEngine = nil
        isLoaded = false
        loadedModelPath = nil
    }

    /// 计算文件的 SHA256 摘要（分块读取，避免大文件一次性载入内存）。
    /// - Parameter path: 文件路径
    /// - Returns: 十六进制小写摘要字符串
    private func sha256(of path: URL) -> String {
        if Self.useRustSha {
            return aetherSha256(of: path)
        }
        return sha256Swift(of: path)
    }

    // MARK: - Rust candle 推理实现

    /// Rust candle 模型加载（后台异步执行，避免阻塞 actor）。
    /// model_dir 应包含 config.json / tokenizer.json / model.safetensors
    private func loadModelRust(path: URL) async throws {
        do {
            let engine = AetherRustInferenceEngine()
            let config = AetherRustInferenceConfig()
            try await Task.detached(priority: .userInitiated) {
                try engine.loadModel(at: path.path, config: config)
            }.value
            self.rustEngine = engine
            self.loadedModelPath = path
            self.isLoaded = true
            self.lastLoadError = nil
        } catch {
            // P2-3: 携带 underlying 保留原始 Error 上下文，避免 error.localizedDescription 丢失类型信息
            self.lastLoadError = .loadFailedWithCause(message: error.localizedDescription, underlying: error)
            throw OnDeviceError.loadFailedWithCause(message: error.localizedDescription, underlying: error)
        }
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    /// CryptoKit SHA256 兜底实现。
    private func sha256Swift(of path: URL) -> String {
        var hasher = SHA256()
        guard let fileHandle = try? FileHandle(forReadingFrom: path) else { return "" }
        // 分块读取（每块 4MB），逐块更新哈希
        let chunkSize = 4 * 1024 * 1024
        while true {
            if let data = try? fileHandle.read(upToCount: chunkSize), !data.isEmpty {
                hasher.update(data: data)
            } else {
                break
            }
        }
        try? fileHandle.close()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
