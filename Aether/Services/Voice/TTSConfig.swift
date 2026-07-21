import Foundation
import os

/// TTS 朗读音色配置持久化结构体。
/// 存储用户选择的 AVSpeechSynthesisVoice 标识以及 rate / pitch / volume 参数,
/// 通过 UserDefaults 以 JSON 形式持久化。
struct TTSConfig: Codable, Equatable {
    /// AVSpeechSynthesisVoice.identifier() 值,空字符串表示系统默认 zh-CN
    var voiceIdentifier: String
    /// 语速,范围 0...1,默认 0.5
    var rate: Double
    /// 音调倍数,范围 0.5...2.0,默认 1.0
    var pitchMultiplier: Double
    /// 音量,范围 0...1,默认 1.0
    var volume: Float

    // MARK: - 默认值

    /// 默认配置:voiceIdentifier=""(系统默认 zh-CN)、rate=0.5、pitchMultiplier=1.0、volume=1.0
    static let defaultValue = TTSConfig(
        voiceIdentifier: "",
        rate: 0.5,
        pitchMultiplier: 1.0,
        volume: 1.0
    )

    // MARK: - UserDefaults 持久化

    /// UserDefaults 存储键
    static let userDefaultsKey = "ttsConfig"

    /// 从 UserDefaults 读取 JSON 数据并解码为 TTSConfig。
    /// 任何失败(无数据 / 解码失败)一律回退 `defaultValue`,不抛错。
    static func load() -> TTSConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return defaultValue
        }
        do {
            return try JSONDecoder().decode(TTSConfig.self, from: data)
        } catch {
            return defaultValue
        }
    }

    /// JSON 编码后写入 UserDefaults
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: TTSConfig.userDefaultsKey)
        } catch {
            // 编码失败:静默忽略,保留旧数据
            Logger.app.error("TTS 配置保存失败 (编码失败，旧配置保留): \(error.localizedDescription, privacy: .public)")
        }
    }
}
