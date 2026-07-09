import SwiftUI
import PhotosUI

struct ChatInputBar: View {
    @Binding var inputText: String
    let isLoading: Bool
    let isRecording: Bool
    let onSend: () -> Void
    let onPaperclip: () -> Void
    let onToggleVoice: () -> Void
    // Day 5 补充A：相册图片选择回调，把图片数据回传给 ChatViewModel
    let onImagePicked: (Data?) -> Void
    @State private var selectedItem: PhotosPickerItem?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        return HStack(spacing: 10) {
            Button { onPaperclip() } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("知识库")
            .accessibilityHint("打开知识库管理文档")
            .accessibilityIdentifier("knowledgeBaseButton")
            // Day 5 补充A：相册图片选择按钮（位于附件按钮与麦克风按钮之间）
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("选择图片")
            .accessibilityHint("从相册选择图片附加到消息")
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        onImagePicked(data)
                    }
                }
            }
            TextField("输入消息…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isFocused)
                .accessibilityLabel("消息输入框")
                .accessibilityHint("输入要发送的消息")
                .accessibilityIdentifier("messageInputField")
            Button {
                onToggleVoice()
            } label: {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.title3)
                    .foregroundStyle(isRecording ? .red : .secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isRecording ? "停止录音" : "开始录音")
            .accessibilityHint(isRecording ? "停止语音输入" : "开始语音输入")
            .accessibilityIdentifier("voiceInputButton")
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.accentColor : Color(.systemGray3))
                    .clipShape(Circle())
            }
            .contentShape(Circle().inset(by: -4))
            .disabled(!canSend)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: canSend)
            .accessibilityLabel("发送")
            .accessibilityHint("发送消息")
            .accessibilityIdentifier("sendButton")
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: .command)
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Day 19: iPad 适配——输入内容限宽 600 居中，避免在 iPad 上拉伸过宽
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 0.5)
        }
    }
}
