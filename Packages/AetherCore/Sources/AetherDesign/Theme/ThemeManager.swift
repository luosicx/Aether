import Foundation
import SwiftUI
import Observation

/// Task 25: 主题管理器，单例 + @Observable，负责当前主题的内存状态与 UserDefaults 持久化
/// 切换主题后，所有读取 ThemeManager.shared.currentTheme 的视图（含 Color 语义色扩展）会自动重新渲染
@Observable
public final class ThemeManager {
    /// 单例，全局共享
    public static let shared = ThemeManager()

    /// UserDefaults 存储 key
    public static let storageKey = "themeName"

    /// 当前主题，didSet 时持久化到 UserDefaults
    public var currentTheme: AetherTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.storageKey)
        }
    }

    /// 初始化：从 UserDefaults 读取已保存的主题名，未保存时默认 .deepSpace
    init() {
        let name = UserDefaults.standard.string(forKey: Self.storageKey) ?? AetherTheme.deepSpace.rawValue
        currentTheme = AetherTheme(rawValue: name) ?? .deepSpace
    }

    /// 切换到指定主题并持久化
    /// - Parameter theme: 目标主题
    public func switchTheme(_ theme: AetherTheme) {
        currentTheme = theme
    }

    /// 按主题名切换（便于从 UserPreference.themeName 同步）
    /// - Parameter themeName: 主题名，未匹配时保持当前主题
    public func switchTheme(byName themeName: String) {
        if let theme = AetherTheme(rawValue: themeName) {
            currentTheme = theme
        }
    }
}
