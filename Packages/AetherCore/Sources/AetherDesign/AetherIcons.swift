import SwiftUI

/// Aether 图标分类：用于组织图标资源与设计规范
public enum AetherIconCategory: String, CaseIterable {
    case navigation
    case feature
    case status
    case health
}

/// Aether 自定义图标集：统一管理品牌专属图标资源
/// 优先从 Asset Catalog 加载 SVG 资源；资源不存在时使用 AetherIconRenderer 作为 fallback
public enum AetherIcon: String, CaseIterable {
    // MARK: - 品牌与历史图标（v1.0）

    /// Aether 品牌 Logo
    case logo = "aether.logo"
    /// MCP（Model Context Protocol）连接节点
    case mcp = "aether.mcp"
    /// 记忆 / 知识库
    case memory = "aether.memory"
    /// Agent 智能体
    case agent = "aether.agent"
    /// 插件
    case plugin = "aether.plugin"
    /// 分支 / 版本
    case branch = "aether.branch"
    /// 主题 / 调色板
    case theme = "aether.theme"
    /// 人设 / 角色
    case persona = "aether.persona"

    // MARK: - v1.1: 占位图标（symbolset 命名空间，待设计资源就绪）

    /// 对话气泡（ConversationList / MenuBarPanel 等会话场景）
    case bubble = "aether-bubble"
    /// 知识库（KnowledgeBaseView 主图标）
    case knowledge = "aether-knowledge"
    /// 端侧模型芯片（OnDeviceModelView）
    case chip = "aether-chip"
    /// 健康洞察（HealthSettingsView / 健康相关卡片）
    case heartPulse = "aether-heart-pulse"
    /// 快捷指令（Shortcuts 集成入口）
    case shortcut = "aether-shortcut"
    /// 云端（云同步 / 云模型）
    case cloud = "aether-cloud"
    /// 安全防护（隐私 / 加密入口）
    case shield = "aether-shield"
    /// MCP 协议图标（与 .mcp 区分：用于 symbolset 资源命名空间）
    case mcpSymbol = "aether-mcp"
    /// 工具调用（ToolRegistry / Tool 调用卡片）
    case tool = "aether-tool"
    /// 导出（ConversationExporter / 分享入口）
    case exportIcon = "aether-export"

    // MARK: - v1.2 新增：导航类图标

    /// 设置入口（SettingsView tab / sidebar）
    case settings = "aether-settings"
    /// 对话历史（ConversationList sidebar）
    case history = "aether-history"
    /// 新建对话（顶栏 + 按钮）
    case newConversation = "aether-new-conversation"
    /// 搜索（全局搜索 / 命令面板）
    case search = "aether-search"

    // MARK: - v1.2 新增：功能类图标

    /// 端侧模型下载（OnDeviceModelDownloader）
    case modelDownload = "aether-model-download"
    /// Agent 协作图（DAGVisualizationView）
    case agentCollaboration = "aether-agent-collaboration"
    /// 插件市场（PluginMarketplaceView）
    case marketplace = "aether-marketplace"

    // MARK: - v1.2 新增：状态类图标

    /// 同步中（iCloud / 远程同步状态指示）
    case syncing = "aether-syncing"
    /// 离线（无网络 / 离线模式）
    case offline = "aether-offline"
    /// 加载中（异步加载占位）
    case loading = "aether-loading"
    /// 错误（错误状态 / 错误覆盖层）
    case error = "aether-error"

    /// 从 Asset Catalog 加载对应图片资源
    /// 专属 SVG 资源就绪后可使用 `Image(self.rawValue, bundle: nil)`
    public var image: Image {
        Image(self.rawValue, bundle: nil)
    }

    /// 兜底 SF Symbol 名称
    /// 当 Aether 专属 SVG 资源未就绪时，使用对应 SF Symbol 作为 placeholder
    /// 资源就绪后视图层可平滑切换为 `.image` 加载专属资源
    public var fallbackSystemName: String {
        switch self {
        case .logo: return "sparkles"
        case .mcp: return "network"
        case .memory: return "brain.head.profile"
        case .agent: return "cpu"
        case .plugin: return "puzzlepiece.extension"
        case .branch: return "arrow.triangle.branch"
        case .theme: return "paintpalette"
        case .persona: return "person.circle"
        case .bubble: return "bubble.left.and.bubble.right"
        case .knowledge: return "books.vertical.fill"
        case .chip: return "cpu"
        case .heartPulse: return "heart.text.square"
        case .shortcut: return "link"
        case .cloud: return "icloud"
        case .shield: return "shield.lefthalf.filled"
        case .mcpSymbol: return "network"
        case .tool: return "wrench.and.screwdriver"
        case .exportIcon: return "square.and.arrow.up"
        // v1.2 导航类
        case .settings: return "gearshape"
        case .history: return "clock.arrow.circlepath"
        case .newConversation: return "square.and.pencil"
        case .search: return "magnifyingglass"
        // v1.2 功能类
        case .modelDownload: return "arrow.down.circle"
        case .agentCollaboration: return "person.2.wave.2"
        case .marketplace: return "cart.fill"
        // v1.2 状态类
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .loading: return "progress.indicator"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// 兜底系统图标视图
    /// 专属 SVG 资源未就绪时使用；资源就绪后视图层切换为 `.image`
    public var systemImage: Image {
        Image(systemName: fallbackSystemName)
    }

    /// 无障碍标签
    public var accessibilityLabel: String {
        switch self {
        case .logo: return "Aether Logo"
        case .mcp: return "MCP 连接"
        case .memory: return "记忆"
        case .agent: return "智能体"
        case .plugin: return "插件"
        case .branch: return "分支"
        case .theme: return "主题"
        case .persona: return "人设"
        case .bubble: return "对话"
        case .knowledge: return "知识库"
        case .chip: return "端侧模型"
        case .heartPulse: return "健康洞察"
        case .shortcut: return "快捷指令"
        case .cloud: return "云端"
        case .shield: return "安全"
        case .mcpSymbol: return "MCP 协议"
        case .tool: return "工具调用"
        case .exportIcon: return "导出"
        // v1.2 导航类
        case .settings: return "设置"
        case .history: return "历史"
        case .newConversation: return "新建对话"
        case .search: return "搜索"
        // v1.2 功能类
        case .modelDownload: return "下载模型"
        case .agentCollaboration: return "智能体协作"
        case .marketplace: return "插件市场"
        // v1.2 状态类
        case .syncing: return "同步中"
        case .offline: return "离线"
        case .loading: return "加载中"
        case .error: return "错误"
        }
    }

    /// 图标所属分类
    public var category: AetherIconCategory {
        switch self {
        // 导航类
        case .bubble, .history, .newConversation, .search, .settings:
            return .navigation
        // 功能类（含品牌 Logo）
        case .logo, .mcp, .memory, .agent, .plugin, .branch, .theme, .persona,
             .knowledge, .chip, .shortcut, .cloud, .tool, .exportIcon,
             .modelDownload, .agentCollaboration, .marketplace:
            return .feature
        // 状态类
        case .syncing, .offline, .loading, .error:
            return .status
        // 健康类
        case .heartPulse, .shield, .mcpSymbol:
            return .health
        }
    }
}

// MARK: - v1.2: Image(aetherIcon:) 便捷初始化器

public extension Image {
    /// 用 AetherIcon 创建图标视图
    /// 优先使用专属 SVG 资源（Asset Catalog）；未就绪时调用方应回退到 `systemImage`
    /// - Parameter aetherIcon: Aether 图标枚举值
    init(aetherIcon: AetherIcon) {
        // 优先尝试加载专属资源；失败回退到 SF Symbol
        // 注意：Image(name:, bundle:) 在资源不存在时返回空图像，
        // 因此实际视图层应使用 `Image(systemName: aetherIcon.fallbackSystemName)` 或 AetherIconRenderer
        self.init(aetherIcon.rawValue, bundle: nil)
    }
}
