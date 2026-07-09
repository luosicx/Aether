import SwiftUI

/// 字体 token：统一字体样式
extension Font {
    /// AI 对话正文（.body）
    static let bodyAI = Font.body
    /// AI 副标题（.subheadline）
    static let subheadlineAI = Font.subheadline
    /// AI 注释（.caption2）
    static let captionAI = Font.caption2
    /// AI 标题（.headline）
    static let headlineAI = Font.headline
    /// AI 大标题（.title2）
    static let titleAI = Font.title2
    /// 空状态大标题（.system size: 34 light）
    static let emptyStateTitle = Font.system(size: 34, weight: .light)
    /// 等宽字体（工具消息 / 代码）
    static let monoAI = Font.callout.monospaced()
    /// 工具标签（caption2 medium）
    static let toolLabel = Font.caption2.weight(.medium)
}
