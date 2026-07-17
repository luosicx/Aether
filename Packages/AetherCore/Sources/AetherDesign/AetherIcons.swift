import SwiftUI

/// Aether 自定义图标集：统一管理品牌专属图标资源
/// 优先从 Asset Catalog 加载 SVG 资源；资源不存在时使用 AetherIconRenderer 作为 fallback
public enum AetherIcon: String, CaseIterable {
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

    // MARK: - Task 17: Aether 专属图标（symbolset 占位，待设计资源就绪）

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
        }
    }
}
