import Foundation

/// 插件沙箱：基于插件清单的权限声明，校验插件可执行的操作。
///
/// 每个插件实例对应一个 PluginSandbox，所有权限检查均从 manifest.permissions 读取。
/// 执行限制（超时时间、内存上限）为固定常量，防止插件占用过多资源。
final class PluginSandbox {
    /// 关联的插件清单
    private let manifest: PluginManifest

    /// 构造沙箱
    /// - Parameter manifest: 插件清单
    init(manifest: PluginManifest) {
        self.manifest = manifest
    }

    /// 检查插件是否有权限执行指定工具
    /// - Parameter toolName: 工具名
    /// - Returns: 工具在 manifest.tools 中声明时返回 true
    func canExecute(toolName: String) -> Bool {
        manifest.tools.contains { $0.name == toolName }
    }

    /// 检查插件是否有网络访问权限
    func canAccessNetwork() -> Bool {
        hasPermission(.network)
    }

    /// 检查插件是否有文件系统访问权限
    func canAccessFileSystem() -> Bool {
        hasPermission(.fileSystem)
    }

    /// 检查插件是否有剪贴板访问权限
    func canAccessClipboard() -> Bool {
        hasPermission(.clipboard)
    }

    /// 最大执行时间（秒），固定 30 秒
    var maxExecutionTime: TimeInterval { 30 }

    /// 最大内存使用（MB），固定 50MB
    var maxMemoryMB: Int { 50 }

    // MARK: - Private

    /// 检查 manifest 中是否声明了指定权限类型
    private func hasPermission(_ type: PluginPermission.PermissionType) -> Bool {
        manifest.permissions.contains { $0.type == type }
    }
}
