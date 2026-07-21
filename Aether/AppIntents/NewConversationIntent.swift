import AppIntents
import Foundation
import SwiftData

/// Day 18: 「新建对话」AppIntent，让 Siri / 快捷指令能在以太中创建新会话。
/// 由于 AppIntent 无直接访问主 App 的 ModelContext，这里创建独立 ModelContainer
/// （schema 与 AetherApp 保持一致以保证读写同一 SQLite 文件）。
///
/// P1-2: ModelContext 非 Sendable，AppIntent perform 在后台 actor 执行，
/// 故用 `MainActor.run { ... }` 将 ModelContext 操作 hop 到主线程，
/// 既满足 SwiftData 隔离规则，也避免与主 App 的 ModelContext 跨 actor 共享。
struct NewConversationIntent: AppIntent {
    /// Siri / 快捷指令中显示的标题
    static var title: LocalizedStringResource = "新建对话"
    /// 描述（用于快捷指令详情页）
    static var description = IntentDescription("在以太中创建新对话")

    /// 执行 intent：创建新 Conversation 写入 SwiftData，返回会话 ID。
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // P1-2: 整个 ModelContext 生命周期在 MainActor 上完成，避免跨 actor 访问
        let conversationId: String = try await MainActor.run {
            // 创建与主 App 同 schema 的 ModelContainer（读写同一 SQLite 文件）
            let container = try ModelContainer(
                for: Conversation.self, ChatMessage.self,
                DocumentChunk.self, MessageFeedback.self, HealthInsight.self
            )
            let context = ModelContext(container)
            // 创建新 Conversation 并持久化
            let conversation = Conversation()
            context.insert(conversation)
            try context.save()
            // 返回 conversationId uuidString 供后续 intent / Handoff 使用
            return conversation.id.uuidString
        }
        return .result(value: conversationId)
    }
}
