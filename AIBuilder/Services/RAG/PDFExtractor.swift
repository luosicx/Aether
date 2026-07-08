import Foundation
import PDFKit

/// PDF 文本提取工具（无实例，纯静态方法）
enum PDFExtractor {
    /// 提取 PDF 全文。失败返回 nil 的两种情形：
    /// 1) PDFDocument(url:) 初始化失败（文件损坏或非 PDF）；
    /// 2) document.string 为空或 nil（PDF 无文本层，如扫描件）。
    static func extractText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        return document.string?.isEmpty == false ? document.string : nil
    }
}
