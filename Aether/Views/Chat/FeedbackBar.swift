import SwiftUI

/// Day 12: 用户反馈条（👍 / 👎）。仅用于 assistant 消息气泡下方。
/// 已记录的反馈状态由父视图传入 isPositive（nil 表示未反馈）；点击后回调 onFeedback。
struct FeedbackBar: View {
    /// 当前已记录的反馈状态（nil=未反馈 / true=赞 / false=踩）
    let isPositive: Bool?
    /// 点击反馈按钮的回调，参数为新选择的反馈值
    let onFeedback: (Bool) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                onFeedback(true)
            } label: {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.callout)
                    .foregroundStyle(isPositive == true ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("赞")
            .accessibilityHint("标记此回复为有帮助")
            .accessibilityIdentifier("thumbsUpButton")

            Button {
                onFeedback(false)
            } label: {
                Image(systemName: "hand.thumbsdown.fill")
                    .font(.callout)
                    .foregroundStyle(isPositive == false ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("踩")
            .accessibilityHint("标记此回复为无帮助")
            .accessibilityIdentifier("thumbsDownButton")
        }
    }
}
