import AppIntents
import Foundation
import SwiftData

/// Day 18: 「切换会话」AppIntent，按关键词切换到最近匹配的会话。
/// 通过 title 字段做大小写不敏感包含匹配，按创建时间降序取首个匹配。
struct SwitchConversationIntent: AppIntent {
    /// Siri / 快捷指令中显示的标题
    static var title: LocalizedStringResource = "Switch Conversation"
    /// 描述（用于快捷指令详情页）
    static var description = IntentDescription("按关键词切换到最近匹配的会话")

    /// 用户输入的搜索关键词
    @Parameter(title: "关键词")
    var keyword: String

    /// 执行 intent：查询 title 包含 keyword 的会话，返回最近一个会话标题。
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 创建与主 App 同 schema 的 ModelContainer
        let container = try ModelContainer(
            for: Conversation.self, ChatMessage.self,
            DocumentChunk.self, MessageFeedback.self, HealthInsight.self
        )
        let context = ModelContext(container)
        // 查询 title CONTAINS keyword 的 Conversation，按 createdAt 降序取首个。
        // 将 keyword 绑定到局部常量，避免 #Predicate 宏捕获 self（self 引用无法在谓词中表达）
        let keyword = self.keyword
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.title.localizedStandardContains(keyword) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let matches = try context.fetch(descriptor)
        // 未匹配时返回提示文本
        guard let matched = matches.first else {
            return .result(value: "未找到匹配会话")
        }
        return .result(value: matched.title)
    }
}
