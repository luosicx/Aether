import Foundation
import CoreGraphics
import Vision
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// v1.4: 基于 Apple Vision 框架的 `VisionInferenceEngine` 原生实现。
///
/// v1.3 提供协议与占位实现，v1.4 使用 Apple 原生 Vision 框架组合多个请求
/// （图像分类 / 人脸检测 / 矩形检测 / 文字识别 / 条码检测）提供基础图像理解。
/// 虽不及 MLX-VLM 的语义理解，但无需外部模型，三端原生可用，作为
/// MLX-VLM 集成前的过渡实现与兜底路径（置信度 <0.6 时降级到此）。
///
/// 设计参考 MASTER_PLAN §6.1.4 跨平台 OCR：
/// > Vision 置信度 <0.6 时自动降级到 VLM 路径
/// v1.4 反向：VLM 不可用时降级到 Vision 原生路径。
public final class NativeVisionEngine: VisionInferenceEngine, @unchecked Sendable {
    /// 模型加载状态（Vision 框架无需加载，始终为已加载）
    public let isLoaded = true
    /// 模型名称（用于 UI 展示）
    public let loadedModelName: String? = "Apple Vision (Native)"

    public init() {}

    public func loadModel(at modelPath: URL, modelName: String) async throws {
        // Vision 框架无需加载模型，保持兼容（no-op）
        // 真实 MLX-VLM 集成后将调用 ModelContainer.load
    }

    public func unloadModel() async {
        // Vision 框架无可卸载模型，no-op
    }

    /// 图像理解：组合多个 Vision 请求生成结构化描述
    ///
    /// 流程：
    /// 1. 并发执行 5 个 Vision 请求（分类 / 人脸 / 矩形 / 文字 / 条码）
    /// 2. 汇总结果生成中文描述
    /// 3. 根据 prompt 关键字聚焦返回（如 "文字" → 仅返回 OCR 结果）
    public func describe(image: CGImage, prompt: String) async throws -> String {
        // 并发执行多个 Vision 请求
        async let classification = classifyImage(image)
        async let faces = detectFaces(image)
        async let rectangles = detectRectangles(image)
        async let texts = recognizeTexts(image)
        async let barcodes = detectBarcodes(image)

        let classificationDesc = await classification
        let faceCount = await faces
        let rectCount = await rectangles
        let textList = await texts
        let barcodeList = await barcodes

        // 根据 prompt 聚焦返回
        let lowerPrompt = prompt.lowercased()
        if lowerPrompt.contains("文字") || lowerPrompt.contains("text") || lowerPrompt.contains("ocr") {
            if textList.isEmpty {
                return "图像中未识别到文字。"
            }
            return "识别到 \(textList.count) 行文字：\n" + textList.joined(separator: "\n")
        }

        if lowerPrompt.contains("人脸") || lowerPrompt.contains("face") || lowerPrompt.contains("人") {
            if faceCount == 0 {
                return "图像中未检测到人脸。"
            }
            return "检测到 \(faceCount) 张人脸。"
        }

        if lowerPrompt.contains("条码") || lowerPrompt.contains("barcode") || lowerPrompt.contains("二维码") {
            if barcodeList.isEmpty {
                return "图像中未检测到条码或二维码。"
            }
            return "检测到 \(barcodeList.count) 个条码：\n" + barcodeList.joined(separator: "\n")
        }

        // 默认汇总描述
        var description = "图像理解（Apple Vision 原生）："
        description += "\n- 尺寸：\(image.width)×\(image.height)"
        if !classificationDesc.isEmpty {
            description += "\n- 分类：\(classificationDesc)"
        }
        description += "\n- 人脸：\(faceCount) 张"
        description += "\n- 矩形：\(rectCount) 个"
        if !textList.isEmpty {
            description += "\n- 文字（\(textList.count) 行）：\n  " + textList.joined(separator: "\n  ")
        } else {
            description += "\n- 文字：无"
        }
        if !barcodeList.isEmpty {
            description += "\n- 条码：\(barcodeList.count) 个"
        }
        return description
    }

    // MARK: - 子任务

    /// 单个 Vision 请求的兜底窗口。
    private static let requestDeadline: TimeInterval = 10

    /// Vision 请求的执行队列。
    ///
    /// `VNImageRequestHandler.perform` 是同步阻塞调用，不能留在 Swift 协作线程池上：
    /// `describe` 用五个 `async let` 并发发起请求，runner 的协作池只有与核数等量的线程，
    /// 请求一挂死整个池就被抽干，连兜底分支的 `resume` 都排不上线程，10 秒窗口形同不存在
    /// （CI 上正是如此：加了兜底之后 `testDescribe*` 仍照样越满 60 秒）。
    /// 挪到独立执行队列后，挂死只消耗该队列的工作线程，等待方仍能被兜底放行。
    /// 这里用 `maxConcurrentOperationCount = 5` 而不是并发 DispatchQueue：挂死的 perform
    /// 永远不会交还线程，设上限才能保证最坏只占住 5 条，而不是每调一次 `describe` 再泄漏 5 条。
    private static let workQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.aether.NativeVisionEngine.perform"
        queue.maxConcurrentOperationCount = 5
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// CGImage 未标注 Sendable，但不可变，且每个 box 只被一个队列读取一次。
    private struct ImageBox: @unchecked Sendable {
        let image: CGImage
    }

    /// 在执行队列上跑一个 Vision 请求，超时则以 `fallback` 收尾。
    /// completion handler、超时兜底与 `perform` 抛错三条路径共用同一个
    /// `ResumeOnceContinuation`，谁先到谁生效。
    private func performWithDeadline<Value: Sendable>(
        _ image: CGImage,
        fallback: Value,
        makeRequest: @escaping @Sendable (ResumeOnceContinuation<Value, Never>) -> VNRequest
    ) async -> Value {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            let once = ResumeOnceContinuation(continuation)
            let seconds = Self.requestDeadline
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                once.resume(returning: fallback)
            }
            let box = ImageBox(image: image)
            Self.workQueue.addOperation {
                let request = makeRequest(once)
                let handler = VNImageRequestHandler(cgImage: box.image)
                do {
                    try handler.perform([request])
                } catch {
                    once.resume(returning: fallback)
                }
            }
        }
    }

    /// 图像分类（VNClassifyImageRequest）
    private func classifyImage(_ image: CGImage) async -> String {
        await performWithDeadline(image, fallback: "") { once in
            VNClassifyImageRequest { request, error in
                if error != nil {
                    once.resume(returning: "")
                    return
                }
                let observations = request.results as? [VNClassificationObservation] ?? []
                // 取前 3 个置信度最高的分类
                let top = observations.prefix(3).map { obs in
                    "\(obs.identifier)（\(Int(obs.confidence * 100))%）"
                }
                once.resume(returning: top.joined(separator: " / "))
            }
        }
    }

    /// 人脸检测（VNDetectFaceRectanglesRequest）
    private func detectFaces(_ image: CGImage) async -> Int {
        await performWithDeadline(image, fallback: 0) { once in
            VNDetectFaceRectanglesRequest { request, _ in
                let count = request.results?.count ?? 0
                once.resume(returning: count)
            }
        }
    }

    /// 矩形检测（VNDetectRectanglesRequest）
    private func detectRectangles(_ image: CGImage) async -> Int {
        await performWithDeadline(image, fallback: 0) { once in
            VNDetectRectanglesRequest { request, _ in
                let count = request.results?.count ?? 0
                once.resume(returning: count)
            }
        }
    }

    /// 文字识别（VNRecognizeTextRequest）
    private func recognizeTexts(_ image: CGImage) async -> [String] {
        await performWithDeadline(image, fallback: []) { once in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    once.resume(returning: [])
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                once.resume(returning: texts)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en"]
            return request
        }
    }

    /// 条码检测（VNDetectBarcodesRequest）
    private func detectBarcodes(_ image: CGImage) async -> [String] {
        await performWithDeadline(image, fallback: []) { once in
            VNDetectBarcodesRequest { request, _ in
                let observations = request.results as? [VNBarcodeObservation] ?? []
                let payloads = observations.compactMap { $0.payloadStringValue }
                once.resume(returning: payloads)
            }
        }
    }
}

/// Vision 请求的 completion handler 与 `perform()` 抛错后的 catch 路径可能先后
/// 触发 resume，CheckedContinuation 重复 resume 会直接 fatalError 使整个进程崩溃
/// （CI 上表现为测试进程反复崩溃重启、后续用例全部未执行）。用锁保证只 resume 一次。
final class ResumeOnceContinuation<Value, Failure: Error>: @unchecked Sendable {
    private let continuation: CheckedContinuation<Value, Failure>
    private let lock = NSLock()
    private var resumed = false

    init(_ continuation: CheckedContinuation<Value, Failure>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }

    func resume(throwing error: Failure) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }
}
