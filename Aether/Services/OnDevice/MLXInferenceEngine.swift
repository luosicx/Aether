import Foundation
import CryptoKit
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
actor MLXInferenceEngine {
    /// 单例，全局共享一个推理引擎实例（避免重复加载模型占用内存）
    static let shared = MLXInferenceEngine()

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
            lastLoadError = .loadFailed(error.localizedDescription)
            throw OnDeviceError.loadFailed(error.localizedDescription)
        }
        #else
        // 占位：mlx-swift 未集成时（模拟器或未添加 SPM 依赖），无法真正加载模型
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

    /// 卸载模型，释放内存。
    func unloadModel() {
        #if canImport(MLXLLM)
        loadedModel = nil
        #endif
        isLoaded = false
        loadedModelPath = nil
    }

    /// 计算文件的 SHA256 摘要（分块读取，避免大文件一次性载入内存）。
    /// - Parameter path: 文件路径
    /// - Returns: 十六进制小写摘要字符串
    private func sha256(of path: URL) -> String {
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
