import SwiftUI
import AetherDesign

struct ConversationRow: View {
    let conversation: Conversation
    var isSelected: Bool = false
    var showsCheckbox: Bool = false

    private var lastMessage: ChatMessage? {
        conversation.messages.last
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {
            if showsCheckbox {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.aetherPurple : Color.duskGray)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.captionAI)
                            .foregroundColor(Color.aetherPurple)
                            .accessibilityHidden(true)
                    }
                    Text(conversation.title)
                        .font(.bodyAI.weight(.medium))
                        .foregroundStyle(Color.starlight)
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.createdAt, style: .relative)
                        .font(.captionAI)
                        .foregroundStyle(Color.duskGray)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.captionAI)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.aetherPurple)
                            .clipShape(Capsule())
                    }
                }
                if let msg = lastMessage {
                    Text(msg.content)
                        .font(.subheadlineAI)
                        .foregroundStyle(Color.duskGray)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, Spacing.sm + 2)
        .listRowBackground(
            ZStack {
                Color.liquidGlass.opacity(0.4)
                if isSelected {
                    Color.aetherPurple.opacity(0.28)
                }
            }
            .background(.ultraThinMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: NSLocalizedString("%@，最后消息：%@", comment: ""), conversation.title, lastMessage?.content ?? NSLocalizedString("无", comment: ""))))
        .accessibilityHint("打开此会话")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("conversationRow_\(conversation.id.uuidString)")
    }
}
