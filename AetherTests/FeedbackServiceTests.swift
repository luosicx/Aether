import XCTest
@testable import Aether

/// Day 20: FeedbackService 单元测试
final class FeedbackServiceTests: XCTestCase {
    private let service = FeedbackService.shared

    /// collectDeviceInfo() 应返回非空字符串
    func testCollectDeviceInfoReturnsNonEmpty() {
        let info = service.collectDeviceInfo()
        XCTAssertFalse(info.isEmpty, "collectDeviceInfo() 不应返回空字符串")
    }

    /// collectDeviceInfo() 返回值应包含 "App 版本" 字样
    func testCollectDeviceInfoContainsAppVersion() {
        let info = service.collectDeviceInfo()
        XCTAssertTrue(info.contains("App 版本"), "collectDeviceInfo() 应包含 'App 版本'，实际：\(info)")
    }
}
