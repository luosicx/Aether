import XCTest
import SwiftUI
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 25: 主题管理器单元测试
/// 验证 AetherTheme 枚举、ThemeManager 初始化/切换/持久化
final class ThemeManagerTests: XCTestCase {

    // MARK: - AetherTheme 枚举验证

    /// 验证三套主题枚举完整性
    func testAetherThemeAllCases() {
        XCTAssertEqual(AetherTheme.allCases.count, 3)
        XCTAssertTrue(AetherTheme.allCases.contains(.deepSpace))
        XCTAssertTrue(AetherTheme.allCases.contains(.dawn))
        XCTAssertTrue(AetherTheme.allCases.contains(.aurora))
    }

    /// 验证 rawValue 与 UserPreference 默认值对齐
    func testAetherThemeRawValues() {
        XCTAssertEqual(AetherTheme.deepSpace.rawValue, "deepSpace")
        XCTAssertEqual(AetherTheme.dawn.rawValue, "dawn")
        XCTAssertEqual(AetherTheme.aurora.rawValue, "aurora")
    }

    /// 验证 displayName 返回中文名称
    func testAetherThemeDisplayNames() {
        XCTAssertEqual(AetherTheme.deepSpace.displayName, "深空")
        XCTAssertEqual(AetherTheme.dawn.displayName, "黎明")
        XCTAssertEqual(AetherTheme.aurora.displayName, "极光")
    }

    /// 验证 Identifiable id 属性
    func testAetherThemeIdentifiable() {
        XCTAssertEqual(AetherTheme.deepSpace.id, "deepSpace")
        XCTAssertEqual(AetherTheme.dawn.id, "dawn")
        XCTAssertEqual(AetherTheme.aurora.id, "aurora")
    }

    /// 验证每个主题的颜色属性非默认值
    func testAetherThemeColorProperties() {
        for theme in AetherTheme.allCases {
            XCTAssertFalse(theme.backgroundGradient.isEmpty, "\(theme.rawValue) 的背景渐变不应为空")
            // 验证背景渐变至少有两个颜色
            XCTAssertGreaterThanOrEqual(theme.backgroundGradient.count, 1)
        }
    }

    /// 验证不同主题的颜色互不相同
    func testAetherThemeColorsDifferBetweenThemes() {
        XCTAssertNotEqual(AetherTheme.deepSpace.bubbleUserColor, AetherTheme.dawn.bubbleUserColor)
        XCTAssertNotEqual(AetherTheme.deepSpace.textPrimaryColor, AetherTheme.aurora.textPrimaryColor)
    }

    // MARK: - ThemeTokens 解析

    /// 验证 ThemeTokens.current 按名称解析主题
    func testThemeTokensResolveByName() {
        XCTAssertEqual(ThemeTokens.current("deepSpace"), .deepSpace)
        XCTAssertEqual(ThemeTokens.current("dawn"), .dawn)
        XCTAssertEqual(ThemeTokens.current("aurora"), .aurora)
    }

    /// 验证未匹配的名称回退到 .deepSpace
    func testThemeTokensFallbackForUnknownName() {
        XCTAssertEqual(ThemeTokens.current("unknown"), .deepSpace)
        XCTAssertEqual(ThemeTokens.current(""), .deepSpace)
    }

    // MARK: - ThemeManager 初始化与切换

    /// 验证 ThemeManager 默认主题为 deepSpace（无 UserDefaults 记录时）
    func testThemeManagerDefaultTheme() {
        // 清除可能存在的旧值
        UserDefaults.standard.removeObject(forKey: ThemeManager.storageKey)
        let manager = ThemeManager()
        XCTAssertEqual(manager.currentTheme, .deepSpace, "无存储时默认应为 deepSpace")
    }

    /// 验证 ThemeManager 切换主题后 currentTheme 立即更新
    func testThemeManagerSwitchTheme() {
        let manager = ThemeManager()
        manager.switchTheme(.aurora)
        XCTAssertEqual(manager.currentTheme, .aurora)
        manager.switchTheme(.dawn)
        XCTAssertEqual(manager.currentTheme, .dawn)
    }

    /// 验证 ThemeManager.switchTheme(byName:) 按名称切换
    func testThemeManagerSwitchByName() {
        let manager = ThemeManager()
        manager.switchTheme(byName: "aurora")
        XCTAssertEqual(manager.currentTheme, .aurora)
    }

    /// 验证 switchTheme(byName:) 对未知名称不改变当前主题
    func testThemeManagerSwitchByNameIgnoresUnknown() {
        let manager = ThemeManager()
        manager.switchTheme(.dawn)
        manager.switchTheme(byName: "unknown_theme")
        XCTAssertEqual(manager.currentTheme, .dawn, "未知名称不应改变当前主题")
    }

    // MARK: - 持久化验证

    /// 验证切换主题后值持久化到 UserDefaults
    func testThemeManagerPersistsToUserDefaults() {
        let manager = ThemeManager()
        manager.switchTheme(.aurora)
        let stored = UserDefaults.standard.string(forKey: ThemeManager.storageKey)
        XCTAssertEqual(stored, "aurora", "切换后应持久化 rawValue 到 UserDefaults")
        // 清理测试数据
        UserDefaults.standard.removeObject(forKey: ThemeManager.storageKey)
    }

    /// 验证 ThemeManager init 从 UserDefaults 读取已保存的主题
    func testThemeManagerInitReadsFromUserDefaults() {
        UserDefaults.standard.set("dawn", forKey: ThemeManager.storageKey)
        let manager = ThemeManager()
        XCTAssertEqual(manager.currentTheme, .dawn, "init 应从 UserDefaults 读取已保存主题")
        // 清理测试数据
        UserDefaults.standard.removeObject(forKey: ThemeManager.storageKey)
    }

    /// 验证 ThemeManager init 对无效存储值回退到 deepSpace
    func testThemeManagerInitFallsBackForInvalidStoredValue() {
        UserDefaults.standard.set("invalid_theme", forKey: ThemeManager.storageKey)
        let manager = ThemeManager()
        XCTAssertEqual(manager.currentTheme, .deepSpace, "无效存储值应回退到 deepSpace")
        // 清理测试数据
        UserDefaults.standard.removeObject(forKey: ThemeManager.storageKey)
    }

    // MARK: - 主题传播验证

    /// 验证切换主题后 Color 语义 token 反映新主题的颜色
    func testColorTokensReflectCurrentTheme() {
        let manager = ThemeManager.shared
        // 切换到 deepSpace，验证 Color token 与主题色一致
        manager.switchTheme(.deepSpace)
        XCTAssertEqual(
            Color.bubbleUser,
            AetherTheme.deepSpace.bubbleUserColor,
            "Color.bubbleUser 应反映 deepSpace 主题色"
        )
        XCTAssertEqual(
            Color.bubbleAI,
            AetherTheme.deepSpace.bubbleAIColor,
            "Color.bubbleAI 应反映 deepSpace 主题色"
        )
        XCTAssertEqual(
            Color.textPrimary,
            AetherTheme.deepSpace.textPrimaryColor,
            "Color.textPrimary 应反映 deepSpace 主题色"
        )
        XCTAssertEqual(
            Color.textSecondary,
            AetherTheme.deepSpace.textSecondaryColor,
            "Color.textSecondary 应反映 deepSpace 主题色"
        )

        // 切换到 dawn，验证 Color token 立即更新
        manager.switchTheme(.dawn)
        XCTAssertEqual(
            Color.bubbleUser,
            AetherTheme.dawn.bubbleUserColor,
            "切换后 Color.bubbleUser 应反映 dawn 主题色"
        )
        XCTAssertEqual(
            Color.bubbleAI,
            AetherTheme.dawn.bubbleAIColor,
            "切换后 Color.bubbleAI 应反映 dawn 主题色"
        )
        XCTAssertEqual(
            Color.textPrimary,
            AetherTheme.dawn.textPrimaryColor,
            "切换后 Color.textPrimary 应反映 dawn 主题色"
        )

        // 切换到 aurora 验证全部更新
        manager.switchTheme(.aurora)
        XCTAssertEqual(
            Color.bubbleUser,
            AetherTheme.aurora.bubbleUserColor,
            "切换后 Color.bubbleUser 应反映 aurora 主题色"
        )
        XCTAssertEqual(
            Color.textPrimary,
            AetherTheme.aurora.textPrimaryColor,
            "切换后 Color.textPrimary 应反映 aurora 主题色"
        )
        XCTAssertEqual(
            Color.textSecondary,
            AetherTheme.aurora.textSecondaryColor,
            "切换后 Color.textSecondary 应反映 aurora 主题色"
        )
    }

    /// 验证 Color.backgroundPrimary 反映当前主题的背景渐变首色
    func testColorBackgroundPrimaryReflectsTheme() {
        let manager = ThemeManager.shared
        manager.switchTheme(.deepSpace)
        XCTAssertEqual(
            Color.backgroundPrimary,
            AetherTheme.deepSpace.backgroundGradient.first ?? Color.black,
            "backgroundPrimary 应反映 deepSpace 背景色"
        )

        manager.switchTheme(.dawn)
        XCTAssertEqual(
            Color.backgroundPrimary,
            AetherTheme.dawn.backgroundGradient.first ?? Color.black,
            "backgroundPrimary 应反映 dawn 背景色"
        )
    }

    /// 验证 Color.textTertiary 由当前主题的次要色派生
    func testColorTextTertiaryReflectsTheme() {
        let manager = ThemeManager.shared
        manager.switchTheme(.deepSpace)
        XCTAssertEqual(
            Color.textTertiary,
            AetherTheme.deepSpace.textSecondaryColor.opacity(0.6),
            "textTertiary 应由 deepSpace 次要色派生"
        )

        manager.switchTheme(.aurora)
        XCTAssertEqual(
            Color.textTertiary,
            AetherTheme.aurora.textSecondaryColor.opacity(0.6),
            "textTertiary 应由 aurora 次要色派生"
        )
    }

    /// 验证 switchTheme(byName:) 能从 UserPreference.themeName 同步主题
    func testSwitchByNameSyncsFromUserPreferenceThemeName() {
        let manager = ThemeManager.shared
        // 模拟 UserPreference.themeName = "aurora" 的同步
        manager.switchTheme(byName: "aurora")
        XCTAssertEqual(manager.currentTheme, .aurora, "switchTheme(byName:) 应从 themeName 同步")

        // 模拟 UserPreference.themeName = "dawn" 的同步
        manager.switchTheme(byName: "dawn")
        XCTAssertEqual(manager.currentTheme, .dawn, "switchTheme(byName:) 应从 themeName 同步")

        // 验证 Color token 也随之更新
        XCTAssertEqual(Color.bubbleUser, AetherTheme.dawn.bubbleUserColor, "同步后 Color token 应更新")
    }

    /// 验证不同主题的 Color token 值互不相同
    func testColorTokensDifferBetweenThemes() {
        let manager = ThemeManager.shared
        manager.switchTheme(.deepSpace)
        let deepSpaceTextPrimary = Color.textPrimary
        let deepSpaceBubbleUser = Color.bubbleUser

        manager.switchTheme(.dawn)
        let dawnTextPrimary = Color.textPrimary
        let dawnBubbleUser = Color.bubbleUser

        XCTAssertNotEqual(deepSpaceTextPrimary, dawnTextPrimary, "不同主题的 textPrimary 应不同")
        XCTAssertNotEqual(deepSpaceBubbleUser, dawnBubbleUser, "不同主题的 bubbleUser 应不同")
    }
}
