import Foundation

/// Day 14: 结构化埋点事件。各 case 关联值携带事件上下文（provider / model / token / latency 等）。
/// 通过 TelemetryService.track() 写入本地环形缓冲，由 LogUploader 批量上报。
enum TelemetryEvent: Sendable {
    /// 用户发送消息：provider / model / 估算输入 token 数
    case messageSent(provider: String, model: String, inputTokens: Int)
    /// LLM 响应：延迟毫秒 / 是否成功 / 输出 token 数
    case llmResponse(latencyMs: Int, success: Bool, outputTokens: Int)
    /// 工具调用：工具名 / 是否成功 / 耗时毫秒
    case toolCall(toolName: String, success: Bool, durationMs: Int)
    /// 触发降级：原 provider / 备用 provider / 原因
    case fallbackTriggered(from: String, to: String, reason: String)
    /// 错误发生：错误类型 / 用户可见消息
    case errorOccurred(errorType: String, userMessage: String)

    /// 事件名（取 case 名字符串，如 "messageSent"）
    var name: String {
        switch self {
        case .messageSent: return "messageSent"
        case .llmResponse: return "llmResponse"
        case .toolCall: return "toolCall"
        case .fallbackTriggered: return "fallbackTriggered"
        case .errorOccurred: return "errorOccurred"
        }
    }

    /// 将关联值编码为 payload 字典（值统一转 String），供上报与调试展示
    var payload: [String: String] {
        switch self {
        case let .messageSent(provider, model, inputTokens):
            return [
                "provider": provider,
                "model": model,
                "inputTokens": String(inputTokens)
            ]
        case let .llmResponse(latencyMs, success, outputTokens):
            return [
                "latencyMs": String(latencyMs),
                "success": String(success),
                "outputTokens": String(outputTokens)
            ]
        case let .toolCall(toolName, success, durationMs):
            return [
                "toolName": toolName,
                "success": String(success),
                "durationMs": String(durationMs)
            ]
        case let .fallbackTriggered(from, to, reason):
            return [
                "from": from,
                "to": to,
                "reason": reason
            ]
        case let .errorOccurred(errorType, userMessage):
            return [
                "errorType": errorType,
                "userMessage": userMessage
            ]
        }
    }
}

/// 单条埋点记录：事件名 + payload + 时间戳，用于本地缓冲与批量上报。
struct TelemetryRecord: Codable, Sendable, Equatable {
    /// 记录唯一标识
    let id: UUID
    /// 事件名（对应 TelemetryEvent.name）
    let event: String
    /// 事件关联值载荷
    let payload: [String: String]
    /// 事件发生时间
    let timestamp: Date
}

/// Day 14: 遥测埋点服务。本地环形缓冲存储最多 1000 条事件，主线程 fire-and-forget 写入。
/// actor 隔离保证并发安全。drain() 供 LogUploader 批量取出并清空。
actor TelemetryService {
    /// 本地环形缓冲，最多 maxBufferSize 条
    private var buffer: [TelemetryRecord] = []

    /// 缓冲区上限，超出移除最旧的一条
    private let maxBufferSize = 1000

    /// 最近一次上报时间，nil 表示尚未上报过
    private(set) var lastUploadAt: Date?

    /// 最近一次上报状态：idle / success / failed
    private(set) var lastUploadStatus: String = "idle"

    /// 单例，供全局 fire-and-forget 调用
    static let shared = TelemetryService()

    /// 记录一条事件：转为 TelemetryRecord 写入 buffer；超出上限移除最旧的一条（removeFirst）。
    func track(_ event: TelemetryEvent) {
        let record = TelemetryRecord(
            id: UUID(),
            event: event.name,
            payload: event.payload,
            timestamp: Date()
        )
        buffer.append(record)
        // 超出上限移除最旧的一条
        if buffer.count > maxBufferSize {
            buffer.removeFirst()
        }
    }

    /// 取出 buffer 全部内容并清空，返回取出的数组。供 LogUploader 批量上报使用。
    func drain() -> [TelemetryRecord] {
        let records = buffer
        buffer.removeAll()
        return records
    }

    /// 判断是否应触发上报：buffer 达阈值、距上次上报超 interval、或从未上报过且有数据。
    /// - Parameters:
    ///   - now: 当前时间
    ///   - threshold: 缓冲数量阈值，默认 100
    ///   - interval: 距上次上报的最小间隔，默认 300 秒（5 分钟）
    func shouldUpload(now: Date, threshold: Int = 100, interval: TimeInterval = 300) -> Bool {
        // 缓冲达到阈值即触发
        if buffer.count >= threshold {
            return true
        }
        // 已上报过：距上次超过 interval 触发
        if let lastUploadAt = lastUploadAt, now.timeIntervalSince(lastUploadAt) >= interval {
            return true
        }
        // 从未上报过且有数据：触发一次首次上报
        if lastUploadAt == nil && !buffer.isEmpty {
            return true
        }
        return false
    }

    /// 当前缓冲区事件数，供 DebugPanel 读取展示
    var bufferCount: Int { buffer.count }
}
