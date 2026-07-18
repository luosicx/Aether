import Foundation
import AetherFoundation

/// `mcp.json` 配置文件根模型。
///
/// 对应规划文档 3.3 节的 JSON 格式，包含三段：
/// - servers：Server 列表（含传输方式、信任档位、自动连接、工具白/黑名单）
/// - discovery：动态发现配置（zeroconf 开关、扫描类型、扫描间隔）
/// - policy：全局权限策略（默认信任档位、Server 白/黑名单）
public struct MCPConfigFile: Codable, Sendable, Equatable {
    /// Server 列表
    public let servers: [Server]
    /// 动态发现配置（可选，缺省不启用 zeroconf）
    public let discovery: Discovery?
    /// 全局权限策略（可选，缺省使用默认值）
    public let policy: Policy?

    private enum CodingKeys: String, CodingKey {
        case servers
        case discovery
        case policy
    }

    public init(servers: [Server], discovery: Discovery?, policy: Policy?) {
        self.servers = servers
        self.discovery = discovery
        self.policy = policy
    }

    // MARK: - Server

    /// 单个 MCP Server 配置（mcp.json 中的 server 对象）。
    public struct Server: Codable, Sendable, Equatable, Hashable {
        /// 唯一标识
        public let id: String
        /// 显示名称
        public let name: String
        /// 传输方式（复用 MCPConfig.Transport）
        public let transport: MCPConfig.Transport
        /// 信任档位（缺省 lan）
        public let trust: TrustBoundary
        /// 是否启动时自动连接（缺省 false）
        public let autoConnect: Bool
        /// 工具白名单（自动放行，nil 表示全部需确认）
        public let toolWhitelist: [String]?
        /// 工具黑名单（自动拒绝）
        public let toolBlacklist: [String]?
        /// Server 公钥指纹（SHA-256，格式 `sha256:base64`，用于防中间人攻击）
        public let publicKeyPin: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case transport
            case trust
            case autoConnect
            case toolWhitelist
            case toolBlacklist
            case publicKeyPin
        }

        /// 构造 Server 配置
        /// - Parameters:
        ///   - id: 唯一标识
        ///   - name: 显示名称
        ///   - transport: 传输方式
        ///   - trust: 信任档位（缺省 lan）
        ///   - autoConnect: 是否自动连接（缺省 false）
        ///   - toolPolicy: 工具白/黑名单策略（缺省 nil，表示全部需确认）
        ///   - publicKeyPin: 公钥指纹（缺省 nil）
        public init(
            id: String,
            name: String,
            transport: MCPConfig.Transport,
            trust: TrustBoundary = .lan,
            autoConnect: Bool = false,
            toolPolicy: ToolPolicy? = nil,
            publicKeyPin: String? = nil
        ) {
            self.id = id
            self.name = name
            self.transport = transport
            self.trust = trust
            self.autoConnect = autoConnect
            self.toolWhitelist = toolPolicy?.whitelist
            self.toolBlacklist = toolPolicy?.blacklist
            self.publicKeyPin = publicKeyPin
        }

        /// 自定义解码：trust 缺省为 .lan，autoConnect 缺省为 false
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            transport = try container.decode(MCPConfig.Transport.self, forKey: .transport)
            // trust 缺省为 .lan
            trust = try container.decodeIfPresent(TrustBoundary.self, forKey: .trust) ?? .lan
            // autoConnect 缺省为 false
            autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
            toolWhitelist = try container.decodeIfPresent([String].self, forKey: .toolWhitelist)
            toolBlacklist = try container.decodeIfPresent([String].self, forKey: .toolBlacklist)
            publicKeyPin = try container.decodeIfPresent(String.self, forKey: .publicKeyPin)
        }

        /// 转换为 MCPConfig（用于 MCPClientManager.connect）。
        /// autoConnect 映射为 enabled 字段。
        public func toMCPConfig() -> MCPConfig {
            MCPConfig(
                id: id,
                name: name,
                transport: transport,
                enabled: autoConnect
            )
        }
    }

    /// Server 的工具白/黑名单策略（合并以减少构造器参数数量）。
    public struct ToolPolicy: Codable, Sendable, Equatable, Hashable {
        /// 工具白名单（自动放行，nil 表示全部需确认）
        public let whitelist: [String]?
        /// 工具黑名单（自动拒绝）
        public let blacklist: [String]?

        /// 构造 ToolPolicy
        /// - Parameters:
        ///   - whitelist: 工具白名单（nil 表示全部需确认）
        ///   - blacklist: 工具黑名单
        public init(whitelist: [String]? = nil, blacklist: [String]? = nil) {
            self.whitelist = whitelist
            self.blacklist = blacklist
        }
    }

    // MARK: - Discovery

    /// 动态发现配置。
    public struct Discovery: Codable, Sendable, Equatable {
        /// 是否启用 zeroconf 扫描
        public let zeroconf: Bool
        /// Bonjour 服务类型（缺省 `_aether_mcp._tcp.`）
        public let zeroconfType: String
        /// 扫描间隔（秒，缺省 60）
        public let scanIntervalSec: Int

        private enum CodingKeys: String, CodingKey {
            case zeroconf
            case zeroconfType
            case scanIntervalSec
        }

        public init(zeroconf: Bool, zeroconfType: String, scanIntervalSec: Int) {
            self.zeroconf = zeroconf
            self.zeroconfType = zeroconfType
            self.scanIntervalSec = scanIntervalSec
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            zeroconf = try container.decodeIfPresent(Bool.self, forKey: .zeroconf) ?? false
            zeroconfType = try container.decodeIfPresent(String.self, forKey: .zeroconfType) ?? "_aether_mcp._tcp."
            scanIntervalSec = try container.decodeIfPresent(Int.self, forKey: .scanIntervalSec) ?? 60
        }
    }

    // MARK: - Policy

    /// 全局权限策略。
    public struct Policy: Codable, Sendable, Equatable {
        /// 默认信任档位（缺省 lan）
        public let defaultTrust: TrustBoundary
        /// Server 黑名单（自动拒绝，优先级最高）
        public let blacklist: [String]?
        /// Server 白名单（自动放行）
        public let whitelist: [String]?

        private enum CodingKeys: String, CodingKey {
            case defaultTrust
            case blacklist
            case whitelist
        }

        public init(defaultTrust: TrustBoundary, blacklist: [String]?, whitelist: [String]?) {
            self.defaultTrust = defaultTrust
            self.blacklist = blacklist
            self.whitelist = whitelist
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            defaultTrust = try container.decodeIfPresent(TrustBoundary.self, forKey: .defaultTrust) ?? .lan
            blacklist = try container.decodeIfPresent([String].self, forKey: .blacklist)
            whitelist = try container.decodeIfPresent([String].self, forKey: .whitelist)
        }

        /// 转换为运行时 PermissionPolicy
        public func toPermissionPolicy() -> PermissionPolicy {
            PermissionPolicy(
                whitelist: whitelist,
                blacklist: blacklist,
                defaultTrust: defaultTrust
            )
        }
    }
}
