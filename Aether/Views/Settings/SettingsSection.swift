import Foundation

// MARK: - SettingsSection

/// 设置页分类,用于 iPad/macOS NavigationSplitView 左侧导航
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case provider
    case inference
    case voice
    case features
    case health
    case icloud
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: return String(localized: "API 与模型")
        case .inference: return String(localized: "推理配置")
        case .voice: return String(localized: "语音朗读")
        case .features: return String(localized: "功能与偏好")
        case .health: return String(localized: "健康")
        case .icloud: return String(localized: "iCloud 同步")
        case .about: return String(localized: "关于")
        }
    }

    var icon: String {
        switch self {
        case .provider: return "network"
        case .inference: return "cpu"
        case .voice: return "speaker.wave.2"
        case .features: return "switch.2"
        case .health: return "heart.text.square"
        case .icloud: return "icloud"
        case .about: return "info.circle"
        }
    }
}
