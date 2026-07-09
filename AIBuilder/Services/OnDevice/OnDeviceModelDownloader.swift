import Foundation
import CryptoKit

/// Day 16: 端侧模型下载器（actor 隔离，保证并发安全）。
/// 基于 URLSessionDownloadTask 流式下载模型文件，支持进度回调、取消、断点续传与 SHA256 校验。
/// 简化实现：单任务串行下载，不支持并发多模型下载。
actor OnDeviceModelDownloader {
    /// 单例
    static let shared = OnDeviceModelDownloader()

    /// 当前下载进度（0.0-1.0）
    private(set) var progress: Double = 0.0
    /// 是否正在下载
    private(set) var isDownloading = false
    /// 最近一次下载错误（供 UI 展示）
    private(set) var lastError: OnDeviceError?
    /// 断点续传数据（取消时保存，resumeDownload 时使用）
    private var resumeData: Data?

    /// 当前下载会话与任务（受 actor 隔离保护）
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var delegate: DownloadDelegate?

    /// 启动下载。下载完成后自动校验 SHA256。
    /// - Parameters:
    ///   - url: 模型文件远端下载地址
    ///   - destinationURL: 本地保存路径
    ///   - expectedSHA256: 期望的 SHA256 摘要（非空时下载完成后校验）
    func startDownload(url: URL, to destinationURL: URL, expectedSHA256: String = "") async {
        // 已在下载则直接返回，避免并发重复下载
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0.0
        lastError = nil

        // 使用 CheckedContinuation 等待下载完成回调（delegate 在后台队列触发）
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
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
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
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
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
            // URLError 已取消时保存 resumeData
            if let urlError = error as? URLError {
                self.resumeData = urlError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            }
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
