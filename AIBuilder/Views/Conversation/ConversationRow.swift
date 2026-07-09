import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    var isSelected: Bool = false
    var showsCheckbox: Bool = false

    private var lastMessage: ChatMessage? {
        conversation.messages.last
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsCheckbox {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                            .accessibilityHidden(true)
                    }
                    Text(conversation.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let msg = lastMessage {
                    Text(msg.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: NSLocalizedString("%@，最后消息：%@", comment: ""), conversation.title, lastMessage?.content ?? NSLocalizedString("无", comment: ""))))
        .accessibilityHint("打开此会话")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("conversationRow_\(conversation.id.uuidString)")
    }
}
