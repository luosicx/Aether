/// 设备信息获取工具（跨平台：iOS + macOS）
///
/// 返回设备型号、OS 版本、电量、可用存储空间等信息。
/// 调用方式：execute(arguments: [:])，无入参。
/// iOS 通过 UIDevice 读取型号/版本/电量，macOS 通过 ProcessInfo 读取 OS 版本。
import Foundation
#if os(iOS)
import UIKit
#endif

/// 设备信息工具，返回设备型号、OS 版本、电量、可用存储空间
final class DeviceInfoTool: ToolProtocol {
    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "get_device_info",
            description: "获取设备型号、OS 版本、电量、可用存储空间",
            parameters: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        )
    }

    /// 返回多行设备信息字符串。
    /// - iOS：UIDevice 读取型号/版本/电量，FileManager 读取可用存储
    /// - macOS：ProcessInfo 读取 OS 版本，电量返回 "不适用"，存储同上
    func execute(arguments: [String: Any]) async throws -> String {
        let model = deviceModel()
        let osVersion = systemVersion()
        let battery = batteryPercentage()
        let storage = availableStorageGB()

        return """
        设备型号：\(model)
        系统版本：\(osVersion)
        电量：\(battery)
        可用存储：\(storage)
        """
    }

    /// 设备型号：iOS 用 UIDevice.current.model；macOS 固定 "Mac"
    private func deviceModel() -> String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    /// 系统版本：iOS "iOS <systemVersion>"；macOS "macOS x.y.z"
    private func systemVersion() -> String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    /// 电量百分比：iOS 开启电池监听后读取 batteryLevel；macOS 返回 "不适用"
    private func batteryPercentage() -> String {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        // batteryLevel 返回 0.0...1.0，-1 表示未就绪（如模拟器）
        guard level >= 0 else { return "未知" }
        return "\(Int(level * 100))%"
        #else
        return "不适用"
        #endif
    }

    /// 可用存储 GB：用 home 目录 URL 的 volumeAvailableCapacityForImportantUsageKey
    private func availableStorageGB() -> String {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        guard
            let values = try? home.resourceValues(forKeys: [key]),
            let bytes = values.volumeAvailableCapacityForImportantUsage
        else {
            return "未知"
        }
        let gb = Double(bytes) / 1_000_000_000.0
        return String(format: "%.1f GB", gb)
    }
}
