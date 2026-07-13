#if os(watchOS)
import SwiftUI
import WatchConnectivity

/// Day 17: watchOS 快速对话页。提供快速回复按钮与文字输入，通过 WCSession 发送到 iOS 端。
///
/// - Note: 此文件仅在 watchOS target 中编译。
struct WatchQuickChatView: View {
    /// 用户输入的快速对话文本
    @State private var inputText: String = ""
    /// 最近发送的消息列表（本地缓存，不持久化）
    @State private var messages: [String] = []
    /// 发送状态提示
    @State private var statusMessage: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // 最近消息列表
                    ForEach(messages.indices, id: \.self) { index in
                        Text(messages[index])
                            .font(.caption2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                            .accessibilityLabel("已发送消息")
                            .accessibilityValue(messages[index])
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("发送状态")
                            .accessibilityValue(statusMessage)
                    }

                    // 快速回复按钮
                    HStack {
                        Button(NSLocalizedString("你好", comment: "Watch 快速回复：你好")) { sendQuickChat(NSLocalizedString("你好", comment: "Watch 快速回复：你好")) }
                            .accessibilityLabel("快速回复：你好")
                            .accessibilityHint("发送「你好」到 iPhone")
                        Button(NSLocalizedString("今天天气", comment: "Watch 快速回复按钮")) { sendQuickChat(NSLocalizedString("今天天气怎么样？", comment: "Watch 快速回复：今天天气怎么样")) }
                            .accessibilityLabel("快速回复：今天天气")
                            .accessibilityHint("发送「今天天气怎么样？」到 iPhone")
                    }
                    .font(.caption)

                    Button(NSLocalizedString("发送", comment: "Watch 发送按钮")) {
                        sendQuickChat(inputText)
                        inputText = ""
                    }
                    .disabled(inputText.isEmpty)
                    .accessibilityLabel("发送")
                    .accessibilityHint("发送输入的文本到 iPhone")
                    .accessibilityIdentifier("watchSendButton")
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(NSLocalizedString("快速对话", comment: "Watch 导航标题：快速对话"))
            .accessibilityIdentifier("watchQuickChatView")
        }
    }

    /// 通过 WCSession 发送快速对话消息到 iOS 端。
    /// 优先用 sendMessage（实时），不可达时回退到 transferUserInfo（后台可靠投递）。
    private func sendQuickChat(_ message: String) {
        guard WCSession.default.activationState == .activated else {
            statusMessage = NSLocalizedString("未连接 iPhone", comment: "Watch 未连接 iPhone 提示")
            return
        }
        let payload: [String: Any] = ["action": "quickChat", "message": message]
        if WCSession.default.isReachable {
            // iOS 端可达时实时发送
            WCSession.default.sendMessage(payload, replyHandler: nil)
        } else {
            // 不可达时通过 transferUserInfo 后台投递，iOS 端会在下次启动/唤醒时收到
            WCSession.default.transferUserInfo(payload)
        }
        messages.append(String(format: NSLocalizedString("我：%@", comment: "Watch 已发送消息前缀"), message))
        statusMessage = NSLocalizedString("已发送", comment: "Watch 已发送状态")
    }
}
#endif
