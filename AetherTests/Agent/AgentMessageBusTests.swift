import XCTest
@testable import Aether

/// v1.1 Phase B: AgentMessageBus 单元测试。
///
/// 覆盖：
/// - publish/subscribe 基本消息传递
/// - 多订阅者接收同一 topic 消息
/// - 无订阅者时消息丢弃（fire-and-forget）
/// - 不同 topic 隔离
/// - subscriberCount 诊断方法
/// - reset 清空所有订阅
/// - AgentMessage 各 case 的字段正确性
final class AgentMessageBusTests: XCTestCase {

    // MARK: - 基本消息传递

    /// 订阅者应收到发布到同一 topic 的消息
    func testSubscriberReceivesPublishedMessage() async throws {
        let bus = AgentMessageBus()
        let topic = "test.basic"
        let from = UUID()
        let to = UUID()
        let subTaskId = UUID()

        // 先订阅
        let stream = await bus.subscribe(topic: topic)

        // 发布消息
        let message = AgentMessage.taskDelegation(subTaskId: subTaskId, from: from, to: to, description: "测试委派")
        await bus.publish(topic: topic, message: message)

        // 验证收到消息
        let received = await firstMessage(from: stream, timeoutNanos: 1_000_000_000)
        XCTAssertNotNil(received, "应收到消息")

        if case .taskDelegation(let rid, let rfrom, let rto, let rdesc) = received {
            XCTAssertEqual(rid, subTaskId)
            XCTAssertEqual(rfrom, from)
            XCTAssertEqual(rto, to)
            XCTAssertEqual(rdesc, "测试委派")
        } else {
            XCTFail("收到的消息类型应为 taskDelegation")
        }
    }

    /// 先订阅再发布：消息不丢失
    func testSubscribeBeforePublishDoesNotLoseMessages() async throws {
        let bus = AgentMessageBus()
        let topic = "test.order"

        let stream = await bus.subscribe(topic: topic)
        await bus.publish(topic: topic, message: .statusUpdate(agentId: UUID(), status: .executing))

        let received = await firstMessage(from: stream, timeoutNanos: 1_000_000_000)
        XCTAssertNotNil(received, "先订阅再发布应收到消息")
        if case .statusUpdate(let agentId, let status) = received {
            XCTAssertEqual(status, .executing)
            XCTAssertNotNil(agentId)
        }
    }

    // MARK: - 多订阅者

    /// 同一 topic 的多个订阅者应各自收到消息副本
    func testMultipleSubscribersReceiveMessage() async throws {
        let bus = AgentMessageBus()
        let topic = "test.multi"

        let stream1 = await bus.subscribe(topic: topic)
        let stream2 = await bus.subscribe(topic: topic)

        let count = await bus.subscriberCount(topic: topic)
        XCTAssertEqual(count, 2, "应有 2 个订阅者")

        await bus.publish(topic: topic, message: .statusUpdate(agentId: UUID(), status: .idle))

        let msg1 = await firstMessage(from: stream1, timeoutNanos: 1_000_000_000)
        let msg2 = await firstMessage(from: stream2, timeoutNanos: 1_000_000_000)

        XCTAssertNotNil(msg1, "订阅者 1 应收到消息")
        XCTAssertNotNil(msg2, "订阅者 2 应收到消息")
    }

    // MARK: - 无订阅者

    /// 无订阅者时发布消息不应崩溃（fire-and-forget）
    func testPublishWithoutSubscribersDoesNotCrash() async {
        let bus = AgentMessageBus()
        let topic = "test.noSubs"

        // 无订阅者直接发布
        await bus.publish(topic: topic, message: .statusUpdate(agentId: UUID(), status: .stopped))

        let count = await bus.subscriberCount(topic: topic)
        XCTAssertEqual(count, 0, "无订阅者时计数应为 0")
    }

    // MARK: - topic 隔离

    /// 不同 topic 的消息互不干扰
    func testDifferentTopicsAreIsolated() async throws {
        let bus = AgentMessageBus()

        let streamA = await bus.subscribe(topic: "topic.A")
        let streamB = await bus.subscribe(topic: "topic.B")

        await bus.publish(topic: "topic.A", message: .statusUpdate(agentId: UUID(), status: .executing))
        await bus.publish(topic: "topic.B", message: .statusUpdate(agentId: UUID(), status: .idle))

        let msgA = await firstMessage(from: streamA, timeoutNanos: 1_000_000_000)
        let msgB = await firstMessage(from: streamB, timeoutNanos: 1_000_000_000)

        XCTAssertNotNil(msgA, "topic.A 订阅者应收到 topic.A 的消息")
        XCTAssertNotNil(msgB, "topic.B 订阅者应收到 topic.B 的消息")

        if case .statusUpdate(_, let statusA) = msgA {
            XCTAssertEqual(statusA, .executing, "topic.A 消息应为 executing")
        }
        if case .statusUpdate(_, let statusB) = msgB {
            XCTAssertEqual(statusB, .idle, "topic.B 消息应为 idle")
        }
    }

    /// 发布到 topic A 的消息不应被 topic B 的订阅者收到
    func testMessageNotDeliveredToWrongTopic() async throws {
        let bus = AgentMessageBus()

        let streamB = await bus.subscribe(topic: "topic.B")
        await bus.publish(topic: "topic.A", message: .statusUpdate(agentId: UUID(), status: .executing))

        let msg = await firstMessage(from: streamB, timeoutNanos: 500_000_000)
        XCTAssertNil(msg, "topic.B 订阅者不应收到 topic.A 的消息")
    }

    // MARK: - subscriberCount

    /// subscriberCount 应正确反映当前订阅数
    func testSubscriberCount() async throws {
        let bus = AgentMessageBus()
        let topic = "test.count"

        XCTAssertEqual(await bus.subscriberCount(topic: topic), 0)

        _ = await bus.subscribe(topic: topic)
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 1)

        _ = await bus.subscribe(topic: topic)
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 2)
    }

    /// 未使用的 topic 计数应为 0
    func testSubscriberCountForUnusedTopic() async {
        let bus = AgentMessageBus()
        let count = await bus.subscriberCount(topic: "nonexistent")
        XCTAssertEqual(count, 0)
    }

    // MARK: - reset

    /// reset 应清空所有订阅者
    func testResetClearsAllSubscribers() async throws {
        let bus = AgentMessageBus()

        _ = await bus.subscribe(topic: "topic.A")
        _ = await bus.subscribe(topic: "topic.B")

        XCTAssertEqual(await bus.subscriberCount(topic: "topic.A"), 1)
        XCTAssertEqual(await bus.subscriberCount(topic: "topic.B"), 1)

        await bus.reset()

        XCTAssertEqual(await bus.subscriberCount(topic: "topic.A"), 0)
        XCTAssertEqual(await bus.subscriberCount(topic: "topic.B"), 0)
    }

    // MARK: - AgentMessage 类型

    /// taskDelegation 消息字段应正确
    func testTaskDelegationMessageFields() {
        let subTaskId = UUID()
        let from = UUID()
        let to = UUID()
        let desc = "委派描述"
        let msg = AgentMessage.taskDelegation(subTaskId: subTaskId, from: from, to: to, description: desc)

        if case .taskDelegation(let rid, let rfrom, let rto, let rdesc) = msg {
            XCTAssertEqual(rid, subTaskId)
            XCTAssertEqual(rfrom, from)
            XCTAssertEqual(rto, to)
            XCTAssertEqual(rdesc, desc)
        } else {
            XCTFail("消息应为 taskDelegation 类型")
        }
    }

    /// resultDelivery 消息字段应正确
    func testResultDeliveryMessageFields() {
        let subTaskId = UUID()
        let from = UUID()
        let to = UUID()
        let result = "执行结果"
        let msg = AgentMessage.resultDelivery(subTaskId: subTaskId, from: from, to: to, result: result)

        if case .resultDelivery(let rid, let rfrom, let rto, let rresult) = msg {
            XCTAssertEqual(rid, subTaskId)
            XCTAssertEqual(rfrom, from)
            XCTAssertEqual(rto, to)
            XCTAssertEqual(rresult, result)
        } else {
            XCTFail("消息应为 resultDelivery 类型")
        }
    }

    /// statusUpdate 消息字段应正确
    func testStatusUpdateMessageFields() {
        let agentId = UUID()
        let msg = AgentMessage.statusUpdate(agentId: agentId, status: .waitingForDelegation)

        if case .statusUpdate(let rid, let rstatus) = msg {
            XCTAssertEqual(rid, agentId)
            XCTAssertEqual(rstatus, .waitingForDelegation)
        } else {
            XCTFail("消息应为 statusUpdate 类型")
        }
    }

    // MARK: - 委派场景模拟

    /// 模拟委派流程：发布 taskDelegation → 接收并处理 → 发布 resultDelivery
    func testDelegationFlowRoundTrip() async throws {
        let bus = AgentMessageBus()
        let requesterTopic = "delegation.requests"
        let subTaskId = UUID()
        let delegateAgentId = UUID()
        let requesterId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        // 委派方订阅结果
        let resultTopic = "delegation.result.\(subTaskId)"
        let resultStream = await bus.subscribe(topic: resultTopic)

        // 被委派方订阅请求
        let requestStream = await bus.subscribe(topic: requesterTopic)

        // 委派方发布委派请求
        await bus.publish(topic: requesterTopic, message: .taskDelegation(
            subTaskId: subTaskId,
            from: requesterId,
            to: delegateAgentId,
            description: "请执行此任务"
        ))

        // 被委派方接收请求
        let request = await firstMessage(from: requestStream, timeoutNanos: 1_000_000_000)
        XCTAssertNotNil(request, "被委派方应收到委派请求")

        // 被委派方发布结果
        await bus.publish(topic: resultTopic, message: .resultDelivery(
            subTaskId: subTaskId,
            from: delegateAgentId,
            to: requesterId,
            result: "任务完成"
        ))

        // 委派方接收结果
        let result = await firstMessage(from: resultStream, timeoutNanos: 1_000_000_000)
        XCTAssertNotNil(result, "委派方应收到结果")

        if case .resultDelivery(_, _, _, let r) = result {
            XCTAssertEqual(r, "任务完成")
        } else {
            XCTFail("应收到 resultDelivery 消息")
        }
    }

    // MARK: - 订阅者自动移除与 reset 边界

    /// 订阅者流终止后应自动从 subscribers 中移除（onTermination 回调）
    func testSubscriberAutoRemovalOnStreamTermination() async throws {
        let bus = AgentMessageBus()
        let topic = "test.autoRemoval"

        let stream = await bus.subscribe(topic: topic)
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 1, "订阅后应有 1 个订阅者")

        // 在子任务中消费 stream，取消任务以触发 onTermination
        let consumerTask = Task {
            for await _ in stream {}
        }
        consumerTask.cancel()

        // onTermination 中的 removeSubscriber 是异步 Task，等待完成
        try? await Task.sleep(nanoseconds: 300_000_000)

        let count = await bus.subscriberCount(topic: topic)
        XCTAssertEqual(count, 0, "stream 终止后订阅者应被自动移除")
    }

    /// reset 后应能重新 subscribe 和 publish
    func testPublishAfterResetStillWorks() async throws {
        let bus = AgentMessageBus()
        let topic = "test.afterReset"

        _ = await bus.subscribe(topic: topic)
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 1)

        await bus.reset()
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 0, "reset 后订阅者应清空")

        let stream = await bus.subscribe(topic: topic)
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 1, "reset 后应能重新订阅")

        await bus.publish(topic: topic, message: .statusUpdate(agentId: UUID(), status: .idle))

        let received = await firstMessage(from: stream, timeoutNanos: 1_000_000_000)
        XCTAssertNotNil(received, "reset 后应能重新接收消息")
    }

    /// topic 为空字符串时应仍可正常工作
    func testEmptyTopicString() async throws {
        let bus = AgentMessageBus()
        let topic = ""

        let stream = await bus.subscribe(topic: topic)
        XCTAssertEqual(await bus.subscriberCount(topic: topic), 1, "空 topic 应可订阅")

        await bus.publish(topic: topic, message: .statusUpdate(agentId: UUID(), status: .idle))

        let received = await firstMessage(from: stream, timeoutNanos: 1_000_000_000)
        XCTAssertNotNil(received, "空 topic 应能收到消息")
    }

    // MARK: - 辅助方法

    /// 从 AsyncStream 中获取第一条消息（带超时）
    /// - Parameters:
    ///   - stream: 消息流
    ///   - timeoutNanos: 超时时间（纳秒）
    /// - Returns: 第一条消息，超时返回 nil
    private func firstMessage(from stream: AsyncStream<AgentMessage>, timeoutNanos: UInt64) async -> AgentMessage? {
        await withTaskGroup(of: AgentMessage?.self) { group in
            group.addTask {
                for await msg in stream {
                    return msg
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
