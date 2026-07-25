import XCTest
@testable import Aether

/// v1.3: DeviceCapability 设备能力分级测试
final class DeviceCapabilityTests: XCTestCase {

    // MARK: - 能力等级属性

    func testAllCasesCount() {
        XCTAssertEqual(DeviceCapability.allCases.count, 4, "应有 4 个能力等级")
    }

    func testDisplayNameNonEmpty() {
        for capability in DeviceCapability.allCases {
            XCTAssertFalse(capability.displayName.isEmpty, "displayName 不应为空: \(capability)")
        }
    }

    func testMaxVLMScale() {
        XCTAssertEqual(DeviceCapability.low.maxVLMScale, 0)
        XCTAssertEqual(DeviceCapability.medium.maxVLMScale, 1)
        XCTAssertEqual(DeviceCapability.high.maxVLMScale, 2)
        XCTAssertEqual(DeviceCapability.ultra.maxVLMScale, 11)
    }

    func testSupportsVLM() {
        XCTAssertFalse(DeviceCapability.low.supportsVLM, "low 不应支持 VLM")
        XCTAssertTrue(DeviceCapability.medium.supportsVLM, "medium 应支持 VLM")
        XCTAssertTrue(DeviceCapability.high.supportsVLM, "high 应支持 VLM")
        XCTAssertTrue(DeviceCapability.ultra.supportsVLM, "ultra 应支持 VLM")
    }

    func testSupportsVoiceClone() {
        XCTAssertFalse(DeviceCapability.low.supportsVoiceClone)
        XCTAssertFalse(DeviceCapability.medium.supportsVoiceClone)
        XCTAssertTrue(DeviceCapability.high.supportsVoiceClone)
        XCTAssertTrue(DeviceCapability.ultra.supportsVoiceClone)
    }

    func testSupportsImageGeneration() {
        XCTAssertFalse(DeviceCapability.low.supportsImageGeneration)
        XCTAssertFalse(DeviceCapability.medium.supportsImageGeneration)
        XCTAssertTrue(DeviceCapability.high.supportsImageGeneration)
        XCTAssertTrue(DeviceCapability.ultra.supportsImageGeneration)
    }

    func testRecommendedMemoryBudgetMB() {
        XCTAssertEqual(DeviceCapability.low.recommendedMemoryBudgetMB, 1_500)
        XCTAssertEqual(DeviceCapability.medium.recommendedMemoryBudgetMB, 2_500)
        XCTAssertEqual(DeviceCapability.high.recommendedMemoryBudgetMB, 3_000)
        XCTAssertEqual(DeviceCapability.ultra.recommendedMemoryBudgetMB, 6_000)
    }

    // MARK: - 设备检测

    func testCurrentReturnsValidCapability() {
        let current = DeviceCapability.current
        XCTAssertTrue(DeviceCapability.allCases.contains(current), "current 应在 allCases 中")
    }

    func testDetectReturnsValidCapability() {
        let detected = DeviceCapability.detect()
        XCTAssertTrue(DeviceCapability.allCases.contains(detected), "detect() 应返回有效能力等级")
    }

    // MARK: - Equatable

    func testEquality() {
        XCTAssertEqual(DeviceCapability.low, DeviceCapability.low)
        XCTAssertNotEqual(DeviceCapability.low, DeviceCapability.high)
    }

    func testRawValue() {
        XCTAssertEqual(DeviceCapability.low.rawValue, "low")
        XCTAssertEqual(DeviceCapability.medium.rawValue, "medium")
        XCTAssertEqual(DeviceCapability.high.rawValue, "high")
        XCTAssertEqual(DeviceCapability.ultra.rawValue, "ultra")
    }
}
