import Foundation
import SwiftData

/// Day 17: 持久化 AI 生成的健康洞察，由 HealthInsightGenerator 调用 LLM 后写入。
///
/// 字段说明：
/// - `insightType`：洞察类别，如 "sleep" / "heart" / "steps" / "overall"
/// - `content`：AI 生成的洞察文本，含免责声明
/// - `relatedMetrics`：本次洞察依据的聚合指标（如 avgHeartRate / sleepHours / totalSteps）
@Model
final class HealthInsight {
    /// 唯一标识
    var id: UUID
    /// 生成时间
    var timestamp: Date
    /// 洞察类别："sleep" / "heart" / "steps" / "overall"
    var insightType: String
    /// AI 生成的洞察文本，含免责声明
    var content: String
    /// JSON 编码的聚合指标，如 ["avgHeartRate": 72, "sleepHours": 6.5]
    var relatedMetrics: [String: Double]

    /// 创建 HealthInsight 实例
    /// - Parameters:
    ///   - id: 唯一标识，默认 UUID()
    ///   - timestamp: 生成时间，默认当前时间
    ///   - insightType: 洞察类别
    ///   - content: AI 生成的洞察文本，含免责声明
    ///   - relatedMetrics: 本次洞察依据的聚合指标，默认空字典
    init(id: UUID = UUID(), timestamp: Date = Date(), insightType: String, content: String, relatedMetrics: [String: Double] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.insightType = insightType
        self.content = content
        self.relatedMetrics = relatedMetrics
    }
}
