import XCTest
@testable import Aether

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

    // MARK: - 边缘测试补充

    // setCustomKey 调用不应崩溃（Bugly 不可用时走占位分支）
    func testSetCustomKeyDoesNotCrash() {
        service.setCustomKey("session_id", value: "abc-123")
        XCTAssertTrue(true, "setCustomKey(_:value:) 不应崩溃")
    }

    // reportException 传入 NSError 应正常处理不崩溃
    func testReportExceptionWithNSError() {
        let nsError = NSError(domain: "test.domain", code: 42, userInfo: [NSLocalizedDescriptionKey: "测试错误"])
        service.reportException(nsError)
        XCTAssertTrue(true, "reportException 传入 NSError 不应崩溃")
    }

    // initialize 传入空 appKey 不应崩溃
    func testInitializeWithEmptyAppKey() {
        service.initialize(appKey: "")
        XCTAssertTrue(true, "空 appKey initialize 不应崩溃")
    }

    // setUserId 传入空字符串不应崩溃
    func testSetUserIdWithEmptyString() {
        service.setUserId("")
        XCTAssertTrue(true, "空字符串 setUserId 不应崩溃")
    }

    // 多次设置不同 customKey 不应崩溃
    func testSetMultipleCustomKeys() {
        service.setCustomKey("key1", value: "value1")
        service.setCustomKey("key2", value: "value2")
        service.setCustomKey("key3", value: "value3")
        XCTAssertTrue(true, "多次 setCustomKey 不应崩溃")
    }
}
