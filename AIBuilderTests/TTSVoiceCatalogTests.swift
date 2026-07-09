import XCTest
@testable import Aether

/// TTSVoiceCatalog 单元测试:验证按语言分组排序、displayName 回退、voice 查找。
final class TTSVoiceCatalogTests: XCTestCase {

    // MARK: - allVoices

    func testAllVoicesReturnsNonEmptyList() {
        let voices = TTSVoiceCatalog.allVoices()
        // 模拟器至少有一个 zh-CN compact Tingting
        XCTAssertFalse(voices.isEmpty, "系统至少应有一个可用音色")
        // 所有音色 identifier 应非空
        for v in voices {
            XCTAssertFalse(v.id.isEmpty, "音色 identifier 不应为空")
        }
    }

    // MARK: - groupedByLanguage

    func testGroupedByLanguagePutsChineseFirst() {
        let groups = TTSVoiceCatalog.groupedByLanguage()
        XCTAssertFalse(groups.isEmpty, "至少应有一个语言分组")
        // zh-CN 应是第一组(若存在)
        let zhCNVoices = groups.flatMap { $0.voices }.filter { $0.language == "zh-CN" }
        if !zhCNVoices.isEmpty {
            XCTAssertEqual(groups.first?.language, "zh-CN", "zh-CN 应排在最前")
        }
    }

    // MARK: - displayName

    func testDisplayNameReturnsNameForKnownIdentifier() {
        let voices = TTSVoiceCatalog.allVoices()
        guard let first = voices.first else {
            return // 模拟器无音色,跳过
        }
        let name = TTSVoiceCatalog.displayName(for: first.id)
        XCTAssertTrue(name.contains(first.name), "displayName 应包含音色名称")
        XCTAssertTrue(name.contains(first.language), "displayName 应包含语言代码")
    }

    func testDisplayNameReturnsUnknownForInvalidIdentifier() {
        let name = TTSVoiceCatalog.displayName(for: "com.invalid.nonexistent.voice")
        XCTAssertEqual(name, "(未知音色)")
    }

    // MARK: - voice

    func testVoiceReturnsNilForInvalidIdentifier() {
        let voice = TTSVoiceCatalog.voice(for: "com.invalid.nonexistent.voice")
        XCTAssertNil(voice)
    }

    // MARK: - fallback

    func testFallbackChineseVoicesNotEmpty() {
        XCTAssertFalse(TTSVoiceCatalog.fallbackChineseVoices.isEmpty, "fallback 列表不应为空")
    }
}
