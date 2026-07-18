import Foundation

/// Day 16: 端侧推理错误类型。覆盖内存不足、模型缺失、校验失败、量化不支持与加载失败等场景。
/// LocalizedError：提供用户友好的错误描述。
/// Equatable：AetherError 的 onDeviceInferenceFailed case 包含 OnDeviceError，需 Equatable 才能合成 AetherError Equatable。
public enum OnDeviceError: LocalizedError, Sendable, Equatable {
    /// 设备可用内存不足（端侧推理通常需要 ≥4GB 可用内存）
    case insufficientMemory
    /// 模型文件未找到，携带路径
    case modelNotFound(URL)
    /// SHA256 校验失败，携带期望值与实际值
    case sha256Mismatch(expected: String, actual: String)
    /// 不支持的模型量化格式
    case unsupportedQuantization
    /// 模型加载失败，携带底层错误信息
    case loadFailed(String)
    /// 下载超时（可从断点续传恢复）
    case downloadTimeout

    /// 用户友好的错误描述（不暴露底层实现细节）
    public var errorDescription: String? {
        switch self {
        case .insufficientMemory:
            return NSLocalizedString("设备可用内存不足，端侧推理需要至少 4GB 可用内存", comment: "")
        case .modelNotFound(let url):
            return String(format: NSLocalizedString("模型文件未找到：%@", comment: ""), url.lastPathComponent)
        case .sha256Mismatch(let expected, let actual):
            return String(format: NSLocalizedString("模型文件校验失败（SHA256 不匹配），请重新下载\n期望：%@…\n实际：%@…", comment: ""), String(expected.prefix(8)), String(actual.prefix(8)))
        case .unsupportedQuantization:
            return NSLocalizedString("不支持的模型量化格式，请选择 Q4_K_M 或更轻量版本", comment: "")
        case .loadFailed(let message):
            return String(format: NSLocalizedString("端侧模型加载失败：%@", comment: ""), message)
        case .downloadTimeout:
            return NSLocalizedString("下载超时，请检查网络后点击「继续下载」从断点继续", comment: "")
        }
    }
}
