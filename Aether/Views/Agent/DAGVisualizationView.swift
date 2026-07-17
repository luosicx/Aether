import SwiftUI
import AetherDesign

/// Task 20 阶段 4: DAG 可视化视图。
///
/// 职责：
/// - 使用 SwiftUI Canvas 绘制节点圆角矩形与依赖边（贝塞尔曲线）
/// - 节点颜色映射状态（灰=pending、蓝=running、绿=completed、红=failed、黄=skipped）
/// - 顶部进度条显示 `completed/total` 比例
/// - 点击节点展开详情 sheet（标题/描述/结果/耗时）
/// - 节点数 > 30 时折叠子图（防 UI 卡顿）
///
/// 布局策略：
/// - 按依赖深度分层（拓扑分层）：同层节点水平排列
/// - 每层节点垂直方向堆叠
/// - 依赖边从前驱节点右侧 → 后继节点左侧（贝塞尔曲线）
struct DAGVisualizationView: View {

    /// 待可视化的 AgentTask
    let task: AgentTask

    /// 节点点击回调（外部可订阅触发干预面板）
    var onNodeTap: ((SubTask) -> Void)? = nil

    /// 当前选中的节点（用于详情 sheet）
    @State private var selectedNode: SubTask?

    /// 折叠阈值：节点数超过此值时折叠显示
    static let collapseThreshold: Int = 30

    /// 是否展开全部（默认 false，超过阈值时折叠）
    @State private var isExpanded: Bool = false

    /// 节点布局信息
    struct NodeLayout: Identifiable {
        let id: UUID
        let subTask: SubTask
        let frame: CGRect
        let depth: Int
    }

    /// 依赖边信息
    struct EdgeLayout: Hashable {
        let from: UUID
        let to: UUID
    }

    /// 计算后的节点布局
    private var nodeLayouts: [NodeLayout] {
        computeLayout(task: task, isExpanded: isExpanded)
    }

    /// 计算后的依赖边
    private var edgeLayouts: [EdgeLayout] {
        guard let layoutByID = nodeLayoutsByID else { return [] }
        var edges: [EdgeLayout] = []
        for sub in displayedSubTasks {
            for depID in sub.dependencies {
                if layoutByID[depID] != nil && layoutByID[sub.id] != nil {
                    edges.append(EdgeLayout(from: depID, to: sub.id))
                }
            }
        }
        return edges
    }

    /// 节点 ID → NodeLayout 映射（用于边绘制）
    private var nodeLayoutsByID: [UUID: NodeLayout]? {
        Dictionary(uniqueKeysWithValues: nodeLayouts.map { ($0.id, $0) })
    }

    /// 显示的子任务列表（考虑折叠）
    private var displayedSubTasks: [SubTask] {
        let subs = task.subTasks
        if subs.count > Self.collapseThreshold && !isExpanded {
            return Array(subs.prefix(Self.collapseThreshold))
        }
        return subs
    }

    /// 画布总尺寸
    private var canvasSize: CGSize {
        guard !nodeLayouts.isEmpty else { return CGSize(width: 320, height: 80) }
        let maxX = nodeLayouts.map { $0.frame.maxX }.max() ?? 320
        let maxY = nodeLayouts.map { $0.frame.maxY }.max() ?? 80
        return CGSize(width: maxX + Spacing.lg, height: maxY + Spacing.lg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 顶部：进度条
            progressBar

            // 折叠提示
            if task.subTasks.count > Self.collapseThreshold {
                collapseToggle
            }

            // DAG 画布
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // 底层：Canvas 绘制节点与依赖边
                    Canvas { context, size in
                        drawEdges(in: context, size: size)
                        drawNodes(in: context, size: size)
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)

                    // 上层：透明可点击区域（每个节点对应一个 Button）
                    ForEach(nodeLayouts) { layout in
                        Button {
                            selectedNode = layout.subTask
                            onNodeTap?(layout.subTask)
                        } label: {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .frame(width: layout.frame.width, height: layout.frame.height)
                        .position(x: layout.frame.midX, y: layout.frame.midY)
                        .buttonStyle(.plain)
                        .accessibilityLabel("节点：\(layout.subTask.title)")
                        .accessibilityHint("点击查看节点详情")
                    }
                }
                .background(Color.backgroundSecondary.opacity(0.5))
                .cornerRadius(CornerRadius.small)
            }
            .frame(maxHeight: 320)
        }
        .sheet(item: $selectedNode) { node in
            NodeDetailView(node: node)
                .presentationDetents([.medium])
        }
    }

    // MARK: - 进度条

    /// 顶部进度条：completed/total 比例
    private var progressBar: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("执行进度")
                        .font(.captionAI)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(task.completedCount) / \(task.subTasks.count)")
                        .font(.captionAI)
                        .foregroundColor(.textPrimary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.backgroundTertiary)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: proxy.size.width * task.progressRatio, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    /// 进度条颜色：有 failed 节点时偏红，否则品牌色
    private var progressColor: Color {
        task.hasFailedSubTask ? .red : .electricBlue
    }

    /// 折叠/展开切换按钮
    private var collapseToggle: some View {
        Button {
            withAnimation(AnimationTokens.transition) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.captionAI)
                Text(isExpanded
                     ? "折叠子图（共 \(task.subTasks.count) 节点）"
                     : "已折叠，显示前 \(Self.collapseThreshold) 节点（共 \(task.subTasks.count) 节点）")
                    .font(.captionAI)
            }
            .foregroundColor(.electricBlue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Canvas 绘制

    /// 绘制依赖边（贝塞尔曲线）
    private func drawEdges(in context: GraphicsContext, size: CGSize) {
        guard let layoutByID = nodeLayoutsByID else { return }
        for edge in edgeLayouts {
            guard let from = layoutByID[edge.from],
                  let to = layoutByID[edge.to] else { continue }
            let startPoint = CGPoint(x: from.frame.maxX, y: from.frame.midY)
            let endPoint = CGPoint(x: to.frame.minX, y: to.frame.midY)
            // 中间控制点：水平偏移制造曲线
            let midX = (startPoint.x + endPoint.x) / 2
            let control1 = CGPoint(x: midX, y: startPoint.y)
            let control2 = CGPoint(x: midX, y: endPoint.y)

            var path = Path()
            path.move(to: startPoint)
            path.addCurve(to: endPoint, control1: control1, control2: control2)

            // 边颜色：根据目标节点状态调整
            let edgeColor = edgeColor(for: to.subTask.status)
            context.stroke(path, with: .color(edgeColor), lineWidth: 1.5)
        }
    }

    /// 绘制节点（圆角矩形 + 标题文字）
    private func drawNodes(in context: GraphicsContext, size: CGSize) {
        for layout in nodeLayouts {
            let sub = layout.subTask
            let frame = layout.frame

            // 圆角矩形背景
            let rect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)
            let roundedRect = Path(roundedRect: rect, cornerRadius: 8)
            context.fill(roundedRect, with: .color(nodeColor(for: sub.status).opacity(0.85)))
            context.stroke(roundedRect, with: .color(nodeBorderColor(for: sub.status)), lineWidth: 1.5)

            // 标题文字
            let titleText = Text(sub.title)
                .font(.captionAI)
                .foregroundColor(.white)
            context.draw(titleText, at: CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // MARK: - 颜色映射

    /// 节点填充色（按状态）
    /// - Parameter status: 子任务状态
    /// - Returns: 对应颜色（灰=pending、蓝=running、绿=completed、红=failed、黄=skipped）
    private func nodeColor(for status: SubTaskStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .electricBlue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }

    /// 节点边框色（略深于填充色）
    private func nodeBorderColor(for status: SubTaskStatus) -> Color {
        switch status {
        case .pending: return .duskGray
        case .inProgress: return .electricBlue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }

    /// 依赖边颜色（根据目标节点状态）
    private func edgeColor(for status: SubTaskStatus) -> Color {
        switch status {
        case .failed, .skipped: return .orange.opacity(0.6)
        case .completed: return .green.opacity(0.5)
        case .inProgress: return .electricBlue.opacity(0.7)
        case .pending: return .secondary.opacity(0.4)
        }
    }

    // MARK: - 布局计算

    /// 计算所有节点的布局
    /// - Parameters:
    ///   - task: AgentTask
    ///   - isExpanded: 是否展开（false 时折叠超出阈值的节点）
    /// - Returns: 节点布局数组
    private func computeLayout(task: AgentTask, isExpanded: Bool) -> [NodeLayout] {
        let subs = displayedSubTasks
        guard !subs.isEmpty else { return [] }

        // 1. 计算每个节点的深度（依赖链最长前驱路径 + 1）
        var depths: [UUID: Int] = [:]
        // 拓扑排序：迭代计算
        var inDegree: [UUID: Int] = [:]
        for sub in subs { inDegree[sub.id] = 0 }
        for sub in subs {
            for depID in sub.dependencies where inDegree[sub.id] != nil {
                inDegree[sub.id, default: 0] += 1
            }
        }
        // Kahn 算法
        var queue: [UUID] = inDegree.filter { $0.value == 0 }.map { $0.key }
        var processed = 0
        while !queue.isEmpty {
            let current = queue.removeFirst()
            processed += 1
            // 找到所有依赖 current 的节点
            for sub in subs where sub.dependencies.contains(current) {
                inDegree[sub.id, default: 0] -= 1
                if inDegree[sub.id] == 0 {
                    queue.append(sub.id)
                    // 深度 = max(前驱深度) + 1
                    let maxDepDepth = sub.dependencies.compactMap { depths[$0] }.max() ?? 0
                    depths[sub.id] = maxDepDepth + 1
                }
            }
            if depths[current] == nil { depths[current] = 0 }
        }
        // 处理循环依赖或孤立节点
        for sub in subs where depths[sub.id] == nil {
            depths[sub.id] = 0
        }

        // 2. 按深度分层
        let maxDepth = depths.values.max() ?? 0
        let layers: [[SubTask]] = (0...maxDepth).map { depth in
            subs.filter { depths[$0.id] == depth }
                .sorted { $0.order < $1.order }
        }

        // 3. 计算每层节点的 frame
        let nodeWidth: CGFloat = 100
        let nodeHeight: CGFloat = 36
        let horizontalGap: CGFloat = 32
        let verticalGap: CGFloat = 24
        let leftPadding: CGFloat = Spacing.lg
        let topPadding: CGFloat = Spacing.lg

        var layouts: [NodeLayout] = []
        for (depth, layer) in layers.enumerated() {
            let layerMaxWidth = layer.count * Int(nodeWidth + horizontalGap)
            let layerX = leftPadding
            for (idx, sub) in layer.enumerated() {
                let x = layerX + CGFloat(idx) * (nodeWidth + horizontalGap)
                let y = topPadding + CGFloat(depth) * (nodeHeight + verticalGap)
                let frame = CGRect(x: x, y: y, width: nodeWidth, height: nodeHeight)
                layouts.append(NodeLayout(id: sub.id, subTask: sub, frame: frame, depth: depth))
            }
            _ = layerMaxWidth
        }
        return layouts
    }
}

// MARK: - 节点详情视图

/// 节点详情 sheet 内容
private struct NodeDetailView: View {
    let node: SubTask

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // 标题
                    Text(node.title)
                        .font(.headlineAI)
                        .foregroundColor(.textPrimary)

                    // 状态标签
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                        Text(statusText)
                            .font(.captionAI)
                            .foregroundColor(statusColor)
                    }

                    Divider()

                    // 描述
                    if !node.description.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("描述")
                                .font(.subheadlineAI)
                                .foregroundColor(.textSecondary)
                            Text(node.description)
                                .font(.bodyAI)
                                .foregroundColor(.textPrimary)
                        }
                    }

                    // 工具
                    if let toolName = node.toolName {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("使用工具")
                                .font(.subheadlineAI)
                                .foregroundColor(.textSecondary)
                            Text(toolName)
                                .font(.bodyAI)
                                .foregroundColor(.electricBlue)
                        }
                    }

                    // 结果
                    if let result = node.result, !result.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("执行结果")
                                .font(.subheadlineAI)
                                .foregroundColor(.textSecondary)
                            Text(result)
                                .font(.bodyAI)
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(CornerRadius.small)
                        }
                    }

                    // 元信息
                    HStack(spacing: Spacing.lg) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("顺序")
                                .font(.captionAI)
                                .foregroundColor(.textSecondary)
                            Text("#\(node.order)")
                                .font(.bodyAI)
                                .foregroundColor(.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("深度")
                                .font(.captionAI)
                                .foregroundColor(.textSecondary)
                            Text("第 \(node.depth) 层")
                                .font(.bodyAI)
                                .foregroundColor(.textPrimary)
                        }
                        if node.parallel {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("并行")
                                    .font(.captionAI)
                                    .foregroundColor(.textSecondary)
                                Text("可并行执行")
                                    .font(.bodyAI)
                                    .foregroundColor(.textPrimary)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .navigationTitle("节点详情")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var statusIcon: String {
        switch node.status {
        case .pending: return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .skipped: return "forward.circle.fill"
        }
    }

    private var statusColor: Color {
        switch node.status {
        case .pending: return .secondary
        case .inProgress: return .electricBlue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }

    private var statusText: String {
        switch node.status {
        case .pending: return "待执行"
        case .inProgress: return "执行中"
        case .completed: return "已完成"
        case .failed: return "已失败"
        case .skipped: return "已跳过"
        }
    }
}
