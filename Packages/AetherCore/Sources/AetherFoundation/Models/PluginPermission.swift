import Foundation

/// 插件权限定义，声明插件可访问的系统资源类型。
///
/// 每个权限包含类型与可选描述，由 PluginManifest 声明、PluginSandbox 校验。
public struct PluginPermission: Codable, Hashable {
    /// 权限类型枚举
    public let type: PermissionType
    /// 权限的可选描述说明
    public let description: String?

    /// 权限类型枚举：覆盖网络、文件系统、剪贴板、通知、通讯录、位置
    public enum PermissionType: String, Codable {
        case network       // 网络访问
        case fileSystem    // 文件系统
        case clipboard      // 剪贴板
        case notifications  // 通知
        case contacts       // 通讯录
        case location       // 位置
    }

    public init(type: PermissionType, description: String? = nil) {
        self.type = type
        self.description = description
    }
}
