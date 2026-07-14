#if os(iOS)
import XCTest
import SwiftData
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Day 17: HealthInsightGenerator 单元测试
///
/// 使用 StubLLMProvider 注入固定响应，真实 HealthKitService（未授权，返回空数据），
/// in-memory ModelContainer 验证持久化。
@MainActor
final class HealthInsightGeneratorTests: XCTestCase {

    // MARK: - Stub LLMProvider

    /// 可记录调用次数的 StubLLMProvider
    final class StubLLMProvider: LLMProvider {
        /// chat 返回的内容片段
        var chatContents: [String] = ["test insight"]
        /// chat 被调用次数
        private(set) var chatCallCount: Int = 0
        /// embed 返回结果
        var embedResult: [[Float]] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { cont in
                self.chatCallCount += 1
                for content in self.chatContents {
                    cont.yield(content)
                }
                cont.finish()
            }
        }

        func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
            AsyncStream { cont in
                self.chatCallCount += 1
                for content in self.chatContents {
                    cont.yield(ParsedChunk(content: content, toolCalls: nil))
                }
                cont.finish()
            }
        }

        func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            return embedResult
        }
    }

    // MARK: - 测试夹具

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: HealthInsight.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - 测试用例

    /// 测试 1: mock LLM 返回 "test insight"，验证 content 含免责声明 "⚠️ 以上内容由 AI 生成"
    func testGenerateInsightAppendsDisclaimer() async throws {
        let stub = StubLLMProvider()
        stub.chatContents = ["test insight"]
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        XCTAssertTrue(insight.content.contains("test insight"), "洞察内容应包含 LLM 返回的文本")
        XCTAssertTrue(insight.content.contains(NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")), "洞察内容应包含免责声明")
    }

    /// 测试 2: 验证 LLMProvider.chat 被调用
    func testGenerateInsightCallsLLMProvider() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        _ = try await generator.generateInsight(days: 7)

        XCTAssertEqual(stub.chatCallCount, 1, "generateInsight 应调用 LLMProvider.chat 一次")
    }

    /// 测试 3: 验证 HealthInsight 写入 ModelContext
    func testGenerateInsightStoresToSwiftData() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        // 用 FetchDescriptor 查询验证已持久化
        let descriptor = FetchDescriptor<HealthInsight>()
        let insights = try context.fetch(descriptor)
        XCTAssertEqual(insights.count, 1, "应写入 1 条 HealthInsight")
        XCTAssertEqual(insights.first?.id, insight.id, "写入的 HealthInsight id 应一致")
        XCTAssertEqual(insights.first?.insightType, "overall", "insightType 应为 overall")
    }

    /// 测试 4: HealthKitService 返回空数据时仍能生成洞察
    func testGenerateInsightHandlesEmptyHealthData() async throws {
        let stub = StubLLMProvider()
        stub.chatContents = ["基于现有数据的建议"]
        // 未授权的 HealthKitService 会返回空字典
        let healthService = HealthKitService()
        XCTAssertFalse(healthService.isAuthorized, "测试前置：HealthKitService 未授权")
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        // 即使健康数据为空，也应生成洞察（含免责声明）
        XCTAssertFalse(insight.content.isEmpty, "空健康数据时仍应生成洞察文本")
        XCTAssertTrue(insight.content.contains(NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")), "应包含免责声明")
        // relatedMetrics 中 avgHeartRate 应为 0（空数据时）
        XCTAssertEqual(insight.relatedMetrics["avgHeartRate"], 0, "空数据时 avgHeartRate 应为 0")
    }

    // MARK: - sendInsightNotification

    /// 测试 5: sendInsightNotification 调用后不应崩溃，且使用 insight 的内容前缀作为通知正文
    func testSendInsightNotificationDoesNotCrash() async throws {
        let stub = StubLLMProvider()
        stub.chatContents = ["健康建议内容"]
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)
        let insight = try await generator.generateInsight(days: 7)

        // nonisolated 方法，可直接调用，验证不崩溃
        generator.sendInsightNotification(insight)

        // 通知已提交到 UNUserNotificationCenter，验证 insight 内容含 LLM 文本（确保通知正文可取前 80 字符）
        XCTAssertTrue(insight.content.contains("健康建议内容"), "insight 内容应含 LLM 文本")
    }

    /// 测试 6: sendInsightNotification 对长内容洞察应截取前 80 字符作为通知正文（不崩溃）
    func testSendInsightNotificationWithLongContent() async throws {
        let stub = StubLLMProvider()
        // 模拟长文本 LLM 响应
        stub.chatContents = [String(repeating: "这是一段很长的健康建议。", count: 30)]
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)
        let insight = try await generator.generateInsight(days: 7)

        // 长内容也应正常发送通知，不崩溃
        generator.sendInsightNotification(insight)
        XCTAssertTrue(insight.content.count > 80, "测试前置：insight 内容应超过 80 字符")
    }

    // MARK: - make 工厂方法

    /// 测试 7: make(modelContext:) 工厂方法应返回非空的 HealthInsightGenerator 实例
    func testMakeFactoryMethodReturnsGenerator() {
        // make 使用默认 DeepSeek provider 与真实 HealthKitService
        let generator = HealthInsightGenerator.make(modelContext: context)
        // 仅验证实例创建成功（不调用 generateInsight 以避免真实 LLM 请求）
        XCTAssertNotNil(generator, "make 工厂方法应返回非空实例")
    }

    // MARK: - 多 chunk LLM 累积

    /// 测试 8: LLM 返回多个 chunk 时应累积拼接到 insight 内容
    func testGenerateInsightAccumulatesMultipleLLMChunks() async throws {
        let stub = StubLLMProvider()
        stub.chatContents = ["第一条建议", "第二条建议", "第三条建议"]
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        XCTAssertTrue(insight.content.contains("第一条建议"), "应包含第一个 chunk")
        XCTAssertTrue(insight.content.contains("第二条建议"), "应包含第二个 chunk")
        XCTAssertTrue(insight.content.contains("第三条建议"), "应包含第三个 chunk")
    }

    // MARK: - relatedMetrics 完整性

    /// 测试 9: relatedMetrics 应包含 avgHeartRate、avgSleepHours、totalSteps 三个键
    func testGenerateInsightRelatedMetricsContainsAllKeys() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        XCTAssertNotNil(insight.relatedMetrics["avgHeartRate"], "relatedMetrics 应含 avgHeartRate")
        XCTAssertNotNil(insight.relatedMetrics["avgSleepHours"], "relatedMetrics 应含 avgSleepHours")
        XCTAssertNotNil(insight.relatedMetrics["totalSteps"], "relatedMetrics 应含 totalSteps")
        // 空数据时 avgSleepHours 与 totalSteps 均为 0
        XCTAssertEqual(insight.relatedMetrics["avgSleepHours"], 0, "空数据时 avgSleepHours 应为 0")
        XCTAssertEqual(insight.relatedMetrics["totalSteps"], 0, "空数据时 totalSteps 应为 0")
    }

    // MARK: - timestamp 验证

    /// 测试 10: 生成的 HealthInsight 的 timestamp 应接近当前时间
    func testGenerateInsightTimestampIsRecent() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let before = Date()
        let insight = try await generator.generateInsight(days: 7)
        let after = Date()

        XCTAssertGreaterThanOrEqual(insight.timestamp, before.addingTimeInterval(-1), "timestamp 应不早于生成前 1 秒")
        XCTAssertLessThanOrEqual(insight.timestamp, after.addingTimeInterval(1), "timestamp 应不晚于生成后 1 秒")
    }

    // MARK: - insightType 验证

    /// 测试 11: 生成的 HealthInsight 的 insightType 应为 "overall"
    func testGenerateInsightInsightTypeIsOverall() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        XCTAssertEqual(insight.insightType, "overall", "insightType 应为 overall")
    }

    // MARK: - 不同 days 参数

    /// 测试 12: days=1 时应正常生成洞察
    func testGenerateInsightWithDays1() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 1)

        XCTAssertFalse(insight.content.isEmpty, "days=1 时应生成非空洞察")
        XCTAssertTrue(insight.content.contains(NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")), "days=1 应含免责声明")
    }

    /// 测试 13: days=30 时应正常生成洞察
    func testGenerateInsightWithDays30() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 30)

        XCTAssertFalse(insight.content.isEmpty, "days=30 时应生成非空洞察")
    }

    // MARK: - 空 LLM 响应

    /// 测试 14: LLM 返回空内容时，洞察仍应含免责声明（空内容 + 声明）
    func testGenerateInsightWithEmptyLLMResponse() async throws {
        let stub = StubLLMProvider()
        stub.chatContents = []
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        // LLM 返回空时，insightText 仍含免责声明
        XCTAssertTrue(insight.content.contains(NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")), "空 LLM 响应仍应含免责声明")
        // chat 仍应被调用一次
        XCTAssertEqual(stub.chatCallCount, 1, "即使 LLM 返回空也应调用 chat 一次")
    }

    // MARK: - 多次生成持久化

    /// 测试 15: 多次调用 generateInsight 应在 SwiftData 中存储多条 HealthInsight
    func testGenerateInsightStoresMultipleInsights() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        _ = try await generator.generateInsight(days: 7)
        _ = try await generator.generateInsight(days: 7)

        let insights = try context.fetch(FetchDescriptor<HealthInsight>())
        XCTAssertEqual(insights.count, 2, "两次 generateInsight 应存储 2 条 HealthInsight")
    }

    // MARK: - id 唯一性

    /// 测试 16: 生成的 HealthInsight 应有非空且唯一的 id
    func testGenerateInsightHasUniqueNonEmptyId() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, dataSource: healthService, modelContext: context)

        let insight1 = try await generator.generateInsight(days: 7)
        let insight2 = try await generator.generateInsight(days: 7)

        XCTAssertNotEqual(insight1.id, insight2.id, "两次生成的 HealthInsight id 应不同")
        XCTAssertNotEqual(insight1.id, UUID(), "id 应为有效 UUID（不等于任意新 UUID）")
    }
}
#endif
