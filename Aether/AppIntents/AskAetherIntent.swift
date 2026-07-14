import AppIntents
import Foundation
import AetherServices

/// Day 16/18: 「向 Aether 提问」AppIntent，支持 Siri 与快捷指令发起对话。
/// Day 18: 通过 IntentChatService 走真实 LLM 流程（不再返回占位文本），
/// AppIntent 不直接持有 ChatViewModel（ViewModel 生命周期绑定 SwiftUI 视图）。
/// Task 5: openAppWhenRun = true，允许 Widget 点击后打开主 App。
struct AskAetherIntent: AppIntent {
    /// Siri / 快捷指令中显示的标题
    static var title: LocalizedStringResource = "向以太提问"
    /// 描述（用于快捷指令详情页）
    static var description = IntentDescription("向以太发送问题并获取回复")
    /// Task 5: Widget 点击后打开主 App，deeplink 携带 query 参数供 ChatView 接收并自动发送
    static var openAppWhenRun: Bool = true

    /// 用户输入的问题文本
    @Parameter(title: "问题")
    var query: String

    /// 执行 intent：调用 IntentChatService 走真实 LLM 流程并返回完整回复。
    /// API Key 未配置或 LLM 失败时返回用户友好的错误提示文本（不抛错打断 Siri）。
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let reply = try await IntentChatService.shared.ask(query: query)
            // 空回复兜底，避免 Siri 朗读空白
            return .result(value: reply.isEmpty ? NSLocalizedString("以太未返回内容，请重试。", comment: "") : reply)
        } catch {
            // API Key 未配置或 LLM 失败时返回提示
            return .result(value: String(format: NSLocalizedString("以太暂时无法回复：%@", comment: ""), error.localizedDescription))
        }
    }
}

/// Day 16/18: 注册 App 快捷指令，让用户可在 Siri 中用「向 Aether 提问」触发。
/// Day 18: 新增「新建对话」「切换会话」两个快捷指令。
struct AskAetherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAetherIntent(),
            phrases: ["向 \(.applicationName) 提问", "问 \(.applicationName)"],
            shortTitle: "向以太提问",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: NewConversationIntent(),
            phrases: ["新建对话 \(.applicationName)", "新对话 \(.applicationName)"],
            shortTitle: "新建对话",
            systemImageName: "plus.bubble"
        )
        AppShortcut(
            intent: SwitchConversationIntent(),
            phrases: ["切换会话 \(.applicationName)", "查找会话 \(.applicationName)"],
            shortTitle: "切换会话",
            systemImageName: "arrow.left.arrow.right"
        )
    }
}
