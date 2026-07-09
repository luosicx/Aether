import Foundation

/// 下载源类型：国内 ModelScope / 国外 HuggingFace
enum DownloadSource: String, Codable, Sendable, CaseIterable {
    case domestic       // 国内 ModelScope
    case international  // 国外 HuggingFace

    var displayName: String {
        switch self {
        case .domestic: return NSLocalizedString("国内（ModelScope）", comment: "")
        case .international: return NSLocalizedString("国外（HuggingFace）", comment: "")
        }
    }
}

/// 端侧模型目录项：含模型元数据与双源下载 URL
struct OnDeviceModelEntry: Identifiable, Sendable, Equatable {
    let id: String                    // 模型 ID（用作本地文件名）
    let name: String                  // 模型名
    let description: String           // 中文简介
    let estimatedSizeMB: Int          // 估计文件大小（MB）
    let huggingFaceURL: URL            // HuggingFace 下载 URL
    let modelScopeURL: URL             // ModelScope 下载 URL
    let sha256: String                // SHA256 校验值

    /// 根据下载源返回对应 URL
    func url(for source: DownloadSource) -> URL {
        switch source {
        case .domestic: return modelScopeURL
        case .international: return huggingFaceURL
        }
    }
}

/// 端侧模型目录：预定义的可用模型列表
enum OnDeviceModelCatalog {
    /// 所有可用模型（均已验证 ModelScope 可访问）
    static let models: [OnDeviceModelEntry] = [
        OnDeviceModelEntry(
            id: "Llama-3.2-1B-Instruct-4bit",
            name: "Llama-3.2-1B-Instruct-4bit",
            description: "Meta Llama 3.2 1B 参数指令模型，4bit 量化。轻量通用对话模型，适合日常问答与文本生成。",
            estimatedSizeMB: 695,
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors") ?? URL(fileURLWithPath: ""),
            modelScopeURL: URL(string: "https://www.modelscope.cn/api/v1/models/mlx-community/Llama-3.2-1B-Instruct-4bit/repo?Revision=master&FilePath=model.safetensors") ?? URL(fileURLWithPath: ""),
            sha256: "35e396644bca888eec399f9c0f843ec7fa78b8f8c5e06841661be62b4edf96dd"
        ),
        OnDeviceModelEntry(
            id: "Qwen2-0.5B-Instruct-4bit",
            name: "Qwen2-0.5B-Instruct-4bit",
            description: "阿里通义千问 Qwen2 0.5B 参数指令模型，4bit 量化。超轻量模型，推理速度最快，适合资源受限设备。",
            estimatedSizeMB: 278,
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Qwen2-0.5B-Instruct-4bit/resolve/main/model.safetensors") ?? URL(fileURLWithPath: ""),
            modelScopeURL: URL(string: "https://www.modelscope.cn/api/v1/models/mlx-community/Qwen2-0.5B-Instruct-4bit/repo?Revision=master&FilePath=model.safetensors") ?? URL(fileURLWithPath: ""),
            sha256: "961b4727c18aec86456a213028e08f54cbe0081ad7b9e3e5eccfd967e47387dd"
        ),
        OnDeviceModelEntry(
            id: "Phi-3-mini-4k-instruct-4bit",
            name: "Phi-3-mini-4k-instruct-4bit",
            description: "微软 Phi-3-mini 3.8B 参数指令模型，4bit 量化，4k 上下文。推理能力更强但体积较大，适合高质量推理场景。",
            estimatedSizeMB: 2150,
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Phi-3-mini-4k-instruct-4bit/resolve/main/model.safetensors") ?? URL(fileURLWithPath: ""),
            modelScopeURL: URL(string: "https://www.modelscope.cn/api/v1/models/mlx-community/Phi-3-mini-4k-instruct-4bit/repo?Revision=master&FilePath=model.safetensors") ?? URL(fileURLWithPath: ""),
            sha256: "8d75680621a09474f6601e9176f2f61f92a5e4c079d68d583901f51699fda50a"
        )
    ]

    /// 按 ID 查找模型
    static func find(id: String) -> OnDeviceModelEntry? {
        models.first { $0.id == id }
    }
}
