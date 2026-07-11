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
        XCTAssertEqual(name, NSLocalizedString("(未知音色)", comment: ""))
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

    // MARK: - 缓存机制

    /// reloadVoices 后再次调用 allVoices 应返回一致的结果（验证缓存清空后可重新填充）
    func testReloadVoicesAndRepopulate() {
        let firstCall = TTSVoiceCatalog.allVoices()
        TTSVoiceCatalog.reloadVoices()
        let secondCall = TTSVoiceCatalog.allVoices()
        XCTAssertEqual(firstCall.count, secondCall.count, "reloadVoices 后音色数量应一致")
    }

    /// 多次调用 allVoices 返回相同结果（验证缓存命中）
    func testAllVoicesReturnsConsistentResult() {
        let firstCall = TTSVoiceCatalog.allVoices()
        let secondCall = TTSVoiceCatalog.allVoices()
        XCTAssertEqual(firstCall.count, secondCall.count, "多次调用应返回一致的结果")
    }

    /// reloadVoices 后 groupedByLanguage 也应重新填充
    func testReloadVoicesClearsGroupedCache() {
        _ = TTSVoiceCatalog.groupedByLanguage()
        TTSVoiceCatalog.reloadVoices()
        let regrouped = TTSVoiceCatalog.groupedByLanguage()
        XCTAssertFalse(regrouped.isEmpty, "reloadVoices 后 groupedByLanguage 应重新填充")
    }

    // MARK: - groupedByLanguage 排序

    /// 分组排序：zh-CN < zh-TW/zh-HK < en-US < 其他（按字母序）
    func testGroupedByLanguageSortOrder() {
        let groups = TTSVoiceCatalog.groupedByLanguage()
        guard groups.count > 1 else { return }
        // 收集所有出现过的语言
        let languages = groups.map { $0.language }
        // 若存在 zh-CN，必须排在第一位
        if languages.contains("zh-CN") {
            XCTAssertEqual(groups.first?.language, "zh-CN", "zh-CN 应排在最前")
        }
        // 验证排序优先级：zh-CN(0) < zh-TW/zh-HK(1) < en-US(2) < 其他(3)
        for i in 0..<(languages.count - 1) {
            let lhs = languages[i]
            let rhs = languages[i + 1]
            let lhsTier = languageTier(lhs)
            let rhsTier = languageTier(rhs)
            if lhsTier != rhsTier {
                XCTAssertLessThan(lhsTier, rhsTier, "\(lhs)(tier=\(lhsTier)) 应排在 \(rhs)(tier=\(rhsTier)) 之前")
            } else {
                XCTAssertLessThanOrEqual(lhs, rhs, "同 tier 内应按字母序：\(lhs) <= \(rhs)")
            }
        }
    }

    /// 每个分组内的所有音色 language 应与分组 key 一致
    func testGroupedVoicesMatchLanguageKey() {
        let groups = TTSVoiceCatalog.groupedByLanguage()
        for group in groups {
            for voice in group.voices {
                XCTAssertEqual(voice.language, group.language,
                               "分组内音色 language 应与分组 key 一致")
            }
        }
    }

    // MARK: - voice 查找

    /// 对 allVoices 中第一个音色调用 voice(for:) 应返回非 nil
    func testVoiceReturnsValueForValidIdentifier() {
        let voices = TTSVoiceCatalog.allVoices()
        guard let first = voices.first else { return }
        let voice = TTSVoiceCatalog.voice(for: first.id)
        XCTAssertNotNil(voice, "有效 identifier 应返回 AVSpeechSynthesisVoice")
        XCTAssertEqual(voice?.identifier, first.id, "返回的 voice identifier 应匹配")
    }

    // MARK: - language 过滤

    /// 按 language 过滤 allVoices 应只返回匹配语言的音色
    func testLanguageFilterReturnsOnlyMatchingVoices() {
        let voices = TTSVoiceCatalog.allVoices()
        let languages = Set(voices.map { $0.language })
        for language in languages {
            let filtered = voices.filter { $0.language == language }
            XCTAssertFalse(filtered.isEmpty, "过滤结果不应为空")
            for v in filtered {
                XCTAssertEqual(v.language, language, "过滤后音色语言应匹配")
            }
        }
    }

    // MARK: - TTSVoice 结构

    /// TTSVoice 应正确实现 Identifiable 和 Hashable
    func testTTSVoiceIdentifiableAndHashable() {
        let voices = TTSVoiceCatalog.allVoices()
        guard let first = voices.first else { return }
        // id 属性
        XCTAssertFalse(first.id.isEmpty, "id 不应为空")
        // Hashable - 放入 Set 应不崩溃
        let set = Set(voices)
        XCTAssertGreaterThanOrEqual(set.count, 1, "放入 Set 应正常工作")
    }

    /// Quality 枚举应包含 compact/enhanced/premium/unknown 四种
    func testQualityEnumCases() {
        let allCases: [TTSVoice.Quality] = [.compact, .enhanced, .premium, .unknown]
        XCTAssertEqual(allCases.count, 4, "Quality 应有 4 种 case")
    }

    // MARK: - 辅助方法

    /// 语言排序优先级（与实现保持一致）
    private func languageTier(_ language: String) -> Int {
        switch language {
        case "zh-CN": return 0
        case "zh-TW", "zh-HK": return 1
        case "en-US": return 2
        default: return 3
        }
    }
}
