import Foundation
import SwiftUI

/// App 内语言切换管理器。
///
/// 通过写入 `AppleLanguages` UserDefaults 实现持久化，下次启动时由系统按该数组
/// 依次匹配可用的本地化资源。当前不在运行时即时切换（SwiftUI 对运行时切换
/// 支持有限，强切可能导致文案混合），切换后提示用户重启 App。
@MainActor
final class LanguageManager: ObservableObject {

    /// 可选语言枚举
    enum AppLanguage: String, CaseIterable, Identifiable {
        /// 跟随系统（清空 AppleLanguages，使用系统默认）
        case system
        /// 简体中文
        case zhHans = "zh-Hans"
        /// 繁体中文
        case zhHant = "zh-Hant"
        /// 英文
        case en = "en"
        /// 日语
        case ja = "ja"
        /// 韩语
        case ko = "ko"
        /// 法语
        case fr = "fr"
        /// 德语
        case de = "de"
        /// 西班牙语
        case es = "es"

        var id: String { rawValue }

        /// 在 UI 中展示的名称（用自身语言书写，便于用户识别）
        var displayName: String {
            switch self {
            case .system: return String(localized: "跟随系统")
            case .zhHans: return String(localized: "简体中文")
            case .zhHant: return String(localized: "繁体中文")
            case .en: return String(localized: "英文")
            case .ja: return String(localized: "日本語")
            case .ko: return String(localized: "한국어")
            case .fr: return String(localized: "Français")
            case .de: return String(localized: "Deutsch")
            case .es: return String(localized: "Español")
            }
        }

        /// SF Symbol 图标（用于设置项视觉区分）
        var icon: String {
            switch self {
            case .system: return "globe"
            case .zhHans: return "character.bubble"
            case .zhHant: return "character.bubble"
            case .en: return "e.bubble"
            case .ja: return "character.bubble"
            case .ko: return "character.bubble"
            case .fr: return "character.bubble"
            case .de: return "character.bubble"
            case .es: return "character.bubble"
            }
        }
    }

    /// UserDefaults 持久化 key
    private let storageKey = "app_preferred_language"

    /// 单例
    static let shared = LanguageManager()

    /// 当前选择的语言（已持久化），默认 .system
    @Published var current: AppLanguage {
        didSet {
            persist(current)
            applyToAppleLanguages(current)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        current = AppLanguage(rawValue: raw) ?? .system
    }

    /// 持久化选择到 UserDefaults
    private func persist(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }

    /// 写入 AppleLanguages 数组，下次启动按该顺序匹配本地化资源
    private func applyToAppleLanguages(_ language: AppLanguage) {
        switch language {
        case .system:
            // 跟随系统：移除自定义偏好，回退到设备系统语言
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .zhHans, .zhHant, .en, .ja, .ko, .fr, .de, .es:
            // 设置首选语言数组，首元素为用户选择
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        // 注意：AppleLanguages 在下次 App 启动时生效，运行时无法即时切换
    }

    /// 判断当前语言是否与给定语言一致（用于 UI 高亮选中项）
    func isSelected(_ language: AppLanguage) -> Bool {
        current == language
    }
}
