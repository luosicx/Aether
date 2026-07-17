import SwiftUI

// MARK: - PermissionPromptInfo

/// 权限审批弹窗的数据模型。
///
/// 包含 Server 元信息、工具列表、信任档位、公钥指纹等，
/// 供 `PermissionPromptView` 展示。
struct PermissionPromptInfo: Equatable, Sendable {
    /// Server 唯一标识
    let serverID: String
    /// Server 显示名称
    let serverName: String
    /// 信任档位
    let trust: TrustBoundary
    /// 传输方式描述（如 "SSE: https://example.com/sse"）
    let transportDescription: String
    /// 工具数量
    let toolCount: Int
    /// 工具名列表
    let toolNames: [String]
    /// 公钥指纹（可选，公网 Server 用于防中间人攻击校验）
    let publicKeyPin: String?

    init(
        serverID: String,
        serverName: String,
        trust: TrustBoundary,
        transportDescription: String,
        toolCount: Int,
        toolNames: [String],
        publicKeyPin: String?
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.trust = trust
        self.transportDescription = transportDescription
        self.toolCount = toolCount
        self.toolNames = toolNames
        self.publicKeyPin = publicKeyPin
    }
}

// MARK: - TrustBoundary 显示扩展

extension TrustBoundary {
    /// 信任档位的本地化显示名称
    var displayName: String {
        switch self {
        case .local: return "本地"
        case .lan: return "局域网"
        case .public: return "公网"
        }
    }

    /// 风险等级描述
    var riskLevel: String {
        switch self {
        case .local: return "低"
        case .lan: return "中"
        case .public: return "高"
        }
    }

    /// 风险等级对应的颜色（用于 UI 显示）
    var riskColor: Color {
        switch self {
        case .local: return .green
        case .lan: return .orange
        case .public: return .red
        }
    }
}

// MARK: - PermissionPromptView

/// MCP Server 权限审批弹窗。
///
/// 公网 Server 首次调用前必弹此视图，显示：
/// - Server 元信息（名称、ID、传输方式）
/// - 信任档位与风险等级
/// - 工具列表（含数量）
/// - 公钥指纹（若有，用于防中间人攻击）
/// - 批准 / 拒绝按钮
///
/// 用户拒绝后不再注册该 Server 的工具。
struct PermissionPromptView: View {
    /// 审批信息
    let info: PermissionPromptInfo
    /// 批准回调
    let onApprove: () -> Void
    /// 拒绝回调
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // 头部：图标 + 标题
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title)
                    .foregroundStyle(info.trust.riskColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP Server 请求连接")
                        .font(.headline)
                    Text(info.serverName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Server 元信息
            detailRow(label: "Server ID", value: info.serverID)
            detailRow(label: "信任档位", value: "\(info.trust.displayName)（风险：\(info.trust.riskLevel)）")
            detailRow(label: "传输方式", value: info.transportDescription)
            detailRow(label: "工具数量", value: "\(info.toolCount) 个")

            // 公钥指纹（若有）
            if let pin = info.publicKeyPin {
                detailRow(label: "公钥指纹", value: pin)
                    .font(.caption)
            }

            // 工具列表（最多显示 5 个，超出折叠）
            if !info.toolNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("工具列表")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let displayTools = Array(info.toolNames.prefix(5))
                    ForEach(displayTools, id: \.self) { name in
                        Text("• \(name)")
                            .font(.caption)
                    }
                    if info.toolNames.count > 5 {
                        Text("…以及其他 \(info.toolNames.count - 5) 个工具")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: onReject) {
                    Text("拒绝")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityIdentifier("rejectButton")

                Button(action: onApprove) {
                    Text("批准连接")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("approveButton")
            }
        }
        .padding()
        .frame(maxWidth: 480)
        .accessibilityIdentifier("PermissionPromptView")
    }

    /// 详情行：标签 + 值
    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 预览

#Preview("Permission Prompt") {
    PermissionPromptView(
        info: PermissionPromptInfo(
            serverID: "example-server",
            serverName: "示例 MCP Server",
            trust: .public,
            transportDescription: "SSE: https://example.com/sse",
            toolCount: 3,
            toolNames: ["search", "calc", "fs_read"],
            publicKeyPin: "sha256:abcdef1234567890"
        ),
        onApprove: { print("approved") },
        onReject: { print("rejected") }
    )
}
