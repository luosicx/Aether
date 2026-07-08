import Foundation

/// Day 14: 日志批量上报服务。从 TelemetryService 取出缓冲事件，批量 POST 到国内云存储（阿里云 OSS / 腾讯云 COS）。
/// 失败时指数退避重试最多 3 次；事件上报失败即丢弃，避免无限累积。actor 隔离保证并发安全。
actor LogUploader {
    /// 上报 endpoint，默认指向阿里云 OSS 占位 URL，可通过 init 注入用于测试
    private let endpointURL: URL

    /// 单批上报条数上限（预留，当前 Phase 直接全量上报 drain 出的全部记录）
    private let batchSize = 100

    /// 最大重试次数（含首次共 3 次尝试）
    private let maxRetries = 3

    /// 最近一次上报时间
    private(set) var lastUploadAt: Date?

    /// 最近一次上报状态：idle / success / failed
    private(set) var lastUploadStatus: String = "idle"

    /// 单例，供 App 启动与后台任务调度调用
    static let shared = LogUploader()

    /// 允许测试注入 endpoint
    init(endpointURL: URL? = nil) {
        self.endpointURL = endpointURL ?? URL(
            string: "https://aibuilder-logs.oss-cn-hangzhou.aliyuncs.com/logs"
        )!
    }

    /// 触发上报：drain 出 TelemetryService 缓冲 → 编码为 JSON 数组 → POST 到 endpoint。
    /// 缓冲为空时记为 success（nothing to upload）；失败时记为 failed 并丢弃事件（不回写 buffer）。
    func uploadIfNeeded() async {
        // 取出缓冲全部内容并清空
        let records = await TelemetryService.shared.drain()
        let now = Date()
        // 无数据可上报：直接记成功
        if records.isEmpty {
            lastUploadAt = now
            lastUploadStatus = "success"
            return
        }
        // 尝试批量上报，带重试
        do {
            try await uploadBatch(records, retry: 0)
            lastUploadAt = now
            lastUploadStatus = "success"
        } catch {
            // 上报失败：丢弃事件（不回写 buffer，避免无限累积）
            lastUploadStatus = "failed"
        }
    }

    /// 批量上报一批记录：编码为 JSON 数组 → 构造 POST 请求 → 发送。
    /// 成功（2xx）直接返回；失败时按指数退避（1s / 2s / 4s）递归重试，超过 maxRetries 抛错。
    /// - Parameters:
    ///   - records: 待上报记录数组
    ///   - retry: 当前重试次数（从 0 开始）
    private func uploadBatch(_ records: [TelemetryRecord], retry: Int) async throws {
        // 编码为 JSON 数组
        let jsonData = try JSONEncoder().encode(records)
        // 构造 POST 请求
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // 校验状态码：2xx 视为成功
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return
            }
            // 非 2xx 视为失败，进入重试逻辑
            throw URLError(.badServerResponse)
        } catch {
            // 重试判定：未达上限则指数退避后递归
            if retry < maxRetries - 1 {
                // 指数退避：1s * 2^retry（1s / 2s / 4s）
                let delaySeconds = pow(2.0, Double(retry))
                let nanos = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                try await uploadBatch(records, retry: retry + 1)
                return
            }
            // 超过重试上限，抛错
            throw error
        }
    }
}
