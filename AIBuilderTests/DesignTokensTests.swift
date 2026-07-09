import XCTest
import SwiftUI
@testable import AIBuilder

final class DesignTokensTests: XCTestCase {

    func testSpacingTokensFollowFourPointGrid() {
        XCTAssertEqual(Spacing.xs, 2)
        XCTAssertEqual(Spacing.sm, 4)
        XCTAssertEqual(Spacing.md, 8)
        XCTAssertEqual(Spacing.lg, 12)
        XCTAssertEqual(Spacing.xl, 16)
        XCTAssertEqual(Spacing.xxl, 24)
        XCTAssertEqual(Spacing.xxxl, 32)
    }

    func testCornerRadiusTokens() {
        XCTAssertEqual(CornerRadius.small, 8)
        XCTAssertEqual(CornerRadius.medium, 12)
        XCTAssertEqual(CornerRadius.large, 18)
    }

    func testColorTokensResolveOnCurrentPlatform() {
        // 仅验证可解析，不验证具体色值（平台相关）
        _ = Color.backgroundPrimary
        _ = Color.backgroundSecondary
        _ = Color.backgroundTertiary
        _ = Color.bubbleUser
        _ = Color.bubbleAssistant
        _ = Color.textPrimary
        _ = Color.textSecondary
        _ = Color.textTertiary
        _ = Color.separator
        _ = Color.codeBackgroundLight
        _ = Color.codeBackgroundDark
        _ = Color.codeBorder
    }

    func testTypographyTokensResolve() {
        _ = Font.bodyAI
        _ = Font.subheadlineAI
        _ = Font.captionAI
        _ = Font.headlineAI
        _ = Font.titleAI
        _ = Font.emptyStateTitle
        _ = Font.monoAI
        _ = Font.toolLabel
    }

    func testAnimationTokensResolve() {
        _ = AnimationTokens.transition
        _ = AnimationTokens.messageAppear
        _ = AnimationTokens.buttonPress
        _ = AnimationTokens.skeleton
        _ = AnimationTokens.blink
    }
}
