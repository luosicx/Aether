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

    /// 从 Asset Catalog 加载对应图片资源
    public var image: Image {
        Image(self.rawValue, bundle: nil)
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
        }
    }
}
