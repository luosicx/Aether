import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// v1.3: 设备能力分级。
///
/// 根据 SoC 型号、物理内存、GPU 核数判定设备多模态能力等级，
/// 用于自动选择合适的模型规模（2B / 7B / 11B）。
///
/// 设计参考 MASTER_PLAN §4.1.3：iPhone 15 Pro 自动选择 2B，Mac 选择 11B。
public enum DeviceCapability: String, Sendable, Equatable {
    /// 低端：iPhone SE / iPhone 14 及以下，仅支持 0.5B 模型
    case low
    /// 中端：iPhone 15 / 15 Plus，支持 1B 模型
    case medium
    /// 高端：iPhone 15 Pro / 16 系列，支持 2B VLM
    case high
    /// 超高端：iPad Pro M4 / Mac，支持 7B+ 模型
    case ultra

    /// 显示名称（用于 UI 展示）
    public var displayName: String {
        switch self {
        case .low: return "低端设备"
        case .medium: return "中端设备"
        case .high: return "高端设备"
        case .ultra: return "超高端设备"
        }
    }

    /// 支持的最大 VLM 参数规模（B）
    public var maxVLMScale: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .ultra: return 11
        }
    }

    /// 是否支持 VLM 图像理解
    public var supportsVLM: Bool {
        self != .low
    }

    /// 是否支持语音克隆（OpenVoice v2 蒸馏）
    public var supportsVoiceClone: Bool {
        switch self {
        case .low, .medium: return false
        case .high, .ultra: return true
        }
    }

    /// 是否支持图像生成（SD Mobile）
    public var supportsImageGeneration: Bool {
        switch self {
        case .low, .medium: return false
        case .high, .ultra: return true
        }
    }

    /// 推荐的最大内存预算（MB）
    public var recommendedMemoryBudgetMB: Int {
        switch self {
        case .low: return 1_500
        case .medium: return 2_500
        case .high: return 3_000
        case .ultra: return 6_000
        }
    }

    /// 自动检测当前设备能力等级
    public static var current: DeviceCapability {
        detect()
    }

    /// 检测设备能力等级
    /// 基于物理内存 + 平台 + 机器型号判定
    public static func detect() -> DeviceCapability {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / (1024 * 1024 * 1024)

        #if os(macOS)
        // macOS：8GB+ 视为 ultra
        return memoryGB >= 8 ? .ultra : .high
        #elseif os(iOS)
        // iOS：按物理内存与机器型号分级
        let machine = machineIdentifier
        if memoryGB >= 8 {
            // iPhone 15 Pro / 16 Pro / iPad Pro M4
            return .ultra
        } else if memoryGB >= 6 {
            // iPhone 15 / 15 Plus / 16
            return .high
        } else if memoryGB >= 4 {
            // iPhone 14 / 14 Plus / 13
            return .medium
        } else {
            // iPhone SE / iPhone 12 及以下
            return .low
        }
        #else
        // 其他平台默认 medium
        return .medium
        #endif
    }

    #if canImport(UIKit)
    /// 获取设备型号标识（如 "iPhone16,1"）
    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    #else
    private static var machineIdentifier: String { "" }
    #endif
}
