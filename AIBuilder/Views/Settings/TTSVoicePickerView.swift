import SwiftUI

/// TTS 音色选择页:按语言分组展示系统可用音色,选中后回写 ttsConfig 并持久化。
struct TTSVoicePickerView: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var chatViewModel: ChatViewModel

    /// 按语言分组的音色列表(在 onAppear 中加载,避免每次 body 重算都触发查询)。
    @State private var groupedVoices: [(language: String, voices: [TTSVoice])] = []

    var body: some View {
        List {
            // 系统默认选项(空 identifier,使用 zh-CN 默认音色)
            Section {
                voiceRow(
                    identifier: "",
                    name: "系统默认",
                    language: "zh-CN",
                    quality: .compact,
                    isDownloaded: true
                )
            } header: {
                Text("默认")
            }

            // 按 language 分组的系统音色
            ForEach(groupedVoices, id: \.language) { group in
                Section {
                    ForEach(group.voices) { voice in
                        voiceRow(
                            identifier: voice.id,
                            name: voice.name,
                            language: voice.language,
                            quality: voice.quality,
                            isDownloaded: voice.isDownloaded
                        )
                    }
                } header: {
                    Text(languageDisplay(group.language))
                }
            }
        }
        .navigationTitle("音色")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            groupedVoices = TTSVoiceCatalog.groupedByLanguage()
        }
    }

    // MARK: - 行视图

    /// 单个音色行:名称 + 质量标签 + 下载状态 + 选中 checkmark
    private func voiceRow(
        identifier: String,
        name: String,
        language: String,
        quality: TTSVoice.Quality,
        isDownloaded: Bool
    ) -> some View {
        let isSelected = settingsVM.ttsConfig.voiceIdentifier == identifier
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.bodyAI)
                    qualityTag(quality)
                    if !isDownloaded && !identifier.isEmpty {
                        Text("需下载")
                            .font(.captionAI)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(languageDisplay(language))
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectVoice(identifier: identifier)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(qualityLabel(quality)) \(languageDisplay(language))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 辅助视图

    /// 质量标签
    @ViewBuilder
    private func qualityTag(_ quality: TTSVoice.Quality) -> some View {
        let (text, color) = qualityStyling(quality)
        Text(text)
            .font(.captionAI)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    /// 质量枚举转 (文本, 颜色) 元组
    private func qualityStyling(_ quality: TTSVoice.Quality) -> (String, Color) {
        switch quality {
        case .compact: return ("标准", .secondary)
        case .enhanced: return ("增强", .blue)
        case .premium: return ("优质", .purple)
        case .unknown: return ("未知", .secondary)
        }
    }

    // MARK: - 辅助方法

    /// 选中音色:更新 settingsVM.ttsConfig + chatViewModel.ttsConfig + 持久化
    private func selectVoice(identifier: String) {
        var newConfig = settingsVM.ttsConfig
        newConfig.voiceIdentifier = identifier
        settingsVM.updateTTSConfig(newConfig)
        chatViewModel.ttsConfig = newConfig
    }

    /// 语言代码转可读名称
    private func languageDisplay(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// 质量枚举转可读名称
    private func qualityLabel(_ quality: TTSVoice.Quality) -> String {
        switch quality {
        case .compact: return "标准"
        case .enhanced: return "增强"
        case .premium: return "优质"
        case .unknown: return "未知"
        }
    }
}
