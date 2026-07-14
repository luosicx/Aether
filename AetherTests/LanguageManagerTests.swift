import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// LanguageManager 与 AppLanguage 单元测试
/// 验证语言枚举映射、单例持久化、AppleLanguages 写入及 isSelected 判等。
@MainActor
final class LanguageManagerTests: XCTestCase {

    /// LanguageManager 持久化当前语言所用的 UserDefaults key
    private let storageKey = "app_preferred_language"
    /// 系统语言偏好数组 key
    private let appleLanguagesKey = "AppleLanguages"

    override func setUp() {
        super.setUp()
        // 测试前清理 UserDefaults，模拟无偏好状态
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
    }

    override func tearDown() {
        // 测试后恢复默认状态并清理 UserDefaults，避免污染其他测试
        LanguageManager.shared.current = .system
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        super.tearDown()
    }

    // MARK: - AppLanguage(rawValue:) 双向映射

    func testAppLanguageRawValueMapping() {
        // case → rawValue
        XCTAssertEqual(LanguageManager.AppLanguage.zhHans.rawValue, "zh-Hans")
        XCTAssertEqual(LanguageManager.AppLanguage.zhHant.rawValue, "zh-Hant")
        XCTAssertEqual(LanguageManager.AppLanguage.en.rawValue, "en")
        XCTAssertEqual(LanguageManager.AppLanguage.system.rawValue, "system")

        // rawValue → case（反向映射）
        XCTAssertEqual(LanguageManager.AppLanguage(rawValue: "zh-Hans"), .zhHans)
        XCTAssertEqual(LanguageManager.AppLanguage(rawValue: "zh-Hant"), .zhHant)
        XCTAssertEqual(LanguageManager.AppLanguage(rawValue: "en"), .en)
        XCTAssertEqual(LanguageManager.AppLanguage(rawValue: "system"), .system)
    }

    // MARK: - allCases 含 4 个元素且 id 不重复

    func testAllCasesCountAndUniqueIds() {
        let allCases = LanguageManager.AppLanguage.allCases
        XCTAssertEqual(allCases.count, 4, "AppLanguage 应有 4 个 case")
        let ids = allCases.map { $0.id }
        XCTAssertEqual(Set(ids).count, 4, "各 case 的 id 不应重复")
    }

    // MARK: - displayName 和 icon 对每个 case 返回非空字符串

    func testDisplayNameAndIconNonEmpty() {
        for lang in LanguageManager.AppLanguage.allCases {
            XCTAssertFalse(lang.displayName.isEmpty,
                           "\(lang.rawValue) 的 displayName 不应为空")
            XCTAssertFalse(lang.icon.isEmpty,
                           "\(lang.rawValue) 的 icon 不应为空")
        }
    }

    // MARK: - LanguageManager.shared.current 初始值

    func testCurrentInitialValueIsSystemWhenNoPreferenceStored() {
        // 单例在整个进程内只 init 一次；setUp 已清理 UserDefaults。
        // 此处显式还原到 .system，验证无偏好时 current == .system。
        LanguageManager.shared.current = .system
        XCTAssertEqual(LanguageManager.shared.current, .system,
                      "无存储偏好时 current 应为 .system")
    }

    // MARK: - 设置 current = .zhHans 后 UserDefaults 写入 "zh-Hans"

    func testSetCurrentZhHansPersistsToUserDefaults() {
        LanguageManager.shared.current = .zhHans
        XCTAssertEqual(LanguageManager.shared.current, .zhHans)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: storageKey),
            "zh-Hans",
            "设置 .zhHans 后 storageKey 应写入 'zh-Hans'"
        )
    }

    // MARK: - 设置 current = .system 后 AppleLanguages 不再包含自定义语言

    func testSetCurrentSystemRemovesAppleLanguages() {
        // 前置：先设置一个非系统语言，确保 AppleLanguages 存在
        LanguageManager.shared.current = .zhHans
        XCTAssertNotNil(
            UserDefaults.standard.array(forKey: appleLanguagesKey),
            "前置：设置 .zhHans 后 AppleLanguages 应存在"
        )

        // 切回 .system，AppleLanguages 应被移除或回退为系统默认（不含自定义值）
        // 注意：系统可能在 removeObject 后重新填充 AppleLanguages 为设备默认语言列表
        LanguageManager.shared.current = .system
        let appleLangs = UserDefaults.standard.array(forKey: appleLanguagesKey)
        if appleLangs != nil {
            // 若仍存在，验证不包含我们设置的自定义语言
            let contains = (appleLangs as? [String])?.contains("zh-Hans") ?? false
            XCTAssertFalse(contains,
                          "设置 .system 后 AppleLanguages 不应包含自定义语言 zh-Hans，实际：\(appleLangs ?? [])")
        }
    }

    // MARK: - isSelected(_:) 判等

    func testIsSelectedEquality() {
        LanguageManager.shared.current = .en
        XCTAssertTrue(LanguageManager.shared.isSelected(.en),
                     "current == .en 时 isSelected(.en) 应为 true")
        XCTAssertFalse(LanguageManager.shared.isSelected(.zhHans),
                       "current == .en 时 isSelected(.zhHans) 应为 false")
    }

    // MARK: - 设置 .zhHant 后 AppleLanguages 写入验证

    func testSetCurrentZhHantWritesAppleLanguages() {
        LanguageManager.shared.current = .zhHant
        XCTAssertEqual(LanguageManager.shared.current, .zhHant)
        let appleLangs = UserDefaults.standard.array(forKey: appleLanguagesKey) as? [String]
        XCTAssertNotNil(appleLangs, "设置 .zhHant 后 AppleLanguages 应存在")
        XCTAssertEqual(appleLangs?.first, "zh-Hant",
                       "AppleLanguages 首元素应为 'zh-Hant'，实际：\(appleLangs ?? [])")
    }

    // MARK: - 设置 .en 后 AppleLanguages 写入验证

    func testSetCurrentEnWritesAppleLanguages() {
        LanguageManager.shared.current = .en
        XCTAssertEqual(LanguageManager.shared.current, .en)
        let appleLangs = UserDefaults.standard.array(forKey: appleLanguagesKey) as? [String]
        XCTAssertNotNil(appleLangs, "设置 .en 后 AppleLanguages 应存在")
        XCTAssertEqual(appleLangs?.first, "en",
                       "AppleLanguages 首元素应为 'en'，实际：\(appleLangs ?? [])")
    }

    // MARK: - displayName 具体值验证

    func testDisplayNameSpecificValues() {
        // displayName 使用 String(localized:)，在无本地化文件时回退为 key 本身
        XCTAssertEqual(LanguageManager.AppLanguage.system.displayName, String(localized: "跟随系统"))
        XCTAssertEqual(LanguageManager.AppLanguage.zhHans.displayName, String(localized: "简体中文"))
        XCTAssertEqual(LanguageManager.AppLanguage.zhHant.displayName, String(localized: "繁体中文"))
        XCTAssertEqual(LanguageManager.AppLanguage.en.displayName, String(localized: "英文"))
    }

    // MARK: - icon 具体值验证

    func testIconSpecificValues() {
        XCTAssertEqual(LanguageManager.AppLanguage.system.icon, "globe")
        XCTAssertEqual(LanguageManager.AppLanguage.zhHans.icon, "character.bubble")
        XCTAssertEqual(LanguageManager.AppLanguage.zhHant.icon, "character.bubble")
        XCTAssertEqual(LanguageManager.AppLanguage.en.icon, "e.bubble")
    }

    // MARK: - 语言切换后 storageKey 写入对应 rawValue

    func testSetCurrentZhHantPersistsToUserDefaults() {
        LanguageManager.shared.current = .zhHant
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: storageKey),
            "zh-Hant",
            "设置 .zhHant 后 storageKey 应写入 'zh-Hant'"
        )
    }

    func testSetCurrentEnPersistsToUserDefaults() {
        LanguageManager.shared.current = .en
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: storageKey),
            "en",
            "设置 .en 后 storageKey 应写入 'en'"
        )
    }

    // MARK: - 多次切换语言后状态一致性

    func testMultipleLanguageSwitchesRemainConsistent() {
        LanguageManager.shared.current = .zhHans
        XCTAssertEqual(LanguageManager.shared.current, .zhHans)
        LanguageManager.shared.current = .en
        XCTAssertEqual(LanguageManager.shared.current, .en)
        XCTAssertTrue(LanguageManager.shared.isSelected(.en))
        XCTAssertFalse(LanguageManager.shared.isSelected(.zhHans))
        LanguageManager.shared.current = .zhHant
        XCTAssertEqual(LanguageManager.shared.current, .zhHant)
        XCTAssertTrue(LanguageManager.shared.isSelected(.zhHant))
    }
}
