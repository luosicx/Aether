import XCTest
@testable import Aether

/// Day 12: SmartRouter 智能路由单元测试
final class SmartRouterTests: XCTestCase {

    func testShortSimpleTextReturnsChat() {
        // 短文本无关键词 → deepseek-chat
        let result = SmartRouter.route(input: "你好", toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-chat")
    }

    func testLongTextReturnsReasoner() {
        // >= 50 字符 → deepseek-reasoner
        let longText = String(repeating: "啊", count: 50)
        XCTAssertEqual(longText.count, 50)
        let result = SmartRouter.route(input: longText, toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-reasoner")
    }

    func testKeywordTriggerReturnsReasoner() {
        // 含关键词 → deepseek-reasoner
        let result = SmartRouter.route(input: "为什么天空是蓝色的", toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-reasoner")
    }

    func testToolsEnabledReturnsChat() {
        // toolsEnabled=true → deepseek-chat
        let result = SmartRouter.route(input: "为什么...", toolsEnabled: true, hasImage: false)
        XCTAssertEqual(result, "deepseek-chat")
    }

    func testHasImageReturnsChat() {
        // hasImage=true → deepseek-chat（即使含关键词）
        let result = SmartRouter.route(input: "为什么...", toolsEnabled: false, hasImage: true)
        XCTAssertEqual(result, "deepseek-chat")
    }

    func testToolsAndImagePriority() {
        // toolsEnabled + hasImage + 关键词 + 长文本 → 优先 deepseek-chat
        let longText = String(repeating: "啊", count: 100) + "为什么"
        let result = SmartRouter.route(input: longText, toolsEnabled: true, hasImage: true)
        XCTAssertEqual(result, "deepseek-chat")
    }
}
