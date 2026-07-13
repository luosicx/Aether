import SwiftUI

/// Aether 自定义图标渲染器：使用 SwiftUI Path / Shape 绘制简单图标
/// 作为 Asset Catalog SVG 资源的 fallback，无需额外资源文件即可显示
struct AetherIconRenderer: View {
    let icon: AetherIcon
    var size: CGFloat = 24

    var body: some View {
        Group {
            switch icon {
            case .logo: logoView
            case .mcp: mcpView
            case .memory: memoryView
            case .agent: agentView
            case .plugin: pluginView
            case .branch: branchView
            case .theme: themeView
            case .persona: personaView
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(icon.accessibilityLabel)
    }

    // MARK: - Logo：四角星

    private var logoView: some View {
        FourPointStar()
            .fill(Color.aetherGradient)
    }

    // MARK: - MCP：连接节点

    private var mcpView: some View {
        ZStack {
            // 连线
            Path { path in
                path.move(to: CGPoint(x: size * 0.3, y: size * 0.35))
                path.addLine(to: CGPoint(x: size * 0.7, y: size * 0.35))
                path.move(to: CGPoint(x: size * 0.3, y: size * 0.35))
                path.addLine(to: CGPoint(x: size * 0.5, y: size * 0.75))
                path.move(to: CGPoint(x: size * 0.7, y: size * 0.35))
                path.addLine(to: CGPoint(x: size * 0.5, y: size * 0.75))
            }
            .stroke(Color.aetherPurple, lineWidth: max(size * 0.06, 1.5))

            // 节点圆点
            Circle()
                .fill(Color.aetherPurple)
                .frame(width: size * 0.22, height: size * 0.22)
                .position(x: size * 0.3, y: size * 0.35)
            Circle()
                .fill(Color.electricBlue)
                .frame(width: size * 0.22, height: size * 0.22)
                .position(x: size * 0.7, y: size * 0.35)
            Circle()
                .fill(Color.nebulaGlow)
                .frame(width: size * 0.22, height: size * 0.22)
                .position(x: size * 0.5, y: size * 0.75)
        }
    }

    // MARK: - Memory：堆叠记忆层

    private var memoryView: some View {
        ZStack(alignment: .center) {
            // 三层堆叠的圆角矩形，模拟记忆 / 数据库
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(Color.aetherPurple.opacity(0.4))
                .frame(width: size * 0.8, height: size * 0.22)
                .offset(y: size * 0.25)
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(Color.aetherPurple.opacity(0.65))
                .frame(width: size * 0.8, height: size * 0.22)
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(Color.electricBlue)
                .frame(width: size * 0.8, height: size * 0.22)
                .offset(y: -size * 0.25)
        }
    }

    // MARK: - Agent：机器人

    private var agentView: some View {
        ZStack {
            // 天线
            Path { path in
                path.move(to: CGPoint(x: size * 0.5, y: size * 0.08))
                path.addLine(to: CGPoint(x: size * 0.5, y: size * 0.22))
            }
            .stroke(Color.aetherPurple, lineWidth: max(size * 0.06, 1.5))
            Circle()
                .fill(Color.aetherPurple)
                .frame(width: size * 0.1, height: size * 0.1)
                .position(x: size * 0.5, y: size * 0.06)

            // 头部
            RoundedRectangle(cornerRadius: size * 0.15)
                .stroke(Color.aetherPurple, lineWidth: max(size * 0.06, 1.5))
                .frame(width: size * 0.65, height: size * 0.5)
                .position(x: size * 0.5, y: size * 0.55)

            // 眼睛
            Circle()
                .fill(Color.electricBlue)
                .frame(width: size * 0.12, height: size * 0.12)
                .position(x: size * 0.38, y: size * 0.5)
            Circle()
                .fill(Color.electricBlue)
                .frame(width: size * 0.12, height: size * 0.12)
                .position(x: size * 0.62, y: size * 0.5)
        }
    }

    // MARK: - Plugin：拼图插件

    private var pluginView: some View {
        ZStack {
            // 拼图主体：圆角方形 + 右侧凸出
            Path { path in
                let inset: CGFloat = size * 0.15
                let tabR: CGFloat = size * 0.1
                // 从左上开始顺时针
                path.move(to: CGPoint(x: inset, y: inset))
                // 上边 → 右上
                path.addLine(to: CGPoint(x: size - inset, y: inset))
                path.addLine(to: CGPoint(x: size - inset, y: size * 0.4))
                // 右侧凸出半圆
                path.addArc(
                    center: CGPoint(x: size - inset, y: size * 0.5),
                    radius: tabR,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                // 下边 → 左下
                path.addLine(to: CGPoint(x: inset, y: size - inset))
                path.closeSubpath()
            }
            .fill(Color.aetherPurple.opacity(0.7))
            .overlay(
                Path { path in
                    let inset: CGFloat = size * 0.15
                    let tabR: CGFloat = size * 0.1
                    path.move(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.addLine(to: CGPoint(x: size - inset, y: size * 0.4))
                    path.addArc(
                        center: CGPoint(x: size - inset, y: size * 0.5),
                        radius: tabR,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(90),
                        clockwise: false
                    )
                    path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.closeSubpath()
                }
                .stroke(Color.aetherPurple, lineWidth: max(size * 0.05, 1.5))
            )
        }
    }

    // MARK: - Branch：分支

    private var branchView: some View {
        ZStack {
            // 主线 + 分支线
            Path { path in
                // 垂直主线
                path.move(to: CGPoint(x: size * 0.35, y: size * 0.2))
                path.addLine(to: CGPoint(x: size * 0.35, y: size * 0.8))
                // 分支弧线
                path.move(to: CGPoint(x: size * 0.35, y: size * 0.5))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.7, y: size * 0.5),
                    control: CGPoint(x: size * 0.5, y: size * 0.35)
                )
            }
            .stroke(Color.aetherPurple, lineWidth: max(size * 0.06, 1.5))

            // 三个节点
            Circle()
                .fill(Color.aetherPurple)
                .frame(width: size * 0.2, height: size * 0.2)
                .position(x: size * 0.35, y: size * 0.2)
            Circle()
                .fill(Color.electricBlue)
                .frame(width: size * 0.2, height: size * 0.2)
                .position(x: size * 0.35, y: size * 0.8)
            Circle()
                .fill(Color.nebulaGlow)
                .frame(width: size * 0.2, height: size * 0.2)
                .position(x: size * 0.7, y: size * 0.5)
        }
    }

    // MARK: - Theme：调色板

    private var themeView: some View {
        ZStack {
            // 调色板主体：椭圆
            Ellipse()
                .fill(Color.liquidGlass.opacity(0.6))
                .overlay(
                    Ellipse()
                        .stroke(Color.aetherPurple, lineWidth: max(size * 0.05, 1.5))
                )
                .frame(width: size * 0.85, height: size * 0.7)
                .position(x: size * 0.5, y: size * 0.5)

            // 颜料点
            Circle()
                .fill(Color.aetherPurple)
                .frame(width: size * 0.12, height: size * 0.12)
                .position(x: size * 0.3, y: size * 0.38)
            Circle()
                .fill(Color.electricBlue)
                .frame(width: size * 0.12, height: size * 0.12)
                .position(x: size * 0.5, y: size * 0.32)
            Circle()
                .fill(Color.nebulaGlow)
                .frame(width: size * 0.12, height: size * 0.12)
                .position(x: size * 0.68, y: size * 0.42)
        }
    }

    // MARK: - Persona：人设

    private var personaView: some View {
        ZStack {
            // 头部圆
            Circle()
                .fill(Color.aetherPurple.opacity(0.7))
                .frame(width: size * 0.35, height: size * 0.35)
                .position(x: size * 0.5, y: size * 0.3)

            // 肩膀 / 身体
            Path { path in
                path.move(to: CGPoint(x: size * 0.2, y: size * 0.85))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.8, y: size * 0.85),
                    control: CGPoint(x: size * 0.5, y: size * 0.45)
                )
                path.closeSubpath()
            }
            .fill(Color.aetherPurple.opacity(0.5))
        }
    }
}

// MARK: - 四角星 Shape

/// Aether Logo 使用的四角星：四角内凹的菱形
struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let w = rect.width / 2
        let h = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - h))
        path.addLine(to: CGPoint(x: cx + w * 0.35, y: cy - h * 0.35))
        path.addLine(to: CGPoint(x: cx + w, y: cy))
        path.addLine(to: CGPoint(x: cx + w * 0.35, y: cy + h * 0.35))
        path.addLine(to: CGPoint(x: cx, y: cy + h))
        path.addLine(to: CGPoint(x: cx - w * 0.35, y: cy + h * 0.35))
        path.addLine(to: CGPoint(x: cx - w, y: cy))
        path.addLine(to: CGPoint(x: cx - w * 0.35, y: cy - h * 0.35))
        path.closeSubpath()
        return path
    }
}

// MARK: - 预览

#Preview("Icon Grid") {
    let columns = [GridItem(.adaptive(minimum: 60))]
    ScrollView {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(AetherIcon.allCases, id: \.self) { icon in
                VStack(spacing: 6) {
                    AetherIconRenderer(icon: icon, size: 28)
                    Text(icon.accessibilityLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
