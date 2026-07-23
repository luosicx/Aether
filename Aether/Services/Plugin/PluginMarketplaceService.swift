import Foundation
import CryptoKit
import Observation
import AetherFoundation

/// 插件市场服务：负责从远程注册中心获取插件列表、下载插件与签名校验。
///
/// 放在 Aether App 目录（而非 AetherCore SPM 包），因为它需要网络访问与 CryptoKit。
/// PluginManager 通过 `updateChecker` 闭包注入本服务的能力，避免循环依赖。
@MainActor
@Observable
final class PluginMarketplaceService {
    /// 远程插件注册中心 JSON 列表 URL
    let registryURL: URL
    /// 用于网络请求的 URLSession（默认 shared，测试可注入 mock session）
    let urlSession: URLSession
    /// 用于验签的 Ed25519 公钥（base64 编码）。nil 表示跳过验签。
    var publicKeyBase64: String?
    /// 已获取的插件列表
    private(set) var plugins: [PluginManifest] = []
    /// 当前下载中的插件 ID 集合（用于 UI 进度展示）
    private(set) var downloadingPluginIDs: Set<String> = []
    /// 下载进度（0.0 ~ 1.0），key 为插件 ID
    private(set) var downloadProgress: [String: Double] = [:]
    /// 最近一次错误信息（UI 展示）
    private(set) var lastError: String?

    /// 默认注册中心 URL（占位常量，实际请求在测试中 mock）
    static let defaultRegistryURL = URL(string: "https://raw.githubusercontent.com/luosicx/Aether/main/plugins/registry.json")!

    /// 初始化
    /// - Parameters:
    ///   - registryURL: 远程插件列表 JSON URL
    ///   - publicKeyBase64: Ed25519 公钥（base64），nil 跳过验签
    ///   - urlSession: 网络会话（默认 shared，测试可注入）
    init(registryURL: URL = PluginMarketplaceService.defaultRegistryURL,
         publicKeyBase64: String? = nil,
         urlSession: URLSession = .shared) {
        self.registryURL = registryURL
        self.publicKeyBase64 = publicKeyBase64
        self.urlSession = urlSession
    }

    // MARK: - 获取插件列表

    /// 从远程 JSON 获取插件列表，更新 `plugins`。
    /// - Throws: 网络或解码错误
    func fetchPluginList() async throws {
        do {
            let (data, response) = try await urlSession.data(from: registryURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "PluginMarketplaceService", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "获取插件列表失败，HTTP \(http.statusCode)"])
            }
            let decoder = JSONDecoder()
            plugins = try decoder.decode([PluginManifest].self, from: data)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - 下载插件

    /// 下载插件到 AppSupport/Plugins/{pluginID}/，包含 manifest.json 与入口 JS 文件。
    /// 下载完成后验签（如果配置了公钥且 manifest 带 signature）。
    /// - Parameter manifest: 插件清单
    /// - Throws: 下载失败、验签失败或文件写入错误
    func downloadPlugin(manifest: PluginManifest) async throws {
        guard let downloadURL = manifest.downloadURL else {
            throw NSError(domain: "PluginMarketplaceService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "插件 \(manifest.id) 无下载地址"])
        }
        downloadingPluginIDs.insert(manifest.id)
        downloadProgress[manifest.id] = 0
        defer {
            downloadingPluginIDs.remove(manifest.id)
            downloadProgress.removeValue(forKey: manifest.id)
        }

        do {
            let (data, response) = try await urlSession.data(from: downloadURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "PluginMarketplaceService", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "下载插件失败，HTTP \(http.statusCode)"])
            }
            downloadProgress[manifest.id] = 0.5

            // 签名校验（配置了公钥且 manifest 带 signature 时）
            if let pubKey = publicKeyBase64, let signature = manifest.signature {
                guard verifySignature(data: data, signature: signature, publicKeyBase64: pubKey) else {
                    throw NSError(domain: "PluginMarketplaceService", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "插件 \(manifest.id) 签名校验失败"])
                }
            }

            // 写入文件
            let pluginDir = pluginDirectory(for: manifest.id)
            try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

            // 写入 JS 入口文件（下载的内容即为 JS 代码）
            let entryURL = pluginDir.appendingPathComponent(manifest.entryPoint)
            try data.write(to: entryURL, options: .atomic)

            // 写入 manifest.json
            let manifestURL = pluginDir.appendingPathComponent("manifest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)

            downloadProgress[manifest.id] = 1.0
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - 签名校验

    /// Ed25519 签名校验。
    /// - Parameters:
    ///   - data: 原始数据
    ///   - signature: 签名（base64 编码）
    ///   - publicKeyBase64: 公钥（base64 编码）
    /// - Returns: 签名有效返回 true
    func verifySignature(data: Data, signature: String) -> Bool {
        guard let pubKey = publicKeyBase64 else { return true } // 未配置公钥，跳过验签
        return Self.verifySignature(data: data, signature: signature, publicKeyBase64: pubKey)
    }

    /// 静态 Ed25519 签名校验实现。
    /// - Parameters:
    ///   - data: 原始数据
    ///   - signature: 签名（base64 编码）
    ///   - publicKeyBase64: 公钥（base64 编码）
    /// - Returns: 签名有效返回 true
    static func verifySignature(data: Data, signature: String, publicKeyBase64: String) -> Bool {
        guard let pubKeyData = Data(base64Encoded: publicKeyBase64),
              let signatureData = Data(base64Encoded: signature) else {
            return false
        }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
            return publicKey.isValidSignature(signatureData, for: data)
        } catch {
            return false
        }
    }

    // MARK: - 搜索

    /// 本地过滤插件列表（按 name / description / author 模糊匹配）。
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的插件清单
    func searchPlugins(query: String) -> [PluginManifest] {
        guard !query.isEmpty else { return plugins }
        let lowercased = query.lowercased()
        return plugins.filter { manifest in
            manifest.name.lowercased().contains(lowercased)
                || manifest.description.lowercased().contains(lowercased)
                || manifest.author.lowercased().contains(lowercased)
        }
    }

    // MARK: - 更新检查（供 PluginManager.updateChecker 注入）

    /// 检查指定插件是否有新版本。
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 新版本号，无更新或插件不在市场返回 nil
    func checkUpdate(for pluginID: String) async throws -> String? {
        // 确保插件列表已加载
        if plugins.isEmpty {
            try await fetchPluginList()
        }
        return plugins.first(where: { $0.id == pluginID })?.version
    }

    // MARK: - Private

    /// 获取插件目录 URL：AppSupport/Plugins/{pluginID}/
    private func pluginDirectory(for pluginID: String) -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return appSupport
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
    }
}
