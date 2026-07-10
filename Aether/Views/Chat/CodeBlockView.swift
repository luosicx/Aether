import SwiftUI

/// 代码块视图：深浅色双主题 / 语法高亮 / 等宽字体 / 圆角 / 横向滚动
struct CodeBlockView: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme

    /// 缓存语法高亮结果的包装类（NSCache value 要求 NSObject 子类，AttributedString 不是 NSObject）
    private final class CachedHighlight: NSObject {
        let attributed: AttributedString
        init(attributed: AttributedString) {
            self.attributed = attributed
            super.init()
        }
    }

    /// 模块级语法高亮缓存：避免 body 重算时重复执行正则匹配导致主线程卡顿。
    /// key 由 `code + language + theme` 组合，确保不同代码/语言/主题互不干扰。
    private static let highlightCache: NSCache<NSString, CachedHighlight> = {
        let cache = NSCache<NSString, CachedHighlight>()
        cache.countLimit = 100  // 代码块缓存数量比 markdown 少
        return cache
    }()

    /// 当前主题（跟随系统深浅色）
    private var theme: SyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }

    /// 代码块背景（跟随系统深浅色）
    private var background: Color {
        colorScheme == .dark ? Color.codeBackgroundDark : Color.codeBackgroundLight
    }

    /// 语法高亮后的属性字符串（命中缓存则直接返回，未命中则计算并写入缓存）
    private var highlightedText: AttributedString {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(trimmedCode)\u{1F}\(language ?? "")\u{1F}\(theme)" as NSString
        if let cached = CodeBlockView.highlightCache.object(forKey: cacheKey) {
            return cached.attributed
        }
        let attributed = CodeSyntaxHighlighter.highlight(
            trimmedCode,
            language: language,
            theme: theme
        )
        CodeBlockView.highlightCache.setObject(CachedHighlight(attributed: attributed), forKey: cacheKey)
        return attributed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 语言标签栏（有语言时显示）
            if let language, !language.isEmpty {
                HStack {
                    Text(language.capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 0.62, green: 0.65, blue: 0.70))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(background)
            }
            // 代码内容
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .cardStyle(background: Color.backgroundTertiary, cornerRadius: CornerRadius.medium, padding: Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(language.map { String(format: NSLocalizedString("%@ 代码块", comment: ""), $0.capitalized) } ?? NSLocalizedString("代码块", comment: "")))
        .accessibilityValue(code)
    }
}
