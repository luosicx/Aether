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

    /// mailContent() 应返回包含 to / subject / body 三个键的字典，且 to 为反馈邮箱
    func testMailContentContainsThreeKeys() {
        let content = service.mailContent()
        XCTAssertNotNil(content["to"], "mailContent() 应包含 'to' 键")
        XCTAssertNotNil(content["subject"], "mailContent() 应包含 'subject' 键")
        XCTAssertNotNil(content["body"], "mailContent() 应包含 'body' 键")
        XCTAssertEqual(content["to"], "feedback@aether.app", "'to' 应为反馈收件邮箱")
    }

    /// mailContent() 的 body 应包含设备信息标识（硬编码字符串，不走 NSLocalizedString）
    func testMailContentBodyContainsDeviceInfo() {
        let body = service.mailContent()["body"] ?? ""
        XCTAssertTrue(body.contains("设备："), "body 应包含 '设备：' 标识，实际：\(body)")
        XCTAssertTrue(body.contains("系统："), "body 应包含 '系统：' 标识，实际：\(body)")
        XCTAssertTrue(body.contains("App 版本："), "body 应包含 'App 版本：' 标识，实际：\(body)")
    }

    /// mailtoURL() 应返回有效的 mailto: URL
    func testMailtoURLIsValidMailtoScheme() {
        let url = service.mailtoURL()
        XCTAssertNotNil(url, "mailtoURL() 不应返回 nil")
        XCTAssertEqual(url?.scheme, "mailto", "URL scheme 应为 'mailto'")
    }

    /// mailtoURL() 应包含收件人邮箱和 subject 参数
    func testMailtoURLContainsRecipientAndSubject() {
        let url = service.mailtoURL()
        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("feedback@aether.app"),
                      "URL 应包含收件人邮箱，实际：\(urlString)")
        XCTAssertTrue(urlString.contains("subject="),
                      "URL 应包含 subject 参数，实际：\(urlString)")
    }

    /// collectDeviceInfo() 应包含系统名称（iOS 或 macOS，跨平台兼容）
    func testCollectDeviceInfoContainsSystemName() {
        let info = service.collectDeviceInfo()
        XCTAssertTrue(info.contains("iOS") || info.contains("macOS"),
                      "collectDeviceInfo() 应包含 'iOS' 或 'macOS'，实际：\(info)")
    }

    /// collectDeviceInfo() 应包含 "App 版本 (构建号)" 格式
    func testCollectDeviceInfoContainsBuildNumberFormat() {
        let info = service.collectDeviceInfo()
        // 匹配 "App 版本：X (Y)" 格式，X 为版本号，Y 为构建号
        let pattern = "App 版本：.*\\([^)]+\\)"
        XCTAssertTrue(info.range(of: pattern, options: .regularExpression) != nil,
                      "collectDeviceInfo() 应包含 'App 版本 (构建号)' 格式，实际：\(info)")
    }

    /// 通过 mailContent() 间接验证 subject 非空（subject 走 NSLocalizedString，不断言具体文案）
    func testSubjectIsNotEmpty() {
        let subject = service.mailContent()["subject"] ?? ""
        XCTAssertFalse(subject.isEmpty, "subject 不应为空")
    }
}
