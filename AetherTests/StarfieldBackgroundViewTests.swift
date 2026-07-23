import XCTest
import SwiftUI
@testable import Aether

/// v1.1 Phase D: StarfieldBackgroundView 单元测试
///
/// 覆盖：
/// - 粒子初始化与数量（80 颗）
/// - 固定种子可复现性
/// - 粒子位置在 0..<1 范围内
/// - 粒子亮度/大小范围
/// - 粒子漂移回绕逻辑（超过 1.0 回绕到 0.0）
final class StarfieldBackgroundViewTests: XCTestCase {

    // MARK: - 粒子初始化与数量

    /// 默认初始化应生成 80 颗粒子
    func testDefaultParticleCount() {
        let view = StarfieldBackgroundView()
        XCTAssertEqual(view.particles.count, StarfieldBackgroundView.particleCount, "默认粒子数应等于 particleCount")
        XCTAssertEqual(view.particles.count, 80, "默认粒子数应为 80")
    }

    /// 自定义粒子数应正确生成
    func testCustomParticleCount() {
        let view = StarfieldBackgroundView(particleCount: 30, seed: 42)
        XCTAssertEqual(view.particles.count, 30, "自定义粒子数应为 30")
    }

    /// 零粒子数应生成空集合（不崩溃）
    func testZeroParticleCount() {
        let view = StarfieldBackgroundView(particleCount: 0, seed: 1)
        XCTAssertTrue(view.particles.isEmpty, "零粒子数应生成空集合")
    }

    // MARK: - 固定种子可复现性

    /// 相同种子应生成相同粒子集合
    func testSeededReproducibility() {
        let view1 = StarfieldBackgroundView(seed: 0xAE7E5EED)
        let view2 = StarfieldBackgroundView(seed: 0xAE7E5EED)
        XCTAssertEqual(view1.particles, view2.particles, "相同种子应生成相同粒子集合")
    }

    /// 不同种子应生成不同粒子集合
    func testDifferentSeedProducesDifferentParticles() {
        let view1 = StarfieldBackgroundView(seed: 1)
        let view2 = StarfieldBackgroundView(seed: 2)
        XCTAssertNotEqual(view1.particles, view2.particles, "不同种子应生成不同粒子集合")
    }

    // MARK: - 粒子位置范围

    /// 所有粒子横坐标应在 [0, 1) 范围内
    func testParticleXInRange() {
        let view = StarfieldBackgroundView()
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.x, 0, "x 应 >= 0")
            XCTAssertLessThan(particle.x, 1.0, "x 应 < 1.0")
        }
    }

    /// 所有粒子纵坐标应在 [0, 1) 范围内
    func testParticleYInRange() {
        let view = StarfieldBackgroundView()
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.y, 0, "y 应 >= 0")
            XCTAssertLessThan(particle.y, 1.0, "y 应 < 1.0")
        }
    }

    /// 所有粒子亮度应在 [0, 1] 范围内
    func testParticleBrightnessInRange() {
        let view = StarfieldBackgroundView()
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.brightness, 0, "brightness 应 >= 0")
            XCTAssertLessThanOrEqual(particle.brightness, 1.0, "brightness 应 <= 1.0")
        }
    }

    /// 所有星点大小应在 1-3 像素范围
    func testParticleSizeInRange() {
        let view = StarfieldBackgroundView()
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.size, 1.0, "size 应 >= 1.0")
            XCTAssertLessThanOrEqual(particle.size, 3.0, "size 应 <= 3.0")
        }
    }

    /// 混色比例 tint 应在 [0, 1] 范围内
    func testParticleTintInRange() {
        let view = StarfieldBackgroundView()
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.tint, 0, "tint 应 >= 0")
            XCTAssertLessThanOrEqual(particle.tint, 1.0, "tint 应 <= 1.0")
        }
    }

    // MARK: - 漂移回绕逻辑

    /// 漂移超过 1.0 时回绕到 0.0 范围
    func testDriftWrapAroundAboveOne() {
        // 初始 x=0.9, speed=0.1, elapsed=2 → 0.9 + 0.2 = 1.1 → 回绕到 0.1
        let result = StarfieldBackgroundView.advancedX(0.9, driftSpeed: 0.1, elapsed: 2)
        XCTAssertEqual(result, 0.1, accuracy: 0.0001, "0.9 + 0.2 应回绕到 0.1")
    }

    /// 漂移未超过 1.0 时保持原值
    func testDriftNoWrapBelowOne() {
        let result = StarfieldBackgroundView.advancedX(0.3, driftSpeed: 0.1, elapsed: 1)
        XCTAssertEqual(result, 0.4, accuracy: 0.0001, "0.3 + 0.1 应为 0.4")
    }

    /// 漂移经过多个周期正确回绕
    func testDriftMultipleWrapAround() {
        // x=0.5, speed=0.3, elapsed=10 → 0.5 + 3.0 = 3.5 → 3.5 mod 1.0 = 0.5
        let result = StarfieldBackgroundView.advancedX(0.5, driftSpeed: 0.3, elapsed: 10)
        XCTAssertEqual(result, 0.5, accuracy: 0.0001, "多周期回绕应为 0.5")
    }

    /// 零漂移速度时位置不变
    func testDriftZeroSpeed() {
        let result = StarfieldBackgroundView.advancedX(0.7, driftSpeed: 0, elapsed: 100)
        XCTAssertEqual(result, 0.7, accuracy: 0.0001, "零速度时位置不变")
    }

    /// 回绕结果始终在 [0, 1) 范围内
    func testDriftResultAlwaysInRange() {
        let speeds: [Double] = [0.005, 0.01, 0.02, 0.1, 0.5]
        for x in stride(from: 0.0, through: 0.95, by: 0.05) {
            for speed in speeds {
                let result = StarfieldBackgroundView.advancedX(x, driftSpeed: speed, elapsed: 1234.5)
                XCTAssertGreaterThanOrEqual(result, 0, "回绕结果应 >= 0 (x=\(x), speed=\(speed))")
                XCTAssertLessThan(result, 1.0, "回绕结果应 < 1.0 (x=\(x), speed=\(speed))")
            }
        }
    }

    /// 漂移恰好到达 1.0 时回绕到 0.0
    func testDriftExactOne() {
        // x=0.5, speed=0.5, elapsed=1 → 0.5 + 0.5 = 1.0 → 1.0 mod 1.0 = 0.0
        let result = StarfieldBackgroundView.advancedX(0.5, driftSpeed: 0.5, elapsed: 1)
        XCTAssertEqual(result, 0.0, accuracy: 0.0001, "恰好 1.0 应回绕到 0.0")
    }

    // MARK: - 粒子参数范围边界测试

    /// 所有粒子的 twinklePhase 应在 0.5...2.0 范围内（源码 Double.random(in: 0.5...2.0)）
    func testTwinklePhaseInRange() {
        let view = StarfieldBackgroundView()
        XCTAssertFalse(view.particles.isEmpty, "默认应有粒子")
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.twinklePhase, 0.5, "twinklePhase 应 >= 0.5")
            XCTAssertLessThanOrEqual(particle.twinklePhase, 2.0, "twinklePhase 应 <= 2.0")
        }
    }

    /// 所有粒子的 driftSpeed 应在 0.005...0.02 范围内（源码 Double.random(in: 0.005...0.02)）
    func testDriftSpeedInRange() {
        let view = StarfieldBackgroundView()
        XCTAssertFalse(view.particles.isEmpty, "默认应有粒子")
        for particle in view.particles {
            XCTAssertGreaterThanOrEqual(particle.driftSpeed, 0.005, "driftSpeed 应 >= 0.005")
            XCTAssertLessThanOrEqual(particle.driftSpeed, 0.02, "driftSpeed 应 <= 0.02")
        }
    }

    // MARK: - 负漂移速度回绕

    /// 负 driftSpeed 时 advancedX 应正确回绕到 [0, 1) 范围
    func testAdvancedXWithNegativeDriftSpeed() {
        // x=0.1, speed=-0.1, elapsed=2 → 0.1 - 0.2 = -0.1 → truncatingRemainder = -0.1 → +1.0 = 0.9
        let result1 = StarfieldBackgroundView.advancedX(0.1, driftSpeed: -0.1, elapsed: 2)
        XCTAssertEqual(result1, 0.9, accuracy: 0.0001, "负漂移 -0.1 应回绕到 0.9")

        // x=0.5, speed=-0.3, elapsed=10 → 0.5 - 3.0 = -2.5 → truncatingRemainder(-2.5, 1.0) = -0.5 → +1.0 = 0.5
        let result2 = StarfieldBackgroundView.advancedX(0.5, driftSpeed: -0.3, elapsed: 10)
        XCTAssertEqual(result2, 0.5, accuracy: 0.0001, "多周期负漂移应回绕到 0.5")

        // 负漂移结果始终在 [0, 1) 范围内
        let result3 = StarfieldBackgroundView.advancedX(0.3, driftSpeed: -0.5, elapsed: 1234.5)
        XCTAssertGreaterThanOrEqual(result3, 0, "负漂移结果应 >= 0")
        XCTAssertLessThan(result3, 1.0, "负漂移结果应 < 1.0")
    }

    // MARK: - SeededRandomNumberGenerator 边界测试

    /// seed=0 时 SeededRandomNumberGenerator 不应产生全 0 序列（init 注入常数 0x9E3779B97F4A7C15）
    func testSeededGeneratorWithZeroSeed() {
        var rng = SeededRandomNumberGenerator(seed: 0)
        var values: [UInt64] = []
        for _ in 0..<10 {
            values.append(rng.next())
        }
        XCTAssertTrue(values.contains(where: { $0 != 0 }), "seed=0 不应产生全 0 序列（init 注入常数）")
    }

    /// 两个相同 seed 的 SeededRandomNumberGenerator 应产出相同序列
    func testSeededGeneratorReproducibility() {
        let seed: UInt64 = 12345
        var rng1 = SeededRandomNumberGenerator(seed: seed)
        var rng2 = SeededRandomNumberGenerator(seed: seed)

        var seq1: [UInt64] = []
        var seq2: [UInt64] = []
        for _ in 0..<10 {
            seq1.append(rng1.next())
            seq2.append(rng2.next())
        }
        XCTAssertEqual(seq1, seq2, "相同 seed 应产出相同序列")
    }
}
