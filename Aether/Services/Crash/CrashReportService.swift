import Foundation
#if canImport(Bugly)
import Bugly
#endif

/// Day 20: 崩溃监控服务，封装 Bugly 初始化与上报。
/// - Note: Bugly SDK 不通过 SPM 集成，用 `#if canImport(Bugly)` 条件编译保护，
///   模拟器或未集成 Bugly 时走占位分支，不影响 App 正常运行。
final class CrashReportService {
    /// 单例
    static let shared = CrashReportService()
    private init() {}

    /// 初始化崩溃监控
    /// - Parameter appKey: Bugly App Key（Info.plist 中读取）
    func initialize(appKey: String) {
        #if canImport(Bugly)
        let config = BuglyConfig()
        config.appKey = appKey
        Bugly.start(withAppKey: appKey)
        print("[CrashReport] Bugly initialized")
        #else
        // Bugly SDK 未集成时占位（不影响 App 正常运行）
        print("[CrashReport] Bugly not integrated, crash reporting disabled")
        #endif
    }

    /// 设置匿名用户标识
    /// - Parameter id: 匿名 UUID，用于崩溃聚合与去重
    func setUserId(_ id: String) {
        #if canImport(Bugly)
        Bugly.setUserIdentifier(id)
        #else
        print("[CrashReport] setUserId: \(id) (placeholder)")
        #endif
    }

    /// 设置自定义键值对
    /// - Parameters:
    ///   - key: 自定义键
    ///   - value: 自定义值
    func setCustomKey(_ key: String, value: String) {
        #if canImport(Bugly)
        Bugly.setUserValue(value, forKey: key)
        #else
        print("[CrashReport] setCustomKey: \(key)=\(value) (placeholder)")
        #endif
    }

    /// 手动上报异常
    /// - Parameter error: 需上报的 Error
    func reportException(_ error: Error) {
        #if canImport(Bugly)
        Bugly.reportException(error)
        #else
        print("[CrashReport] Exception: \(error.localizedDescription) (placeholder)")
        #endif
    }
}
