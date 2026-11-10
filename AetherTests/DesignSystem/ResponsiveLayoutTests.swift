import XCTest
import AetherDesign

/// v1.2 响应式布局单元测试
/// 覆盖 LayoutSize 判定 / 属性映射 / DefaultLayoutStrategy 决策
final class ResponsiveLayoutTests: XCTestCase {

    // MARK: - LayoutSize.resolve 判定测试

    /// compact size class + 375pt 宽度 → .compact
    func testResolveCompactSizeClassNarrowWidth() {
        XCTAssertEqual(LayoutSize.resolve(width: 320, horizontalSizeClass: .compact), .compact)
        XCTAssertEqual(LayoutSize.resolve(width: 375, horizontalSizeClass: .compact), .compact)
    }

    /// compact size class + 较宽宽度 → .medium
    func testResolveCompactSizeClassWideWidth() {
        XCTAssertEqual(LayoutSize.resolve(width: 400, horizontalSizeClass: .compact), .medium)
        XCTAssertEqual(LayoutSize.resolve(width: 430, horizontalSizeClass: .compact), .medium)
    }

    /// regular size class + 768 以下 → .medium
    func testResolveRegularSizeClassNarrowWidth() {
        XCTAssertEqual(LayoutSize.resolve(width: 600, horizontalSizeClass: .regular), .medium)
        XCTAssertEqual(LayoutSize.resolve(width: 700, horizontalSizeClass: .regular), .medium)
    }

    /// regular size class + 768~1024 → .large
    func testResolveRegularSizeClassMediumWidth() {
        XCTAssertEqual(LayoutSize.resolve(width: 768, horizontalSizeClass: .regular), .large)
        XCTAssertEqual(LayoutSize.resolve(width: 1000, horizontalSizeClass: .regular), .large)
    }

    /// regular size class + ≥1440 → .xl
    func testResolveRegularSizeClassXlWidth() {
        XCTAssertEqual(LayoutSize.resolve(width: 1440, horizontalSizeClass: .regular), .xl)
        XCTAssertEqual(LayoutSize.resolve(width: 1920, horizontalSizeClass: .regular), .xl)
    }

    /// nil size class 视作 regular 行为
    func testResolveNilSizeClassFallsBackToRegular() {
        XCTAssertEqual(LayoutSize.resolve(width: 800, horizontalSizeClass: nil), .large)
    }

    // MARK: - bubbleMaxWidth 测试

    /// compact 气泡宽度无限制（撑满）
    func testBubbleMaxWidthCompactIsInfinite() {
        XCTAssertTrue(LayoutSize.compact.bubbleMaxWidth.isInfinite)
    }

    /// medium 气泡宽度限制为 500pt
    func testBubbleMaxWidthMediumIs500() {
        XCTAssertEqual(LayoutSize.medium.bubbleMaxWidth, 500)
    }

    /// large / xl 气泡宽度限制为 680pt（防止过宽难读）
    func testBubbleMaxWidthLargeAndXlIs680() {
        XCTAssertEqual(LayoutSize.large.bubbleMaxWidth, 680)
        XCTAssertEqual(LayoutSize.xl.bubbleMaxWidth, 680)
    }

    // MARK: - 工具栏折叠 / 输入框单行 / 三栏测试

    /// compact 工具栏折叠为 Menu
    func testToolbarCollapseToMenuCompactOnly() {
        XCTAssertTrue(LayoutSize.compact.toolbarCollapseToMenu)
        XCTAssertFalse(LayoutSize.medium.toolbarCollapseToMenu)
        XCTAssertFalse(LayoutSize.large.toolbarCollapseToMenu)
        XCTAssertFalse(LayoutSize.xl.toolbarCollapseToMenu)
    }

    /// compact 输入框单行
    func testInputBarSingleLineCompactOnly() {
        XCTAssertTrue(LayoutSize.compact.inputBarSingleLine)
        XCTAssertFalse(LayoutSize.medium.inputBarSingleLine)
        XCTAssertFalse(LayoutSize.large.inputBarSingleLine)
    }

    /// 仅 xl 启用三栏布局
    func testEnableThreeColumnXlOnly() {
        XCTAssertFalse(LayoutSize.compact.enableThreeColumn)
        XCTAssertFalse(LayoutSize.medium.enableThreeColumn)
        XCTAssertFalse(LayoutSize.large.enableThreeColumn)
        XCTAssertTrue(LayoutSize.xl.enableThreeColumn)
    }

    // MARK: - DeviceType 兼容性回归测试

    /// DeviceType 现有 5 档划分保持不变（回归保护）
    func testDeviceTypeRegression() {
        XCTAssertEqual(DeviceType.current(width: 320), .iPhoneSE)
        XCTAssertEqual(DeviceType.current(width: 375), .iPhoneSE)
        XCTAssertEqual(DeviceType.current(width: 400), .iPhone)
        XCTAssertEqual(DeviceType.current(width: 430), .iPhone)
        XCTAssertEqual(DeviceType.current(width: 768), .iPadMini)
        XCTAssertEqual(DeviceType.current(width: 1024), .iPadPro)
        XCTAssertEqual(DeviceType.current(width: 1500), .macWide)
    }

    /// DeviceType.maxContentWidth 回归保护
    func testDeviceTypeMaxContentWidth() {
        XCTAssertTrue(DeviceType.iPhoneSE.maxContentWidth.isInfinite)
        XCTAssertEqual(DeviceType.iPadMini.maxContentWidth, 600)
        XCTAssertEqual(DeviceType.iPadPro.maxContentWidth, 800)
        XCTAssertEqual(DeviceType.macWide.maxContentWidth, 1000)
    }

    // MARK: - DefaultLayoutStrategy 测试

    /// compact 布局策略不支持分栏
    func testCompactStrategyDoesNotSupportSplitView() {
        let strategy = DefaultLayoutStrategy(layoutSize: .compact)
        XCTAssertFalse(strategy.supportsSplitView)
    }

    /// medium 及以上支持分栏
    func testMediumAndAboveStrategySupportsSplitView() {
        XCTAssertTrue(DefaultLayoutStrategy(layoutSize: .medium).supportsSplitView)
        XCTAssertTrue(DefaultLayoutStrategy(layoutSize: .large).supportsSplitView)
        XCTAssertTrue(DefaultLayoutStrategy(layoutSize: .xl).supportsSplitView)
    }

    /// compact 分栏样式为 .automatic
    func testCompactStrategySplitViewStyleAutomatic() {
        XCTAssertEqual(DefaultLayoutStrategy(layoutSize: .compact).splitViewStyle, .automatic)
    }

    /// medium 分栏样式为 .balanced
    func testMediumStrategySplitViewStyleBalanced() {
        XCTAssertEqual(DefaultLayoutStrategy(layoutSize: .medium).splitViewStyle, .balanced)
    }

    /// large / xl 分栏样式为 .prominentDetail
    func testLargeAndXlStrategySplitViewStyleProminentDetail() {
        XCTAssertEqual(DefaultLayoutStrategy(layoutSize: .large).splitViewStyle, .prominentDetail)
        XCTAssertEqual(DefaultLayoutStrategy(layoutSize: .xl).splitViewStyle, .prominentDetail)
    }

    /// 仅 xl 常驻第三栏
    func testOnlyXlStrategyHasPersistentThirdColumn() {
        XCTAssertFalse(DefaultLayoutStrategy(layoutSize: .compact).persistentThirdColumn)
        XCTAssertFalse(DefaultLayoutStrategy(layoutSize: .medium).persistentThirdColumn)
        XCTAssertFalse(DefaultLayoutStrategy(layoutSize: .large).persistentThirdColumn)
        XCTAssertTrue(DefaultLayoutStrategy(layoutSize: .xl).persistentThirdColumn)
    }

    /// layoutSize 属性存储正确
    func testStrategyLayoutSizeStored() {
        let strategy = DefaultLayoutStrategy(layoutSize: .medium)
        XCTAssertEqual(strategy.layoutSize, .medium)
    }

    // MARK: - iPhone Duo 折叠屏适配测试

    /// Duo 外屏 466pt 宽（1398×2034px @3x），compact size class → medium 档
    func testDuoOuterDisplayResolvesMedium() {
        XCTAssertEqual(LayoutSize.resolve(width: 466, horizontalSizeClass: .compact), .medium)
    }

    /// Duo 内屏 669pt 宽（2007×2853px @3x），regular size class → medium 档，支持双栏分屏
    func testDuoInnerDisplayResolvesMediumAndSupportsSplitView() {
        let layout = LayoutSize.resolve(width: 669, horizontalSizeClass: .regular)
        XCTAssertEqual(layout, .medium)
        XCTAssertTrue(DefaultLayoutStrategy(layoutSize: layout).supportsSplitView)
    }

    /// Duo 内屏 Split View 分屏后宽度约减半（~334pt），compact → compact 档
    func testDuoSplitViewHalfWidthResolvesCompact() {
        XCTAssertEqual(LayoutSize.resolve(width: 334, horizontalSizeClass: .compact), .compact)
    }

    /// Duo 两块屏幕宽度均落入 iPadMini 宽度档，内容最大宽度 600pt
    func testDuoDisplayWidthsContentWidth() {
        XCTAssertEqual(DeviceType.current(width: 466), .iPadMini)
        XCTAssertEqual(DeviceType.current(width: 669), .iPadMini)
        XCTAssertEqual(DeviceType.current(width: 466).maxContentWidth, 600)
        XCTAssertEqual(DeviceType.current(width: 669).maxContentWidth, 600)
    }

    /// Duo 姿态切换（外屏→内屏）时布局档位随宽度连续变化，不依赖设备型号
    func testDuoPoseTransitionLayoutContinuity() {
        let outer = LayoutSize.resolve(width: 466, horizontalSizeClass: .compact)
        let inner = LayoutSize.resolve(width: 669, horizontalSizeClass: .regular)
        XCTAssertEqual(outer.bubbleMaxWidth, 500)
        XCTAssertEqual(inner.bubbleMaxWidth, 500)
        XCTAssertFalse(outer.toolbarCollapseToMenu)
        XCTAssertFalse(inner.toolbarCollapseToMenu)
    }

    // MARK: - SplitViewStyle 等价性测试

    /// SplitViewStyle 各 case 互不等价
    func testSplitViewStyleNotEqual() {
        XCTAssertNotEqual(SplitViewStyle.automatic, .balanced)
        XCTAssertNotEqual(SplitViewStyle.balanced, .prominentDetail)
        XCTAssertNotEqual(SplitViewStyle.automatic, .prominentDetail)
        XCTAssertEqual(SplitViewStyle.automatic, .automatic)
    }

    // MARK: - UserInterfaceSizeClass 测试

    /// UserInterfaceSizeClass 3 个 case 互不相等
    func testUserInterfaceSizeClassNotEqual() {
        XCTAssertNotEqual(UserInterfaceSizeClass.compact, .regular)
        XCTAssertNotEqual(UserInterfaceSizeClass.compact, .other)
        XCTAssertNotEqual(UserInterfaceSizeClass.regular, .other)
        XCTAssertEqual(UserInterfaceSizeClass.compact, .compact)
    }
}
