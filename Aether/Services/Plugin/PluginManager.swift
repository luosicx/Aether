import Foundation
import Observation

/// 插件管理器：负责插件的安装、卸载、工具加载与版本管理。
///
/// 使用 @Observable 宏实现响应式，UI 可观察 installedPluginList 变化。
/// 插件工具通过 PluginToolAdapter 适配后注册到 ToolRegistry.shared。
/// @MainActor 隔离，确保线程安全。
@MainActor
@Observable
final class PluginManager {
    /// 已安装的插件字典，key 为插件 ID
    private var installedPlugins: [String: PluginManifest] = [:]
    /// 插件目录 URL（用于持久化插件文件）
    private var pluginDirectory: URL

    /// 初始化插件管理器，创建插件目录
    init() {
        // 默认插件目录：Application Support/Plugins
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        pluginDirectory = appSupport.appendingPathComponent("Plugins", isDirectory: true)
        // 确保目录存在
        try? fm.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 安装 / 卸载

    /// 安装插件。若插件 ID 已存在则覆盖（视为更新）。
    /// - Parameter manifest: 插件清单
    /// - Throws: 插件 ID 为空时抛出错误
    func install(manifest: PluginManifest) throws {
        guard !manifest.id.isEmpty else {
            throw NSError(domain: "PluginManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "插件 ID 不能为空"])
        }
        installedPlugins[manifest.id] = manifest
    }

    /// 卸载插件。先卸载已加载的工具，再从已安装列表中移除。
    /// - Parameter pluginID: 插件 ID
    /// - Throws: 插件未安装时抛出错误
    func uninstall(pluginID: String) throws {
        guard installedPlugins[pluginID] != nil else {
            throw NSError(domain: "PluginManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(pluginID) 未安装"])
        }
        // 先卸载工具（忽略错误，工具可能未加载）
        try? unloadPluginTools(pluginID: pluginID)
        installedPlugins.removeValue(forKey: pluginID)
    }

    // MARK: - 查询

    /// 已安装插件列表
    var installedPluginList: [PluginManifest] {
        Array(installedPlugins.values)
    }

    /// 检查插件是否已安装
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 已安装返回 true
    func isInstalled(_ pluginID: String) -> Bool {
        installedPlugins[pluginID] != nil
    }

    // MARK: - 工具加载 / 卸载

    /// 加载插件工具到 ToolRegistry。
    /// 为插件清单中的每个工具创建 PluginToolAdapter 并注册到 ToolRegistry.shared。
    /// - Parameter pluginID: 插件 ID
    /// - Throws: 插件未安装时抛出错误
    func loadPluginTools(pluginID: String) throws {
        guard let manifest = installedPlugins[pluginID] else {
            throw NSError(domain: "PluginManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(pluginID) 未安装"])
        }
        for toolDef in manifest.tools {
            let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)
            ToolRegistry.shared.register(tool: adapter)
        }
    }

    /// 卸载插件工具：从 ToolRegistry 中注销插件声明的所有工具。
    /// - Parameter pluginID: 插件 ID
    /// - Throws: 插件未安装时抛出错误
    func unloadPluginTools(pluginID: String) throws {
        guard let manifest = installedPlugins[pluginID] else {
            throw NSError(domain: "PluginManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(pluginID) 未安装"])
        }
        for toolDef in manifest.tools {
            ToolRegistry.shared.unregister(name: toolDef.name)
        }
    }
}

// MARK: - Task 15: 版本管理与热更新

extension PluginManager {
    /// 检查插件是否有版本更新。
    /// 简化实现：返回 nil（无更新）。实际场景可请求远程注册中心获取最新版本。
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 新版本号字符串，无更新时返回 nil
    func checkForUpdates(pluginID: String) async throws -> String? {
        // 简化实现：不检查远程，直接返回 nil
        return nil
    }

    /// 热更新插件：卸载旧工具 → 替换清单 → 加载新工具。
    /// - Parameters:
    ///   - pluginID: 插件 ID
    ///   - newManifest: 新的插件清单
    /// - Throws: 插件未安装时抛出错误
    func hotUpdate(pluginID: String, newManifest: PluginManifest) throws {
        guard installedPlugins[pluginID] != nil else {
            throw NSError(domain: "PluginManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(pluginID) 未安装"])
        }
        // 先卸载旧工具
        try unloadPluginTools(pluginID: pluginID)
        // 替换清单
        installedPlugins[pluginID] = newManifest
        // 加载新工具
        try loadPluginTools(pluginID: pluginID)
    }

    /// 获取插件当前版本号
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 版本号字符串，插件未安装时返回 nil
    func getVersion(pluginID: String) -> String? {
        installedPlugins[pluginID]?.version
    }
}
