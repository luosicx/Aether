import Foundation

/// Day 16: 端侧推理错误类型。覆盖内存不足、模型缺失、校验失败、量化不支持与加载失败等场景。
/// LocalizedError：提供用户友好的错误描述。
/// Equatable：AetherError 的 onDeviceInferenceFailed case 包含 OnDeviceError，需 Equatable 才能合成 AetherError Equatable。
///
/// P2-3 上下文丢失修复：新增 `loadFailedWithCause(message:underlying:)` 变体，
/// 在保留 `loadFailed(String)` 向后兼容的同时，允许调用方携带原始底层 Error 用于诊断。
/// 由于 `Error` 不一定 `Equatable`，自定义 `==` 实现仅比较 `message`，忽略 `underlying`。
public enum OnDeviceError: LocalizedError, Sendable, Equatable {
    /// 设备可用内存不足（端侧推理通常需要 ≥4GB 可用内存）
    case insufficientMemory
    /// 模型文件未找到，携带路径
    case modelNotFound(URL)
    /// SHA256 校验失败，携带期望值与实际值
    case sha256Mismatch(expected: String, actual: String)
    /// 不支持的模型量化格式
    case unsupportedQuantization
    /// 模型加载失败，仅携带错误信息字符串（向后兼容变体，不保留原始 Error 上下文）。
    /// 新代码应优先使用 `loadFailedWithCause(message:underlying:)` 以保留底层错误。
    case loadFailed(String)
    /// 模型加载失败，携带错误信息字符串与底层错误。
    /// - Parameters:
    ///   - message: 用户可见的错误信息（通常为 `error.localizedDescription`）
    ///   - underlying: 原始底层错误，保留用于诊断（不参与 Equatable 判等）
    case loadFailedWithCause(message: String, underlying: Error)
    /// 下载超时（可从断点续传恢复）
    case downloadTimeout
    /// URL 构造失败（repo / file 含非法字符）
    case invalidURL

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
        case .loadFailedWithCause(let message, _):
            return String(format: NSLocalizedString("端侧模型加载失败：%@", comment: ""), message)
        case .downloadTimeout:
            return NSLocalizedString("下载超时，请检查网络后点击「继续下载」从断点继续", comment: "")
        case .invalidURL:
            return NSLocalizedString("模型仓库地址无效，请检查配置后重试", comment: "")
        }
    }

    /// 诊断描述（含 underlying 信息），用于日志输出，不直接展示给用户。
    /// 调用方在 Logger.error 时应使用此属性而非 errorDescription，以保留底层错误。
    public var diagnosticDescription: String {
        switch self {
        case .insufficientMemory:
            return "OnDeviceError.insufficientMemory"
        case .modelNotFound(let url):
            return "OnDeviceError.modelNotFound(\(url.path))"
        case .sha256Mismatch(let expected, let actual):
            return "OnDeviceError.sha256Mismatch(expected=\(expected.prefix(8))…, actual=\(actual.prefix(8))…)"
        case .unsupportedQuantization:
            return "OnDeviceError.unsupportedQuantization"
        case .loadFailed(let message):
            return "OnDeviceError.loadFailed(\(message))"
        case .loadFailedWithCause(let message, let underlying):
            return "OnDeviceError.loadFailedWithCause(\(message), underlying: \(type(of: underlying)): \(underlying.localizedDescription))"
        case .downloadTimeout:
            return "OnDeviceError.downloadTimeout"
        case .invalidURL:
            return "OnDeviceError.invalidURL"
        }
    }

    /// 自定义 Equatable 实现。
    /// `loadFailedWithCause` 仅比较 `message`，忽略 `underlying` Error
    /// （Error 不一定 Equatable，无法参与判等）。
    public static func == (lhs: OnDeviceError, rhs: OnDeviceError) -> Bool {
        switch (lhs, rhs) {
        case (.insufficientMemory, .insufficientMemory),
             (.unsupportedQuantization, .unsupportedQuantization),
             (.downloadTimeout, .downloadTimeout),
             (.invalidURL, .invalidURL):
            return true
        case (.modelNotFound(let l), .modelNotFound(let r)):
            return l == r
        case (.sha256Mismatch(let le, let la), .sha256Mismatch(let re, let ra)):
            return le == re && la == ra
        case (.loadFailed(let l), .loadFailed(let r)):
            return l == r
        case (.loadFailedWithCause(let lm, _), .loadFailedWithCause(let rm, _)):
            return lm == rm
        default:
            return false
        }
    }
}
