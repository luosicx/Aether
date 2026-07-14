import SwiftUI
import AetherDesign

/// 用户 / AI 头像标识
public struct AvatarView: View {
    public enum Role {
        case user
        case assistant
    }

    public let role: Role
    public var size: CGFloat = 32
    /// Task 26: 自定义头像二进制数据，非空时优先显示图片
    public var avatarData: Data? = nil

    public init(role: Role, size: CGFloat = 32, avatarData: Data? = nil) {
        self.role = role
        self.size = size
        self.avatarData = avatarData
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            if let data = avatarData, let img = platformImage(from: data) {
                // Task 26: 显示自定义头像
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: glowColor, radius: 6)
        .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        switch role {
        case .user: return Color.aetherPurple.opacity(0.2)
        case .assistant: return Color.electricBlue.opacity(0.2)
        }
    }

    private var iconColor: Color {
        switch role {
        case .user: return Color.aetherPurple
        case .assistant: return Color.electricBlue
        }
    }

    /// Aether 品牌光晕：用户紫 / AI 蓝，体现科技感
    private var glowColor: Color {
        switch role {
        case .user: return Color.aetherPurple.opacity(0.4)
        case .assistant: return Color.electricBlue.opacity(0.4)
        }
    }

    private var iconName: String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        }
    }
}

/// 跨平台从 Data 创建 SwiftUI Image(iOS: UIImage / macOS: NSImage)
private func platformImage(from data: Data) -> Image? {
    #if os(iOS)
    guard let img = UIImage(data: data) else { return nil }
    return Image(uiImage: img)
    #else
    guard let img = NSImage(data: data) else { return nil }
    return Image(nsImage: img)
    #endif
}

#Preview {
    HStack {
        AvatarView(role: .user)
        AvatarView(role: .assistant)
    }
    .padding()
}
