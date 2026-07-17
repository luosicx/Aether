import SwiftUI
import AetherFoundation

/// MCP Server 管理设置页。
///
/// 功能：
/// - 显示已配置的 MCP Server 列表（从 UserDefaults 加载）
/// - 添加新 Server（名称、传输类型、URL/命令）
/// - 编辑 Server 配置
/// - 删除 Server
/// - 显示连接状态（可选，需传入 MCPClientManager）
/// - 保存配置到 UserDefaults（JSON 编码 MCPConfig 数组）
struct MCPSettingsView: View {
    /// 可选的 MCPClientManager，用于显示连接状态（nil 时仅显示启用/禁用状态）
    var clientManager: MCPClientManager?

    /// Server 配置列表（从 UserDefaults 加载）
    @State private var configs: [MCPConfig] = []
    /// 添加 Server sheet 开关
    @State private var showAddSheet = false
    /// 编辑中的配置（非 nil 时展示编辑 sheet）
    @State private var editingConfig: MCPConfig?
    /// 待删除的配置（确认弹窗用）
    @State private var pendingDeleteConfig: MCPConfig?
    /// 删除确认弹窗开关
    @State private var showDeleteConfirm = false
    /// 权限审批弹窗开关（公网 Server 首次连接时弹窗）
    @State private var showPermissionPrompt = false
    /// 待审批的 Server 信息（弹窗显示用）
    @State private var pendingPermissionInfo: PermissionPromptInfo?

    /// UserDefaults 存储键
    private let storageKey = "MCPConfigs"

    var body: some View {
        Form {
            // 已配置的 Server 列表
            Section {
                if configs.isEmpty {
                    Text("尚未配置 MCP Server", comment: "")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .accessibilityIdentifier("emptyMCPConfigHint")
                } else {
                    ForEach(configs) { config in
                        Button {
                            editingConfig = config
                        } label: {
                            serverRow(config)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mcpServerRow_\(config.id)")
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            pendingDeleteConfig = configs[index]
                            showDeleteConfirm = true
                        }
                    }
                }
            } header: {
                Text("MCP Server 列表", comment: "")
            } footer: {
                Text("点击 Server 编辑配置，左滑删除。", comment: "")
                    .font(.captionAI)
            }

            // 已连接的 Server（运行时状态，需 clientManager）
            if let manager = clientManager {
                connectedServersSection(manager: manager)
                candidateServersSection(manager: manager)
                rejectedServersSection(manager: manager)
            }

            // 添加按钮
            Section {
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加 Server", systemImage: "plus")
                }
                .accessibilityLabel("添加 Server")
                .accessibilityHint("添加新的 MCP Server 配置")
                .accessibilityIdentifier("addMCPServerButton")
            }
        }
        .navigationTitle("MCP 配置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("MCPSettingsView")
        .onAppear { loadConfigs() }
        .sheet(isPresented: $showAddSheet) {
            MCPServerEditView(config: nil) { newConfig in
                configs.append(newConfig)
                saveConfigs()
            }
        }
        .sheet(item: $editingConfig) { config in
            MCPServerEditView(config: config) { updated in
                if let idx = configs.firstIndex(where: { $0.id == updated.id }) {
                    configs[idx] = updated
                    saveConfigs()
                }
            }
        }
        .sheet(isPresented: $showPermissionPrompt) {
            if let info = pendingPermissionInfo {
                PermissionPromptView(
                    info: info,
                    onApprove: {
                        if let id = pendingPermissionInfo?.serverID {
                            Task { await clientManager?.approveCandidate(serverID: id) }
                        }
                        showPermissionPrompt = false
                        pendingPermissionInfo = nil
                    },
                    onReject: {
                        if let id = pendingPermissionInfo?.serverID {
                            clientManager?.rejectCandidate(serverID: id)
                        }
                        showPermissionPrompt = false
                        pendingPermissionInfo = nil
                    }
                )
            }
        }
        .confirmationDialog(
            pendingDeleteConfig.map {
                String(format: NSLocalizedString("确认删除「%@」？删除后无法恢复。", comment: ""), $0.name)
            } ?? "",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let config = pendingDeleteConfig {
                    deleteConfig(config)
                }
                pendingDeleteConfig = nil
            }
            .accessibilityIdentifier("confirmDeleteServerButton")
            Button("取消", role: .cancel) {
                pendingDeleteConfig = nil
            }
        }
    }

    // MARK: - 三组 Server 区段

    /// 已连接 Server 区段
    @ViewBuilder
    private func connectedServersSection(manager: MCPClientManager) -> some View {
        let connected = manager.getConnectedServers()
        if !connected.isEmpty {
            Section {
                ForEach(connected) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Text("\(info.tools.count) 个工具")
                                .font(.captionAI)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await manager.disconnect(serverID: info.id) }
                        } label: {
                            Image(systemName: "stop.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("disconnectButton_\(info.id)")
                    }
                }
            } header: {
                Text("已连接", comment: "")
            }
        }
    }

    /// 候选 Server 区段（待审批）
    @ViewBuilder
    private func candidateServersSection(manager: MCPClientManager) -> some View {
        let candidates = manager.getCandidateServers()
        if !candidates.isEmpty {
            Section {
                ForEach(candidates, id: \.id) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.body)
                                .fontWeight(.medium)
                            let boundary = manager.getCandidateTrustBoundary(serverID: server.id) ?? .lan
                            HStack(spacing: 4) {
                                Text(boundary.displayName)
                                    .font(.captionAI)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(boundary.riskColor.opacity(0.2))
                                    .clipShape(Capsule())
                                Text("风险：\(boundary.riskLevel)")
                                    .font(.captionAI)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("批准") {
                            Task { await manager.approveCandidate(serverID: server.id) }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("approveButton_\(server.id)")
                        Button("拒绝") {
                            manager.rejectCandidate(serverID: server.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityIdentifier("rejectButton_\(server.id)")
                    }
                }
            } header: {
                Text("候选 Server（待审批）", comment: "")
            } footer: {
                Text("公网 Server 首次连接需用户确认。", comment: "")
                    .font(.captionAI)
            }
        }
    }

    /// 已拒绝 Server 区段
    @ViewBuilder
    private func rejectedServersSection(manager: MCPClientManager) -> some View {
        let rejected = manager.getRejectedServerIDs()
        if !rejected.isEmpty {
            Section {
                ForEach(rejected, id: \.self) { serverID in
                    HStack {
                        Text(serverID)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "hand.raised.slash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("rejectedServerRow_\(serverID)")
                }
            } header: {
                Text("已拒绝", comment: "")
            }
        }
    }

    // MARK: - 子视图

    /// 单个 Server 行：名称 + 状态徽章 + 传输方式描述
    @ViewBuilder
    private func serverRow(_ config: MCPConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    statusBadge(for: config)
                }
                Text(transportDescription(config.transport))
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// 状态徽章：优先显示 MCPClientManager 的实时连接状态，无 manager 时显示启用/禁用
    @ViewBuilder
    private func statusBadge(for config: MCPConfig) -> some View {
        if let manager = clientManager {
            let info = manager.serverInfos[config.id]
            switch info?.status {
            case .connected:
                Text("已连接", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.green)
            case .connecting:
                Text("连接中", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.orange)
            case .error:
                Text("错误", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.red)
            case .disconnected, nil:
                Text("未连接", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
            }
        } else {
            if config.enabled {
                Text("已启用", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
            } else {
                Text("已禁用", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 数据操作

    /// 传输方式可读描述
    private func transportDescription(_ transport: MCPConfig.Transport) -> String {
        switch transport {
        case .stdio(let command, let args, _):
            let argsStr = args.isEmpty ? "" : " " + args.joined(separator: " ")
            return "stdio: \(command)\(argsStr)"
        case .sse(let url, _):
            return "SSE: \(url)"
        }
    }

    /// 删除指定配置
    private func deleteConfig(_ config: MCPConfig) {
        configs.removeAll { $0.id == config.id }
        saveConfigs()
    }

    /// 从 UserDefaults 加载配置列表
    private func loadConfigs() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            configs = []
            return
        }
        do {
            configs = try JSONDecoder().decode([MCPConfig].self, from: data)
        } catch {
            configs = []
        }
    }

    /// 保存配置列表到 UserDefaults
    private func saveConfigs() {
        do {
            let data = try JSONEncoder().encode(configs)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // 编码失败时忽略（MCPConfig 的 Codable 实现应保证不失败）
        }
    }
}

// MARK: - MCPServerEditView

/// MCP Server 添加/编辑表单。
///
/// 作为 sheet 展示，支持新增（config 为 nil）和编辑（config 非 nil）两种模式。
/// 传输类型支持 stdio（命令 + 参数）和 SSE（URL）。
struct MCPServerEditView: View {
    /// 编辑的配置（nil 表示新增）
    let config: MCPConfig?
    /// 保存回调
    let onSave: (MCPConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var transportType: TransportType = .sse
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var url: String = ""
    @State private var enabled: Bool = true

    /// 传输类型枚举（用于 Picker 选择）
    enum TransportType: String, CaseIterable, Identifiable {
        case stdio = "stdio"
        case sse = "SSE"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section {
                    TextField("名称", text: $name)
                        .accessibilityLabel("名称")
                        .accessibilityHint("MCP Server 显示名称")
                        .accessibilityIdentifier("serverNameField")
                    Toggle("启用", isOn: $enabled)
                        .accessibilityLabel("启用")
                        .accessibilityHint("启用或禁用此 Server")
                        .accessibilityIdentifier("serverEnabledToggle")
                } header: {
                    Text("基本信息", comment: "")
                }

                // 传输配置
                Section {
                    Picker("传输类型", selection: $transportType) {
                        ForEach(TransportType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("传输类型")
                    .accessibilityHint("选择 stdio 或 SSE 传输方式")
                    .accessibilityIdentifier("transportTypePicker")

                    switch transportType {
                    case .stdio:
                        TextField("命令路径", text: $command)
                            .accessibilityLabel("命令路径")
                            .accessibilityHint("可执行文件路径，如 /usr/local/bin/node")
                            .accessibilityIdentifier("commandField")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        TextField("参数（空格分隔）", text: $args)
                            .accessibilityLabel("参数")
                            .accessibilityHint("启动参数，以空格分隔")
                            .accessibilityIdentifier("argsField")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    case .sse:
                        TextField("URL", text: $url)
                            .accessibilityLabel("URL")
                            .accessibilityHint("SSE 端点 URL")
                            .accessibilityIdentifier("urlField")
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    }
                } header: {
                    Text("传输配置", comment: "")
                } footer: {
                    Text(transportType == .stdio
                         ? "stdio 传输通过启动子进程并经 stdin/stdout 通信（仅 macOS）。"
                         : "SSE 传输通过 HTTP Server-Sent Events 连接（跨平台）。")
                        .font(.captionAI)
                }
            }
            .navigationTitle(config == nil ? "添加 Server" : "编辑 Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("cancelServerButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(name.isEmpty || !isTransportValid)
                    .accessibilityIdentifier("saveServerButton")
                }
            }
            .onAppear { loadConfig() }
        }
    }

    /// 传输配置是否有效（用于保存按钮启用判断）
    private var isTransportValid: Bool {
        switch transportType {
        case .stdio:
            return !command.isEmpty
        case .sse:
            return !url.isEmpty
        }
    }

    // MARK: - 数据操作

    /// 加载已有配置到表单字段
    private func loadConfig() {
        guard let config = config else { return }
        name = config.name
        enabled = config.enabled
        switch config.transport {
        case .stdio(let cmd, let args, _):
            transportType = .stdio
            command = cmd
            self.args = args.joined(separator: " ")
        case .sse(let url, _):
            transportType = .sse
            self.url = url
        }
    }

    /// 保存配置（构造 MCPConfig 并回调）
    private func save() {
        let transport: MCPConfig.Transport
        switch transportType {
        case .stdio:
            let argsArray = args
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
            transport = .stdio(command: command, args: argsArray, env: nil)
        case .sse:
            transport = .sse(url: url, headers: nil)
        }

        let id = config?.id ?? UUID().uuidString
        let newConfig = MCPConfig(
            id: id,
            name: name,
            transport: transport,
            enabled: enabled
        )
        onSave(newConfig)
        dismiss()
    }
}
