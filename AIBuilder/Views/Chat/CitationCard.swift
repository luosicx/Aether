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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("引用 \(index + 1)，来源 \(citation.source)")
        .accessibilityHint("查看引用的文档片段")
    }
}
