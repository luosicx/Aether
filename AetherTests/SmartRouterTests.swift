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

    // MARK: - 边缘测试补充

    // 边界条件：长度刚好 49（< 50）且无关键词 → deepseek-chat
    func testBoundaryLength49ReturnsChat() {
        // 49 字符低于 50 阈值，不应触发 reasoner
        let text49 = String(repeating: "啊", count: 49)
        XCTAssertEqual(text49.count, 49)
        let result = SmartRouter.route(input: text49, toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-chat", "长度 49 不足 50 阈值应返回 chat")
    }

    // 英文关键词触发：verify 英文关键词 "explain" 走 reasoner 分支
    func testEnglishKeywordTriggersReasoner() {
        let result = SmartRouter.route(input: "please explain this code", toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-reasoner", "英文关键词 explain 应触发 reasoner")
    }

    // 大小写不敏感：大写关键词经 lowercased() 后仍匹配
    func testKeywordCaseInsensitive() {
        let result = SmartRouter.route(input: "WHY does this happen", toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-reasoner", "大写 WHY 经 lowercased 后应匹配 why 关键词")
    }

    // 空输入边界：空字符串无关键词且长度 < 50 → deepseek-chat
    func testEmptyInputReturnsChat() {
        let result = SmartRouter.route(input: "", toolsEnabled: false, hasImage: false)
        XCTAssertEqual(result, "deepseek-chat", "空输入应返回默认 chat 模型")
    }

    // 降级优先级：hasImage=true 覆盖长文本，强制 deepseek-chat
    func testHasImageOverridesLongText() {
        // 长文本本应走 reasoner，但有图片时强制 chat
        let longText = String(repeating: "啊", count: 80)
        let result = SmartRouter.route(input: longText, toolsEnabled: false, hasImage: true)
        XCTAssertEqual(result, "deepseek-chat", "hasImage 应覆盖长文本分支强制 chat")
    }
}
