import Foundation

/// Day 16: 端侧推理配置。承载端侧模型开关、模型路径、断网自动切换、采样参数等元数据。
/// Codable + Sendable：支持序列化到 UserDefaults 并跨 actor 传递。
public struct OnDeviceConfig: Codable, Sendable, Equatable {
    /// 是否启用端侧推理（默认 false，启用后可在断网或手动切换时走本地 MLX 推理）
    public var enabled: Bool = false
    /// 本地模型文件路径（默认 nil，下载完成后回写）
    public var modelPath: URL?
    /// 断网时自动切换到端侧推理（默认 true）
    public var autoSwitchOnNetworkLoss: Bool = true
    /// 单次响应最大 token 数（默认 512，端侧模型显存受限，不宜过大）
    public var maxTokens: Int = 512
    /// 采样温度，越高越随机（默认 0.7）
    public var temperature: Double = 0.7
    /// 端侧模型名（默认 Llama-3.2-1B-Instruct Q4_K_M 量化版本）
    public var modelName: String = "Llama-3.2-1B-Instruct-Q4_K_M"
    /// 模型下载地址（HuggingFace CDN，MLX 模型为 model.safetensors）
    public var downloadURL: URL? = URL(string: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors")
    /// 镜像下载地址（国内 ModelScope，主地址失败时回退使用）
    public var mirrorDownloadURL: URL? = URL(string: "https://www.modelscope.cn/api/v1/models/mlx-community/Llama-3.2-1B-Instruct-4bit/repo?Revision=master&FilePath=model.safetensors")
    /// 模型文件期望的 SHA256 摘要，用于下载完成后完整性校验
    public var expectedSHA256: String = ""
    /// 下载源：国内 ModelScope（默认） / 国外 HuggingFace
    public var downloadSource: DownloadSource = .domestic

    /// 默认配置（未启用端侧推理时的兜底值）
    public static let `default` = OnDeviceConfig()

    /// UserDefaults 缓存键
    public static let userDefaultsKey = "ondevice_config_cache"

    public init(
        enabled: Bool = false,
        modelPath: URL? = nil,
        autoSwitchOnNetworkLoss: Bool = true,
        maxTokens: Int = 512,
        temperature: Double = 0.7,
        modelName: String = "Llama-3.2-1B-Instruct-Q4_K_M",
        downloadURL: URL? = URL(string: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors"),
        mirrorDownloadURL: URL? = URL(string: "https://www.modelscope.cn/api/v1/models/mlx-community/Llama-3.2-1B-Instruct-4bit/repo?Revision=master&FilePath=model.safetensors"),
        expectedSHA256: String = "",
        downloadSource: DownloadSource = .domestic
    ) {
        self.enabled = enabled
        self.modelPath = modelPath
        self.autoSwitchOnNetworkLoss = autoSwitchOnNetworkLoss
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.modelName = modelName
        self.downloadURL = downloadURL
        self.mirrorDownloadURL = mirrorDownloadURL
        self.expectedSHA256 = expectedSHA256
        self.downloadSource = downloadSource
    }
}

// MARK: - 敏感字段 Keychain 迁移基础设施

public extension OnDeviceConfig {
    /// 敏感字段及其 Keychain account 映射（当前无敏感字段，留空）。
    /// 若未来新增签名密钥或 API key，请在此添加映射（如 ["apiKey": "com.aether.ondevice.apiKey"]），
    /// 并在 SettingsViewModel.saveOnDeviceConfig()/loadOnDeviceConfig() 中实现对应读写，
    /// 同时将该字段从 UserDefaults JSON 中排除。
    static let sensitiveKeychainAccounts: [String: String] = [:]
}
