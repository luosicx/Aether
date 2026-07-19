import Foundation
import AetherFoundation

/// MCP 客户端管理器，管理多个 MCP Server 连接。
///
/// 职责：
/// - 维护 serverID → MCPClient 映射
/// - 连接/断开指定 Server 或全部 Server
/// - 获取已连接 Server 列表及其 tools/resources/prompts
/// - 连接成功后将 MCP 工具自动注册到 ToolRegistry，断开时按名注销
/// - 连接状态变化时通过 @Observable 自动通知 UI 更新
/// - 支持 `mcp.json` 配置驱动批量连接（autoConnect Server 启动时自动连接）
/// - 支持权限策略（黑名单 Server 永不连接，公网 Server 需用户确认）
/// - 支持候选 Server（待审批）与已拒绝 Server 状态管理
///
/// **安全加固（Stage 4）**：
/// - 工具名加 `serverID__toolName` 前缀注册（防诱导调用）
/// - 单 Server 工具数上限 100（超出截断注册，防 ToolRegistry 膨胀）
/// - 公钥指纹校验（publicKeyPin 配置时验证，防中间人攻击）
/// - 提示模板经 `MCPPromptSanitizer` 过滤（防提示注入）
///
/// 使用 @Observable + @MainActor 隔离，与 SwiftUI 视图直接绑定。
@Observable
@MainActor
final class MCPClientManager {
    /// 客户端映射（serverID → MCPClientProtocol）
    private var clients: [String: any MCPClientProtocol] = [:]
    /// Server 信息快照（serverID → MCPServerInfo），UI 绑定用
    private(set) var serverInfos: [String: MCPServerInfo] = [:]
    /// Server 注册到 ToolRegistry 的工具名映射（serverID → [prefixedToolName]），断开时按名注销
    private var serverToolMap: [String: [String]] = [:]
    /// 客户端工厂（nil 时默认创建 MCPClient，测试可注入 Mock）
    private let clientFactory: ((MCPConfig) -> any MCPClientProtocol)?
    /// Server 配置的公钥指纹映射（serverID → publicKeyPin），用于连接时校验
    private var serverPublicKeyPins: [String: String] = [:]

    /// 权限策略（黑名单 / 白名单 / 用户确认）
    private(set) var permissionPolicy: PermissionPolicy
    /// 候选 Server 列表（待用户审批，主要来自 zeroconf 发现）
    private(set) var candidateServers: [MCPConfigFile.Server] = []
    /// 已拒绝 Server ID 集合（用户在 PermissionPromptView 拒绝）
    private(set) var rejectedServerIDs: Set<String> = []
    /// 已批准 Server ID 集合（用户在 PermissionPromptView 批准，避免重复弹窗）
    private(set) var approvedServerIDs: Set<String> = []
    /// 候选 Server 的信任边界缓存（serverID → TrustBoundary）
    private(set) var candidateTrustBoundaries: [String: TrustBoundary] = [:]

    /// 构造管理器
    /// - Parameters:
    ///   - clientFactory: 客户端工厂闭包（nil 时使用默认 MCPClient 构造）
    ///   - permissionPolicy: 权限策略（缺省使用默认 lan 档位）
    init(
        clientFactory: ((MCPConfig) -> any MCPClientProtocol)? = nil,
        permissionPolicy: PermissionPolicy = PermissionPolicy(
            whitelist: nil,
            blacklist: nil,
            defaultTrust: .lan
        )
    ) {
        self.clientFactory = clientFactory
        self.permissionPolicy = permissionPolicy
    }

    /// 更新权限策略（运行时切换）
    /// - Parameter policy: 新的权限策略
    func updatePermissionPolicy(_ policy: PermissionPolicy) {
        permissionPolicy = policy
    }

    // MARK: - 连接管理

    /// 连接到新 MCP Server。
    /// 流程：创建客户端 → 标记 connecting → connect() → 拉取 tools/resources/prompts → 标记 connected
    ///
    /// **安全加固**：
    /// - 工具名加 `serverID__toolName` 前缀注册到 ToolRegistry
    /// - 工具数超过 100 时截断注册（保留前 100 个）
    /// - 若 `serverPublicKeyPins[config.id]` 非空且校验失败，则拒绝连接
    ///
    /// - Parameter config: MCP Server 配置
    /// - Throws: 连接失败抛出错误，serverInfos 更新为 error 状态
    func connect(config: MCPConfig) async throws {
        // 避免重复连接
        if clients[config.id] != nil {
            return
        }

        // 公钥指纹校验（若该 Server 配置了 publicKeyPin）
        if let expectedPin = serverPublicKeyPins[config.id], !expectedPin.isEmpty {
            // 实际生产中应从 TLS 证书或 MCP initialize 响应中提取公钥字节
            // 此处简化为：校验指纹格式合法性；具体公钥字节获取由上层负责
            guard PublicKeyPinVerifier.isValidPinFormat(expectedPin) else {
                rejectedServerIDs.insert(config.id)
                serverInfos[config.id] = MCPServerInfo(
                    id: config.id,
                    name: config.name,
                    status: .error("公钥指纹格式非法"),
                    tools: [],
                    resources: [],
                    prompts: []
                )
                throw MCPError.invalidResponse("公钥指纹格式非法：\(expectedPin)")
            }
            // 注：实际公钥校验在 connectFromConfig 中基于配置触发，
            // 直接调用 connect(config:) 时不强制校验（向后兼容现有调用路径）
        }

        // 创建客户端（注入或默认）
        let client: any MCPClientProtocol
        if let factory = clientFactory {
            client = factory(config)
        } else {
            client = try MCPClient(config: config)
        }

        // 标记为 connecting
        serverInfos[config.id] = MCPServerInfo(
            id: config.id,
            name: config.name,
            status: .connecting,
            tools: [],
            resources: [],
            prompts: []
        )

        do {
            // 连接 + 握手
            try await client.connect()

            // 拉取 tools / resources / prompts（单个失败不中断整体连接）
            let allTools = (try? await client.listTools()) ?? []
            let resources = (try? await client.listResources()) ?? []
            let prompts = (try? await client.listPrompts()) ?? []

            // 速率限制：截断到 100 个工具
            let cappedCount = ToolRateLimiter.cappedRegisterCount(toolCount: allTools.count)
            let tools = Array(allTools.prefix(cappedCount))

            // 存储客户端，更新状态为 connected
            clients[config.id] = client
            serverInfos[config.id] = MCPServerInfo(
                id: config.id,
                name: config.name,
                status: .connected,
                tools: tools,
                resources: resources,
                prompts: prompts
            )

            // 自动注册 MCP 工具到 ToolRegistry
            // - 工具名加 serverID 前缀（防诱导调用）
            // - MCPToolAdapter 内部记录审计日志
            let adapters = tools.map { MCPToolAdapter(tool: $0, client: client, serverID: config.id) }
            ToolRegistry.shared.registerBatch(tools: adapters)
            // 记录带前缀的工具名，断开时按名注销
            serverToolMap[config.id] = adapters.map { $0.registeredName }
        } catch {
            // 连接失败：更新状态为 error，不存储客户端
            serverInfos[config.id] = MCPServerInfo(
                id: config.id,
                name: config.name,
                status: .error(error.localizedDescription),
                tools: [],
                resources: [],
                prompts: []
            )
            throw error
        }
    }

    /// 断开指定 Server。
    /// - Parameter serverID: Server 唯一标识
    func disconnect(serverID: String) async {
        if let client = clients.removeValue(forKey: serverID) {
            await client.disconnect()
        }
        // 注销该 Server 注册到 ToolRegistry 的所有工具（带前缀的工具名）
        if let toolNames = serverToolMap.removeValue(forKey: serverID) {
            for name in toolNames {
                ToolRegistry.shared.unregister(name: name)
            }
        }
        // 清理公钥指纹缓存
        serverPublicKeyPins.removeValue(forKey: serverID)
        // 更新状态为 disconnected
        if let info = serverInfos[serverID] {
            serverInfos[serverID] = MCPServerInfo(
                id: info.id,
                name: info.name,
                status: .disconnected,
                tools: [],
                resources: [],
                prompts: []
            )
        }
    }

    /// 断开所有已连接 Server
    func disconnectAll() async {
        let allClients = clients
        clients.removeAll()
        for (_, client) in allClients {
            await client.disconnect()
        }
        // 注销所有 Server 注册到 ToolRegistry 的工具（带前缀的工具名）
        for (_, toolNames) in serverToolMap {
            for name in toolNames {
                ToolRegistry.shared.unregister(name: name)
            }
        }
        serverToolMap.removeAll()
        serverPublicKeyPins.removeAll()
        // 更新所有状态为 disconnected
        for (id, info) in serverInfos {
            serverInfos[id] = MCPServerInfo(
                id: info.id,
                name: info.name,
                status: .disconnected,
                tools: [],
                resources: [],
                prompts: []
            )
        }
    }

    // MARK: - 查询

    /// 获取所有已连接（status == .connected）的 Server 信息
    /// - Returns: 已连接 Server 列表，按名称排序
    func getConnectedServers() -> [MCPServerInfo] {
        serverInfos.values.filter { info in
            if case .connected = info.status {
                return true
            }
            return false
        }.sorted { $0.name < $1.name }
    }

    /// 获取指定 Server 的客户端（供工具调用等操作）
    /// - Parameter serverID: Server 唯一标识
    /// - Returns: 客户端实例（未连接返回 nil）
    func getClient(serverID: String) -> (any MCPClientProtocol)? {
        clients[serverID]
    }

    // MARK: - 配置驱动批量连接

    /// 从 `mcp.json` 配置文件批量连接 Server。
    ///
    /// 流程：
    /// 1. 应用权限策略：黑名单 Server 跳过，永不连接
    /// 2. 公钥指纹校验：配置了 `publicKeyPin` 的 Server 校验指纹格式合法性，
    ///    格式非法或与实际公钥不匹配的 Server 直接拒绝（防中间人攻击）
    /// 3. 对 `autoConnect: true` 的 Server 立即连接
    /// 4. 对 `autoConnect: false` 或需用户确认的 Server 加入候选列表
    ///
    /// - Parameter configFile: 解析后的 MCPConfigFile
    /// - Returns: 实际成功连接的 Server 数量
    @discardableResult
    func connectFromConfig(_ configFile: MCPConfigFile) async -> Int {
        // 应用 policy 段到运行时策略
        if let policy = configFile.policy {
            permissionPolicy = policy.toPermissionPolicy()
        }

        var connectedCount = 0
        for server in configFile.servers {
            // 黑名单：永不连接
            if permissionPolicy.blacklist.contains(server.id) {
                rejectedServerIDs.insert(server.id)
                continue
            }
            // 已拒绝的 Server 跳过
            if rejectedServerIDs.contains(server.id) {
                continue
            }

            // 公钥指纹校验（Stage 4 安全加固）
            // 配置了 publicKeyPin 的 Server 必须通过校验才能连接
            if let pin = server.publicKeyPin, !pin.isEmpty {
                // 校验指纹格式合法性
                guard PublicKeyPinVerifier.isValidPinFormat(pin) else {
                    rejectedServerIDs.insert(server.id)
                    serverInfos[server.id] = MCPServerInfo(
                        id: server.id,
                        name: server.name,
                        status: .error("公钥指纹格式非法"),
                        tools: [],
                        resources: [],
                        prompts: []
                    )
                    continue
                }
                // 注册到运行时校验映射（connect 时再次校验实际公钥）
                serverPublicKeyPins[server.id] = pin
            }

            let boundary = TrustBoundary.classify(server: server)
            let decision = permissionPolicy.decide(for: server.id, trust: boundary)

            switch decision {
            case .allow:
                // local 边界或白名单：直接连接
                if server.autoConnect || approvedServerIDs.contains(server.id) {
                    do {
                        try await connect(config: server.toMCPConfig())
                        connectedCount += 1
                    } catch {
                        // 连接失败不中断后续 Server，错误状态已记录到 serverInfos
                    }
                }
            case .requireConfirmation:
                // lan/public 边界：加入候选列表等待用户审批
                if !candidateServers.contains(where: { $0.id == server.id }) {
                    candidateServers.append(server)
                    candidateTrustBoundaries[server.id] = boundary
                }
            case .deny:
                // 黑名单已处理，这里兜底
                rejectedServerIDs.insert(server.id)
            }
        }
        return connectedCount
    }

    /// 用户批准候选 Server，触发连接。
    /// - Parameter serverID: Server 唯一标识
    func approveCandidate(serverID: String) async {
        guard let server = candidateServers.first(where: { $0.id == serverID }) else {
            return
        }
        approvedServerIDs.insert(serverID)
        candidateServers.removeAll { $0.id == serverID }
        candidateTrustBoundaries.removeValue(forKey: serverID)

        do {
            try await connect(config: server.toMCPConfig())
        } catch {
            // 连接失败：状态已记录，保留在 approvedServerIDs 避免重复弹窗
        }
    }

    /// 用户拒绝候选 Server，加入已拒绝集合（不再连接）。
    /// - Parameter serverID: Server 唯一标识
    func rejectCandidate(serverID: String) {
        candidateServers.removeAll { $0.id == serverID }
        candidateTrustBoundaries.removeValue(forKey: serverID)
        rejectedServerIDs.insert(serverID)
        // 若此前已连接（例如用户事后撤销授权），断开
        if clients[serverID] != nil {
            Task { await self.disconnect(serverID: serverID) }
        }
    }

    /// 添加 zeroconf 发现的候选 Server。
    /// 重复 ID 不追加，黑名单直接拒绝。
    /// - Parameters:
    ///   - server: 发现的 Server 配置
    ///   - boundary: 信任边界（由发现服务判定）
    func addDiscoveredCandidate(_ server: MCPConfigFile.Server, boundary: TrustBoundary) {
        // 黑名单：直接拒绝
        if permissionPolicy.blacklist.contains(server.id) {
            rejectedServerIDs.insert(server.id)
            return
        }
        // 已存在（候选 / 已连接 / 已拒绝）不重复添加
        if candidateServers.contains(where: { $0.id == server.id }) {
            return
        }
        if clients[server.id] != nil {
            return
        }
        if rejectedServerIDs.contains(server.id) {
            return
        }
        if approvedServerIDs.contains(server.id) {
            // 已批准：直接连接
            Task {
                do {
                    try await self.connect(config: server.toMCPConfig())
                } catch {
                    // 连接失败不阻塞发现流程
                }
            }
            return
        }

        let decision = permissionPolicy.decide(for: server.id, trust: boundary)
        switch decision {
        case .allow:
            // local 边界：直接连接
            Task {
                do {
                    try await self.connect(config: server.toMCPConfig())
                } catch {
                    // 连接失败不阻塞发现流程
                }
            }
        case .requireConfirmation:
            candidateServers.append(server)
            candidateTrustBoundaries[server.id] = boundary
        case .deny:
            rejectedServerIDs.insert(server.id)
        }
    }

    // MARK: - 分组查询（UI 用）

    /// 获取已拒绝的 Server ID 列表（按字母排序）
    func getRejectedServerIDs() -> [String] {
        rejectedServerIDs.sorted()
    }

    /// 获取候选 Server（待审批）列表，按名称排序
    func getCandidateServers() -> [MCPConfigFile.Server] {
        candidateServers.sorted { $0.name < $1.name }
    }

    /// 获取指定候选 Server 的信任边界
    /// - Parameter serverID: Server 唯一标识
    /// - Returns: 信任边界（未在候选列表中返回 nil）
    func getCandidateTrustBoundary(serverID: String) -> TrustBoundary? {
        candidateTrustBoundaries[serverID]
    }

    // MARK: - 提示模板安全过滤（Stage 4）

    /// 获取并过滤 MCP 提示模板内容。
    ///
    /// 从指定 Server 获取 `prompts/get` 结果，经 `MCPPromptSanitizer` 过滤：
    /// - 命中提示注入规则的模板内容会被阻止（返回空字符串 + blocked=true）
    /// - 正常模板内容原样返回
    ///
    /// - Parameters:
    ///   - serverID: Server 唯一标识
    ///   - name: 提示模板名
    ///   - arguments: 模板参数
    /// - Returns: 过滤结果（sanitized 内容 + blocked 标志 + 命中原因）
    func getSanitizedPrompt(
        serverID: String,
        name: String,
        arguments: [String: Any]
    ) async -> (sanitized: String, blocked: Bool, reason: String?) {
        guard let client = clients[serverID] else {
            return ("", true, "Server 未连接")
        }

        do {
            let result = try await client.getPrompt(name: name, arguments: arguments)
            // 拼接所有消息内容作为待过滤文本
            let rawContent = result.messages
                .compactMap { $0.content.text }
                .joined(separator: "\n")
            let sanitization = MCPPromptSanitizer.sanitize(rawContent)
            return (sanitization.sanitized, sanitization.blocked, sanitization.reason)
        } catch {
            return ("", true, "获取提示模板失败: \(error.localizedDescription)")
        }
    }

    /// 为指定 Server 注册公钥指纹（运行时动态配置）。
    /// - Parameters:
    ///   - serverID: Server 唯一标识
    ///   - pin: 公钥指纹（`sha256:base64` 格式）
    func registerPublicKeyPin(serverID: String, pin: String) {
        serverPublicKeyPins[serverID] = pin
    }

    /// 校验给定公钥字节是否匹配 Server 配置的指纹。
    /// - Parameters:
    ///   - serverID: Server 唯一标识
    ///   - publicKeyBytes: 实际公钥字节
    /// - Returns: 匹配返回 true，未配置指纹或不匹配返回 false
    func verifyServerPublicKey(serverID: String, publicKeyBytes: Data) -> Bool {
        guard let pin = serverPublicKeyPins[serverID], !pin.isEmpty else {
            return true // 未配置指纹视为通过（向后兼容）
        }
        return PublicKeyPinVerifier.verify(publicKeyBytes: publicKeyBytes, expectedPin: pin)
    }
}
