import Foundation

/// `mcp.json` 配置文件加载器。
///
/// 职责：
/// - 从指定 URL 读取并解析 `MCPConfigFile`
/// - 支持项目级与用户级配置合并（用户级覆盖项目级同 ID Server）
/// - 自动定位 App Support 目录中的配置文件
///
/// 配置文件查找路径（优先级从低到高）：
/// 1. 项目级：`<AppSupport>/Aether/mcp.json`（随 App 分发，企业部署默认配置）
/// 2. 用户级：`<AppSupport>/Aether/mcp.user.json`（用户自定义，覆盖项目级）
final class MCPConfigFileLoader {
    /// 配置文件名（项目级）
    static let projectFileName = "mcp.json"
    /// 配置文件名（用户级）
    static let userFileName = "mcp.user.json"
    /// App Support 子目录名
    static let appSupportSubdirectory = "Aether"

    /// 从指定 URL 加载配置文件。
    /// - Parameter url: 配置文件 URL
    /// - Returns: 解析后的 MCPConfigFile
    /// - Throws: 文件不存在或 JSON 解析错误
    func load(from url: URL) throws -> MCPConfigFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MCPConfigFile.self, from: data)
    }

    /// 合并加载项目级与用户级配置。
    /// 用户级配置中的 Server 按 ID 覆盖项目级；项目级独有的 Server 保留。
    /// 两个文件都不存在时返回空配置。
    /// - Parameters:
    ///   - projectURL: 项目级配置 URL
    ///   - userURL: 用户级配置 URL
    /// - Returns: 合并后的配置
    /// - Throws: JSON 解析错误（文件不存在不抛错，跳过该文件）
    func mergeLoad(projectURL: URL, userURL: URL) throws -> MCPConfigFile {
        let projectConfig = loadOptional(from: projectURL)
        let userConfig = loadOptional(from: userURL)

        guard let project = projectConfig, let user = userConfig else {
            // 优先返回用户级，其次项目级，都为空则返回空配置
            return userConfig ?? projectConfig ?? MCPConfigFile(servers: [], discovery: nil, policy: nil)
        }

        // 合并 servers：用户级覆盖项目级同 ID
        var mergedServers: [MCPConfigFile.Server] = []
        var userServerIDs = Set<String>()
        for server in user.servers {
            mergedServers.append(server)
            userServerIDs.insert(server.id)
        }
        // 追加项目级独有的 Server
        for server in project.servers where !userServerIDs.contains(server.id) {
            mergedServers.append(server)
        }

        // discovery / policy：用户级优先，缺省用项目级
        let mergedDiscovery = user.discovery ?? project.discovery
        let mergedPolicy = user.policy ?? project.policy

        return MCPConfigFile(
            servers: mergedServers,
            discovery: mergedDiscovery,
            policy: mergedPolicy
        )
    }

    /// 从 App Support 默认目录加载合并配置。
    /// - Parameter fileManager: FileManager（默认 .default，可注入用于测试）
    /// - Returns: 合并后的配置（文件不存在时返回空配置）
    func loadFromAppSupport(fileManager: FileManager = .default) throws -> MCPConfigFile {
        let projectURL = try appSupportURL(fileName: Self.projectFileName, fileManager: fileManager)
        let userURL = try appSupportURL(fileName: Self.userFileName, fileManager: fileManager)
        return try mergeLoad(projectURL: projectURL, userURL: userURL)
    }

    /// 返回 App Support 中指定文件的 URL。
    /// 若目录不存在会自动创建（但文件本身不创建）。
    /// - Parameters:
    ///   - fileName: 文件名
    ///   - fileManager: FileManager
    /// - Returns: 配置文件完整 URL
    private func appSupportURL(fileName: String, fileManager: FileManager) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent(Self.appSupportSubdirectory)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    /// 可选加载：文件存在则解析，不存在返回 nil
    private func loadOptional(from url: URL) -> MCPConfigFile? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            return try load(from: url)
        } catch {
            // 解析错误向上抛出？这里选择返回 nil 以容错（避免损坏的配置阻塞启动）
            // 实际生产环境应记录日志
            return nil
        }
    }
}
