import AVFoundation
import Foundation

/// TTS 音色目录与查询工具。
///
/// 封装 `AVSpeechSynthesisVoice` 的查询能力:将系统音色列表转换为结构化 `TTSVoice`,
/// 提供按语言分组、根据 identifier 查询可读名称、查找原始 `AVSpeechSynthesisVoice`,
/// 并预置中文常用音色 fallback 列表(用于设备无 zh-CN 增强音色时的兜底)。
///
/// 所有方法均为只读查询、无状态,可在任意线程调用。

// MARK: - TTSVoice

/// TTS 音色数据结构,封装 `AVSpeechSynthesisVoice` 的关键属性。
struct TTSVoice: Identifiable, Hashable {
    /// `AVSpeechSynthesisVoice.identifier`
    let id: String
    /// `AVSpeechSynthesisVoice.name`(如 "Tingting")
    let name: String
    /// `AVSpeechSynthesisVoice.language`(BCP 47,如 "zh-CN")
    let language: String
    /// 由 `AVSpeechSynthesisVoice.quality` 转换的质量等级
    let quality: Quality
    /// 设备是否已下载该音色
    let isDownloaded: Bool

    /// 音色质量等级
    enum Quality: String, Hashable {
        case compact
        case enhanced
        case premium
        case unknown
    }
}

// MARK: - TTSVoiceCatalog

/// TTS 音色查询目录,提供静态方法访问系统音色。
enum TTSVoiceCatalog {

    /// 获取所有可用音色,从 `AVSpeechSynthesisVoice.speechVoices()` 转换。
    /// 过滤掉 identifier 为空的项。
    /// 注:speechVoices() 返回的列表本身即为设备已安装的音色,isDownloaded 默认 true。
    static func allVoices() -> [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.identifier.isEmpty }
            .map { voice in
                TTSVoice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: TTSVoice.Quality(from: voice.quality),
                    isDownloaded: true
                )
            }
    }

    /// 按 language 分组返回音色列表。
    ///
    /// 排序规则:
    /// 1. "zh-CN" 永远第一
    /// 2. "zh-TW"、"zh-HK" 第二组(组内按字母序)
    /// 3. "en-US" 第三
    /// 4. 其他按字母序
    static func groupedByLanguage() -> [(language: String, voices: [TTSVoice])] {
        let groups = Dictionary(grouping: allVoices(), by: { $0.language })
        return groups.keys.sorted { lhs, rhs in
            let lhsTier = languageSortTier(lhs)
            let rhsTier = languageSortTier(rhs)
            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }
            return lhs < rhs
        }.map { language in
            (language: language, voices: groups[language] ?? [])
        }
    }

    /// 根据 identifier 返回可读名称(如 "Tingting(zh-CN)")。
    /// 未找到时返回 "(未知音色)"。
    static func displayName(for identifier: String) -> String {
        guard let voice = allVoices().first(where: { $0.id == identifier }) else {
            return "(未知音色)"
        }
        return "\(voice.name)(\(voice.language))"
    }

    /// 根据 identifier 查找 `AVSpeechSynthesisVoice`。
    /// 使用 `AVSpeechSynthesisVoice(identifier:)` 构造,失败返回 nil。
    static func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: identifier)
    }

    /// 预置中文常用音色 fallback 列表。
    /// 若设备无任何 zh-CN 增强音色,提供 compact Tingting 兜底。
    static let fallbackChineseVoices: [String] = [
        "com.apple.voice.compact.zh-CN.Tingting",
        "com.apple.ttsbundle.Ting-Ting.compact"
    ]
}

// MARK: - Quality 转换

private extension TTSVoice.Quality {
    /// 由 `AVSpeechSynthesisVoiceQuality` 转换。
    /// - `.default`(rawValue 1) → compact
    /// - `.enhanced`(rawValue 2) → enhanced
    /// - `.premium`(rawValue 3) → premium
    /// - 其他 → unknown
    init(from quality: AVSpeechSynthesisVoiceQuality) {
        switch quality {
        case .default:
            self = .compact
        case .enhanced:
            self = .enhanced
        case .premium:
            self = .premium
        default:
            self = .unknown
        }
    }
}

// MARK: - 排序辅助

private extension TTSVoiceCatalog {
    /// 语言排序优先级(数值越小越靠前)。
    /// - zh-CN: 0
    /// - zh-TW / zh-HK: 1
    /// - en-US: 2
    /// - 其他: 3(组内再按字母序)
    static func languageSortTier(_ language: String) -> Int {
        switch language {
        case "zh-CN":
            return 0
        case "zh-TW", "zh-HK":
            return 1
        case "en-US":
            return 2
        default:
            return 3
        }
    }
}
