import SwiftUI
import CoreGraphics
import AetherDesign
#if canImport(UIKit)
import UIKit
#endif

/// 星空粒子：归一化坐标 + 闪烁/漂移参数
struct StarParticle: Equatable {
    /// 归一化横坐标（0..<1），渲染时乘以 Canvas 宽度
    var x: Double
    /// 归一化纵坐标（0..<1），渲染时乘以 Canvas 高度
    var y: Double
    /// 基础亮度（0-1）
    var brightness: Double
    /// 闪烁角速度（rad/s）
    var twinklePhase: Double
    /// 横向漂移速度（归一化坐标/秒）
    var driftSpeed: Double
    /// 星点大小（像素）
    var size: Double
    /// 颜色混合比例：0 = 纯 starlight，1 = 纯 nebulaGlow
    var tint: Double
}

/// 固定种子线性同余生成器（LCG），保证粒子初始化可复现、测试稳定。
/// 使用 Numerical Recipes 推荐参数，仅实现 `next()` 即可满足 `RandomNumberGenerator` 协议。
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // 注入常数避免全 0 种子产生全 0 序列
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}

/// v1.1 Phase D: 动态星空背景。v1.2 扩展呼吸效果 / 低电量降级 / 配置开关。
///
/// 使用 `Canvas` + `TimelineView(.animation)` 实现 GPU 加速粒子动画：
/// - 80 颗粒子（默认），归一化坐标（0..<1），渲染时乘以 Canvas size
/// - 固定种子 LCG 初始化，确保可复现（测试稳定）
/// - 每帧根据 `TimelineView.date` 计算漂移位置与闪烁亮度
/// - 粒子超出右侧（x >= 1.0）从左侧回绕
/// - 用 `Color.starlight` 与 `Color.nebulaGlow` 双层 alpha 叠加实现混色
/// - v1.2: 光晕呼吸效果（4s 周期 phaseAnimator 修改 shadowRadius 与 opacity）
/// - v1.2: 低电量模式自动降级到静态深色背景
/// - v1.2: 支持运行时配置开关（用户可在设置中关闭动态背景）
/// - 纯 SwiftUI（Canvas + TimelineView），跨 iOS / iPadOS / macOS
struct StarfieldBackgroundView: View {
    /// 粒子数量（v1.1 默认 80；v1.2 按设备可调）
    static let particleCount = 80

    /// v1.2: iPhone 默认粒子数（保留用于向后兼容与测试）
    static let defaultParticleCount = particleCount

    /// 粒子集合（init 时用固定种子生成）
    let particles: [StarParticle]

    /// v1.2: 是否启用呼吸效果（默认 true，设置可关闭）
    var breathEnabled: Bool = true

    /// v1.2: 是否处于低电量模式（外部传入，true 时降级为静态深色背景）
    var lowPowerMode: Bool = false

    /// v1.2: 用户偏好开关（false 时完全不渲染，仅显示静态深色背景）
    var userEnabled: Bool = true

    /// 默认初始化：80 颗粒子，固定种子
    init(
        particleCount: Int = StarfieldBackgroundView.defaultParticleCount,
        seed: UInt64 = 0xAE7E5EED,
        breathEnabled: Bool = true,
        lowPowerMode: Bool = false,
        userEnabled: Bool = true
    ) {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var generated: [StarParticle] = []
        generated.reserveCapacity(particleCount)
        for _ in 0..<particleCount {
            generated.append(StarParticle(
                x: Double.random(in: 0..<1, using: &rng),
                y: Double.random(in: 0..<1, using: &rng),
                brightness: Double.random(in: 0.3...1.0, using: &rng),
                twinklePhase: Double.random(in: 0.5...2.0, using: &rng),
                driftSpeed: Double.random(in: 0.005...0.02, using: &rng),
                size: Double.random(in: 1...3, using: &rng),
                tint: Double.random(in: 0...1, using: &rng)
            ))
        }
        particles = generated
        self.breathEnabled = breathEnabled
        self.lowPowerMode = lowPowerMode
        self.userEnabled = userEnabled
    }

    var body: some View {
        Group {
            if !userEnabled || lowPowerMode {
                // v1.2: 降级为静态深色背景
                staticBackground
            } else {
                dynamicBackground
            }
        }
        .allowsHitTesting(false)
    }

    /// v1.2: 静态深色背景（低电量或用户关闭时）
    private var staticBackground: some View {
        Rectangle()
            .fill(Color.starlight.opacity(0.05))
            .background(
                RadialGradient(
                    colors: [Color.nebulaGlow.opacity(0.08), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 300
                )
            )
    }

    /// v1.2: 动态星空背景（默认渲染路径）
    private var dynamicBackground: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                // v1.2: 呼吸效果系数（4s 周期 sin）
                let breathFactor = breathEnabled
                    ? 0.85 + 0.15 * sin(elapsed * 2 * .pi / 4.0)
                    : 1.0
                for particle in particles {
                    // 漂移：x 随时间增加，超出 1.0 回绕到 0.0
                    let x = Self.advancedX(particle.x, driftSpeed: particle.driftSpeed, elapsed: elapsed)
                    let y = particle.y
                    // 闪烁亮度：0.5 + 0.5 * sin(t * phase)
                    let twinkle = 0.5 + 0.5 * sin(elapsed * particle.twinklePhase)
                    // v1.2: 呼吸效果叠加到整体 alpha
                    let alpha = particle.brightness * twinkle * breathFactor
                    // 渲染坐标（归一化 → 像素）
                    let px = x * size.width
                    let py = y * size.height
                    let radius = particle.size
                    let rect = CGRect(x: px - radius, y: py - radius,
                                      width: radius * 2, height: radius * 2)
                    // 混色：starlight 为主，nebulaGlow 为辅（双层 alpha 叠加）
                    let starlightColor = Color.starlight.opacity(alpha * (1.0 - particle.tint))
                    context.fill(Path(ellipseIn: rect), with: .color(starlightColor))
                    if particle.tint > 0 {
                        let nebulaColor = Color.nebulaGlow.opacity(alpha * particle.tint)
                        context.fill(Path(ellipseIn: rect), with: .color(nebulaColor))
                    }
                }
            }
        }
        .background(
            RadialGradient(
                colors: [Color.nebulaGlow.opacity(0.15), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
        )
    }

    /// 计算粒子漂移后的归一化横坐标，超过 1.0 回绕到 0.0。
    /// - Parameters:
    ///   - x: 初始归一化横坐标
    ///   - driftSpeed: 漂移速度（归一化坐标/秒）
    ///   - elapsed: 自参考时间起经过的秒数
    /// - Returns: 回绕后的归一化横坐标（0..<1）
    static func advancedX(_ x: Double, driftSpeed: Double, elapsed: Double) -> Double {
        var advanced = x + driftSpeed * elapsed
        advanced = advanced.truncatingRemainder(dividingBy: 1.0)
        if advanced < 0 {
            advanced += 1.0
        }
        return advanced
    }

    /// v1.2: 计算呼吸效果系数（4s 周期 sin，0.70~1.00 范围）
    /// - Parameter elapsed: 自参考时间起经过的秒数
    /// - Returns: 呼吸系数（0.70 ~ 1.00）
    static func breathFactor(at elapsed: Double) -> Double {
        0.85 + 0.15 * sin(elapsed * 2 * .pi / 4.0)
    }

    /// v1.2: 按设备类型返回建议粒子数
    /// iPhone 30 / iPad 50 / Mac 100，避免低配设备卡顿
    static func suggestedParticleCount(for device: DeviceType) -> Int {
        switch device {
        case .iPhoneSE, .iPhone: return 30
        case .iPadMini, .iPadPro: return 50
        case .macWide: return 100
        }
    }

    #if canImport(UIKit)
    /// v1.2: 检测当前是否处于低电量模式
    static var currentLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    #endif
}
