import XCTest
import SwiftData
import AetherFoundation
@testable import Aether

/// P2-6 Task 8: PromptBuilder 单元测试
///
/// 验证 PromptBuilder.buildEffectiveSystemPrompt（base + 用户偏好 + AI 人设拼接）
/// 与 PromptBuilder.limitTokens（token 截断）行为与原 ChatViewModel 等价。
///
/// PromptBuilder 为纯值类型 struct，无依赖，不标注 @MainActor；
/// 测试类标注 @MainActor 以与 UserPreference（SwiftData @Model）创建保持一致（与 AIPersonaTests 同模式）。
@MainActor
final class PromptBuilderTests: XCTestCase {

    // MARK: - buildEffectiveSystemPrompt 用户偏好注入

    /// 所有偏好默认（tone="默认"）时应返回原 base，不注入「【用户偏好】」前缀
    func testBuildEffectiveSystemPromptDefaultToneReturnsBase() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.preferredTone = "默认"  // 默认值
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertEqual(result, "你是助手", "tone 为默认值时不应注入偏好")
    }

    /// preferredTone 非默认时注入「【用户偏好】语气：X」段，原 base 作为前缀保留
    func testBuildEffectiveSystemPromptPreferredTone() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.preferredTone = "正式"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"),
                       "非默认 tone 应注入「【用户偏好】」前缀")
        XCTAssertTrue(result.contains(String(format: NSLocalizedString("语气：%@", comment: ""), "正式")),
                       "注入内容应包含「语气：正式」")
        XCTAssertTrue(result.hasPrefix("你是助手"),
                       "原 systemPrompt 应作为前缀保留")
    }

    /// preferredTools 数组注入为「、」分隔的字符串
    func testBuildEffectiveSystemPromptPreferredTools() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.preferredTools = ["calculate", "weather"]
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"))
        XCTAssertTrue(result.contains("calculate"))
        XCTAssertTrue(result.contains("weather"))
        XCTAssertTrue(result.contains("、"), "偏好工具应以「、」分隔")
    }

    /// customFact 自定义事实注入
    func testBuildEffectiveSystemPromptCustomFact() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.customFact = "我是素食者"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"))
        XCTAssertTrue(result.contains("我是素食者"))
    }

    /// 三个偏好同时注入并以「；」分隔
    func testBuildEffectiveSystemPromptAllCombined() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.preferredTone = "正式"
        pref.preferredTools = ["calculate"]
        pref.customFact = "我是素食者"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"))
        XCTAssertTrue(result.contains(String(format: NSLocalizedString("语气：%@", comment: ""), "正式")))
        XCTAssertTrue(result.contains("calculate"))
        XCTAssertTrue(result.contains("我是素食者"))
        XCTAssertTrue(result.contains("；"), "多个偏好应以「；」分隔")
    }

    /// 空 base + 空 preference（所有字段默认）应返回空字符串
    func testBuildEffectiveSystemPromptEmptyBaseEmptyPreference() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        let result = builder.buildEffectiveSystemPrompt(base: "", preference: pref)
        XCTAssertEqual(result, "", "空 base + 空 preference 应返回空字符串")
    }

    /// 空 base + 默认 preference 时返回空字符串（与上一用例语义互补，验证无意外换行/前缀）
    func testBuildEffectiveSystemPromptEmptyReturnsEmpty() {
        let builder = PromptBuilder()
        let pref = UserPreference()  // 所有字段默认值
        let result = builder.buildEffectiveSystemPrompt(base: "", preference: pref)
        XCTAssertTrue(result.isEmpty, "空 base + 默认 preference 应返回空字符串")
        XCTAssertFalse(result.contains("\n"), "结果不应包含换行")
    }

    // MARK: - buildEffectiveSystemPrompt AI 人设注入

    /// 仅设置人设名称时注入「【AI人设】名称：X」
    func testBuildEffectiveSystemPromptPersonaNameOnly() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.aiPersona = "小以太"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【AI人设】"), "应包含【AI人设】标记")
        XCTAssertTrue(result.contains("小以太"), "应包含人设名称")
        XCTAssertTrue(result.contains("名称：小以太"), "应包含名称字段")
    }

    /// 仅设置性格描述时注入「【AI人设】性格描述：X」
    func testBuildEffectiveSystemPromptPersonaDescriptionOnly() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.aiPersonaDescription = "温和耐心"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【AI人设】"), "应包含【AI人设】标记")
        XCTAssertTrue(result.contains("温和耐心"), "应包含性格描述")
        XCTAssertTrue(result.contains("性格描述：温和耐心"), "应包含性格描述字段")
    }

    /// 同时设置名称和描述时两者都注入
    func testBuildEffectiveSystemPromptFullPersona() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.aiPersona = "以太"
        pref.aiPersonaDescription = "冷静理性，回答简洁"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("名称：以太"), "应包含名称")
        XCTAssertTrue(result.contains("性格描述：冷静理性，回答简洁"), "应包含性格描述")
    }

    /// 人设信息追加在 base 之后（顺序断言）
    func testBuildEffectiveSystemPromptPersonaAfterBase() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.aiPersona = "小以太"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        let baseRange = result.range(of: "你是助手")
        let personaRange = result.range(of: "【AI人设】")
        XCTAssertNotNil(baseRange)
        XCTAssertNotNil(personaRange)
        XCTAssertTrue(baseRange!.lowerBound < personaRange!.lowerBound,
                       "人设信息应追加在 base 之后")
    }

    /// 人设与用户偏好共存：两者都注入，base 在最前
    func testBuildEffectiveSystemPromptPersonaWithUserPreference() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.preferredTone = "正式"
        pref.customFact = "我是素食者"
        pref.aiPersona = "小以太"
        pref.aiPersonaDescription = "温和耐心"
        let result = builder.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"), "应包含用户偏好")
        XCTAssertTrue(result.contains("【AI人设】"), "应包含AI人设")
        XCTAssertTrue(result.contains("正式"), "应包含语气")
        XCTAssertTrue(result.contains("素食者"), "应包含自定义事实")
        XCTAssertTrue(result.contains("小以太"), "应包含人设名称")
    }

    /// 空 base + 仅人设时不应以换行开头
    func testBuildEffectiveSystemPromptEmptyBaseWithPersona() {
        let builder = PromptBuilder()
        let pref = UserPreference()
        pref.aiPersona = "以太"
        let result = builder.buildEffectiveSystemPrompt(base: "", preference: pref)
        XCTAssertTrue(result.contains("【AI人设】"), "空 base 也应包含人设")
        XCTAssertFalse(result.hasPrefix("\n"), "结果不应以换行开头")
    }

    // MARK: - limitTokens token 截断

    /// 表驱动：从尾部累加超过 tokenLimit 时截断（保留最近的、丢弃最早的）
    /// 字符串 estimatedTokens = Int(Double(splitBySpace.count) * 1.3) + Int(Double(nonASCIICount) * 1.5)
    /// "a b" → 2 词 → Int(2.6) = 2 tokens
    func testLimitTokensTruncation() {
        let cases: [(name: String, contents: [String], limit: Int, expectedCount: Int)] = [
            ("全部 fitting", ["a b", "c d", "e f"], 100, 3),   // 2+2+2=6 ≤100，全部保留
            ("超限截断最早一条", ["a b", "c d", "e f", "g h"], 5, 2),  // 反向累加：g h(2)+e f(2)=4 ≤5；再加 c d=6>5 截断 → 保留最近 2 条
            ("空消息列表", [], 10, 0),
            ("tokenLimit=0 立即截断", ["a b"], 0, 0),           // 0+2 > 0 立即 break
            ("单条刚好等于 limit", ["a b"], 2, 1)                // 0+2 ≤2 → 保留 1 条
        ]
        let builder = PromptBuilder()
        for (name, contents, limit, expectedCount) in cases {
            let messages = contents.map {
                APIMessage(role: "user", content: $0, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
            }
            let limited = builder.limitTokens(messages, max: limit)
            XCTAssertEqual(limited.count, expectedCount,
                           "用例「\(name)」：期望保留 \(expectedCount) 条，实际 \(limited.count) 条")
        }
    }

    /// limitTokens 保留最近消息（尾部累加截断策略验证）
    func testLimitTokensKeepsMostRecentMessages() {
        let builder = PromptBuilder()
        // 每条 2 tokens（"a b" → 2 词 → 2 tokens），limit=6 应保留最近 3 条
        let messages = ["a b", "c d", "e f", "g h", "i j"].map {
            APIMessage(role: "user", content: $0, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        }
        let limited = builder.limitTokens(messages, max: 6)
        XCTAssertEqual(limited.count, 3, "limit=6 时应保留最近 3 条（每条 2 tokens）")
        XCTAssertEqual(limited.last?.content, "i j", "应保留最后一条")
        XCTAssertEqual(limited.first?.content, "e f", "应从 e f 开始保留")
    }

    /// limitTokens 单条消息超过 limit 时应返回空数组
    func testLimitTokensSingleMessageExceedsLimit() {
        let builder = PromptBuilder()
        // "a b c d e" → 5 词 → Int(6.5) = 6 tokens > 1
        let messages = [APIMessage(role: "user", content: "a b c d e",
                                   images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let limited = builder.limitTokens(messages, max: 1)
        XCTAssertTrue(limited.isEmpty, "单条消息超过 limit 时应返回空数组")
    }
}
