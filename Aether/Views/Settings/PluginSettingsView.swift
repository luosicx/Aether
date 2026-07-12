import SwiftUI

/// 插件管理设置页。展示已安装插件列表，支持安装、卸载与权限查看。
///
/// 功能：
/// - 显示已安装插件列表（名称、版本、作者、描述）
/// - 安装新插件（安装示例插件用于演示）
/// - 卸载插件
/// - 查看插件声明的权限
struct PluginSettingsView: View {
    /// 插件管理器（@Observable，@State 跟踪变化）
    @State private var pluginManager = PluginManager()
    /// 当前展开查看权限的插件 ID
    @State private var expandedPluginID: String?
    /// 操作结果提示
    @State private var actionMessage: String?

    var body: some View {
        Form {
            // MARK: - 已安装插件列表
            Section {
                if pluginManager.installedPluginList.isEmpty {
                    Text("暂无已安装插件")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .accessibilityIdentifier("pluginEmptyState")
                } else {
                    ForEach(pluginManager.installedPluginList, id: \.id) { plugin in
                        pluginRow(plugin)
                    }
                }
            } header: {
                Text("已安装插件")
            } footer: {
                Text("插件工具会动态注册到工具注册中心，供 AI 调用。")
                    .font(.captionAI)
            }

            // MARK: - 安装新插件
            Section {
                Button {
                    installSamplePlugin()
                } label: {
                    Label("安装示例插件", systemImage: "plus.circle")
                }
                .accessibilityLabel("安装示例插件")
                .accessibilityHint("安装一个示例插件用于演示")
                .accessibilityIdentifier("installSamplePluginButton")
            } header: {
                Text("安装")
            } footer: {
                Text("安装示例插件用于演示插件系统功能。")
                    .font(.captionAI)
            }

            // MARK: - 操作结果
            if let message = actionMessage {
                Section {
                    Text(message)
                        .foregroundStyle(message.contains("失败") ? .red : .green)
                        .font(.footnote)
                }
            }
        }
        .formStyle(.grouped)
        .responsiveLayout()
        .tint(Color.aetherPurple)
        .foregroundStyle(Color.starlight)
        .scrollContentBackground(.hidden)
        .background(Color.deepSpace.ignoresSafeArea())
        .navigationTitle("插件管理")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 插件行

    @ViewBuilder
    private func pluginRow(_ plugin: PluginManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.headlineAI)
                    Text("v\(plugin.version) · \(plugin.author)")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    uninstallPlugin(plugin.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("卸载插件 \(plugin.name)")
                .accessibilityHint("卸载此插件并注销其工具")
                .accessibilityIdentifier("uninstallPluginButton_\(plugin.id)")
            }

            Text(plugin.description)
                .font(.captionAI)
                .foregroundStyle(.secondary)

            // 工具列表
            if !plugin.tools.isEmpty {
                HStack {
                    Text("工具：")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                    Text(plugin.tools.map(\.name).joined(separator: ", "))
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                }
            }

            // 权限查看（可展开）
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedPluginID == plugin.id },
                    set: { isExpanded in
                        expandedPluginID = isExpanded ? plugin.id : nil
                    }
                )
            ) {
                if plugin.permissions.isEmpty {
                    Text("无权限声明")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(plugin.permissions.enumerated()), id: \.offset) { _, perm in
                        HStack {
                            Image(systemName: permissionIcon(perm.type))
                                .foregroundStyle(.secondary)
                            Text(permissionLabel(perm.type))
                                .font(.captionAI)
                            if let desc = perm.description {
                                Spacer()
                                Text(desc)
                                    .font(.captionAI)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("permissionRow_\(plugin.id)_\(perm.type.rawValue)")
                    }
                }
            } label: {
                Text("权限（\(plugin.permissions.count)）")
                    .font(.captionAI)
            }
            .accessibilityIdentifier("pluginPermissionsDisclosure_\(plugin.id)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pluginRow_\(plugin.id)")
    }

    // MARK: - 操作

    /// 安装一个示例插件用于演示
    private func installSamplePlugin() {
        let samplePlugin = PluginManifest(
            id: "sample-\(UUID().uuidString.prefix(8))",
            name: "示例插件",
            version: "1.0.0",
            author: "Aether",
            description: "用于演示插件系统功能的示例插件",
            tools: [
                PluginManifest.PluginToolDef(
                    name: "sample_greet",
                    description: "示例问候工具",
                    parameters: [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "description": "被问候者名字"]
                        ],
                        "required": ["name"]
                    ]
                )
            ],
            permissions: [
                PluginPermission(type: .network, description: "需要网络访问"),
                PluginPermission(type: .clipboard, description: nil)
            ],
            entryPoint: "sample.js"
        )
        do {
            try pluginManager.install(manifest: samplePlugin)
            try pluginManager.loadPluginTools(pluginID: samplePlugin.id)
            actionMessage = "安装成功：\(samplePlugin.name)"
        } catch {
            actionMessage = "安装失败：\(error.localizedDescription)"
        }
    }

    /// 卸载插件
    private func uninstallPlugin(_ pluginID: String) {
        do {
            try pluginManager.uninstall(pluginID: pluginID)
            actionMessage = "已卸载插件"
            if expandedPluginID == pluginID {
                expandedPluginID = nil
            }
        } catch {
            actionMessage = "卸载失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 权限图标与标签

    /// 权限类型对应的 SF Symbol 图标
    private func permissionIcon(_ type: PluginPermission.PermissionType) -> String {
        switch type {
        case .network: return "network"
        case .fileSystem: return "folder"
        case .clipboard: return "doc.on.clipboard"
        case .notifications: return "bell"
        case .contacts: return "person.crop.circle"
        case .location: return "location"
        }
    }

    /// 权限类型的中文标签
    private func permissionLabel(_ type: PluginPermission.PermissionType) -> String {
        switch type {
        case .network: return "网络访问"
        case .fileSystem: return "文件系统"
        case .clipboard: return "剪贴板"
        case .notifications: return "通知"
        case .contacts: return "通讯录"
        case .location: return "位置"
        }
    }
}
