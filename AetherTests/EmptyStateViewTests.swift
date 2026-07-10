import XCTest
import SwiftUI
@testable import Aether

final class EmptyStateViewTests: XCTestCase {

    func testEmptyStateViewInitWithAllFields() {
        let view = EmptyStateView(
            systemImage: "doc.text",
            title: "暂无文档",
            message: "导入文档以启用 RAG",
            primaryButtonTitle: "导入",
            primaryAction: {}
        )
        XCTAssertEqual(view.title, "暂无文档")
        XCTAssertEqual(view.message, "导入文档以启用 RAG")
        XCTAssertEqual(view.primaryButtonTitle, "导入")
        XCTAssertNotNil(view.primaryAction)
    }

    func testEmptyStateViewInitWithoutAction() {
        let view = EmptyStateView(
            systemImage: "sidebar.left",
            title: "选择一个分类",
            message: "从左侧选择"
        )
        XCTAssertNil(view.primaryButtonTitle)
        XCTAssertNil(view.primaryAction)
    }
}
