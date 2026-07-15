import Foundation
import SwiftData
import UserNotifications
import AetherFoundation
import AetherServices

/// Day 17: 健康洞察生成器。读取健康数据后调用 LLM 生成健康建议，并持久化到 SwiftData。
///
/// Task 2.4: 通过注入 HealthDataSource 协议解耦对 HealthKit 的直接依赖。
/// - iOS: 注入 HealthKitAdapter（实现 HealthDataSource）
/// - macOS: 注入 nil（无健康数据，跳过健康上下文）
///
/// 设计要点：
/// - 用 `actor` 隔离，避免与主线程共享 ModelContext 引发数据竞争
/// - 通过工厂方法 `make(modelContext:)` 注入默认 LLMProvider 与 HealthDataSource
/// - 生成完成后追加免责声明，并通过 `sendInsightNotification` 推送本地通知
actor HealthInsightGenerator {
    /// LLM 供应商，用于生成洞察文本
    private let llmProvider: LLMProvider
    /// SwiftData 上下文，用于持久化 HealthInsight
    private let modelContext: ModelContext
    /// 健康数据源（平台无关协议）。nil 时使用空数据跳过健康上下文（macOS 默认）
    private let dataSource: HealthDataSource?

    /// 创建 HealthInsightGenerator 实例
    /// - Parameters:
    ///   - llmProvider: LLM 供应商
    ///   - dataSource: 健康数据源（iOS 注入 HealthKitAdapter，macOS 注入 nil）
    ///   - modelContext: SwiftData 上下文
    init(llmProvider: LLMProvider, dataSource: HealthDataSource?, modelContext: ModelContext) {
        self.llmProvider = llmProvider
        self.dataSource = dataSource
        self.modelContext = modelContext
    }

    /// 生成健康洞察。读取 N 天健康数据后调用 LLM 生成建议，写入 SwiftData。
    /// - Parameter days: 聚合最近 N 天数据，默认 7 天
    /// - Returns: 持久化后的 HealthInsight 实例
    func generateInsight(days: Int = 7) async throws -> HealthInsight {
        // 1. 通过数据源协议读取 N 天数据（无数据源或未授权时返回空字典，不抛错）
        let heartRate: [Date: Double]
        let sleep: [Date: Double]
        let steps: [Date: Int]

        if let dataSource {
            heartRate = (try? await dataSource.fetchHeartRate(days: days)) ?? [:]
            sleep = (try? await dataSource.fetchSleepAnalysis(days: days)) ?? [:]
            steps = (try? await dataSource.fetchStepCount(days: days)) ?? [:]
        } else {
            heartRate = [:]
            sleep = [:]
            steps = [:]
        }

        // 2. 构造 prompt（含聚合数据 + 用户偏好 + "请基于以下健康数据给出 3 条具体建议"）
        let prompt = constructPrompt(heartRate: heartRate, sleep: sleep, steps: steps, days: days)

        // 3. 调用 LLMProvider.chat 生成洞察文本
        let messages: [APIMessage] = [
            APIMessage(role: "system", content: "你是健康助手，根据用户的健康数据给出具体可行的建议。", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: prompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]
        let config = ChatConfig.default
        let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
        var insightText = ""
        for await chunk in stream {
            insightText += chunk
        }

        // 4. 追加免责声明
        insightText += "\n\n" + NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")

        // 5. 聚合指标用于 relatedMetrics
        let avgHeartRate = heartRate.isEmpty ? 0.0 : heartRate.values.reduce(0, +) / Double(heartRate.count)
        let avgSleep = sleep.isEmpty ? 0.0 : sleep.values.reduce(0, +) / Double(sleep.count)
        let totalSteps = steps.values.reduce(0, +)

        // 6. 存储 HealthInsight 到 SwiftData
        let insight = HealthInsight(
            timestamp: Date(),
            insightType: "overall",
            content: insightText,
            relatedMetrics: [
                "avgHeartRate": avgHeartRate,
                "avgSleepHours": avgSleep,
                "totalSteps": Double(totalSteps)
            ]
        )
        modelContext.insert(insight)
        try modelContext.save()

        return insight
    }

    /// 发送洞察生成的本地通知（1 秒后触发）
    /// - Parameter insight: 生成的 HealthInsight
    nonisolated func sendInsightNotification(_ insight: HealthInsight) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("健康洞察已生成", comment: "")
        // 通知正文取洞察内容前 80 字符（避免过长）
        let preview = insight.content.prefix(80)
        content.body = String(preview)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "health-insight-\(insight.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// 工厂方法：注入默认 LLMProvider（DeepSeek）与平台对应的 HealthDataSource。
    /// - Parameter modelContext: SwiftData 上下文
    /// - Returns: 配置好的 HealthInsightGenerator
    static func make(modelContext: ModelContext) -> HealthInsightGenerator {
        let provider = ModelProviderFactory.make(.deepseek)
        // Task 2.4: iOS 注入 HealthKitService（实现 HealthDataSource），macOS 注入 nil
        #if os(iOS)
        let dataSource: HealthDataSource? = HealthKitService()
        #else
        let dataSource: HealthDataSource? = nil
        #endif
        return HealthInsightGenerator(llmProvider: provider, dataSource: dataSource, modelContext: modelContext)
    }

    /// 构造发送给 LLM 的 prompt，包含聚合后的健康数据与请求建议的指令。
    private nonisolated func constructPrompt(heartRate: [Date: Double], sleep: [Date: Double], steps: [Date: Int], days: Int) -> String {
        var lines: [String] = []
        lines.append(String(format: NSLocalizedString("以下是最近 %d 天的健康数据：", comment: ""), days))

        // 心率聚合
        if heartRate.isEmpty {
            lines.append(NSLocalizedString("- 心率：无数据", comment: ""))
        } else {
            let avgHR = heartRate.values.reduce(0, +) / Double(heartRate.count)
            let maxHR = heartRate.values.max() ?? 0
            let minHR = heartRate.values.min() ?? 0
            lines.append(String(format: NSLocalizedString("- 心率：平均 %.1f bpm，最高 %.1f bpm，最低 %.1f bpm", comment: ""), avgHR, maxHR, minHR))
        }

        // 睡眠聚合
        if sleep.isEmpty {
            lines.append(NSLocalizedString("- 睡眠：无数据", comment: ""))
        } else {
            let avgSleep = sleep.values.reduce(0, +) / Double(sleep.count)
            lines.append(String(format: NSLocalizedString("- 睡眠：平均 %.1f 小时/天", comment: ""), avgSleep))
        }

        // 步数聚合
        if steps.isEmpty {
            lines.append(NSLocalizedString("- 步数：无数据", comment: ""))
        } else {
            let avgSteps = Double(steps.values.reduce(0, +)) / Double(steps.count)
            lines.append(String(format: NSLocalizedString("- 步数：平均 %.0f 步/天", comment: ""), avgSteps))
        }

        lines.append("")
        lines.append(NSLocalizedString("请基于以上健康数据给出 3 条具体建议，关注改善睡眠质量、合理运动强度与日常活动量。", comment: ""))

        return lines.joined(separator: "\n")
    }
}
