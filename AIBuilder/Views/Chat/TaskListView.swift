import SwiftUI

/// 任务列表项数据模型
struct TaskListItem: Identifiable {
    let id = UUID()
    let isCompleted: Bool
    let text: String
}

/// Markdown 任务列表渲染视图
struct TaskListView: View {
    let items: [TaskListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(item.isCompleted ? .accentColor : .secondary)
                        .accessibilityHidden(true)

                    if let attributed = try? AttributedString(
                        markdown: item.text,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
                    ) {
                        Text(attributed)
                            .font(.body)
                            .strikethrough(item.isCompleted, color: .secondary)
                    } else {
                        Text(item.text)
                            .font(.body)
                            .strikethrough(item.isCompleted, color: .secondary)
                    }
                }
            }
        }
    }
}
