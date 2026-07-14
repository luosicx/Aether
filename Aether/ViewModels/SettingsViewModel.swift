import Foundation
import SwiftData
import AetherFoundation
import AetherServices

/// 设置 ViewModel，管理 API Key、模型选择、系统提示词。使用 @Observable + @MainActor 隔离。
@Observable
@MainActor
final class SettingsViewModel {
    /// Day 13: DeepSeek 的 API Key
    var deepseekAPIKey: String = ""
    /// Day 13: Qwen 的 API Key
    var qwenAPIKey: String = ""
    /// Day 13: 当前选中的 LLM 供应商
    var selectedProvider: ModelProvider = .deepseek {
        didSet {
            // Day 14: 用户手动切换 provider 时标记，loadFromRemoteConfig 据此跳过覆盖
            if !isLoadingFromRemote { userCustomizedProvider = true }
        }
    }
    /// Day 13: 是否启用自动降级
    var enableFallback: Bool = false
    /// Day 15: BFF 代理配置（endpoint / token / 限流参数），缓存于 UserDefaults
    var bffConfig: BFFConfig = .default
    /// Day 16: 端侧推理配置（开关 / 模型路径 / 采样参数），缓存于 UserDefaults
    var onDeviceConfig: OnDeviceConfig = .default
    /// TTS 朗读配置（音色 / 语速 / 音调 / 音量），缓存于 UserDefaults
    var ttsConfig: TTSConfig = .load()
    /// 当前选中的模型名（默认 APIConfig.defaultModel）
    var selectedModel: String = APIConfig.defaultModel
    /// Day 12: 模型选择模式（"auto"=智能路由 / "deepseek-chat" / "deepseek-reasoner"）
    var modelSelectionMode: String = "auto"
    /// 系统提示词（绑定 TextEditor）
    var systemPrompt: String = "你是一个有帮助的AI助手。"
    /// 是否正在保存
    var isSaving = false
    /// 保存结果消息（成功/失败提示）
    var saveMessage: String?
    /// 已启用的危险/敏感工具名集合（与 ToolRegistry 同步，供设置页 Toggle 绑定）
    var enabledTools: Set<String> = []
    /// 本运行周期内已授权过的敏感工具名集合，避免重复弹 Alert
    var authorizedToolsOnce: Set<String> = []

    // Day 14: 远程配置加载状态标记
    /// 用户是否手动切换过 provider（true 时 loadFromRemoteConfig 不覆盖 selectedProvider）
    @ObservationIgnored private var userCustomizedProvider: Bool = false
    /// 正在从远程配置加载（true 时 selectedProvider 的 didSet 不标记 userCustomizedProvider）
    @ObservationIgnored private var isLoadingFromRemote = false

    /// 默认人设（新建对话时使用，不与具体会话绑定）
    nonisolated static let defaultSystemPrompt = "你是一个有帮助的AI助手。"

    /// 可选模型列表 ["deepseek-chat", "deepseek-reasoner"]
    let availableModels = ["deepseek-chat", "deepseek-reasoner"]

    /// Day 13: 向后兼容字段，等价于 deepseekAPIKey（保留现有 UIT/View 绑定）
    var apiKey: String {
        get { deepseekAPIKey }
        set { deepseekAPIKey = newValue }
    }

    /// 不在 init 中同步访问 Keychain，避免阻塞主线程
    init() {
        // 不在 init 中同步访问 Keychain，避免阻塞主线程
    }

    /// Day 13: 旧 API：只加载 deepseek（向后兼容现有调用方）
    func loadAPIKeyFromKeychain() async {
        let key = await Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey(for: .deepseek)
        }.value
        deepseekAPIKey = key ?? ""
    }

    /// Day 13: 并发加载两个 provider 的 API Key
    func loadAPIKeysFromKeychain() async {
        async let dsKey = Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey(for: .deepseek)
        }.value
        async let qwenKey = Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey(for: .qwen)
        }.value
        let (ds, qwen) = await (dsKey, qwenKey)
        deepseekAPIKey = ds ?? ""
        qwenAPIKey = qwen ?? ""
        // Day 15: API Key 加载后读取缓存的 BFF 配置
        loadBFFConfig()
        // Day 16: 同时读取缓存的端侧推理配置
        loadOnDeviceConfig()
    }

    /// Day 15 / Task 5: 从 UserDefaults 读取非敏感 BFF 字段，从 Keychain 读取 userToken，
    /// 组装为完整 BFFConfig。无缓存或解码失败时用默认值。
    func loadBFFConfig() {
        Self.migrateLegacyBFFConfigIfNeeded()

        var nonSensitive = BFFConfig.NonSensitive()
        if let data = UserDefaults.standard.data(forKey: BFFConfig.userDefaultsKey) {
            nonSensitive = (try? JSONDecoder().decode(BFFConfig.NonSensitive.self, from: data)) ?? nonSensitive
        }

        let token = KeychainManager.shared.read(key: BFFConfig.userTokenKeychainAccount) ?? ""
        bffConfig = BFFConfig(nonSensitive: nonSensitive, userToken: token)
    }

    /// Day 15 / Task 5: 非敏感字段写入 UserDefaults，userToken 写入 Keychain。
    func saveBFFConfig() {
        if let data = try? JSONEncoder().encode(bffConfig.nonSensitive) {
            UserDefaults.standard.set(data, forKey: BFFConfig.userDefaultsKey)
        }
        try? KeychainManager.shared.save(
            key: BFFConfig.userTokenKeychainAccount,
            value: bffConfig.userToken
        )
    }

    /// Task 5: 若 UserDefaults 中仍遗留旧版完整 BFFConfig（含 userToken），
    /// 将 token 迁移到 Keychain，随后将 UserDefaults 重写为非敏感字段子集。
    nonisolated static func migrateLegacyBFFConfigIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: BFFConfig.userDefaultsKey) else { return }
        // 尝试按旧版完整 BFFConfig 解码；失败说明已迁移或数据损坏，无需处理
        guard let legacy = try? JSONDecoder().decode(BFFConfig.self, from: data) else { return }

        if !legacy.userToken.isEmpty {
            try? KeychainManager.shared.save(
                key: BFFConfig.userTokenKeychainAccount,
                value: legacy.userToken
            )
        }
        if let newData = try? JSONEncoder().encode(legacy.nonSensitive) {
            UserDefaults.standard.set(newData, forKey: BFFConfig.userDefaultsKey)
        }
    }

    /// Day 16 / Task 5: 从 UserDefaults 读取端侧推理配置。当前无敏感字段，直接 JSON 解码。
    func loadOnDeviceConfig() {
        guard let data = UserDefaults.standard.data(forKey: OnDeviceConfig.userDefaultsKey) else {
            onDeviceConfig = .default
            return
        }
        onDeviceConfig = (try? JSONDecoder().decode(OnDeviceConfig.self, from: data)) ?? .default
    }

    /// Day 16 / Task 5: 把端侧推理配置写入 UserDefaults。当前无敏感字段，直接 JSON 编码。
    /// 若未来新增签名密钥/API key，请加入 OnDeviceConfig.sensitiveKeychainAccounts 并在此方法中先写入 Keychain。
    func saveOnDeviceConfig() {
        if let data = try? JSONEncoder().encode(onDeviceConfig) {
            UserDefaults.standard.set(data, forKey: OnDeviceConfig.userDefaultsKey)
        }
    }

    /// 更新 TTS 配置：本地状态 + UserDefaults 持久化
    func updateTTSConfig(_ new: TTSConfig) {
        ttsConfig = new
        new.save()
    }

    /// Day 14: 从远程配置加载默认值。仅覆盖用户未自定义的字段（systemPrompt / provider / fallback）。
    /// 远程配置作为初始默认值生效，不覆盖用户已自定义的本地配置。
    func loadFromRemoteConfig() async {
        // 拉取远程配置（失败时 service 内部回退到缓存或内置默认值）
        await RemoteConfigService.shared.fetch()
        let config = await RemoteConfigService.shared.currentConfig
        // 仅当 systemPrompt 仍为默认值（用户未自定义）时用远程 defaultSystemPrompt 覆盖
        if systemPrompt == ChatConfig.default.systemPrompt {
            systemPrompt = config.defaultSystemPrompt
        }
        // 仅当用户未切换过 provider 时用远程 defaultProvider 覆盖
        if !userCustomizedProvider {
            if let provider = ModelProvider(rawValue: config.defaultProvider) {
                // 标记正在远程加载，避免 didSet 误标记用户自定义
                isLoadingFromRemote = true
                selectedProvider = provider
                isLoadingFromRemote = false
            }
        }
        // 仅当 enableFallback == false 且用户未手动开启过时用远程 featureFlags.enableFallback 覆盖
        if !enableFallback {
            enableFallback = config.featureFlags.enableFallback
        }
    }

    /// Day 13: 按 provider 保存 API Key
    func saveAPIKey(for provider: ModelProvider) {
        do {
            let key = provider == .deepseek ? deepseekAPIKey : qwenAPIKey
            try KeychainManager.shared.saveAPIKey(key, for: provider)
            saveMessage = String(format: NSLocalizedString("%@ API Key 已保存", comment: ""), provider.displayName)
        } catch {
            saveMessage = String(format: NSLocalizedString("保存失败：%@", comment: ""), error.localizedDescription)
        }
    }

    /// Day 13: 按 provider 删除 API Key
    func deleteAPIKey(for provider: ModelProvider) {
        KeychainManager.shared.deleteAPIKey(for: provider)
        if provider == .deepseek {
            deepseekAPIKey = ""
        } else {
            qwenAPIKey = ""
        }
        saveMessage = String(format: NSLocalizedString("%@ API Key 已删除", comment: ""), provider.displayName)
    }

    /// 旧 API（向后兼容）：等价于 provider: .deepseek
    func saveAPIKey() { saveAPIKey(for: .deepseek) }

    /// 旧 API（向后兼容）：等价于 provider: .deepseek
    func deleteAPIKey() { deleteAPIKey(for: .deepseek) }

    /// 从指定会话加载 systemPrompt 到本地（用于显示与编辑）。
    /// conversation 为 nil 时用 defaultSystemPrompt。
    func loadSystemPrompt(from conversation: Conversation?) {
        if let conv = conversation {
            systemPrompt = conv.systemPrompt
        } else {
            systemPrompt = Self.defaultSystemPrompt
        }
    }

    /// 把当前 systemPrompt 回写到会话并持久化。conversation 为 nil 时直接返回。
    func updateSystemPrompt(in conversation: Conversation?, modelContext: ModelContext?) {
        guard let conv = conversation else { return }
        conv.systemPrompt = systemPrompt
        try? modelContext?.save()
    }

    // MARK: - 工具启用状态

    /// 从 ToolRegistry 同步当前启用状态到 ViewModel
    func loadSettings() {
        enabledTools = ToolRegistry.shared.enabledTools
    }

    /// 切换指定工具的启用状态，并同步到 ToolRegistry 持久化。
    /// 敏感工具首次启用时应由调用方先展示风险提示 Alert。
    func toggleTool(name: String) {
        let newValue = !ToolRegistry.shared.isEnabled(name: name)
        ToolRegistry.shared.setEnabled(name: name, value: newValue)
        enabledTools = ToolRegistry.shared.enabledTools
    }
}
