import Foundation
import SwiftData

/// P2-6 Task 3: FeedbackCoordinator —— 反馈闭环协调器
///
/// 从 ChatViewModel 抽取的反馈状态 / Toast 提示 / 持久化职责。
/// 封装 `feedbackStates` / `feedbackToast` 内部状态与 `handleFeedback` / `submitFeedback` 两个方法，
/// 通过闭包回调通知 ChatViewModel 更新 @Observable 属性。
///
/// 并发边界：本类标注 `@MainActor`，所有方法与闭包在主 actor 上调用；
/// Toast 自动清除 Task 在 `@MainActor` 上下文中 sleep 2 秒后通过闭包回调清空 toast，
/// 任务引用由 coordinator 持有，新的 handleFeedback 调用会取消上一个未触发的清除 Task。
@MainActor
final class FeedbackCoordinator: Coordinator {
    /// 每条助手消息的反馈状态（messageId -> true=赞 / false=踩），内部状态。
    /// 通过 onFeedbackStatesChange 闭包回调与 ChatViewModel 的 @Observable feedbackStates 同步。
    private var feedbackStates: [UUID: Bool] = [:]
    /// 反馈操作后的提示文本（如"感谢点赞"），nil 表示不显示。内部状态。
    /// 通过 onFeedbackToastChange 闭包回调与 ChatViewModel 的 @Observable feedbackToast 同步。
    private var feedbackToast: String?
    /// 当前 citations 提供者（读取 ChatViewModel 的 @Observable var currentCitations 当前值）
    private let citationsProvider: () -> [DocumentChunk]
    /// feedbackStates 变更回调（ChatViewModel 设置，更新 @Observable var feedbackStates）
    private let onFeedbackStatesChange: ([UUID: Bool]) -> Void
    /// feedbackToast 变更回调（ChatViewModel 设置，更新 @Observable var feedbackToast）
    private let onFeedbackToastChange: (String?) -> Void
    /// Toast 自动清除 Task 引用，便于在新的 handleFeedback 调用时取消上一个未触发的清除。
    private var toastClearTask: Task<Void, Never>?

    /// 构造器
    /// - Parameters:
    ///   - citationsProvider: currentCitations 当前值查询闭包（@MainActor），handleFeedback 内部 submitFeedback 时读取
    ///   - onFeedbackStatesChange: feedbackStates 变更回调（@MainActor），同步到 ChatViewModel @Observable 属性
    ///   - onFeedbackToastChange: feedbackToast 变更回调（@MainActor），同步到 ChatViewModel @Observable 属性
    init(citationsProvider: @escaping () -> [DocumentChunk],
         onFeedbackStatesChange: @escaping ([UUID: Bool]) -> Void,
         onFeedbackToastChange: @escaping (String?) -> Void) {
        self.citationsProvider = citationsProvider
        self.onFeedbackStatesChange = onFeedbackStatesChange
        self.onFeedbackToastChange = onFeedbackToastChange
    }

    /// 提交用户对 assistant 消息的反馈，触发 RAG chunk 权重调整。
    /// 已有反馈记录时走 update 路径（撤销旧权重应用新权重），否则走 save 路径（新建记录）。
    /// - Parameters:
    ///   - messageId: 被反馈的 ChatMessage.id
    ///   - isPositive: true=点赞（提权），false=踩（降权）
    ///   - citations: 该消息关联的 RAG 引用分块（来自 currentCitations）
    ///   - modelContext: SwiftData 上下文
    func submitFeedback(messageId: UUID, isPositive: Bool, citations: [DocumentChunk], modelContext: ModelContext) {
        let storage = ChatStorage(modelContext: modelContext)
        // 查询是否已有反馈记录
        if let existing = storage.fetchFeedback(messageId: messageId) {
            // 切换反馈状态：撤销旧权重应用新权重
            storage.updateFeedback(existing, isPositive: isPositive, citations: citations)
        } else {
            // 新反馈
            storage.saveFeedback(messageId: messageId, isPositive: isPositive, citations: citations)
        }
    }

    /// 便捷方法：处理用户反馈点击，更新 UI 状态并持久化。
    /// 行为等价于 ChatViewModel 原始 handleFeedback 实现：
    /// 1. 相同状态再次点击 → 取消反馈（移除 state、清空 toast、取消未触发的 toast 清除 Task）
    /// 2. 不同状态点击 → 更新 state、设置 toast、submitFeedback 持久化、启动 2 秒后清除 toast 的 Task
    /// - Parameters:
    ///   - messageId: 被反馈的 ChatMessage.id
    ///   - isPositive: true=点赞，false=踩
    ///   - modelContext: SwiftData 上下文
    func handleFeedback(messageId: UUID, isPositive: Bool, modelContext: ModelContext) {
        // 如果点击的是已选中的状态，则取消反馈
        if feedbackStates[messageId] == isPositive {
            feedbackStates.removeValue(forKey: messageId)
            feedbackToast = nil
            onFeedbackStatesChange(feedbackStates)
            onFeedbackToastChange(feedbackToast)
            // 取消未触发的 toast 清除 Task（若有）
            toastClearTask?.cancel()
            toastClearTask = nil
            return
        }
        // 更新 UI 状态
        feedbackStates[messageId] = isPositive
        feedbackToast = isPositive ? NSLocalizedString("感谢点赞", comment: "") : NSLocalizedString("感谢反馈，我们会持续改进", comment: "")
        onFeedbackStatesChange(feedbackStates)
        onFeedbackToastChange(feedbackToast)
        // 持久化反馈
        submitFeedback(messageId: messageId, isPositive: isPositive, citations: citationsProvider(), modelContext: modelContext)
        // 2 秒后自动清除提示：取消上一个未触发的清除 Task，启动新的
        toastClearTask?.cancel()
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.feedbackToast = nil
            self?.onFeedbackToastChange(nil)
        }
    }
}
