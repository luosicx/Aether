import XCTest
import SwiftUI
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 17-19 设计系统测试：AnimationTokens、AetherIcon、DeviceType
final class DesignSystemTests: XCTestCase {

    // MARK: - AnimationTokens 值验证

    func testAnimationTokensResolveWithoutError() {
        // 验证所有动画 token 可正常解析
        _ = AnimationTokens.transition
        _ = AnimationTokens.messageAppear
        _ = AnimationTokens.buttonPress
        _ = AnimationTokens.skeleton
        _ = AnimationTokens.blink
    }

    func testPressableButtonStyleExists() {
        // 验证 PressableButtonStyle 可实例化
        _ = PressableButtonStyle()
    }

    // MARK: - AetherIcon 枚举验证

    func testAetherIconAllCasesCount() {
        XCTAssertEqual(AetherIcon.allCases.count, 8)
    }

    func testAetherIconRawValues() {
        XCTAssertEqual(AetherIcon.logo.rawValue, "aether.logo")
        XCTAssertEqual(AetherIcon.mcp.rawValue, "aether.mcp")
        XCTAssertEqual(AetherIcon.memory.rawValue, "aether.memory")
        XCTAssertEqual(AetherIcon.agent.rawValue, "aether.agent")
        XCTAssertEqual(AetherIcon.plugin.rawValue, "aether.plugin")
        XCTAssertEqual(AetherIcon.branch.rawValue, "aether.branch")
        XCTAssertEqual(AetherIcon.theme.rawValue, "aether.theme")
        XCTAssertEqual(AetherIcon.persona.rawValue, "aether.persona")
    }

    func testAetherIconAccessibilityLabels() {
        for icon in AetherIcon.allCases {
            XCTAssertFalse(icon.accessibilityLabel.isEmpty, "图标 \(icon.rawValue) 的无障碍标签不应为空")
        }
    }

    func testAetherIconRendererInitializes() {
        // 验证渲染器可对所有图标初始化
        for icon in AetherIcon.allCases {
            let renderer = AetherIconRenderer(icon: icon, size: 24)
            _ = renderer
        }
    }

    // MARK: - DeviceType 判断逻辑验证

    func testDeviceTypeBoundaryValues() {
        // 边界值：恰好等于阈值
        XCTAssertEqual(DeviceType.current(width: 0), .iPhoneSE)
        XCTAssertEqual(DeviceType.current(width: 375), .iPhoneSE)
        XCTAssertEqual(DeviceType.current(width: 376), .iPhone)
        XCTAssertEqual(DeviceType.current(width: 430), .iPhone)
        XCTAssertEqual(DeviceType.current(width: 431), .iPadMini)
        XCTAssertEqual(DeviceType.current(width: 768), .iPadMini)
        XCTAssertEqual(DeviceType.current(width: 769), .iPadPro)
        XCTAssertEqual(DeviceType.current(width: 1024), .iPadPro)
        XCTAssertEqual(DeviceType.current(width: 1025), .macWide)
    }

    func testDeviceTypeRepresentativeValues() {
        // 典型设备宽度
        XCTAssertEqual(DeviceType.current(width: 320), .iPhoneSE)
        XCTAssertEqual(DeviceType.current(width: 390), .iPhone)
        XCTAssertEqual(DeviceType.current(width: 414), .iPhone)
        XCTAssertEqual(DeviceType.current(width: 600), .iPadMini)
        XCTAssertEqual(DeviceType.current(width: 834), .iPadPro)
        XCTAssertEqual(DeviceType.current(width: 1024), .iPadPro)
        XCTAssertEqual(DeviceType.current(width: 1440), .macWide)
        XCTAssertEqual(DeviceType.current(width: 2560), .macWide)
    }

    func testDeviceTypeMaxContentWidth() {
        // iPhone 系列不限制宽度
        XCTAssertEqual(DeviceType.iPhoneSE.maxContentWidth, .infinity)
        XCTAssertEqual(DeviceType.iPhone.maxContentWidth, .infinity)
        // iPad / macOS 逐级限制
        XCTAssertEqual(DeviceType.iPadMini.maxContentWidth, 600)
        XCTAssertEqual(DeviceType.iPadPro.maxContentWidth, 800)
        XCTAssertEqual(DeviceType.macWide.maxContentWidth, 1000)
    }

    func testResponsiveModifierExists() {
        // 验证 responsiveLayout() 修饰器可调用
        let view = Color.clear.responsiveLayout()
        _ = view
    }
}
