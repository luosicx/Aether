import AppIntents
import Foundation
import SwiftData

/// Day 18: 「新建对话」AppIntent，让 Siri / 快捷指令能在以太中创建新会话。
/// AppIntent 拿不到主 App 注入的 ModelContext，因此复用 `AetherApp.sharedModelContainer`
/// ——schema 与存储位置都由 AetherApp 单点定义，intent 与主 App 必然读写同一个 store。
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
            // 复用共享容器，不在这里列模型清单：旧写法自建 `ModelContainer(for: 5 个模型)`，
            // CoreData 把同一 store 里多出来的 UserPreference / AgentTask / Memory 当"实体被移除"，
            // 直接删表并清空数据，之后主 App 那次 save 就报 `no such table: ZUSERPREFERENCE`。
            let context = ModelContext(AetherApp.sharedModelContainer)
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
