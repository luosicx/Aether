import XCTest
@testable import AIBuilder

/// Day 20: CrashReportService 单元测试。
/// Bugly 不可用时走占位分支，测试验证不 crash 即可。
final class CrashReportServiceTests: XCTestCase {
    private let service = CrashReportService.shared

    /// initialize 调用不应崩溃（Bugly 不可用时走占位分支）
    func testInitializeDoesNotCrash() {
        service.initialize(appKey: "test")
        // 未抛错即通过
        XCTAssertTrue(true, "initialize(appKey:) 不应崩溃")
    }

    /// setUserId 调用不应崩溃
    func testSetUserIdDoesNotCrash() {
        service.setUserId("test-user")
        XCTAssertTrue(true, "setUserId(_:) 不应崩溃")
    }

    /// reportException 调用不应崩溃
    func testReportExceptionDoesNotCrash() {
        struct TestError: Error {}
        service.reportException(TestError())
        XCTAssertTrue(true, "reportException(_:) 不应崩溃")
    }
}
