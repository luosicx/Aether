import SwiftUI

/// 用户 / AI 头像标识
struct AvatarView: View {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Image(systemName: iconName)
                .font(.system(size: size * 0.5))
                .foregroundStyle(iconColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        switch role {
        case .user: return Color.vermillion.opacity(0.15)
        case .assistant: return Color.jadeGreen.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch role {
        case .user: return Color.vermillion
        case .assistant: return Color.jadeGreen
        }
    }

    private var iconName: String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        }
    }
}

#Preview {
    HStack {
        AvatarView(role: .user)
        AvatarView(role: .assistant)
    }
    .padding()
}
