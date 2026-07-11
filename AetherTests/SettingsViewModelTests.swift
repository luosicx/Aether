import XCTest
import SwiftData
@testable import Aether

/// SettingsViewModel 单元测试
/// 使用真实 Keychain（service="com.aether.apikey"，account="apikey"），
/// setUp/tearDown 清理残留 key；Keychain 不可用时通过 XCTSkip 跳过对应用例
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var vm: SettingsViewModel!
    /// 测试中可能写入的 UserDefaults 键，tearDown 统一清理避免污染
    private let userDefaultsKeysToClean = [
        BFFConfig.userDefaultsKey,
        OnDeviceConfig.userDefaultsKey,
        TTSConfig.userDefaultsKey
    ]

    override func setUpWithError() throws {
        // 注入内存 Keychain 后端，避免依赖真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        vm = SettingsViewModel()
        // 清理可能残留的 Keychain API key（deepseek + qwen）
        KeychainManager.shared.deleteAPIKey(for: .deepseek)
        KeychainManager.shared.deleteAPIKey(for: .qwen)
        // 清理可能残留的 UserDefaults 缓存
        for key in userDefaultsKeysToClean {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        KeychainManager.shared.deleteAPIKey(for: .deepseek)
        KeychainManager.shared.deleteAPIKey(for: .qwen)
        for key in userDefaultsKeysToClean {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
        XCTAssertTrue(vm.saveMessage?.contains(String(format: NSLocalizedString("%@ API Key 已保存", comment: ""), ModelProvider.deepseek.displayName)) == true,
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
        XCTAssertTrue(vm.saveMessage?.contains(String(format: NSLocalizedString("%@ API Key 已删除", comment: ""), ModelProvider.deepseek.displayName)) == true,
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

    // MARK: - 多 provider API Key 保存/读取/删除

    /// loadAPIKeysFromKeychain 应并发加载 deepseek + qwen 两个 provider 的 key
    func testLoadAPIKeysFromKeychainLoadsBothProviders() async throws {
        try KeychainManager.shared.saveAPIKey("ds-multi", for: .deepseek)
        try KeychainManager.shared.saveAPIKey("qwen-multi", for: .qwen)

        XCTAssertEqual(vm.deepseekAPIKey, "", "加载前 deepseekAPIKey 应为空")
        XCTAssertEqual(vm.qwenAPIKey, "", "加载前 qwenAPIKey 应为空")

        await vm.loadAPIKeysFromKeychain()

        XCTAssertEqual(vm.deepseekAPIKey, "ds-multi", "加载后 deepseekAPIKey 应为 ds-multi")
        XCTAssertEqual(vm.qwenAPIKey, "qwen-multi", "加载后 qwenAPIKey 应为 qwen-multi")
    }

    /// loadAPIKeysFromKeychain 无 key 时应回退到空字符串
    func testLoadAPIKeysFromKeychainReturnsEmptyWhenMissing() async throws {
        await vm.loadAPIKeysFromKeychain()
        XCTAssertEqual(vm.deepseekAPIKey, "", "无 key 时 deepseekAPIKey 应为空字符串")
        XCTAssertEqual(vm.qwenAPIKey, "", "无 key 时 qwenAPIKey 应为空字符串")
    }

    /// saveAPIKey(for: .qwen) 应写入 qwen account，不影响 deepseek
    func testSaveAPIKeyForQwen() throws {
        vm.qwenAPIKey = "qwen-save-test"
        vm.saveAPIKey(for: .qwen)

        XCTAssertEqual(KeychainManager.shared.getAPIKey(for: .qwen), "qwen-save-test",
                       "saveAPIKey(for: .qwen) 后应能读回 qwen key")
        XCTAssertNil(KeychainManager.shared.getAPIKey(for: .deepseek),
                     "保存 qwen key 不应影响 deepseek account")
        XCTAssertTrue(vm.saveMessage?.contains("已保存") == true,
                       "saveAPIKey(for: .qwen) 后 saveMessage 应含「已保存」")
    }

    /// deleteAPIKey(for: .qwen) 应清空 qwenAPIKey 与 Keychain
    func testDeleteAPIKeyForQwen() throws {
        try KeychainManager.shared.saveAPIKey("qwen-to-delete", for: .qwen)
        vm.qwenAPIKey = "qwen-to-delete"

        vm.deleteAPIKey(for: .qwen)

        XCTAssertEqual(vm.qwenAPIKey, "", "deleteAPIKey(for: .qwen) 后 qwenAPIKey 应清空")
        XCTAssertNil(KeychainManager.shared.getAPIKey(for: .qwen),
                      "Keychain 中 qwen key 应已删除")
        XCTAssertTrue(vm.saveMessage?.contains("已删除") == true,
                       "deleteAPIKey(for: .qwen) 后 saveMessage 应含「已删除」")
    }

    /// apiKey 别名应等价于 deepseekAPIKey（向后兼容）
    func testApiKeyAliasMatchesDeepseek() {
        vm.apiKey = "alias-key"
        XCTAssertEqual(vm.deepseekAPIKey, "alias-key", "apiKey setter 应写入 deepseekAPIKey")
        XCTAssertEqual(vm.apiKey, "alias-key", "apiKey getter 应返回 deepseekAPIKey")
    }

    // MARK: - BFF 配置

    /// 默认 BFF 配置：enabled=false，endpoint 占位，token 空
    func testBFFConfigDefaultValues() {
        XCTAssertEqual(vm.bffConfig, BFFConfig.default, "初始 bffConfig 应等于 BFFConfig.default")
        XCTAssertFalse(vm.bffConfig.enabled, "默认 BFF enabled 应为 false")
        XCTAssertEqual(vm.bffConfig.userToken, "", "默认 userToken 应为空字符串")
        XCTAssertEqual(vm.bffConfig.chatRateLimitPerMin, 20, "默认 chatRateLimitPerMin 应为 20")
        XCTAssertEqual(vm.bffConfig.embedRateLimitPerMin, 10, "默认 embedRateLimitPerMin 应为 10")
    }

    /// saveBFFConfig + loadBFFConfig 往返应保持一致
    func testSaveAndLoadBFFConfigRoundTrip() {
        var config = vm.bffConfig
        config.enabled = true
        config.endpointURL = URL(string: "https://bff.example.com")!
        config.userToken = "test-bff-token-123"
        config.chatRateLimitPerMin = 50
        config.embedRateLimitPerMin = 30
        vm.bffConfig = config

        vm.saveBFFConfig()
        // 清空内存中的配置后重新加载
        vm.bffConfig = .default
        XCTAssertNotEqual(vm.bffConfig.enabled, true, "保存后清空应回到默认")

        vm.loadBFFConfig()

        XCTAssertEqual(vm.bffConfig.enabled, true, "loadBFFConfig 后 enabled 应为 true")
        XCTAssertEqual(vm.bffConfig.endpointURL.absoluteString, "https://bff.example.com",
                       "loadBFFConfig 后 endpointURL 应保持一致")
        XCTAssertEqual(vm.bffConfig.userToken, "test-bff-token-123",
                       "loadBFFConfig 后 userToken 应保持一致")
        XCTAssertEqual(vm.bffConfig.chatRateLimitPerMin, 50, "chatRateLimitPerMin 应保持一致")
        XCTAssertEqual(vm.bffConfig.embedRateLimitPerMin, 30, "embedRateLimitPerMin 应保持一致")
    }

    /// loadBFFConfig 无缓存数据时应回退到默认值
    func testLoadBFFConfigWithNoDataFallsBackToDefault() {
        // 确保无缓存（setUp 已清理，这里再次确认）
        UserDefaults.standard.removeObject(forKey: BFFConfig.userDefaultsKey)

        vm.bffConfig.enabled = true
        vm.bffConfig.userToken = "should-be-overwritten"

        vm.loadBFFConfig()

        XCTAssertEqual(vm.bffConfig, BFFConfig.default, "无缓存数据时应回退到 BFFConfig.default")
        XCTAssertFalse(vm.bffConfig.enabled, "无缓存时 enabled 应回到 false")
    }

    /// loadBFFConfig 损坏数据时应回退到默认值
    func testLoadBFFConfigWithCorruptDataFallsBackToDefault() {
        let corruptData = "{\"this\":\"is not a valid BFFConfig\"}".data(using: .utf8)!
        UserDefaults.standard.set(corruptData, forKey: BFFConfig.userDefaultsKey)

        vm.loadBFFConfig()

        XCTAssertEqual(vm.bffConfig, BFFConfig.default, "损坏数据时应回退到 BFFConfig.default")
    }

    // MARK: - OnDeviceConfig

    /// 默认 OnDeviceConfig：enabled=false，autoSwitchOnNetworkLoss=true，maxTokens=512
    func testOnDeviceConfigDefaultValues() {
        XCTAssertEqual(vm.onDeviceConfig, OnDeviceConfig.default, "初始 onDeviceConfig 应等于默认值")
        XCTAssertFalse(vm.onDeviceConfig.enabled, "默认 enabled 应为 false")
        XCTAssertTrue(vm.onDeviceConfig.autoSwitchOnNetworkLoss, "默认 autoSwitchOnNetworkLoss 应为 true")
        XCTAssertEqual(vm.onDeviceConfig.maxTokens, 512, "默认 maxTokens 应为 512")
        XCTAssertEqual(vm.onDeviceConfig.temperature, 0.7, accuracy: 0.001, "默认 temperature 应为 0.7")
    }

    /// saveOnDeviceConfig + loadOnDeviceConfig 往返应保持一致
    func testSaveAndLoadOnDeviceConfigRoundTrip() {
        var config = vm.onDeviceConfig
        config.enabled = true
        config.maxTokens = 1024
        config.temperature = 0.5
        config.modelName = "Qwen2-0.5B"
        vm.onDeviceConfig = config

        vm.saveOnDeviceConfig()
        vm.onDeviceConfig = .default
        XCTAssertFalse(vm.onDeviceConfig.enabled, "保存后清空应回到默认")

        vm.loadOnDeviceConfig()

        XCTAssertTrue(vm.onDeviceConfig.enabled, "loadOnDeviceConfig 后 enabled 应为 true")
        XCTAssertEqual(vm.onDeviceConfig.maxTokens, 1024, "maxTokens 应保持一致")
        XCTAssertEqual(vm.onDeviceConfig.temperature, 0.5, accuracy: 0.001, "temperature 应保持一致")
        XCTAssertEqual(vm.onDeviceConfig.modelName, "Qwen2-0.5B", "modelName 应保持一致")
    }

    /// loadOnDeviceConfig 无缓存数据时应回退到默认值
    func testLoadOnDeviceConfigWithNoDataFallsBackToDefault() {
        UserDefaults.standard.removeObject(forKey: OnDeviceConfig.userDefaultsKey)
        vm.onDeviceConfig.enabled = true
        vm.onDeviceConfig.maxTokens = 9999

        vm.loadOnDeviceConfig()

        XCTAssertEqual(vm.onDeviceConfig, OnDeviceConfig.default, "无缓存时应回退到默认值")
    }

    /// loadOnDeviceConfig 损坏数据时应回退到默认值
    func testLoadOnDeviceConfigWithCorruptDataFallsBackToDefault() {
        let corruptData = "not json".data(using: .utf8)!
        UserDefaults.standard.set(corruptData, forKey: OnDeviceConfig.userDefaultsKey)

        vm.loadOnDeviceConfig()

        XCTAssertEqual(vm.onDeviceConfig, OnDeviceConfig.default, "损坏数据时应回退到默认值")
    }

    /// onDeviceConfig.maxTokens 边界值：0 / 负数 / 极大值均应可保存读取
    func testOnDeviceConfigMaxTokensBoundaryValues() {
        let boundaryCases: [Int] = [0, -1, 1, Int.max, 32768]
        for value in boundaryCases {
            vm.onDeviceConfig.maxTokens = value
            vm.saveOnDeviceConfig()
            vm.onDeviceConfig = .default
            vm.loadOnDeviceConfig()
            XCTAssertEqual(vm.onDeviceConfig.maxTokens, value,
                           "maxTokens=\(value) 应能完整往返保存读取")
        }
    }

    // MARK: - modelSelectionMode / enableFallback / fallbackProvider

    /// modelSelectionMode 默认应为 "auto"，切换后应保持新值
    func testModelSelectionModeDefaultAndSwitch() {
        XCTAssertEqual(vm.modelSelectionMode, "auto", "modelSelectionMode 默认应为 auto")

        vm.modelSelectionMode = "deepseek-chat"
        XCTAssertEqual(vm.modelSelectionMode, "deepseek-chat", "切换后应保持新值")

        vm.modelSelectionMode = "deepseek-reasoner"
        XCTAssertEqual(vm.modelSelectionMode, "deepseek-reasoner", "再次切换应保持新值")
    }

    /// enableFallback 默认为 false，切换后应为 true
    func testEnableFallbackToggle() {
        XCTAssertFalse(vm.enableFallback, "默认 enableFallback 应为 false")
        vm.enableFallback = true
        XCTAssertTrue(vm.enableFallback, "切换后 enableFallback 应为 true")
        vm.enableFallback = false
        XCTAssertFalse(vm.enableFallback, "再次切换应回到 false")
    }

    /// selectedProvider.fallback：deepseek↔qwen 互为备用，onDevice 备用为 deepseek
    func testSelectedProviderFallbackMapping() {
        vm.selectedProvider = .deepseek
        XCTAssertEqual(vm.selectedProvider.fallback, .qwen, "deepseek 的 fallback 应为 qwen")

        vm.selectedProvider = .qwen
        XCTAssertEqual(vm.selectedProvider.fallback, .deepseek, "qwen 的 fallback 应为 deepseek")

        vm.selectedProvider = .onDevice
        XCTAssertEqual(vm.selectedProvider.fallback, .deepseek, "onDevice 的 fallback 应为 deepseek")
    }

    /// enableFallback=true 时，selectedProvider.fallback 应返回有效备用 provider
    /// （模拟 ChatView 中 fallbackProvider = enableFallback ? selectedProvider.fallback : nil 的逻辑）
    func testFallbackProviderSetWhenEnabled() {
        // enableFallback=false 时不应有 fallback
        vm.enableFallback = false
        vm.selectedProvider = .deepseek
        let fallbackWhenDisabled: ModelProvider? = vm.enableFallback ? vm.selectedProvider.fallback : nil
        XCTAssertNil(fallbackWhenDisabled, "enableFallback=false 时 fallbackProvider 应为 nil")

        // enableFallback=true 时应有 fallback
        vm.enableFallback = true
        let fallbackWhenEnabled: ModelProvider? = vm.enableFallback ? vm.selectedProvider.fallback : nil
        XCTAssertEqual(fallbackWhenEnabled, .qwen, "enableFallback=true 且 selectedProvider=deepseek 时 fallback 应为 qwen")
    }

    // MARK: - TTS 配置

    /// updateTTSConfig 应更新本地状态并持久化到 UserDefaults
    func testUpdateTTSConfigPersists() {
        let newConfig = TTSConfig(voiceIdentifier: "test-voice", rate: 0.8, pitchMultiplier: 1.5, volume: 0.6)
        vm.updateTTSConfig(newConfig)

        XCTAssertEqual(vm.ttsConfig.voiceIdentifier, "test-voice", "updateTTSConfig 后 voiceIdentifier 应更新")
        XCTAssertEqual(vm.ttsConfig.rate, 0.8, accuracy: 0.001, "rate 应更新")
        XCTAssertEqual(vm.ttsConfig.pitchMultiplier, 1.5, accuracy: 0.001, "pitchMultiplier 应更新")
        XCTAssertEqual(vm.ttsConfig.volume, 0.6, accuracy: 0.001, "volume 应更新")

        // 验证已持久化到 UserDefaults
        let loaded = TTSConfig.load()
        XCTAssertEqual(loaded.voiceIdentifier, "test-voice", "UserDefaults 中 voiceIdentifier 应一致")
        XCTAssertEqual(loaded.rate, 0.8, accuracy: 0.001, "UserDefaults 中 rate 应一致")
    }

    // MARK: - loadFromRemoteConfig 行为

    /// loadFromRemoteConfig 不应覆盖用户已自定义的 systemPrompt（非默认值时保留）
    func testLoadFromRemoteConfigPreservesCustomizedSystemPrompt() async {
        // 设置 systemPrompt 为非默认值（模拟用户自定义）
        vm.systemPrompt = "我是自定义的系统提示词"
        // 注意：defaultSystemPrompt == ChatConfig.default.systemPrompt == "你是一个有帮助的AI助手。"
        // loadFromRemoteConfig 仅在 systemPrompt == ChatConfig.default.systemPrompt 时覆盖

        await vm.loadFromRemoteConfig()

        XCTAssertEqual(vm.systemPrompt, "我是自定义的系统提示词",
                       "loadFromRemoteConfig 不应覆盖用户已自定义的 systemPrompt")
    }

    // MARK: - loadSystemPrompt / updateSystemPrompt

    /// loadSystemPrompt(from: nil) 应使用 defaultSystemPrompt（已有测试，此处验证非默认值被覆盖）
    func testLoadSystemPromptNilOverwritesNonDefault() {
        vm.systemPrompt = "临时值"
        vm.loadSystemPrompt(from: nil)
        XCTAssertEqual(vm.systemPrompt, SettingsViewModel.defaultSystemPrompt,
                       "传 nil 应将 systemPrompt 重置为默认值")
    }

    /// loadSystemPrompt(from: conversation) 应读取会话的 systemPrompt
    func testLoadSystemPromptFromConversation() throws {
        // 使用 in-memory ModelContainer 创建 Conversation
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Conversation.self, ChatMessage.self, configurations: config)
        let context = ModelContext(container)
        let conv = Conversation(title: "测试", systemPrompt: "会话专属提示词")
        context.insert(conv)

        vm.loadSystemPrompt(from: conv)

        XCTAssertEqual(vm.systemPrompt, "会话专属提示词",
                       "loadSystemPrompt(from: conv) 应读取会话的 systemPrompt")
    }

    /// updateSystemPrompt(in: nil, modelContext: _) 应直接返回，不修改状态
    func testUpdateSystemPromptNilConversationIsNoOp() {
        let original = vm.systemPrompt
        vm.updateSystemPrompt(in: nil, modelContext: nil)
        XCTAssertEqual(vm.systemPrompt, original, "conversation 为 nil 时 updateSystemPrompt 应为 no-op")
    }

    /// updateSystemPrompt(in: conversation, modelContext: _) 应回写 systemPrompt
    func testUpdateSystemPromptInConversation() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Conversation.self, ChatMessage.self, configurations: config)
        let context = ModelContext(container)
        let conv = Conversation(title: "测试", systemPrompt: "旧提示词")
        context.insert(conv)

        vm.systemPrompt = "新的系统提示词"
        vm.updateSystemPrompt(in: conv, modelContext: context)

        XCTAssertEqual(conv.systemPrompt, "新的系统提示词",
                       "updateSystemPrompt 后会话的 systemPrompt 应被回写")
    }
}
