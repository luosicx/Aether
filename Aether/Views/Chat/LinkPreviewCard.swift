import SwiftUI
import AetherDesign

/// Task 22: 链接预览卡片——从 URL 异步加载 OpenGraph 元数据并卡片式展示。
/// 加载标题、摘要、缩略图，使用 AsyncImage 加载缩略图。
struct LinkPreviewCard: View {
    /// 待预览的 URL
    let url: URL

    /// 预览数据
    @State private var preview: LinkPreview?
    /// 加载状态
    @State private var isLoading = false
    /// 加载错误信息
    @State private var errorMessage: String?
    /// 当前 fetch Task 句柄，用于管理竞态条件
    @State private var fetchTask: Task<Void, Never>?

    /// 链接预览数据结构
    struct LinkPreview {
        /// 页面标题
        var title: String
        /// 页面摘要描述
        var description: String
        /// 缩略图 URL
        var thumbnailURL: URL?
    }

    var body: some View {
        cardContent
            .task {
                await fetchPreview()
            }
            .onDisappear {
                fetchTask?.cancel()
            }
    }

    /// 卡片内容：根据加载状态展示不同视图
    @ViewBuilder
    private var cardContent: some View {
        if let preview = preview {
            // 已加载——展示完整预览卡片
            Link(destination: url) {
                HStack(spacing: Spacing.md) {
                    // 缩略图
                    if let thumbnailURL = preview.thumbnailURL {
                        AsyncImage(url: thumbnailURL) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: CornerRadius.small)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                    .overlay {
                                        ProgressView()
                                    }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                            case .failure:
                                RoundedRectangle(cornerRadius: CornerRadius.small)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    // 文本内容
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(preview.title)
                            .font(.bodyAI.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        if !preview.description.isEmpty {
                            Text(preview.description)
                                .font(.captionAI)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        // 域名显示
                        Text(url.host ?? url.absoluteString)
                            .font(.captionAI)
                            .foregroundStyle(Color.electricBlue)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(Color.bubbleAI.opacity(0.5))
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .stroke(Color.electricBlue.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
        } else if isLoading {
            // 加载中——骨架占位
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .overlay { ProgressView() }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 120, height: 10)
                }
                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(Color.secondary.opacity(0.05))
            )
        } else if let error = errorMessage {
            // 加载失败——展示错误与域名
            Link(destination: url) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "link")
                        .foregroundStyle(Color.electricBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.host ?? url.absoluteString)
                            .font(.bodyAI)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(error)
                            .font(.captionAI)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(Color.bubbleAI.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// 从 URL 异步加载 OpenGraph 元数据。
    /// 抓取 HTML 并解析 og:title / og:description / og:image 标签。
    /// 使用 Task 句柄管理竞态条件，避免重复请求。
    func fetchPreview() async {
        // 取消之前的 fetch 任务，防止竞态
        fetchTask?.cancel()
        guard !isLoading, preview == nil else { return }
        isLoading = true
        let task = Task { @MainActor [url] in
            defer { isLoading = false }

            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            // 模拟浏览器 User-Agent，部分网站需要
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                // 检查 HTTP 状态码
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    errorMessage = "无法加载预览（HTTP \(httpResponse.statusCode)）"
                    return
                }
                guard let html = String(data: data, encoding: .utf8) else {
                    errorMessage = "无法解析页面内容"
                    return
                }
                let parsed = parseOpenGraph(from: html, baseURL: url)
                preview = parsed
            } catch {
                if !Task.isCancelled {
                    errorMessage = "加载失败：\(error.localizedDescription)"
                }
            }
        }
        fetchTask = task
        await task.value
    }

    /// 从 HTML 中解析 OpenGraph 元数据。
    /// 提取 og:title / og:description / og:image 标签内容。
    /// - Parameters:
    ///   - html: HTML 文本
    ///   - baseURL: 基础 URL，用于将相对图片路径转换为绝对路径
    /// - Returns: 解析出的 LinkPreview
    private func parseOpenGraph(from html: String, baseURL: URL) -> LinkPreview {
        // 优先使用 og: 标签，回退到 <title> / <meta name="description">
        let title = extractMetaContent(html: html, property: "og:title")
            ?? extractMetaContent(html: html, property: "og:title", useName: true)
            ?? extractTitleTag(from: html)
            ?? baseURL.host ?? baseURL.absoluteString

        let description = extractMetaContent(html: html, property: "og:description")
            ?? extractMetaContent(html: html, property: "og:description", useName: true)
            ?? extractMetaContent(html: html, property: "description", useName: true)
            ?? ""

        let imageString = extractMetaContent(html: html, property: "og:image")
        var thumbnailURL: URL? = nil
        if let imageString = imageString {
            // 处理相对路径
            if let url = URL(string: imageString, relativeTo: baseURL) {
                thumbnailURL = url.absoluteURL
            } else if let url = URL(string: imageString) {
                thumbnailURL = url
            }
        }

        return LinkPreview(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            thumbnailURL: thumbnailURL
        )
    }

    /// 从 HTML 中提取 <meta property="..."> 或 <meta name="..."> 的 content 值
    /// - Parameters:
    ///   - html: HTML 文本
    ///   - property: 属性值（如 "og:title"）
    ///   - useName: 是否使用 name 属性而非 property 属性
    /// - Returns: content 值，未找到返回 nil
    private func extractMetaContent(html: String, property: String, useName: Bool = false) -> String? {
        let attrKey = useName ? "name" : "property"
        // 构造正则：匹配 <meta ... property="og:title" ... content="..." 或反向顺序
        let pattern = #"<meta[^>]*\#(attrKey)\s*=\s*["']\#(property)["'][^>]*content\s*=\s*["']([^"']*)["'][^>]*>"#
        let reversePattern = #"<meta[^>]*content\s*=\s*["']([^"']*)["'][^>]*\#(attrKey)\s*=\s*["']\#(property)["'][^>]*>"#

        if let match = firstMatch(pattern: pattern, in: html) {
            return match
        }
        if let match = firstMatch(pattern: reversePattern, in: html) {
            return match
        }
        return nil
    }

    /// 执行正则匹配，返回第一个捕获组
    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange])
        }
        return nil
    }

    /// 从 HTML 中提取 <title>...</title> 标签内容
    private func extractTitleTag(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        if let match = regex.firstMatch(in: html, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: html) {
            return String(html[captureRange])
        }
        return nil
    }
}
