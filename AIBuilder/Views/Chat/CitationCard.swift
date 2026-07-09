import SwiftUI

struct CitationCard: View {
    let citation: DocumentChunk
    var index: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(citation.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Spacer()
                Text("\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            Text(citation.content)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .cardStyle()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: NSLocalizedString("引用 %d，来源 %@", comment: ""), index + 1, citation.source)))
        .accessibilityHint("查看引用的文档片段")
    }
}
