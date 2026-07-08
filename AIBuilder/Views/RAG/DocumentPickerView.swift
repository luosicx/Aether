import SwiftUI
import UniformTypeIdentifiers

/// Day 3: 文档选择器。跨平台实现——使用 SwiftUI 原生 `.fileImporter`，
/// iOS 上呈现 `UIDocumentPickerViewController`，macOS 上呈现 `NSOpenPanel`。
struct DocumentPickerView: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPresented = true

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [
                    UTType.plainText,
                    UTType.pdf,
                    UTType("net.daringfireball.markdown") ?? UTType.plainText
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        onPick(url)
                    }
                case .failure:
                    break
                }
                dismiss()
            }
    }
}
