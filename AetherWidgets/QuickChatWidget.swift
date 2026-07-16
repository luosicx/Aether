import WidgetKit
import SwiftUI
import AppIntents

/// Task 5.3: 快速对话 Widget。
/// 支持 Small / Medium 尺寸，使用 AppIntentConfiguration 关联 AskAetherIntent。
/// 显示预设问题按钮，点击后通过 deeplink（aether://ask?query=...）打开主 App 并发送问题。
struct QuickChatWidget: Widget {
    let kind: String = "QuickChatWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: QuickChatWidgetConfigurationIntent.self,
            provider: QuickChatTimelineProvider()
        ) { entry in
            QuickChatWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(NSLocalizedString("快速对话", comment: "Widget 名称：快速对话"))
        .description(NSLocalizedString("快速向以太提问，点击即发送", comment: "Widget 描述：快速对话"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// 快速对话 Widget 的时间线条目
struct QuickChatEntry: TimelineEntry {
    let date: Date
    /// 预设问题列表
    let presets: [String]
}

/// 快速对话 Widget 的 AppIntentTimelineProvider
struct QuickChatTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = QuickChatWidgetConfigurationIntent
    typealias Entry = QuickChatEntry

    func placeholder(in context: Context) -> QuickChatEntry {
        QuickChatEntry(date: Date(), presets: QuickChatWidgetConfigurationIntent.defaultPresets)
    }

    func snapshot(for configuration: QuickChatWidgetConfigurationIntent, in context: Context) async -> QuickChatEntry {
        QuickChatEntry(date: Date(), presets: QuickChatWidgetConfigurationIntent.defaultPresets)
    }

    func timeline(for configuration: QuickChatWidgetConfigurationIntent, in context: Context) async -> Timeline<QuickChatEntry> {
        // 预设问题静态展示，无需频繁刷新；每 24 小时更新一次
        let entry = QuickChatEntry(date: Date(), presets: QuickChatWidgetConfigurationIntent.defaultPresets)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(24 * 3600)))
    }
}

/// 快速对话 Widget 的配置 Intent（让用户选择预设问题组）
struct QuickChatWidgetConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "快速对话设置"
    static var description = IntentDescription("选择快速对话的预设问题")

    /// 默认预设问题
    static let defaultPresets = [
        NSLocalizedString("你好，今天有什么建议？", comment: "Widget 预设问题 1"),
        NSLocalizedString("帮我写一首短诗", comment: "Widget 预设问题 2"),
        NSLocalizedString("总结一下今天的重点", comment: "Widget 预设问题 3"),
        NSLocalizedString("解释一下量子计算", comment: "Widget 预设问题 4")
    ]

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

/// 快速对话 Widget 视图
struct QuickChatWidgetView: View {
    let entry: QuickChatEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    /// Small 尺寸：显示第一个预设问题，点击发送
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text(NSLocalizedString("快速对话", comment: "Widget 标题"))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            Spacer()
            if let firstPreset = entry.presets.first {
                Link(destination: askURL(for: firstPreset)) {
                    Text(firstPreset)
                        .font(.caption2)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
    }

    /// Medium 尺寸：显示 2x2 网格的预设问题
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text(NSLocalizedString("快速对话", comment: "Widget 标题"))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(entry.presets.prefix(4), id: \.self) { preset in
                    Link(destination: askURL(for: preset)) {
                        Text(preset)
                            .font(.system(size: 10))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    /// 构造 deeplink URL：aether://ask?query=<encoded>
    private func askURL(for query: String) -> URL {
        var components = URLComponents()
        components.scheme = "aether"
        components.host = "ask"
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        return components.url ?? URL(string: "aether://ask")!
    }
}
