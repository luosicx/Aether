import SwiftUI
import AetherFoundation
import AetherServices
import AetherDesign

/// 插件市场视图：展示可下载插件列表，支持搜索、查看详情与下载安装。
///
/// 布局：
/// - 列表页：搜索框 + 插件行（名/描述/作者/下载按钮/进度条）
/// - 详情页：manifest 全字段 + 权限列表 + 安装按钮
struct PluginMarketplaceView: View {
    /// 插件市场服务（@Observable，@State 跟踪变化）
    @State private var marketplace = PluginMarketplaceService()
    /// 搜索关键词
    @State private var searchText = ""
    /// 操作结果提示
    @State private var actionMessage: String?
    /// 是否正在加载列表
    @State private var isLoading = false

    var body: some View {
        List {
            // MARK: - 搜索与刷新
            Section {
                HStack {
                    // v1.2: 使用 AetherIcon.search 替换 SF Symbol
                    AetherIcon.search.systemImage
                        .foregroundStyle(.secondary)
                    TextField("搜索插件", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityLabel("搜索插件")
                        .accessibilityIdentifier("marketplaceSearchField")
                }
                Button {
                    Task { await loadPlugins() }
                } label: {
                    Label("刷新插件列表", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("刷新插件列表")
                .accessibilityIdentifier("refreshPluginListButton")
            }

            // MARK: - 操作结果
            if let message = actionMessage {
                Section {
                    Text(message)
                        .foregroundStyle(message.contains("失败") ? .red : .green)
                        .font(.footnote)
                }
            }

            // MARK: - 加载中
            if isLoading && marketplace.plugins.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("加载中…", comment: "")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - 插件列表
            Section {
                if filteredPlugins.isEmpty && !isLoading {
                    Text("暂无插件", comment: "")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .accessibilityIdentifier("marketplaceEmptyState")
                } else {
                    ForEach(filteredPlugins, id: \.id) { plugin in
                        NavigationLink {
                            PluginDetailView(plugin: plugin, marketplace: marketplace) {
                                actionMessage = $0
                            }
                        } label: {
                            pluginRow(plugin)
                        }
                        .accessibilityIdentifier("marketplacePluginRow_\(plugin.id)")
                    }
                }
            } header: {
                Text("插件列表（\(filteredPlugins.count)）", comment: "")
            }
        }
        .formStyle(.grouped)
        .responsiveLayout()
        .tint(Color.aetherPurple)
        .foregroundStyle(Color.starlight)
        .scrollContentBackground(.hidden)
        .background(Color.deepSpace.ignoresSafeArea())
        .navigationTitle("插件市场")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if marketplace.plugins.isEmpty {
                await loadPlugins()
            }
        }
    }

    // MARK: - 过滤后的插件列表

    private var filteredPlugins: [PluginManifest] {
        marketplace.searchPlugins(query: searchText)
    }

    // MARK: - 插件行

    @ViewBuilder
    private func pluginRow(_ plugin: PluginManifest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.headlineAI)
                    Text("v\(plugin.version) · \(plugin.author)")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if marketplace.downloadingPluginIDs.contains(plugin.id) {
                    ProgressView(value: marketplace.downloadProgress[plugin.id] ?? 0)
                        .frame(width: 60)
                        .accessibilityLabel("下载进度")
                } else {
                    // v1.2: 使用 AetherIcon.modelDownload 替换 SF Symbol
                    AetherIcon.modelDownload.systemImage
                        .foregroundStyle(.secondary)
                }
            }
            Text(plugin.description)
                .font(.captionAI)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 加载插件列表

    private func loadPlugins() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await marketplace.fetchPluginList()
            actionMessage = nil
        } catch {
            actionMessage = String(localized: "加载失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 插件详情页

/// 插件详情视图：展示 manifest 全字段、权限列表与安装按钮。
struct PluginDetailView: View {
    /// 插件清单
    let plugin: PluginManifest
    /// 市场服务（用于下载）
    @Bindable var marketplace: PluginMarketplaceService
    /// 安装结果回调
    var onResult: (String) -> Void

    /// 插件管理器（用于安装到本地）
    @State private var pluginManager = PluginManager()

    var body: some View {
        Form {
            // MARK: - 基本信息
            Section {
                infoRow("名称", plugin.name)
                infoRow("版本", plugin.version)
                infoRow("作者", plugin.author)
                infoRow("ID", plugin.id)
                infoRow("入口", plugin.entryPoint)
                infoRow("描述", plugin.description)
            } header: {
                Text("基本信息", comment: "")
            }

            // MARK: - 市场元信息
            Section {
                if let url = plugin.downloadURL {
                    infoRow("下载地址", url.absoluteString)
                }
                if let sig = plugin.signature {
                    infoRow("签名", sig)
                }
                if let minVer = plugin.minAppVersion {
                    infoRow("最低 App 版本", minVer)
                }
                if !plugin.dependencies.isEmpty {
                    infoRow("依赖", plugin.dependencies.joined(separator: ", "))
                }
                if !plugin.hooks.isEmpty {
                    infoRow("钩子", plugin.hooks.map(\.rawValue).joined(separator: ", "))
                }
            } header: {
                Text("市场信息", comment: "")
            }

            // MARK: - 工具列表
            if !plugin.tools.isEmpty {
                Section {
                    ForEach(Array(plugin.tools.enumerated()), id: \.offset) { _, tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .font(.subheadline)
                            Text(tool.description)
                                .font(.captionAI)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("工具（\(plugin.tools.count)）", comment: "")
                }
            }

            // MARK: - 权限列表
            Section {
                if plugin.permissions.isEmpty {
                    Text("无权限声明", comment: "")
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
                    }
                }
            } header: {
                Text("权限（\(plugin.permissions.count)）", comment: "")
            }

            // MARK: - 安装
            Section {
                if marketplace.downloadingPluginIDs.contains(plugin.id) {
                    VStack {
                        ProgressView(value: marketplace.downloadProgress[plugin.id] ?? 0)
                        Text("下载中…", comment: "")
                            .font(.captionAI)
                            .foregroundStyle(.secondary)
                    }
                } else if pluginManager.isInstalled(plugin.id) {
                    Label("已安装", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await installPlugin() }
                    } label: {
                        Label("下载并安装", systemImage: "arrow.down.to.line")
                    }
                    .accessibilityLabel("下载并安装插件 \(plugin.name)")
                    .accessibilityIdentifier("installPluginButton_\(plugin.id)")
                }
            } header: {
                Text("安装", comment: "")
            }
        }
        .formStyle(.grouped)
        .responsiveLayout()
        .tint(Color.aetherPurple)
        .foregroundStyle(Color.starlight)
        .scrollContentBackground(.hidden)
        .background(Color.deepSpace.ignoresSafeArea())
        .navigationTitle(plugin.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 安装插件

    private func installPlugin() async {
        do {
            try await marketplace.downloadPlugin(manifest: plugin)
            // 下载完成后注册到 PluginManager
            try pluginManager.install(manifest: plugin)
            try pluginManager.loadPluginTools(pluginID: plugin.id)
            onResult(String(localized: "安装成功：\(plugin.name)"))
        } catch {
            onResult(String(localized: "安装失败：\(error.localizedDescription)"))
        }
    }

    // MARK: - 信息行

    @ViewBuilder
    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: key)
                .font(.captionAI)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.captionAI)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 权限图标与标签

    private func permissionIcon(_ type: PluginPermission.PermissionType) -> String {
        switch type {
        case .network: return "network"
        case .fileSystem: return "folder"
        case .clipboard: return "doc.on.clipboard"
        case .notifications: return "bell"
        case .contacts: return "person.crop.circle"
        case .location: return "location"
        case .health: return "heart"
        case .photoLibrary: return "photo"
        }
    }

    private func permissionLabel(_ type: PluginPermission.PermissionType) -> String {
        switch type {
        case .network: return String(localized: "网络访问")
        case .fileSystem: return String(localized: "文件系统")
        case .clipboard: return String(localized: "剪贴板")
        case .notifications: return String(localized: "通知")
        case .contacts: return String(localized: "通讯录")
        case .location: return String(localized: "位置")
        case .health: return String(localized: "健康数据")
        case .photoLibrary: return String(localized: "相册")
        }
    }
}
