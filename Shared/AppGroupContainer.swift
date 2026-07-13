import Foundation
import SwiftData

/// Task 4/5: App Group 共享容器辅助工具。
/// 提供 iOS / watchOS / Widget Extension 共用的 SwiftData store URL，
/// 确保三端读写同一 SQLite 文件。
///
/// - Note: 使用此工具前需在所有 target 的 entitlements 中配置相同的 App Group。
enum AppGroupContainer {
    /// App Group 标识符（iOS / watchOS / Widget 共用）
    static let groupIdentifier = "group.com.aether.app"

    /// App Group 容器 URL。App Group 未配置时返回 nil。
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// 共享 SwiftData store URL（位于 App Group 容器内）。
    /// App Group 未配置时返回 nil（调用方应回退到默认存储）。
    static var sharedStoreURL: URL? {
        containerURL?.appendingPathComponent("Aether.sqlite")
    }

    /// 创建使用 App Group 共享存储的 ModelConfiguration。
    /// App Group 未配置时回退到默认存储（开发/测试兜底）。
    static func makeModelConfiguration() -> ModelConfiguration {
        if let url = sharedStoreURL {
            return ModelConfiguration(url: url)
        }
        return ModelConfiguration(isStoredInMemoryOnly: false)
    }
}
