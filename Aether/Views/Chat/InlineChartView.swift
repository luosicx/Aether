import SwiftUI
import AetherDesign

/// Task 22: 内联图表视图——使用自定义 Path 绘制简单图表。
/// 支持 bar（竖条形图）/ line（折线图）/ pie（饼图）三种类型。
struct InlineChartView: View {
    /// 图表数据：标签与数值对
    let data: [(label: String, value: Double)]
    /// 图表类型
    let type: ChartType

    /// 图表类型枚举
    enum ChartType {
        case bar
        case line
        case pie
    }

    /// 颜色调色板（饼图各扇区颜色循环使用）
    private let palette: [Color] = [
        Color.aetherPurple,
        Color.electricBlue,
        Color.nebulaGlow,
        .orange,
        .green,
        .red,
        .pink,
        .teal
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartContent
                .frame(height: chartHeight)
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(Color.bubbleAI.opacity(0.4))
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .stroke(Color.aetherPurple.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

            // 图例
            if !data.isEmpty {
                legendView
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("图表数据")
        .accessibilityValue(data.map { "\($0.label): \(String(format: "%.1f", $0.value))" }.joined(separator: "，"))
    }

    // MARK: - 图表内容

    /// 图表高度
    private var chartHeight: CGFloat {
        switch type {
        case .bar, .line:
            return 180
        case .pie:
            return 200
        }
    }

    /// 根据类型选择图表渲染
    @ViewBuilder
    private var chartContent: some View {
        if data.isEmpty {
            Text("暂无数据", comment: "")
                .font(.captionAI)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch type {
            case .bar:
                barChart
            case .line:
                lineChart
            case .pie:
                pieChart
            }
        }
    }

    // MARK: - 竖条形图

    /// 竖条形图：每个数据项一个竖条，底部标注标签
    private var barChart: some View {
        GeometryReader { geo in
            let maxValue = data.map(\.value).max() ?? 1
            let barCount = data.count
            let totalSpacing: CGFloat = CGFloat(barCount) * 8
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(barCount), 12)
            let chartHeight = geo.size.height - 24 // 底部留 24pt 给标签

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 4) {
                        // 数值标签
                        Text(formatValue(item.value))
                            .font(.captionAI)
                            .foregroundStyle(.secondary)

                        // 竖条
                        let height = maxValue > 0
                            ? CGFloat(item.value / maxValue) * chartHeight
                            : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(palette[index % palette.count])
                            .frame(width: barWidth, height: max(height, 2))

                        // 底部标签
                        Text(item.label)
                            .font(.captionAI)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: barWidth)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - 折线图

    /// 折线图：按顺序连接各数据点
    private var lineChart: some View {
        GeometryReader { geo in
            let maxValue = data.map(\.value).max() ?? 1
            let minValue = data.map(\.value).min() ?? 0
            let valueRange = maxValue - minValue > 0 ? maxValue - minValue : 1
            let chartWidth = geo.size.width
            let chartHeight = geo.size.height - 24 // 底部留 24pt 给标签
            let stepX = data.count > 1 ? chartWidth / CGFloat(data.count - 1) : chartWidth

            // 计算各数据点坐标
            let points = data.enumerated().map { index, item -> CGPoint in
                let x = data.count > 1 ? CGFloat(index) * stepX : chartWidth / 2
                let normalizedValue = CGFloat((item.value - minValue) / valueRange)
                let y = chartHeight - normalizedValue * chartHeight
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // 绘制折线
                if points.count >= 2 {
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            path.addLine(to: points[i])
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.aetherPurple, Color.electricBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }

                // 绘制填充区域
                if points.count >= 2 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: chartHeight))
                        path.addLine(to: points[0])
                        for i in 1..<points.count {
                            path.addLine(to: points[i])
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: chartHeight))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.aetherPurple.opacity(0.2), Color.electricBlue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // 绘制数据点
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(palette[index % palette.count])
                        .frame(width: 8, height: 8)
                        .position(point)
                }

                // 底部标签
                VStack {
                    Spacer()
                    HStack {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                            Text(item.label)
                                .font(.captionAI)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if data.count > 1 { Spacer() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 饼图

    /// 饼图：各扇区占比展示
    private var pieChart: some View {
        GeometryReader { geo in
            let total = data.map(\.value).reduce(0, +)
            let center = CGPoint(x: geo.size.width / 2, y: (geo.size.height - 24) / 2)
            let radius = min(geo.size.width, geo.size.height - 24) / 2 - 8

            ZStack {
                if total > 0 {
                    // 绘制饼图扇区
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        let startAngle = startAngleFor(item: index, total: total)
                        let endAngle = endAngleFor(item: index, total: total)

                        // 扇区
                        Path { path in
                            path.move(to: center)
                            path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(palette[index % palette.count])
                        .overlay(
                            Path { path in
                                path.move(to: center)
                                path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                                path.closeSubpath()
                            }
                            .stroke(Color.white, lineWidth: 2)
                        )
                    }

                    // 中心百分比文字（仅当扇区足够大时显示）
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        let percentage = total > 0 ? item.value / total : 0
                        if percentage > 0.1 {
                            let midAngle = midAngleFor(item: index, total: total)
                            let labelRadius = radius * 0.65
                            let labelX = center.x + cos(midAngle) * labelRadius
                            let labelY = center.y + sin(midAngle) * labelRadius

                            Text(String(format: "%.0f%%", percentage * 100))
                                .font(.captionAI.weight(.medium))
                                .foregroundStyle(.white)
                                .position(x: labelX, y: labelY)
                        }
                    }
                } else {
                    Text("暂无数据", comment: "")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                }

                // 底部标签
                VStack {
                    Spacer()
                    HStack {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                            Text(item.label)
                                .font(.captionAI)
                                .foregroundStyle(.secondary)
                            if data.count > 1 { Spacer() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 饼图角度计算

    /// 计算指定数据项的起始角度
    private func startAngleFor(item index: Int, total: Double) -> Angle {
        let prior = data.prefix(index).map(\.value).reduce(0, +)
        let ratio = total > 0 ? prior / total : 0
        return .degrees(-90 + ratio * 360)
    }

    /// 计算指定数据项的结束角度
    private func endAngleFor(item index: Int, total: Double) -> Angle {
        let prior = data.prefix(index + 1).map(\.value).reduce(0, +)
        let ratio = total > 0 ? prior / total : 0
        return .degrees(-90 + ratio * 360)
    }

    /// 计算指定数据项的中线角度
    private func midAngleFor(item index: Int, total: Double) -> CGFloat {
        let start = startAngleFor(item: index, total: total).degrees
        let end = endAngleFor(item: index, total: total).degrees
        let mid = (start + end) / 2
        // SwiftUI Path 的角度以弧度计算，且 y 轴向下为正
        return CGFloat(mid) * .pi / 180
    }

    // MARK: - 图例

    /// 图例视图
    private var legendView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: Spacing.xs) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(palette[index % palette.count])
                        .frame(width: 8, height: 8)
                    Text(item.label)
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 格式化

    /// 格式化数值显示
    private func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        } else if value == value.rounded() {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}
