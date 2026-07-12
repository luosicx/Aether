import Foundation

/// 管理每个工具的启用状态，使用 `UserDefaults` 持久化。
///
/// 高危工具默认禁用，未知工具默认启用。单例 `shared` 供生产使用，
/// 测试可通过注入自定义 `UserDefaults` 或调用 `resetToDefaults()` 隔离状态。
@MainActor
final class ToolPermissionStore {
    static let shared = ToolPermissionStore()

    private let defaults: UserDefaults
    private let baseKey = "toolPermissions"

    /// 创建权限存储。
    /// - Parameter defaults: 用于持久化的 `UserDefaults` 实例，默认 `standard`。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 首次使用时写入默认值，确保高危工具默认禁用。
        if defaults.object(forKey: baseKey) == nil {
            resetToDefaults()
        }
    }

    /// 查询指定工具名是否启用。未知工具默认启用。
    func isEnabled(_ toolName: String) -> Bool {
        let key = storageKey(for: toolName)
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        return defaultState(for: toolName)
    }

    /// 查询已知工具是否启用。
    func isEnabled(_ permission: ToolPermission) -> Bool {
        isEnabled(permission.toolName)
    }

    /// 设置指定工具名的启用状态。
    func setEnabled(_ enabled: Bool, for toolName: String) {
        defaults.set(enabled, forKey: storageKey(for: toolName))
    }

    /// 设置已知工具的启用状态。
    func setEnabled(_ enabled: Bool, for permission: ToolPermission) {
        setEnabled(enabled, for: permission.toolName)
    }

    /// 将所有已知工具重置为默认状态（高危工具禁用，其余启用）。
    func resetToDefaults() {
        defaults.set(true, forKey: baseKey)
        for permission in ToolPermission.allCases {
            setEnabled(permission.isEnabledByDefault, for: permission.toolName)
        }
    }

    /// 移除持久化数据（用于测试清理或恢复出厂设置）。
    func clearAll() {
        for permission in ToolPermission.allCases {
            defaults.removeObject(forKey: storageKey(for: permission.toolName))
        }
        defaults.removeObject(forKey: baseKey)
    }

    /// 生产侧使用的 UserDefaults 键，便于 SwiftUI `@AppStorage` 直接绑定同一键值。
    static func storageKey(for toolName: String) -> String {
        "toolPermissions.\(toolName)"
    }

    private func storageKey(for toolName: String) -> String {
        Self.storageKey(for: toolName)
    }

    private func defaultState(for toolName: String) -> Bool {
        guard let permission = ToolPermission(rawValue: toolName) else { return true }
        return permission.isEnabledByDefault
    }
}
