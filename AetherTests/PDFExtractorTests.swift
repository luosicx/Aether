import XCTest
import PDFKit
#if os(iOS)
import UIKit
#endif
@testable import Aether

/// Day 11: PDFExtractor 单元测试
final class PDFExtractorTests: XCTestCase {

    private var tempPDFURL: URL!
    private let fixtureText = "Aether test PDF content for extraction. This is a unit test fixture."

    override func setUp() async throws {
        try await super.setUp()
        tempPDFURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AetherTest_\(UUID().uuidString).pdf")
        try await generateTestPDF()
    }

    override func tearDown() {
        if let url = tempPDFURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempPDFURL = nil
        super.tearDown()
    }

    // MARK: - 用例

    func testInvalidURLReturnsNil() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/file.pdf")
        XCTAssertNil(PDFExtractor.extractText(from: url), "不存在的文件 URL 应返回 nil")
    }

    func testEmptyStringReturnsNil() {
        let url = URL(fileURLWithPath: "")
        XCTAssertNil(PDFExtractor.extractText(from: url), "空字符串路径应返回 nil")
    }

    func testFixturePDFExtraction() {
        let text = PDFExtractor.extractText(from: tempPDFURL)
        XCTAssertNotNil(text, "有效 PDF 应返回非 nil 文本")
        XCTAssertFalse(text?.isEmpty ?? true, "提取的文本不应为空")
        XCTAssertTrue(text?.contains("Aether") ?? false, "提取的文本应含原文关键字 Aether")
    }

    // MARK: - 辅助：动态生成临时 PDF

    private func generateTestPDF() async throws {
        #if os(iOS)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            context.beginPage()
            let rect = CGRect(x: 50, y: 50, width: 500, height: 700)
            fixtureText.draw(
                in: rect,
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)]
            )
        }
        try data.write(to: tempPDFURL)
        #else
        // macOS: NSTextView 等 AppKit UI 必须在主线程操作，避免
        // "NSWindow should only be instantiated on the main thread!" 崩溃
        let data: Data = try await MainActor.run {
            let pageRect = NSRect(x: 0, y: 0, width: 612, height: 792)
            let textView = NSTextView(frame: pageRect)
            textView.string = fixtureText
            textView.font = NSFont.systemFont(ofSize: 14)
            return textView.dataWithPDF(inside: textView.bounds)
        }
        try data.write(to: tempPDFURL)
        #endif
    }
}
