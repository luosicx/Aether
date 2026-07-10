import Foundation

/// Day 16: 端侧推理配置。承载端侧模型开关、模型路径、断网自动切换、采样参数等元数据。
/// Codable + Sendable：支持序列化到 UserDefaults 并跨 actor 传递。
struct OnDeviceConfig: Codable, Sendable, Equatable {
    /// 是否启用端侧推理（默认 false，启用后可在断网或手动切换时走本地 MLX 推理）
    var enabled: Bool = false
    /// 本地模型文件路径（默认 nil，下载完成后回写）
    var modelPath: URL?
    /// 断网时自动切换到端侧推理（默认 true）
    var autoSwitchOnNetworkLoss: Bool = true
    /// 单次响应最大 token 数（默认 512，端侧模型显存受限，不宜过大）
    var maxTokens: Int = 512
    /// 采样温度，越高越随机（默认 0.7）
    var temperature: Double = 0.7
    /// 端侧模型名（默认 Llama-3.2-1B-Instruct Q4_K_M 量化版本）
    var modelName: String = "Llama-3.2-1B-Instruct-Q4_K_M"
    /// 模型下载地址（HuggingFace CDN，MLX 模型为 model.safetensors）
    var downloadURL: URL = URL(string: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors") ?? URL(fileURLWithPath: "")
    /// 镜像下载地址（国内 ModelScope，主地址失败时回退使用）
    var mirrorDownloadURL: URL = URL(string: "https://www.modelscope.cn/api/v1/models/mlx-community/Llama-3.2-1B-Instruct-4bit/repo?Revision=master&FilePath=model.safetensors")
        ?? URL(fileURLWithPath: "")
    /// 模型文件期望的 SHA256 摘要，用于下载完成后完整性校验
    var expectedSHA256: String = ""
    /// 下载源：国内 ModelScope（默认） / 国外 HuggingFace
    var downloadSource: DownloadSource = .domestic

    /// 默认配置（未启用端侧推理时的兜底值）
    static let `default` = OnDeviceConfig()

    /// UserDefaults 缓存键
    static let userDefaultsKey = "ondevice_config_cache"
}
