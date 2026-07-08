import Foundation
import SwiftData

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

    // Day 14: 远程配置加载状态标记
    /// 用户是否手动切换过 provider（true 时 loadFromRemoteConfig 不覆盖 selectedProvider）
    @ObservationIgnored private var userCustomizedProvider: Bool = false
    /// 正在从远程配置加载（true 时 selectedProvider 的 didSet 不标记 userCustomizedProvider）
    @ObservationIgnored private var isLoadingFromRemote = false

    /// 默认人设（新建对话时使用，不与具体会话绑定）
    static let defaultSystemPrompt = "你是一个有帮助的AI助手。"

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

    /// Day 15: 从 UserDefaults 读取缓存的 BFF 配置（JSON 解码）。无缓存或解码失败时用默认值。
    func loadBFFConfig() {
        guard let data = UserDefaults.standard.data(forKey: BFFConfig.userDefaultsKey) else {
            bffConfig = .default
            return
        }
        bffConfig = (try? JSONDecoder().decode(BFFConfig.self, from: data)) ?? .default
    }

    /// Day 15: 把当前 BFF 配置写入 UserDefaults（JSON 编码）
    func saveBFFConfig() {
        if let data = try? JSONEncoder().encode(bffConfig) {
            UserDefaults.standard.set(data, forKey: BFFConfig.userDefaultsKey)
        }
    }

    /// Day 16: 从 UserDefaults 读取缓存的端侧推理配置（JSON 解码）。无缓存或解码失败时用默认值。
    func loadOnDeviceConfig() {
        guard let data = UserDefaults.standard.data(forKey: OnDeviceConfig.userDefaultsKey) else {
            onDeviceConfig = .default
            return
        }
        onDeviceConfig = (try? JSONDecoder().decode(OnDeviceConfig.self, from: data)) ?? .default
    }

    /// Day 16: 把当前端侧推理配置写入 UserDefaults（JSON 编码）
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
            saveMessage = "\(provider.displayName) API Key 已保存"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
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
        saveMessage = "\(provider.displayName) API Key 已删除"
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
}
