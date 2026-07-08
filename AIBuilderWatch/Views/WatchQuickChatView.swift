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
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 快速回复按钮
                    HStack {
                        Button("你好") { sendQuickChat("你好") }
                        Button("今天天气") { sendQuickChat("今天天气怎么样？") }
                    }
                    .font(.caption)

                    Button("发送") {
                        sendQuickChat(inputText)
                        inputText = ""
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("快速对话")
        }
    }

    /// 通过 WCSession 发送快速对话消息到 iOS 端
    private func sendQuickChat(_ message: String) {
        guard WCSession.default.activationState == .activated else {
            statusMessage = "未连接 iPhone"
            return
        }
        WCSession.default.sendMessage(["action": "quickChat", "message": message], replyHandler: nil)
        messages.append("我：\(message)")
        statusMessage = "已发送"
    }
}
#endif
