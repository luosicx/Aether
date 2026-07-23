import Foundation
import AetherFoundation
import Observation

/// 插件管理器：负责插件的安装、卸载、工具加载与版本管理。
///
/// 使用 @Observable 宏实现响应式，UI 可观察 installedPluginList 变化。
/// 插件工具通过 PluginToolAdapter 适配后注册到 ToolRegistry.shared（通过 ToolRegistering 协议注入）。
/// @MainActor 隔离，确保线程安全。
@MainActor
@Observable
public final class PluginManager {
    /// 已安装的插件字典，key 为插件 ID
    private var installedPlugins: [String: PluginManifest] = [:]
    /// 插件目录 URL（用于持久化插件文件）
    private var pluginDirectory: URL

    /// 工具注册中心（由 App 启动时注入 ToolRegistry.shared，解耦 SPM 与 App 层循环依赖）。
    /// 默认 nil：loadPluginTools/unloadPluginTools 在未注入时为 no-op。
    nonisolated(unsafe) public static var toolRegistry: ToolRegistering?

    /// 更新检查闭包（由 App 注入 PluginMarketplaceService.checkUpdate，默认返回 nil）。
    /// 参数为插件 ID，返回新版本号（无更新返回 nil）。
    public var updateChecker: @MainActor (String) async throws -> String? = { _ in nil }

    /// 初始化插件管理器，创建插件目录
    public init() {
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
    public func install(manifest: PluginManifest) throws {
        guard !manifest.id.isEmpty else {
            throw NSError(domain: "PluginManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "插件 ID 不能为空"])
        }
        installedPlugins[manifest.id] = manifest
    }

    /// 卸载插件。先卸载已加载的工具，再从已安装列表中移除。
    /// - Parameter pluginID: 插件 ID
    /// - Throws: 插件未安装时抛出错误
    public func uninstall(pluginID: String) throws {
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
    public var installedPluginList: [PluginManifest] {
        Array(installedPlugins.values)
    }

    /// 检查插件是否已安装
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 已安装返回 true
    public func isInstalled(_ pluginID: String) -> Bool {
        installedPlugins[pluginID] != nil
    }

    // MARK: - 工具加载 / 卸载

    /// 加载插件工具到 ToolRegistry。
    /// 为插件清单中的每个工具创建 PluginToolAdapter 并注册到注入的 ToolRegistering。
    /// - Parameter pluginID: 插件 ID
    /// - Throws: 插件未安装时抛出错误
    public func loadPluginTools(pluginID: String) throws {
        guard let manifest = installedPlugins[pluginID] else {
            throw NSError(domain: "PluginManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(pluginID) 未安装"])
        }
        guard let registry = Self.toolRegistry else {
            // 未注入工具注册中心，跳过注册（no-op）
            return
        }
        for toolDef in manifest.tools {
            let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)
            registry.register(tool: adapter)
        }
    }

    /// 卸载插件工具：从 ToolRegistry 中注销插件声明的所有工具。
    /// - Parameter pluginID: 插件 ID
    /// - Throws: 插件未安装时抛出错误
    public func unloadPluginTools(pluginID: String) throws {
        guard let manifest = installedPlugins[pluginID] else {
            throw NSError(domain: "PluginManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(pluginID) 未安装"])
        }
        guard let registry = Self.toolRegistry else {
            // 未注入工具注册中心，跳关注销（no-op）
            return
        }
        for toolDef in manifest.tools {
            registry.unregister(name: toolDef.name)
        }
    }

    // MARK: - 本地插件扫描

    /// 扫描插件目录（AppSupport/Plugins），加载每个子目录下的 manifest.json + 入口 JS 文件。
    ///
    /// 约定目录结构：
    /// ```
    /// AppSupport/Plugins/
    ///   ├── plugin-a/
    ///   │   ├── manifest.json
    ///   │   └── main.js
    ///   └── plugin-b/
    ///       ├── manifest.json
    ///       └── index.js
    /// ```
    /// 扫描结果会合并到 installedPlugins（已存在的 ID 覆盖为磁盘版本）。
    /// - Returns: 成功扫描并加载的插件清单数组
    @discardableResult
    public func scanLocalPlugins() throws -> [PluginManifest] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: pluginDirectory.path) else {
            return []
        }
        let subDirs = (try? fm.contentsOfDirectory(at: pluginDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var loaded: [PluginManifest] = []
        let decoder = JSONDecoder()
        for dir in subDirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(PluginManifest.self, from: data) else {
                continue
            }
            // 校验入口 JS 文件存在
            let entryURL = dir.appendingPathComponent(manifest.entryPoint)
            guard fm.fileExists(atPath: entryURL.path) else {
                continue
            }
            installedPlugins[manifest.id] = manifest
            loaded.append(manifest)
        }
        return loaded
    }

    /// 获取插件目录下指定插件入口 JS 文件的完整 URL。
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 入口 JS 文件 URL，插件未安装或文件不存在返回 nil
    public func entryFileURL(for pluginID: String) -> URL? {
        guard let manifest = installedPlugins[pluginID] else { return nil }
        return pluginDirectory
            .appendingPathComponent(pluginID, isDirectory: true)
            .appendingPathComponent(manifest.entryPoint)
    }
}

// MARK: - Task 15: 版本管理与热更新

extension PluginManager {
    /// 检查插件是否有版本更新。
    /// 通过注入的 updateChecker 闭包查询 PluginMarketplaceService，默认返回 nil。
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 新版本号字符串，无更新时返回 nil
    public func checkForUpdates(pluginID: String) async throws -> String? {
        return try await updateChecker(pluginID)
    }

    /// 热更新插件：卸载旧工具 → 替换清单 → 加载新工具。
    /// - Parameters:
    ///   - pluginID: 插件 ID
    ///   - newManifest: 新的插件清单
    /// - Throws: 插件未安装时抛出错误
    public func hotUpdate(pluginID: String, newManifest: PluginManifest) throws {
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
    public func getVersion(pluginID: String) -> String? {
        installedPlugins[pluginID]?.version
    }
}
