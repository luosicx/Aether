import XCTest
import SwiftData
@testable import Aether

/// HealthInsight 单元测试
/// HealthInsight 是 SwiftData @Model，使用 in-memory ModelContainer 测试。
/// 覆盖初始化（默认参数 / 全参数）、字段读写、SwiftData 持久化。
@MainActor
final class HealthInsightTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: HealthInsight.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - 初始化

    /// 默认参数初始化：id/timestamp 自动生成，relatedMetrics 为空字典
    func testInitWithDefaults() {
        let before = Date()
        let insight = HealthInsight(insightType: "sleep", content: "睡眠质量良好")
        let after = Date()

        XCTAssertEqual(insight.insightType, "sleep", "insightType 应为传入值")
        XCTAssertEqual(insight.content, "睡眠质量良好", "content 应为传入值")
        XCTAssertEqual(insight.relatedMetrics, [:], "默认 relatedMetrics 应为空字典")
        XCTAssertNotNil(insight.id, "id 应非 nil（自动生成）")
        XCTAssertTrue(insight.timestamp >= before && insight.timestamp <= after,
                      "timestamp 应自动设为当前时间")
    }

    /// 全参数初始化：所有字段应正确赋值
    func testInitWithAllParameters() {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1000000)
        let metrics: [String: Double] = ["avgHeartRate": 72.5, "sleepHours": 6.8]

        let insight = HealthInsight(
            id: id,
            timestamp: timestamp,
            insightType: "heart",
            content: "心率处于正常范围",
            relatedMetrics: metrics
        )

        XCTAssertEqual(insight.id, id, "id 应为传入值")
        XCTAssertEqual(insight.timestamp, timestamp, "timestamp 应为传入值")
        XCTAssertEqual(insight.insightType, "heart")
        XCTAssertEqual(insight.content, "心率处于正常范围")
        XCTAssertEqual(insight.relatedMetrics, metrics, "relatedMetrics 应为传入字典")
    }

    /// 多次初始化应生成不同的 UUID
    func testInitGeneratesUniqueIDs() {
        let a = HealthInsight(insightType: "steps", content: "a")
        let b = HealthInsight(insightType: "steps", content: "b")
        XCTAssertNotEqual(a.id, b.id, "不同实例的 id 应不同")
    }

    /// 各类别（sleep/heart/steps/overall）均可创建
    func testInitWithDifferentInsightTypes() {
        let types = ["sleep", "heart", "steps", "overall"]
        for type in types {
            let insight = HealthInsight(insightType: type, content: "测试 \(type)")
            XCTAssertEqual(insight.insightType, type, "insightType=\(type) 应正确存储")
        }
    }

    // MARK: - 字段读写

    /// content 可为空字符串（边界值）
    func testEmptyContent() {
        let insight = HealthInsight(insightType: "overall", content: "")
        XCTAssertEqual(insight.content, "", "content 应可为空字符串")
    }

    /// relatedMetrics 含多键值时应正确存储
    func testRelatedMetricsWithMultipleKeys() {
        let metrics: [String: Double] = [
            "avgHeartRate": 72,
            "sleepHours": 7.5,
            "totalSteps": 8500,
            "restingHR": 60
        ]
        let insight = HealthInsight(
            insightType: "overall",
            content: "综合洞察",
            relatedMetrics: metrics
        )
        XCTAssertEqual(insight.relatedMetrics.count, 4, "relatedMetrics 应含 4 个键")
        XCTAssertEqual(insight.relatedMetrics["avgHeartRate"], 72)
        XCTAssertEqual(insight.relatedMetrics["sleepHours"], 7.5)
        XCTAssertEqual(insight.relatedMetrics["totalSteps"], 8500)
        XCTAssertEqual(insight.relatedMetrics["restingHR"], 60)
    }

    /// relatedMetrics 含 0 与负数值时应正确存储（边界值）
    func testRelatedMetricsBoundaryValues() {
        let metrics: [String: Double] = ["zero": 0, "negative": -1.5]
        let insight = HealthInsight(
            insightType: "heart",
            content: "边界值测试",
            relatedMetrics: metrics
        )
        XCTAssertEqual(insight.relatedMetrics["zero"], 0, "0 值应正确存储")
        XCTAssertEqual(insight.relatedMetrics["negative"], -1.5, "负值应正确存储")
    }

    /// 字段在创建后可修改
    func testFieldMutation() {
        let insight = HealthInsight(insightType: "sleep", content: "旧内容")
        insight.content = "新内容"
        insight.insightType = "overall"
        insight.relatedMetrics = ["hours": 8.0]

        XCTAssertEqual(insight.content, "新内容")
        XCTAssertEqual(insight.insightType, "overall")
        XCTAssertEqual(insight.relatedMetrics, ["hours": 8.0])
    }

    // MARK: - SwiftData 持久化

    /// 插入并 fetch 应返回存储的 insight
    func testSwiftDataInsertAndFetch() throws {
        let insight = HealthInsight(
            insightType: "heart",
            content: "持久化测试",
            relatedMetrics: ["hr": 75.0]
        )
        context.insert(insight)
        try context.save()

        let descriptor = FetchDescriptor<HealthInsight>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "应 fetch 到 1 条记录")
        XCTAssertEqual(fetched.first?.insightType, "heart")
        XCTAssertEqual(fetched.first?.content, "持久化测试")
        XCTAssertEqual(fetched.first?.relatedMetrics["hr"], 75.0)
    }

    /// 插入多条后 fetch 应返回全部
    func testSwiftDataInsertMultipleInsights() throws {
        let types = ["sleep", "heart", "steps", "overall"]
        for type in types {
            context.insert(HealthInsight(insightType: type, content: "洞察 \(type)"))
        }
        try context.save()

        let descriptor = FetchDescriptor<HealthInsight>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 4, "应 fetch 到 4 条记录")
    }

    /// 按 insightType 过滤 fetch（使用 fetch + filter，避免 #Predicate 宏在测试目标中的限制）
    func testSwiftDataFetchByInsightType() throws {
        context.insert(HealthInsight(insightType: "sleep", content: "a"))
        context.insert(HealthInsight(insightType: "heart", content: "b"))
        context.insert(HealthInsight(insightType: "sleep", content: "c"))
        try context.save()

        let descriptor = FetchDescriptor<HealthInsight>()
        let allInsights = try context.fetch(descriptor)
        let fetched = allInsights.filter { $0.insightType == "sleep" }
        XCTAssertEqual(fetched.count, 2, "insightType=sleep 应有 2 条记录")
        XCTAssertTrue(fetched.allSatisfy { $0.insightType == "sleep" })
    }

    /// 按 timestamp 排序 fetch
    func testSwiftDataFetchSortedByTimestamp() throws {
        let old = HealthInsight(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1000),
            insightType: "sleep",
            content: "旧"
        )
        let newer = HealthInsight(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 2000),
            insightType: "sleep",
            content: "新"
        )
        context.insert(old)
        context.insert(newer)
        try context.save()

        let descriptor = FetchDescriptor<HealthInsight>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.first?.content, "新", "降序排列时最新的应在最前")
    }

    /// 删除 insight 后 fetch 应返回空
    func testSwiftDataDeleteInsight() throws {
        let insight = HealthInsight(insightType: "steps", content: "待删除")
        context.insert(insight)
        try context.save()

        context.delete(insight)
        try context.save()

        let descriptor = FetchDescriptor<HealthInsight>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 0, "删除后应 fetch 到 0 条记录")
    }
}
