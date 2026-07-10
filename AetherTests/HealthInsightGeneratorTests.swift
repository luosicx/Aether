#if os(iOS)
import XCTest
import SwiftData
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
        let generator = HealthInsightGenerator(llmProvider: stub, healthKitService: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        XCTAssertTrue(insight.content.contains("test insight"), "洞察内容应包含 LLM 返回的文本")
        XCTAssertTrue(insight.content.contains(NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")), "洞察内容应包含免责声明")
    }

    /// 测试 2: 验证 LLMProvider.chat 被调用
    func testGenerateInsightCallsLLMProvider() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, healthKitService: healthService, modelContext: context)

        _ = try await generator.generateInsight(days: 7)

        XCTAssertEqual(stub.chatCallCount, 1, "generateInsight 应调用 LLMProvider.chat 一次")
    }

    /// 测试 3: 验证 HealthInsight 写入 ModelContext
    func testGenerateInsightStoresToSwiftData() async throws {
        let stub = StubLLMProvider()
        let healthService = HealthKitService()
        let generator = HealthInsightGenerator(llmProvider: stub, healthKitService: healthService, modelContext: context)

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
        let generator = HealthInsightGenerator(llmProvider: stub, healthKitService: healthService, modelContext: context)

        let insight = try await generator.generateInsight(days: 7)

        // 即使健康数据为空，也应生成洞察（含免责声明）
        XCTAssertFalse(insight.content.isEmpty, "空健康数据时仍应生成洞察文本")
        XCTAssertTrue(insight.content.contains(NSLocalizedString("⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。", comment: "")), "应包含免责声明")
        // relatedMetrics 中 avgHeartRate 应为 0（空数据时）
        XCTAssertEqual(insight.relatedMetrics["avgHeartRate"], 0, "空数据时 avgHeartRate 应为 0")
    }
}
#endif
