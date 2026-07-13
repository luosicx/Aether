import XCTest
import SwiftData
@testable import Aether

/// Task 26: AI 人设单元测试
/// 验证 UserPreference 人设字段、ChatViewModel.buildEffectiveSystemPrompt 人设注入
@MainActor
final class AIPersonaTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - UserPreference 人设字段验证

    /// 验证 UserPreference 默认人设字段为空
    func testUserPreferenceDefaultPersonaFields() {
        let pref = UserPreference()
        XCTAssertEqual(pref.aiPersona, "", "默认 aiPersona 应为空字符串")
        XCTAssertEqual(pref.aiPersonaDescription, "", "默认 aiPersonaDescription 应为空字符串")
        XCTAssertNil(pref.avatarData, "默认 avatarData 应为 nil")
    }

    /// 验证 UserPreference 人设字段可赋值
    func testUserPreferenceSetPersonaFields() {
        let pref = UserPreference()
        pref.aiPersona = "小以太"
        pref.aiPersonaDescription = "温和耐心，善于鼓励"
        pref.avatarData = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(pref.aiPersona, "小以太")
        XCTAssertEqual(pref.aiPersonaDescription, "温和耐心，善于鼓励")
        XCTAssertEqual(pref.avatarData, Data([0x89, 0x50, 0x4E, 0x47]))
    }

    /// 验证 UserPreference 初始化时可传入人设参数
    func testUserPreferenceInitWithPersona() {
        let avatarData = Data([0x01, 0x02])
        let pref = UserPreference(
            aiPersona: "以太",
            aiPersonaDescription: "冷静理性",
            avatarData: avatarData
        )
        XCTAssertEqual(pref.aiPersona, "以太")
        XCTAssertEqual(pref.aiPersonaDescription, "冷静理性")
        XCTAssertEqual(pref.avatarData, avatarData)
    }

    /// 验证 ChatStorage.fetchPreference 返回持久化的 UserPreference
    func testChatStoragePersistsPersona() {
        let storage = ChatStorage(modelContext: context)
        let pref = storage.fetchPreference()
        pref.aiPersona = "测试人设"
        pref.aiPersonaDescription = "测试描述"
        try? context.save()

        // 重新读取验证持久化
        let storage2 = ChatStorage(modelContext: context)
        let pref2 = storage2.fetchPreference()
        XCTAssertEqual(pref2.aiPersona, "测试人设")
        XCTAssertEqual(pref2.aiPersonaDescription, "测试描述")
    }

    // MARK: - buildEffectiveSystemPrompt 人设注入验证

    /// 验证空人设时 systemPrompt 不追加人设信息
    func testBuildSystemPromptWithoutPersona() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertEqual(result, "你是助手", "空人设时 systemPrompt 应保持不变")
    }

    /// 验证仅设置人设名称时注入名称
    func testBuildSystemPromptWithPersonaNameOnly() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.aiPersona = "小以太"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【AI人设】"), "应包含【AI人设】标记")
        XCTAssertTrue(result.contains("小以太"), "应包含人设名称")
        XCTAssertTrue(result.contains("名称：小以太"), "应包含名称字段")
    }

    /// 验证仅设置性格描述时注入描述
    func testBuildSystemPromptWithDescriptionOnly() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.aiPersonaDescription = "温和耐心"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【AI人设】"), "应包含【AI人设】标记")
        XCTAssertTrue(result.contains("温和耐心"), "应包含性格描述")
        XCTAssertTrue(result.contains("性格描述：温和耐心"), "应包含性格描述字段")
    }

    /// 验证同时设置名称和描述时两者都注入
    func testBuildSystemPromptWithFullPersona() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.aiPersona = "以太"
        pref.aiPersonaDescription = "冷静理性，回答简洁"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("名称：以太"), "应包含名称")
        XCTAssertTrue(result.contains("性格描述：冷静理性，回答简洁"), "应包含性格描述")
    }

    /// 验证人设信息追加在 base 之后
    func testBuildSystemPromptPersonaAfterBase() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.aiPersona = "小以太"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        let baseRange = result.range(of: "你是助手")
        let personaRange = result.range(of: "【AI人设】")
        XCTAssertNotNil(baseRange)
        XCTAssertNotNil(personaRange)
        // 人设应在 base 之后
        XCTAssertTrue(baseRange!.lowerBound < personaRange!.lowerBound, "人设信息应追加在 base 之后")
    }

    /// 验证人设与用户偏好共存
    func testBuildSystemPromptPersonaWithUserPreference() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.preferredTone = "正式"
        pref.customFact = "我是素食者"
        pref.aiPersona = "小以太"
        pref.aiPersonaDescription = "温和耐心"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"), "应包含用户偏好")
        XCTAssertTrue(result.contains("【AI人设】"), "应包含AI人设")
        XCTAssertTrue(result.contains("正式"), "应包含语气")
        XCTAssertTrue(result.contains("素食者"), "应包含自定义事实")
        XCTAssertTrue(result.contains("小以太"), "应包含人设名称")
    }

    /// 验证空 base 时仅输出人设信息
    func testBuildSystemPromptEmptyBaseWithPersona() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.aiPersona = "以太"
        let result = vm.buildEffectiveSystemPrompt(base: "", preference: pref)
        XCTAssertTrue(result.contains("【AI人设】"), "空 base 也应包含人设")
        XCTAssertFalse(result.hasPrefix("\n"), "结果不应以换行开头")
    }
}
