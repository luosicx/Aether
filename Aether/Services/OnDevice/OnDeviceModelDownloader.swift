import Foundation
import CryptoKit
import AetherFoundation
import AetherRust

/// Day 16: 端侧模型下载器（actor 隔离，保证并发安全）。
/// 基于 URLSessionDownloadTask 流式下载模型文件，支持进度回调、取消、断点续传与 SHA256 校验。
/// 简化实现：单任务串行下载，不支持并发多模型下载。
actor OnDeviceModelDownloader {
    /// 单例
    static let shared = OnDeviceModelDownloader()

    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true

    /// 当前下载进度（0.0-1.0）
    private(set) var progress: Double = 0.0
    /// 是否正在下载
    private(set) var isDownloading = false
    /// 最近一次下载错误（供 UI 展示）
    private(set) var lastError: OnDeviceError?
    /// 断点续传数据（取消时保存，resumeDownload 时使用）
    private var resumeData: Data?
    /// 是否存在可恢复的断点续传数据（供 UI 决定是否展示「继续下载」按钮）
    var hasResumeData: Bool { resumeData != nil }

    /// 当前下载会话与任务（受 actor 隔离保护）
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var delegate: DownloadDelegate?

    /// 启动下载。下载完成后自动校验 SHA256。主地址失败且未捕获断点续传数据时回退到镜像地址。
    /// - Parameters:
    ///   - url: 模型文件远端下载地址
    ///   - destinationURL: 本地保存路径
    ///   - expectedSHA256: 期望的 SHA256 摘要（非空时下载完成后校验）
    ///   - mirrorURL: 镜像下载地址（主地址失败时回退使用，nil 表示不回退）
    func startDownload(url: URL, to destinationURL: URL, expectedSHA256: String = "", mirrorURL: URL? = nil) async {
        // 已在下载则直接返回，避免并发重复下载
        guard !isDownloading else { return }
        // 若存在断点续传数据，优先续传而非重新下载
        if resumeData != nil {
            await resumeDownload()
            return
        }
        isDownloading = true
        progress = 0.0
        lastError = nil

        let primaryFailed = await performDownload(url: url, to: destinationURL, expectedSHA256: expectedSHA256)

        // 镜像回退：主地址失败且未捕获断点续传数据时，使用镜像地址重试一次
        if primaryFailed, let mirrorURL = mirrorURL, mirrorURL != url {
            let currentResumeExists = resumeData != nil
            if !currentResumeExists {
                isDownloading = true
                progress = 0.0
                lastError = nil
                await performDownload(url: mirrorURL, to: destinationURL, expectedSHA256: expectedSHA256)
            }
        }
    }

    /// 下载完整 MLX 模型目录（含 config.json、tokenizer.json、model.safetensors 等必需文件）。
    /// MLXLMCommon 的 ModelContainer.load 需要完整模型目录，而非单个 safetensors 文件。
    /// 先下载小体积配置文件（无进度追踪），再下载大体积 model.safetensors（有进度追踪与 SHA256 校验）。
    /// - Parameters:
    ///   - repo: HuggingFace 仓库 ID（如 "mlx-community/Llama-3.2-1B-Instruct-4bit"）
    ///   - destinationDirectory: 本地模型目录路径
    ///   - mirrorRepo: ModelScope 镜像仓库 ID（主地址失败时回退，nil 表示不回退）
    ///   - expectedSHA256: model.safetensors 的期望 SHA256（仅校验权重文件，空字符串跳过校验）
    func startModelDownload(repo: String, to destinationDirectory: URL, mirrorRepo: String? = nil, expectedSHA256: String = "") async {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0.0
        lastError = nil

        // 创建本地模型目录
        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        // 小体积配置文件列表（快速下载，不追踪进度）
        let configFiles = ["config.json", "tokenizer_config.json", "special_tokens_map.json", "tokenizer.json"]

        for file in configFiles {
            let hfURL = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
            let destURL = destinationDirectory.appendingPathComponent(file)
            var failed = await downloadFile(url: hfURL, to: destURL)

            // 镜像回退
            if failed, let mirror = mirrorRepo {
                lastError = nil
                let msURL = URL(string: "https://www.modelscope.cn/api/v1/models/\(mirror)/repo?Revision=master&FilePath=\(file)")!
                failed = await downloadFile(url: msURL, to: destURL)
            }

            if failed {
                isDownloading = false
                return
            }
        }

        // 大体积权重文件：model.safetensors（使用 performDownload 以获取进度回调与 SHA256 校验）
        let modelFileURL = URL(string: "https://huggingface.co/\(repo)/resolve/main/model.safetensors")!
        let modelDestURL = destinationDirectory.appendingPathComponent("model.safetensors")

        let modelFailed = await performDownload(url: modelFileURL, to: modelDestURL, expectedSHA256: expectedSHA256)

        // 镜像回退
        if modelFailed, let mirror = mirrorRepo {
            let currentResumeExists = resumeData != nil
            if !currentResumeExists {
                isDownloading = true
                progress = 0.0
                lastError = nil
                let msURL = URL(string: "https://www.modelscope.cn/api/v1/models/\(mirror)/repo?Revision=master&FilePath=model.safetensors")!
                await performDownload(url: msURL, to: modelDestURL, expectedSHA256: expectedSHA256)
            }
        }

        progress = 1.0
        isDownloading = false
    }

    /// 执行单次下载尝试，返回是否失败（lastError 非空即视为失败）。
    /// - Parameters:
    ///   - url: 模型文件远端下载地址
    ///   - destinationURL: 本地保存路径
    ///   - expectedSHA256: 期望的 SHA256 摘要（非空时下载完成后校验）
    /// - Returns: 下载失败返回 true，成功返回 false
    private func performDownload(url: URL, to destinationURL: URL, expectedSHA256: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = DownloadDelegate(
                destinationURL: destinationURL,
                onProgress: { [weak self] p in
                    await self?.updateProgress(p)
                },
                onDone: { [weak self] result in
                    await self?.handleDownloadDone(result: result, destination: destinationURL, expectedSHA256: expectedSHA256)
                    continuation.resume()
                }
            )
            self.delegate = delegate
            let session = URLSession(configuration: makeDownloadSessionConfig(), delegate: delegate, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
        return lastError != nil
    }

    /// 静默下载单个文件（不更新 isDownloading / progress，不校验 SHA256）。
    /// 用于下载 config.json / tokenizer.json 等小体积配置文件。
    /// - Parameters:
    ///   - url: 文件远端下载地址
    ///   - destinationURL: 本地保存路径
    /// - Returns: 下载失败返回 true，成功返回 false
    private func downloadFile(url: URL, to destinationURL: URL) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = DownloadDelegate(
                destinationURL: destinationURL,
                onProgress: { _ in },
                onDone: { [weak self] result in
                    Task { await self?.handleFileDownloadDone(result: result) }
                    continuation.resume()
                }
            )
            self.delegate = delegate
            let session = URLSession(configuration: makeDownloadSessionConfig(), delegate: delegate, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
        return lastError != nil
    }

    /// 断点续传下载（使用上次取消保存的 resumeData）。
    func resumeDownload() async {
        guard !isDownloading, let resumeData = resumeData else { return }
        isDownloading = true
        progress = 0.0
        lastError = nil
        let data = resumeData
        self.resumeData = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = DownloadDelegate(
                destinationURL: URL(fileURLWithPath: NSTemporaryDirectory()),
                onProgress: { [weak self] p in
                    await self?.updateProgress(p)
                },
                onDone: { [weak self] _ in
                    await self?.setIsDownloading(false)
                    continuation.resume()
                }
            )
            self.delegate = delegate
            let session = URLSession(configuration: makeDownloadSessionConfig(), delegate: delegate, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(withResumeData: data)
            self.task = task
            task.resume()
        }
    }

    /// 取消当前下载，保存 resumeData 供后续续传。
    func cancelDownload() {
        if let task = task {
            task.cancel { [weak self] data in
                guard let self = self else { return }
                Task { await self.setResumeData(data) }
            }
        }
        isDownloading = false
        session?.invalidateAndCancel()
        session = nil
    }

    /// 删除本地模型文件。
    /// - Parameter url: 模型文件路径
    /// - Throws: 文件删除失败时抛出 OnDeviceError.loadFailed
    func deleteModel(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OnDeviceError.modelNotFound(url)
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw OnDeviceError.loadFailed(String(format: NSLocalizedString("删除模型文件失败：%@", comment: ""), error.localizedDescription))
        }
    }

    /// 校验文件 SHA256 摘要。
    /// - Parameters:
    ///   - filePath: 待校验文件路径
    ///   - expected: 期望的 SHA256 十六进制摘要
    /// - Returns: 校验通过返回 true
    func verifySHA256(filePath: URL, expected: String) -> Bool {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return false }
        let actual = sha256(of: filePath)
        return actual == expected
    }

    // MARK: - 内部方法

    /// 构建下载专用 URLSessionConfiguration。
    /// Apple 默认 timeoutIntervalForRequest = 60s，对 ~700MB MLX 模型（尤其国内访问 HuggingFace CDN）过短，
    /// 这里放宽到 5 分钟单请求超时、2 小时整体资源超时，并禁用蜂窝、等待连通。
    /// internal 以便单元测试验证配置值。
    func makeDownloadSessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 7200
        config.waitsForConnectivity = true
        config.allowsCellularAccess = false
        return config
    }

    /// 更新下载进度（由 delegate 回调经 actor hop 触发）
    private func updateProgress(_ p: Double) {
        progress = p
    }

    /// 处理下载完成回调：移动文件 → 校验 SHA256 → 更新状态
    private func handleDownloadDone(result: Result<URL, Error>, destination: URL, expectedSHA256: String) {
        isDownloading = false
        switch result {
        case .success(let fileURL):
            // SHA256 校验（expectedSHA256 非空时执行）
            if !expectedSHA256.isEmpty {
                let actual = sha256(of: fileURL)
                guard actual == expectedSHA256 else {
                    lastError = .sha256Mismatch(expected: expectedSHA256, actual: actual)
                    return
                }
            }
            progress = 1.0
            lastError = nil
        case .failure(let error):
            // URLError（取消 / 超时等）时尝试保存 resumeData 供断点续传
            if let urlError = error as? URLError {
                self.resumeData = urlError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                if urlError.code == .timedOut {
                    lastError = .downloadTimeout
                    return
                }
            }
            lastError = .loadFailed(String(format: NSLocalizedString("下载失败：%@", comment: ""), error.localizedDescription))
        }
    }

    /// 处理配置文件下载完成回调（不更新 isDownloading / progress，不校验 SHA256）
    private func handleFileDownloadDone(result: Result<URL, Error>) {
        switch result {
        case .success:
            lastError = nil
        case .failure(let error):
            lastError = .loadFailed(String(format: NSLocalizedString("下载失败：%@", comment: ""), error.localizedDescription))
        }
    }

    /// 设置 resumeData（cancel 回调经 actor hop 写入）
    private func setResumeData(_ data: Data?) {
        resumeData = data
    }

    /// 设置 isDownloading（resumeDownload 的 onDone 回调经 actor hop 写入）
    private func setIsDownloading(_ value: Bool) {
        isDownloading = value
    }

    /// 计算文件 SHA256 摘要（分块读取，避免大文件一次性载入内存）
    private func sha256(of path: URL) -> String {
        if Self.useRust {
            return aetherSha256(of: path)
        }
        return sha256Swift(of: path)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    /// CryptoKit SHA256 兜底实现。
    private func sha256Swift(of path: URL) -> String {
        var hasher = SHA256()
        guard let fileHandle = try? FileHandle(forReadingFrom: path) else { return "" }
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

/// 下载代理：非 isolated 类，在 URLSession 后台队列回调，通过 async 闭包 hop 回 actor 更新状态。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    /// 下载完成后的本地保存路径
    private let destinationURL: URL
    /// 进度回调（async，经 Task hop 回 actor）
    private let onProgress: (Double) async -> Void
    /// 完成回调（success 携带文件路径，failure 携带错误）
    private let onDone: (Result<URL, Error>) async -> Void
    /// 标记是否已回调过 onDone，避免 didFinish 与 didComplete 双触发
    private var doneFired = false

    init(destinationURL: URL,
         onProgress: @escaping (Double) async -> Void,
         onDone: @escaping (Result<URL, Error>) async -> Void) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.onDone = onDone
        super.init()
    }

    /// 下载进度回调
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { await onProgress(p) }
    }

    /// 下载完成：同步移动临时文件到目标路径（避免临时文件被 URLSession 清理后再异步访问）
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 先尝试移动到目标路径；失败则复制后删除临时文件
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            doneFired = true
            Task { await onDone(.success(destinationURL)) }
        } catch {
            if !doneFired {
                doneFired = true
                Task { await onDone(.failure(error)) }
            }
        }
    }

    /// 任务结束回调（成功时 error=nil，失败时携带错误）
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }  // 成功时 error=nil，已由 didFinish 处理
        if !doneFired {
            doneFired = true
            Task { await onDone(.failure(error)) }
        }
    }
}
