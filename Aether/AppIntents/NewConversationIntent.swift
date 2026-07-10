import AppIntents
import Foundation
import SwiftData

/// Day 18: 「新建对话」AppIntent，让 Siri / 快捷指令能在以太中创建新会话。
/// 由于 AppIntent 无直接访问主 App 的 ModelContext，这里创建独立 ModelContainer
/// （schema 与 AetherApp 保持一致以保证读写同一 SQLite 文件）。
struct NewConversationIntent: AppIntent {
    /// Siri / 快捷指令中显示的标题
    static var title: LocalizedStringResource = "新建对话"
    /// 描述（用于快捷指令详情页）
    static var description = IntentDescription("在以太中创建新对话")

    /// 执行 intent：创建新 Conversation 写入 SwiftData，返回会话 ID。
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
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
        return .result(value: conversation.id.uuidString)
    }
}
