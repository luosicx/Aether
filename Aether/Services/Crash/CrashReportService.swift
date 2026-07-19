import Foundation
import os
#if canImport(Bugly)
import Bugly
#endif

/// Day 20: 崩溃监控服务，封装 Bugly 初始化与上报。
/// - Note: Bugly SDK 不通过 SPM 集成，用 `#if canImport(Bugly)` 条件编译保护，
///   模拟器或未集成 Bugly 时走占位分支，不影响 App 正常运行。
/// - Task 8: 标记 `@unchecked Sendable`，单例从 NotificationCenter 后台队列与
///   @MainActor 上下文均会访问；类本身无可变实例状态，Bugly SDK 内部线程安全。
final class CrashReportService: @unchecked Sendable {
    /// 单例
    static let shared = CrashReportService()
    private init() {
        // 单例模式：外部不可创建实例
    }

    /// 初始化崩溃监控
    /// - Parameter appKey: Bugly App Key（Info.plist 中读取）
    func initialize(appKey: String) {
        #if canImport(Bugly)
        let config = BuglyConfig()
        config.appKey = appKey
        Bugly.start(withAppKey: appKey)
        Logger.crash.info("Bugly initialized")
        #else
        // Bugly SDK 未集成时占位（不影响 App 正常运行）
        Logger.crash.warning("Bugly not integrated, crash reporting disabled")
        #endif
    }

    /// 设置匿名用户标识
    /// - Parameter id: 匿名 UUID，用于崩溃聚合与去重
    func setUserId(_ id: String) {
        #if canImport(Bugly)
        Bugly.setUserIdentifier(id)
        #else
        Logger.crash.info("setUserId: \(id) (placeholder)")
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
        Logger.crash.info("setCustomKey: \(key)=\(value) (placeholder)")
        #endif
    }

    /// 手动上报异常
    /// - Parameter error: 需上报的 Error
    func reportException(_ error: Error) {
        #if canImport(Bugly)
        Bugly.reportException(error)
        #else
        Logger.crash.error("Exception: \(error.localizedDescription, privacy: .public) (placeholder)")
        #endif
    }
}
