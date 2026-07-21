import XCTest
import SwiftData
@testable import Aether

/// P2-6 Task 3: FeedbackCoordinator 单元测试
///
/// 验证 FeedbackCoordinator 正确封装反馈状态、Toast 提示与持久化职责：
/// - handleFeedback toggle 行为（点赞 / 踩 / 取消 / 切换）
/// - submitFeedback 新增 / 更新持久化路径
/// - Toast 2 秒自动清除 Task 由 coordinator 管理
/// - citations chunk weight 调整
/// 通过闭包回调更新外部状态，不直接持有 @Observable 属性。
@MainActor
final class FeedbackCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self,
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - 辅助

    /// 构造一个 FeedbackCoordinator 并捕获闭包回调值，便于断言。
    /// citationsProvider 默认返回空数组，模拟 ChatViewModel.currentCitations 为空。
    private func makeCoordinator(
        citations: [DocumentChunk] = []
    ) -> (coordinator: FeedbackCoordinator,
          feedbackStates: NonIsolatedBox<[UUID: Bool]>,
          feedbackToast: NonIsolatedBox<String?>) {
        let statesBox = NonIsolatedBox<[UUID: Bool]>([:])
        let toastBox = NonIsolatedBox<String?>(nil)
        let coordinator = FeedbackCoordinator(
            citationsProvider: { citations },
            onFeedbackStatesChange: { statesBox.value = $0 },
            onFeedbackToastChange: { toastBox.value = $0 }
        )
        return (coordinator, statesBox, toastBox)
    }

    // MARK: - handleFeedback 基础行为

    /// handleFeedback 点赞：应通过 onFeedbackStatesChange 设置 [msgId: true]，
    /// 并通过 onFeedbackToastChange 设置非空 toast 文本。
    func testHandleFeedbackPositiveSetsState() {
        let (coordinator, statesBox, toastBox) = makeCoordinator()
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)

        XCTAssertEqual(statesBox.value[msgId], true, "点赞后 feedbackStates[msgId] 应为 true")
        XCTAssertNotNil(toastBox.value, "点赞后 feedbackToast 应被设置")
    }

    /// handleFeedback 踩：应通过 onFeedbackStatesChange 设置 [msgId: false]，
    /// 并通过 onFeedbackToastChange 设置非空 toast 文本。
    func testHandleFeedbackNegativeSetsState() {
        let (coordinator, statesBox, toastBox) = makeCoordinator()
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)

        XCTAssertEqual(statesBox.value[msgId], false, "踩后 feedbackStates[msgId] 应为 false")
        XCTAssertNotNil(toastBox.value, "踩后 feedbackToast 应被设置")
    }

    /// handleFeedback 相同状态再次点击应取消反馈（toggle 行为）：
    /// 通过 onFeedbackStatesChange 通知移除 msgId 键，通过 onFeedbackToastChange 通知 nil。
    func testHandleFeedbackToggleCancelsFeedback() {
        let (coordinator, statesBox, toastBox) = makeCoordinator()
        let msgId = UUID()

        // 首次点赞
        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertEqual(statesBox.value[msgId], true, "前置：首次点赞后应为 true")

        // 再次点击相同状态 → 取消
        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)

        XCTAssertNil(statesBox.value[msgId], "相同状态再次点击应取消反馈")
        XCTAssertNil(toastBox.value, "取消后 feedbackToast 应为 nil")
    }

    /// handleFeedback 从赞切换到踩：应通过 onFeedbackStatesChange 通知 [msgId: false]，
    /// 并通过 onFeedbackToastChange 通知新的非空 toast 文本。
    func testHandleFeedbackSwitchFromPositiveToNegative() {
        let (coordinator, statesBox, toastBox) = makeCoordinator()
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertEqual(statesBox.value[msgId], true)

        coordinator.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)

        XCTAssertEqual(statesBox.value[msgId], false, "切换到踩后应为 false")
        XCTAssertNotNil(toastBox.value, "切换后 feedbackToast 应被设置")
    }

    // MARK: - 持久化

    /// handleFeedback 应持久化反馈记录到 SwiftData，可通过 ChatStorage.fetchFeedback 验证。
    func testHandleFeedbackPersistsToStorage() {
        let (coordinator, _, _) = makeCoordinator()
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)

        let storage = ChatStorage(modelContext: context)
        let feedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertNotNil(feedback, "handleFeedback 应持久化反馈记录")
        XCTAssertEqual(feedback?.isPositive, true)
    }

    /// handleFeedback 切换反馈状态时，应更新已有记录而非创建新记录。
    func testHandleFeedbackUpdatesExistingFeedback() {
        let (coordinator, _, _) = makeCoordinator()
        let msgId = UUID()

        // 首次点赞
        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        // 切换为踩
        coordinator.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)

        let storage = ChatStorage(modelContext: context)
        let feedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertEqual(feedback?.isPositive, false, "切换后反馈记录应为 false（踩）")

        // 验证未创建重复记录：fetch 全量应只有 1 条
        let allFeedbacks = (try? context.fetch(FetchDescriptor<MessageFeedback>())) ?? []
        XCTAssertEqual(allFeedbacks.count, 1, "切换反馈状态不应创建新记录")
    }

    // MARK: - Toast 自动清除

    /// handleFeedback 后启动的 Toast 自动清除 Task 在 2 秒后应通过 onFeedbackToastChange 通知 nil。
    func testHandleFeedbackToastAutoClears() async throws {
        let (coordinator, _, toastBox) = makeCoordinator()
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertNotNil(toastBox.value, "前置：点赞后应设置 feedbackToast")

        // 等待 2.5 秒让自动清除 Task 执行
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertNil(toastBox.value, "2 秒后 feedbackToast 应被自动清除")
    }

    /// 先点赞再点踩，feedbackToast 应更新为踩的提示文本（两次 toast 不同）。
    func testFeedbackToastResetOnToggle() {
        let (coordinator, _, toastBox) = makeCoordinator()
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        let positiveToast = toastBox.value
        XCTAssertNotNil(positiveToast)

        coordinator.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)
        let negativeToast = toastBox.value
        XCTAssertNotNil(negativeToast)
        XCTAssertNotEqual(positiveToast, negativeToast,
                          "切换反馈状态后 feedbackToast 应更新")
    }

    // MARK: - citations 权重调整

    /// handleFeedback 传入 citations 时应调整关联 chunk 权重（踩后 chunk.weight *= 0.8）。
    /// citationsProvider 闭包返回 chunk，handleFeedback 内部 submitFeedback 时将其传入。
    func testHandleFeedbackWithCitationsAdjustsChunkWeight() {
        let chunk = DocumentChunk(content: "测试分块")
        context.insert(chunk)
        try? context.save()

        let (coordinator, _, _) = makeCoordinator(citations: [chunk])
        let msgId = UUID()

        coordinator.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)

        let storage = ChatStorage(modelContext: context)
        let feedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertEqual(feedback?.isPositive, false)
        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.0001,
                       "踩后关联 chunk weight 应降为 0.8")
    }

    // MARK: - submitFeedback

    /// submitFeedback 对已存在的反馈记录应调用 updateFeedback 而非 saveFeedback：
    /// 切换 isPositive 后 fetch 同一条记录，isPositive 反映新值。
    func testSubmitFeedbackUpdatesExistingFeedback() {
        let (coordinator, _, _) = makeCoordinator()
        let msgId = UUID()

        // 首次点赞（saveFeedback 路径）
        coordinator.submitFeedback(messageId: msgId, isPositive: true, citations: [], modelContext: context)
        let storage = ChatStorage(modelContext: context)
        let firstFeedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertNotNil(firstFeedback)
        XCTAssertEqual(firstFeedback?.isPositive, true)

        // 切换为踩（updateFeedback 路径）
        coordinator.submitFeedback(messageId: msgId, isPositive: false, citations: [], modelContext: context)
        let updatedFeedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertNotNil(updatedFeedback)
        XCTAssertEqual(updatedFeedback?.isPositive, false, "切换后应为 false（踩）")

        // 验证未创建重复记录
        let allFeedbacks = (try? context.fetch(FetchDescriptor<MessageFeedback>())) ?? []
        XCTAssertEqual(allFeedbacks.count, 1, "submitFeedback 切换状态应更新而非新建")
    }
}
