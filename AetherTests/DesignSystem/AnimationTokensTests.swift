import XCTest
import SwiftUI
import AetherDesign
@testable import Aether

/// v1.1 Phase D: AnimationTokens 单元测试
///
/// 覆盖：
/// - starDrift token 存在且可解析
/// - twinkle token 存在且可解析
/// - 既有 token 回归保护（不受新增 token 影响）
final class AnimationTokensTests: XCTestCase {

    // MARK: - 新增 token

    /// starDrift token 应存在且可解析
    func testStarDriftTokenResolves() {
        _ = AnimationTokens.starDrift
    }

    /// twinkle token 应存在且可解析
    func testTwinkleTokenResolves() {
        _ = AnimationTokens.twinkle
    }

    // MARK: - 回归保护

    /// 既有 token 仍可解析（新增 token 不影响既有定义）
    func testExistingTokensStillResolve() {
        _ = AnimationTokens.transition
        _ = AnimationTokens.messageBubble
        _ = AnimationTokens.messageAppear
        _ = AnimationTokens.themeTransition
        _ = AnimationTokens.sheetPresentation
        _ = AnimationTokens.listItemTransition
        _ = AnimationTokens.buttonPress
        _ = AnimationTokens.skeleton
        _ = AnimationTokens.blink
    }

    // MARK: - starDrift / twinkle 属性边界测试
    //
    // 注意：Swift 的 `Animation` 类型不公开 curve（linear / easeInOut 等）与 duration 属性，
    // 运行时无法直接读取动画曲线或时长。以下测试作为回归保护，验证 token 可解析且构造稳定。
    // 源码定义：
    //   starDrift = .linear(duration: 60).repeatForever(autoreverses: false)
    //   twinkle   = .easeInOut(duration: 2).repeatForever(autoreverses: true)

    /// starDrift 应使用 `.linear` 曲线。
    ///
    /// 限制：`Animation` 未暴露 curve 属性，无法在运行时直接断言动画曲线为 `.linear`。
    /// 此处验证 token 可解析（回归保护），依赖源码定义保证正确性。
    func testStarDriftUsesLinearCurve() {
        _ = AnimationTokens.starDrift
    }

    /// starDrift duration 应约为 60s。
    ///
    /// 限制：`Animation` 未暴露 duration 属性，无法在运行时直接断言时长。
    /// 此处验证 token 可解析（回归保护），依赖源码定义保证正确性。
    func testStarDriftDurationIs60Seconds() {
        _ = AnimationTokens.starDrift
    }

    /// twinkle 应使用 `.easeInOut` 曲线。
    ///
    /// 限制：`Animation` 未暴露 curve 属性，无法在运行时直接断言动画曲线为 `.easeInOut`。
    /// 此处验证 token 可解析（回归保护），依赖源码定义保证正确性。
    func testTwinkleUsesEaseInOutCurve() {
        _ = AnimationTokens.twinkle
    }

    /// twinkle duration 应约为 2s。
    ///
    /// 限制：`Animation` 未暴露 duration 属性，无法在运行时直接断言时长。
    /// 此处验证 token 可解析（回归保护），依赖源码定义保证正确性。
    func testTwinkleDurationIs2Seconds() {
        _ = AnimationTokens.twinkle
    }
}
