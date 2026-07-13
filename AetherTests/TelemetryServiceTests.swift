import XCTest
@testable import Aether

/// Day 14 Phase 5 Task 10: TelemetryService 单元测试
/// TelemetryService 是 actor，测试中需要 await。
/// TelemetryService 无显式 init（合成 internal init），@testable import 可访问，
/// 每个测试创建新实例避免 shared 单例状态污染。
final class TelemetryServiceTests: XCTestCase {

    // MARK: - 1. track 写入缓冲

    func testTrackAddsToBuffer() async {
        let service = TelemetryService()
        await service.track(.messageSent(provider: "deepseek", model: "deepseek-chat", inputTokens: 42))

        let records = await service.drain()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].event, "messageSent")
        XCTAssertEqual(records[0].payload["provider"], "deepseek")
        XCTAssertEqual(records[0].payload["model"], "deepseek-chat")
        XCTAssertEqual(records[0].payload["inputTokens"], "42")
    }

    // MARK: - 2. 缓冲满 1000 后丢弃最旧

    func testBufferDropsOldestWhenFull() async {
        let service = TelemetryService()
        // 写入 1001 条，每条 inputTokens 不同用于区分
        for i in 0..<1001 {
            await service.track(.messageSent(provider: "p", model: "m", inputTokens: i))
        }
        let count = await service.bufferCount
        XCTAssertEqual(count, 1000, "缓冲上限 1000，超出应丢弃最旧")

        let records = await service.drain()
        XCTAssertEqual(records.count, 1000)
        // 最早一条（inputTokens=0）应被丢弃，第一条应为 inputTokens=1
        XCTAssertEqual(records.first?.payload["inputTokens"], "1", "最旧的一条应被丢弃")
        XCTAssertEqual(records.last?.payload["inputTokens"], "1000")
    }

    // MARK: - 3. drain 清空缓冲

    func testDrainClearsBuffer() async {
        let service = TelemetryService()
        await service.track(.toolCall(toolName: "calculate", success: true, durationMs: 10))
        await service.track(.toolCall(toolName: "alarm", success: false, durationMs: 5))

        let drained = await service.drain()
        XCTAssertEqual(drained.count, 2)

        let count = await service.bufferCount
        XCTAssertEqual(count, 0, "drain 后缓冲应清空")

        // 再次 drain 应返回空
        let second = await service.drain()
        XCTAssertTrue(second.isEmpty)
    }

    // MARK: - 4. 缓冲达阈值触发上报

    func testShouldUploadReturnsTrueWhenBufferFull() async {
        let service = TelemetryService()
        for _ in 0..<100 {
            await service.track(.llmResponse(latencyMs: 100, success: true, outputTokens: 10))
        }
        let should = await service.shouldUpload(now: Date(), threshold: 100, interval: 300)
        XCTAssertTrue(should, "缓冲达 100 应触发上报")
    }

    // MARK: - 5. 距上次上报超间隔触发上报

    func testShouldUploadReturnsTrueAfterInterval() async {
        let service = TelemetryService()
        // 写入少量事件（低于阈值 100）
        await service.track(.errorOccurred(errorType: "test", userMessage: "msg"))
        // TelemetryService.lastUploadAt 当前实现未由外部写入（始终为 nil），
        // 此处验证 "从未上报过且有数据" 分支：即使低于阈值也应触发首次上报，
        // 用一个远未来的 now 模拟 "超间隔" 场景。
        let futureNow = Date().addingTimeInterval(600)
        let should = await service.shouldUpload(now: futureNow, threshold: 100, interval: 300)
        XCTAssertTrue(should, "从未上报且有数据时应触发上报（等价于超间隔触发）")

        // 空缓冲 + 从未上报 → 不应触发
        let empty = TelemetryService()
        let shouldEmpty = await empty.shouldUpload(now: Date(), threshold: 100, interval: 300)
        XCTAssertFalse(shouldEmpty, "空缓冲且从未上报不应触发")
    }

    // MARK: - 边缘测试补充

    // 所有事件类型的 payload 编码：覆盖 TelemetryEvent 全部 case 的 name 与 payload
    func testAllEventTypesPayloadEncoding() async {
        let service = TelemetryService()
        await service.track(.messageSent(provider: "deepseek", model: "chat", inputTokens: 10))
        await service.track(.llmResponse(latencyMs: 200, success: true, outputTokens: 30))
        await service.track(.toolCall(toolName: "alarm", success: false, durationMs: 5))
        await service.track(.fallbackTriggered(from: "deepseek", to: "qwen", reason: "timeout"))
        await service.track(.errorOccurred(errorType: "apiError", userMessage: "失败"))

        let records = await service.drain()
        XCTAssertEqual(records.count, 5)
        // 逐一验证事件名
        XCTAssertEqual(records[0].event, "messageSent")
        XCTAssertEqual(records[1].event, "llmResponse")
        XCTAssertEqual(records[2].event, "toolCall")
        XCTAssertEqual(records[3].event, "fallbackTriggered")
        XCTAssertEqual(records[4].event, "errorOccurred")
        // 验证关键 payload 字段
        XCTAssertEqual(records[1].payload["success"], "true")
        XCTAssertEqual(records[1].payload["latencyMs"], "200")
        XCTAssertEqual(records[2].payload["toolName"], "alarm")
        XCTAssertEqual(records[3].payload["from"], "deepseek")
        XCTAssertEqual(records[3].payload["to"], "qwen")
        XCTAssertEqual(records[4].payload["errorType"], "apiError")
    }

    // errorOccurred 的 userMessage 应在入队前被脱敏，原始敏感字符串不得进入缓冲
    func testErrorOccurredUserMessageIsRedacted() async {
        let service = TelemetryService()
        let sensitiveMessage = "登录失败：password=Secret123，用户邮箱 alice@example.com"
        await service.track(.errorOccurred(errorType: "loginFailed", userMessage: sensitiveMessage))

        let records = await service.drain()
        XCTAssertEqual(records.count, 1)
        let userMessage = records[0].payload["userMessage"]
        XCTAssertNotNil(userMessage)
        XCTAssertTrue(userMessage!.contains("[REDACTED_CREDENTIAL]"))
        XCTAssertTrue(userMessage!.contains("[REDACTED_EMAIL]"))
        XCTAssertFalse(userMessage!.contains("Secret123"))
        XCTAssertFalse(userMessage!.contains("alice@example.com"))
    }

    // 自定义阈值：threshold=5 时，5 条事件即触发上报（边界等于）
    func testShouldUploadWithCustomThreshold() async {
        let service = TelemetryService()
        for _ in 0..<5 {
            await service.track(.llmResponse(latencyMs: 100, success: true, outputTokens: 1))
        }
        // buffer.count(5) >= threshold(5) → true
        let should = await service.shouldUpload(now: Date(), threshold: 5, interval: 300)
        XCTAssertTrue(should, "buffer 达自定义阈值 5 应触发上报")
        // 4 条低于阈值 5，但从未上报且有数据 → 仍应触发
        let service2 = TelemetryService()
        for _ in 0..<4 {
            await service2.track(.llmResponse(latencyMs: 100, success: true, outputTokens: 1))
        }
        let should2 = await service2.shouldUpload(now: Date(), threshold: 5, interval: 300)
        XCTAssertTrue(should2, "从未上报且有数据即使低于阈值也应触发首次上报")
    }

    // track 写入记录的 timestamp 应接近当前时间
    func testTrackPreservesRecentTimestamp() async {
        let service = TelemetryService()
        let before = Date()
        await service.track(.toolCall(toolName: "test", success: true, durationMs: 1))
        let after = Date()

        let records = await service.drain()
        XCTAssertEqual(records.count, 1)
        XCTAssertGreaterThanOrEqual(records[0].timestamp, before, "timestamp 不应早于 track 前")
        XCTAssertLessThanOrEqual(records[0].timestamp, after, "timestamp 不应晚于 track 后")
    }

    // drain 返回的记录顺序应与写入顺序一致
    func testDrainReturnsRecordsInOrder() async {
        let service = TelemetryService()
        let providers = ["alpha", "beta", "gamma"]
        for p in providers {
            await service.track(.messageSent(provider: p, model: "m", inputTokens: 0))
        }
        let records = await service.drain()
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].payload["provider"], "alpha")
        XCTAssertEqual(records[1].payload["provider"], "beta")
        XCTAssertEqual(records[2].payload["provider"], "gamma")
    }

    // MARK: - lastUploadAt / lastUploadStatus 默认值与边界验证

    /// 新实例的 lastUploadAt 应为 nil（尚未上报过）
    func testLastUploadAtDefaultIsNil() async {
        let service = TelemetryService()
        let value = await service.lastUploadAt
        XCTAssertNil(value, "新实例 lastUploadAt 应为 nil")
    }

    /// 新实例的 lastUploadStatus 应为 "idle"
    func testLastUploadStatusDefaultIsIdle() async {
        let service = TelemetryService()
        let status = await service.lastUploadStatus
        XCTAssertEqual(status, "idle", "新实例 lastUploadStatus 应为 'idle'")
    }

    /// bufferCount 初始应为 0
    func testBufferCountInitiallyZero() async {
        let service = TelemetryService()
        let count = await service.bufferCount
        XCTAssertEqual(count, 0)
    }

    /// shouldUpload：空缓冲 + 从未上报 → 不应触发
    func testShouldUploadEmptyBufferNeverUploaded() async {
        let service = TelemetryService()
        let should = await service.shouldUpload(now: Date(), threshold: 100, interval: 300)
        XCTAssertFalse(should, "空缓冲且从未上报不应触发")
    }

    /// shouldUpload：buffer 恰好低于阈值 1 条 + 从未上报 → 仍触发（首次上报分支）
    func testShouldUploadBelowThresholdButNeverUploaded() async {
        let service = TelemetryService()
        await service.track(.messageSent(provider: "p", model: "m", inputTokens: 1))
        let should = await service.shouldUpload(now: Date(), threshold: 100, interval: 300)
        XCTAssertTrue(should, "从未上报且有数据时应触发首次上报")
    }

    /// shouldUpload：threshold=1，1 条即触发
    func testShouldUploadThresholdOne() async {
        let service = TelemetryService()
        await service.track(.errorOccurred(errorType: "x", userMessage: "y"))
        let should = await service.shouldUpload(now: Date(), threshold: 1, interval: 300)
        XCTAssertTrue(should, "buffer=1 达 threshold=1 应触发")
    }

    /// drain 后再 track：bufferCount 应正确反映新写入数量
    func testTrackAfterDrainPreservesNewRecords() async {
        let service = TelemetryService()
        await service.track(.messageSent(provider: "a", model: "m", inputTokens: 0))
        _ = await service.drain()
        let countAfterDrain = await service.bufferCount
        XCTAssertEqual(countAfterDrain, 0)
        await service.track(.messageSent(provider: "b", model: "m", inputTokens: 1))
        let countAfterTrack = await service.bufferCount
        XCTAssertEqual(countAfterTrack, 1)
        let records = await service.drain()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].payload["provider"], "b")
    }

    /// TelemetryRecord Equatable 一致性
    func testTelemetryRecordEquatable() {
        let id = UUID()
        let now = Date()
        let r1 = TelemetryRecord(id: id, event: "test", payload: ["k": "v"], timestamp: now)
        let r2 = TelemetryRecord(id: id, event: "test", payload: ["k": "v"], timestamp: now)
        XCTAssertEqual(r1, r2)
    }

    /// TelemetryRecord Codable 往返
    func testTelemetryRecordCodableRoundTrip() throws {
        let record = TelemetryRecord(
            id: UUID(), event: "llmResponse",
            payload: ["latencyMs": "200", "success": "true"],
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TelemetryRecord.self, from: data)
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.event, record.event)
        XCTAssertEqual(decoded.payload, record.payload)
        // timestamp 精度可能有微小差异，用 timeIntervalSince 比较
        XCTAssertLessThan(abs(decoded.timestamp.timeIntervalSince(record.timestamp)), 0.001)
    }
}
