import XCTest
import SwiftUI
import AetherDesign

final class AetherIconsTests: XCTestCase {

    // MARK: - AetherIcon 表驱动测试

    /// 验证所有 case 的 rawValue 非空：rawValue 是 Asset Catalog 资源名，必须非空
    func testAllCasesRawValuesNonEmpty() {
        for icon in AetherIcon.allCases {
            XCTAssertFalse(icon.rawValue.isEmpty,
                           "AetherIcon.\(icon) 的 rawValue 不应为空")
        }
    }

    /// 验证所有 case 的 fallbackSystemName 非空：SF Symbol 兜底名称必须可用
    func testAllCasesFallbackSystemNamesNonEmpty() {
        for icon in AetherIcon.allCases {
            XCTAssertFalse(icon.fallbackSystemName.isEmpty,
                           "AetherIcon.\(icon) 的 fallbackSystemName 不应为空")
        }
    }

    /// 验证所有 case 的 accessibilityLabel 非空：无障碍标签是必备信息
    func testAllCasesAccessibilityLabelsNonEmpty() {
        for icon in AetherIcon.allCases {
            XCTAssertFalse(icon.accessibilityLabel.isEmpty,
                           "AetherIcon.\(icon) 的 accessibilityLabel 不应为空")
        }
    }

    /// 验证 case 数量为 18：新增/删除 case 时该测试会失败，作为变更护栏
    func testAllCasesCountIsEighteen() {
        XCTAssertEqual(AetherIcon.allCases.count, 18,
                       "AetherIcon 当前应有 18 个 case")
    }

    /// 验证 fallbackSystemName 长度合理（<= 50 字符）：SF Symbol 名称通常较短
    func testAllCasesFallbackSystemNameLengthReasonable() {
        for icon in AetherIcon.allCases {
            XCTAssertLessThanOrEqual(icon.fallbackSystemName.count, 50,
                                     "AetherIcon.\(icon) 的 fallbackSystemName 长度应 <= 50")
        }
    }

    /// 验证 accessibilityLabel 长度合理（<= 30 字符）：标签需简洁，便于 VoiceOver 朗读
    func testAllCasesAccessibilityLabelLengthReasonable() {
        for icon in AetherIcon.allCases {
            XCTAssertLessThanOrEqual(icon.accessibilityLabel.count, 30,
                                     "AetherIcon.\(icon) 的 accessibilityLabel 长度应 <= 30")
        }
    }

    /// 验证 fallbackSystemName 不含空格：SF Symbol 命名规范使用点分隔，不含空格
    func testAllCasesFallbackSystemNameNoSpaces() {
        for icon in AetherIcon.allCases {
            XCTAssertFalse(icon.fallbackSystemName.contains(" "),
                           "AetherIcon.\(icon) 的 fallbackSystemName 不应含空格")
        }
    }

    /// 验证 .image 属性可访问（不崩溃）：Asset Catalog 资源名构造 Image 的入口
    func testAllCasesImageAccessible() {
        for icon in AetherIcon.allCases {
            _ = icon.image
        }
    }

    /// 验证 .systemImage 属性可访问（不崩溃）：SF Symbol 兜底图构造入口
    func testAllCasesSystemImageAccessible() {
        for icon in AetherIcon.allCases {
            _ = icon.systemImage
        }
    }

    // MARK: - 特定 case 验证

    /// 验证关键 case 的 fallbackSystemName 与设计契约一致
    func testSpecificCasesFallbackSystemNames() {
        XCTAssertEqual(AetherIcon.logo.fallbackSystemName, "sparkles")
        XCTAssertEqual(AetherIcon.mcp.fallbackSystemName, "network")
        XCTAssertEqual(AetherIcon.knowledge.fallbackSystemName, "books.vertical.fill")
        XCTAssertEqual(AetherIcon.cloud.fallbackSystemName, "icloud")
    }

    /// 验证关键 case 的 accessibilityLabel 与产品文案一致
    func testSpecificCasesAccessibilityLabels() {
        XCTAssertEqual(AetherIcon.logo.accessibilityLabel, "Aether Logo")
        XCTAssertEqual(AetherIcon.knowledge.accessibilityLabel, "知识库")
    }

    // MARK: - FourPointStar Shape 测试

    /// 验证 FourPointStar 实例化不崩溃：Shape 应支持无参初始化
    func testFourPointStarInstanceCreation() {
        _ = FourPointStar()
    }

    /// 验证 FourPointStar.path(in:) 在标准 rect 下返回非空 Path
    func testFourPointStarPathNonEmpty() {
        let star = FourPointStar()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = star.path(in: rect)
        XCTAssertFalse(path.isEmpty,
                       "FourPointStar.path(in: 100x100) 不应返回空 Path")
    }

    /// 验证不同 rect 尺寸下 Path 的 boundingBox 都落在输入 rect 范围内
    func testFourPointStarPathBoundingBoxWithinRect() {
        let star = FourPointStar()
        let rects: [CGRect] = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 10, y: 20, width: 50, height: 80),
            CGRect(x: -50, y: -50, width: 200, height: 200),
            CGRect(x: 0, y: 0, width: 24, height: 24),
        ]
        for rect in rects {
            let path = star.path(in: rect)
            let bounds = path.boundingBox
            XCTAssertTrue(rect.contains(bounds),
                          "boundingBox \(bounds) 应包含在 rect \(rect) 内")
        }
    }

    /// 验证零尺寸 rect 不崩溃：边界条件，至少不抛出异常
    func testFourPointStarZeroSizeRectDoesNotCrash() {
        let star = FourPointStar()
        let rect = CGRect(x: 0, y: 0, width: 0, height: 0)
        let path = star.path(in: rect)
        let bounds = path.boundingBox
        // 零尺寸下 boundingBox 面积应为 0
        XCTAssertEqual(bounds.width, 0)
        XCTAssertEqual(bounds.height, 0)
    }

    /// 验证正方形与非正方形 rect 都能正常生成 Path
    func testFourPointStarRectWithDifferentAspectRatios() {
        let star = FourPointStar()
        let squareRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let wideRect = CGRect(x: 0, y: 0, width: 200, height: 50)
        let tallRect = CGRect(x: 0, y: 0, width: 50, height: 200)

        let squarePath = star.path(in: squareRect)
        let widePath = star.path(in: wideRect)
        let tallPath = star.path(in: tallRect)

        XCTAssertFalse(squarePath.isEmpty, "正方形 rect 应生成非空 Path")
        XCTAssertFalse(widePath.isEmpty, "宽矩形 rect 应生成非空 Path")
        XCTAssertFalse(tallPath.isEmpty, "高矩形 rect 应生成非空 Path")

        XCTAssertTrue(squareRect.contains(squarePath.boundingBox))
        XCTAssertTrue(wideRect.contains(widePath.boundingBox))
        XCTAssertTrue(tallRect.contains(tallPath.boundingBox))
    }

    // MARK: - AetherIconRenderer View Smoke Test

    /// 验证 AetherIconRenderer 实例化不崩溃，且公开属性正确存储
    func testAetherIconRendererInstanceCreation() {
        let renderer = AetherIconRenderer(icon: .logo, size: 24)
        XCTAssertEqual(renderer.icon, .logo)
        XCTAssertEqual(renderer.size, 24)
    }

    /// 遍历所有 AetherIcon case 创建 AetherIconRenderer 不崩溃
    func testAetherIconRendererAllCasesCreation() {
        for icon in AetherIcon.allCases {
            let renderer = AetherIconRenderer(icon: icon, size: 32)
            XCTAssertEqual(renderer.icon, icon)
            XCTAssertEqual(renderer.size, 32)
        }
    }

    /// 验证不同 size（1.0 / 12.0 / 24.0 / 100.0）都能正常创建
    func testAetherIconRendererDifferentSizes() {
        let sizes: [CGFloat] = [1.0, 12.0, 24.0, 100.0]
        for size in sizes {
            let renderer = AetherIconRenderer(icon: .mcp, size: size)
            XCTAssertEqual(renderer.size, size,
                           "size=\(size) 应被正确存储")
        }
    }

    /// 验证极端 size（0.0 / -1.0）也不崩溃（不抛出 fatalError）
    func testAetherIconRendererExtremeSizes() {
        let renderer0 = AetherIconRenderer(icon: .logo, size: 0.0)
        XCTAssertEqual(renderer0.size, 0.0)

        let rendererNeg = AetherIconRenderer(icon: .logo, size: -1.0)
        XCTAssertEqual(rendererNeg.size, -1.0)
    }
}
