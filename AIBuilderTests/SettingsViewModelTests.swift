import XCTest
@testable import AIBuilder

/// SettingsViewModel 单元测试
/// 使用真实 Keychain（service="com.aibuilder.apikey"，account="apikey"），
/// setUp/tearDown 清理残留 key；Keychain 不可用时通过 XCTSkip 跳过对应用例
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var vm: SettingsViewModel!

    override func setUpWithError() throws {
        // 注入内存 Keychain 后端，避免依赖真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        vm = SettingsViewModel()
        // 清理可能残留的 Keychain API key
        KeychainManager.shared.deleteAPIKey()
    }

    override func tearDownWithError() throws {
        KeychainManager.shared.deleteAPIKey()
        KeychainManager.shared.backend = SystemKeychainBackend()
        vm = nil
    }

    /// 后台读取：先 saveAPIKey，再 loadAPIKeyFromKeychain，应返回相同字符串
    func testLoadAPIKeyFromKeychain() async throws {
        try KeychainManager.shared.saveAPIKey("test-key-abc")

        XCTAssertEqual(vm.apiKey, "", "加载前 apiKey 应为空字符串")
        await vm.loadAPIKeyFromKeychain()
        XCTAssertEqual(vm.apiKey, "test-key-abc",
                       "loadAPIKeyFromKeychain 后应读取已保存的 key")
    }

    /// saveAPIKey 后 saveMessage 应含「已保存」
    func testSaveAPIKeySuccessMessage() throws {
        try KeychainManager.shared.saveAPIKey("probe")

        vm.apiKey = "new-key-123"
        vm.saveAPIKey()  // 内部 do/catch，不抛出

        XCTAssertNotNil(vm.saveMessage, "saveAPIKey 后 saveMessage 应非 nil")
        XCTAssertTrue(vm.saveMessage?.contains("已保存") == true,
                       "saveMessage 应含「已保存」，实际：\(vm.saveMessage ?? "nil")")
        // 验证确实写入 Keychain
        XCTAssertEqual(KeychainManager.shared.getAPIKey(), "new-key-123")
    }

    /// deleteAPIKey 后 saveMessage 应含「已删除」
    func testDeleteAPIKeySuccessMessage() throws {
        // 先保存一个 key 再删除
        try KeychainManager.shared.saveAPIKey("will-delete")
        vm.apiKey = "will-delete"

        vm.deleteAPIKey()

        XCTAssertEqual(vm.apiKey, "", "deleteAPIKey 后 apiKey 应清空")
        XCTAssertNotNil(vm.saveMessage, "deleteAPIKey 后 saveMessage 应非 nil")
        XCTAssertTrue(vm.saveMessage?.contains("已删除") == true,
                       "saveMessage 应含「已删除」，实际：\(vm.saveMessage ?? "nil")")
        XCTAssertNil(KeychainManager.shared.getAPIKey(),
                     "Keychain 中应已删除该 key")
    }

    /// loadSystemPrompt(nil) 应使用 defaultSystemPrompt
    func testLoadSystemPromptNilUsesDefault() {
        // 预置一个非默认值以验证会被覆盖
        vm.systemPrompt = "临时非默认值"

        vm.loadSystemPrompt(from: nil)

        XCTAssertEqual(vm.systemPrompt, SettingsViewModel.defaultSystemPrompt,
                       "传 nil 应使用 defaultSystemPrompt")
    }

    /// availableModels 应为 ["deepseek-chat", "deepseek-reasoner"]
    func testAvailableModels() {
        XCTAssertEqual(vm.availableModels, ["deepseek-chat", "deepseek-reasoner"],
                       "availableModels 应等于 [deepseek-chat, deepseek-reasoner]")
    }
}
