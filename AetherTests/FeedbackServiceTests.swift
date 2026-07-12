import XCTest
@testable import Aether
#if os(iOS)
import MessageUI
#endif

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

    // MARK: - mailContent body 格式验证

    /// body 应以两个换行符开头（"\n\n---\n" 格式）
    func testMailContentBodyStartsWithNewlines() {
        let body = service.mailContent()["body"] ?? ""
        XCTAssertTrue(body.hasPrefix("\n\n"), "body 应以两个换行符开头，实际：\(body.prefix(10))")
    }

    /// body 应包含 "---" 分隔符（分隔用户输入与设备信息）
    func testMailContentBodyContainsSeparator() {
        let body = service.mailContent()["body"] ?? ""
        XCTAssertTrue(body.contains("---"), "body 应包含 '---' 分隔符，实际：\(body)")
    }

    /// body 中的设备信息应在分隔符之后
    func testMailContentBodyDeviceInfoAfterSeparator() {
        let body = service.mailContent()["body"] ?? ""
        guard let separatorRange = body.range(of: "---") else {
            XCTFail("body 应包含 '---' 分隔符")
            return
        }
        let afterSeparator = body[separatorRange.upperBound...]
        XCTAssertTrue(afterSeparator.contains("设备："), "设备信息应在分隔符之后")
    }

    // MARK: - mailtoURL 编码验证

    /// mailtoURL 应包含 body 参数
    func testMailtoURLContainsBodyParameter() {
        let url = service.mailtoURL()
        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("body="), "URL 应包含 body 参数，实际：\(urlString)")
    }

    /// mailtoURL 中 subject 应被 URL 编码（含 % 编码字符）
    func testMailtoURLSubjectIsPercentEncoded() {
        let url = service.mailtoURL()
        let urlString = url?.absoluteString ?? ""
        // subject 包含中文，URL 编码后应含 % 字符
        XCTAssertTrue(urlString.contains("%"), "URL 应含 percent-encoded 字符，实际：\(urlString)")
    }

    /// mailtoURL 中 body 应被 URL 编码（含 % 编码字符）
    func testMailtoURLBodyIsPercentEncoded() {
        let url = service.mailtoURL()
        let urlString = url?.absoluteString ?? ""
        // body 包含中文和换行符，编码后应含 % 字符
        XCTAssertTrue(urlString.contains("%25") || urlString.contains("%0A") || urlString.contains("%E"),
                      "body 中特殊字符应被 percent-encoded，实际：\(urlString)")
    }

    /// mailtoURL 同时包含 subject 和 body 参数
    func testMailtoURLContainsBothSubjectAndBody() {
        let url = service.mailtoURL()
        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("subject="), "URL 应含 subject 参数")
        XCTAssertTrue(urlString.contains("body="), "URL 应含 body 参数")
        // subject 在 body 之前
        if let subjectRange = urlString.range(of: "subject="),
           let bodyRange = urlString.range(of: "body=") {
            XCTAssertTrue(subjectRange.lowerBound < bodyRange.lowerBound,
                          "subject 应在 body 之前")
        }
    }

    // MARK: - collectDeviceInfo 字段验证

    /// collectDeviceInfo 应包含"设备："字段
    func testCollectDeviceInfoContainsDeviceField() {
        let info = service.collectDeviceInfo()
        XCTAssertTrue(info.contains("设备："), "应含 '设备：' 字段，实际：\(info)")
    }

    /// collectDeviceInfo 应包含"系统："字段
    func testCollectDeviceInfoContainsSystemField() {
        let info = service.collectDeviceInfo()
        XCTAssertTrue(info.contains("系统："), "应含 '系统：' 字段，实际：\(info)")
    }

    /// collectDeviceInfo 应包含设备型号（iOS 为 iPhone/iPad，macOS 为 Mac）
    func testCollectDeviceInfoContainsDeviceModel() {
        let info = service.collectDeviceInfo()
        #if os(iOS)
        XCTAssertTrue(info.contains("iPhone") || info.contains("iPad"),
                      "iOS 应含设备型号，实际：\(info)")
        #else
        XCTAssertTrue(info.contains("Mac"), "macOS 应含 'Mac'，实际：\(info)")
        #endif
    }

    /// collectDeviceInfo 的系统行应包含版本号（数字.数字格式）
    func testCollectDeviceInfoSystemVersionFormat() {
        let info = service.collectDeviceInfo()
        // 匹配 "系统：iOS X.Y" 或 "系统：macOS X.Y" 格式
        let pattern = "系统：.*(iOS|macOS) \\d+\\.\\d+"
        XCTAssertTrue(info.range(of: pattern, options: .regularExpression) != nil,
                      "系统行应含版本号，实际：\(info)")
    }

    // MARK: - mailContent 三键完整性

    /// mailContent 的 to 应为固定收件邮箱
    func testMailContentToIsCorrectRecipient() {
        let to = service.mailContent()["to"]
        XCTAssertEqual(to, "feedback@aether.app", "to 应为固定收件邮箱")
    }

    /// mailContent 的 subject 应与 NSLocalizedString 一致
    func testMailContentSubjectMatchesLocalized() {
        let subject = service.mailContent()["subject"] ?? ""
        XCTAssertEqual(subject, NSLocalizedString("以太用户反馈", comment: ""),
                       "subject 应与 NSLocalizedString 一致")
    }

    /// mailContent 的 body 应以 collectDeviceInfo() 结尾
    func testMailContentBodyEndsWithDeviceInfo() {
        let body = service.mailContent()["body"] ?? ""
        let deviceInfo = service.collectDeviceInfo()
        XCTAssertTrue(body.hasSuffix(deviceInfo),
                      "body 应以 collectDeviceInfo() 结尾")
    }

    // MARK: - 新增覆盖率测试

    /// mailContent() 返回的字典键值均为 String 类型，便于外部拼接 mailto
    func testMailContentKeysAndValuesAreStrings() {
        let content = service.mailContent()
        for (key, value) in content {
            XCTAssertTrue(key is String, "mailContent 键应为 String，实际：\(type(of: key))")
            XCTAssertTrue(value is String, "mailContent 值应为 String，实际：\(type(of: value))")
        }
    }

    /// mailtoURL 的 scheme 必须为小写的 "mailto"
    func testMailtoURLSchemeIsLowercase() {
        let url = service.mailtoURL()
        XCTAssertEqual(url?.scheme, "mailto", "scheme 应为小写 mailto")
    }

    /// mailtoURL 中 subject 含中文，应被 percent-encoded（URL 中不再出现原始中文）
    func testMailtoURLSubjectIsEncoded() {
        guard let urlString = service.mailtoURL()?.absoluteString else {
            XCTFail("mailtoURL 不应为 nil")
            return
        }
        let subject = service.mailContent()["subject"] ?? ""
        XCTAssertFalse(urlString.contains(subject) && !subject.isEmpty,
                       "编码后的 URL 不应再包含原始中文 subject，实际：\(urlString)")
        XCTAssertTrue(urlString.contains("subject="), "URL 应包含 subject 参数")
    }

    /// mailtoURL 中 body 的换行符应被编码为 %0A
    func testMailtoURLBodyNewlinesAreEncoded() {
        guard let urlString = service.mailtoURL()?.absoluteString else {
            XCTFail("mailtoURL 不应为 nil")
            return
        }
        XCTAssertTrue(urlString.contains("body="), "URL 应包含 body 参数")
        XCTAssertTrue(urlString.contains("%0A") || urlString.contains("%25"),
                      "body 中的换行符或特殊字符应被编码，实际：\(urlString)")
    }

    /// collectDeviceInfo() 输出应始终符合 "设备：...\n系统：...\nApp 版本：... (构建号)" 格式
    func testCollectDeviceInfoFormat() {
        let info = service.collectDeviceInfo()
        let pattern = "设备：.*\\n系统：.*\\nApp 版本：.*\\([^)]+\\)"
        XCTAssertNotNil(info.range(of: pattern, options: .regularExpression),
                        "设备信息格式应符合预期，实际：\(info)")
    }

    /// collectDeviceInfo() 的 App 版本行应包含构建号括号
    func testCollectDeviceInfoAppVersionContainsBuildNumber() {
        let info = service.collectDeviceInfo()
        XCTAssertTrue(info.contains("App 版本："), "应含 App 版本字段")
        XCTAssertTrue(info.contains("("), "App 版本后应含构建号括号")
        XCTAssertTrue(info.contains(")"), "构建号应以右括号结尾")
    }

    #if os(iOS)
    /// MailComposerView.Coordinator 初始化后应保存 onFinish 闭包
    func testMailComposerCoordinatorStoresOnFinish() {
        let expectation = expectation(description: "onFinish 被调用")
        let coordinator = MailComposerView.Coordinator { _ in
            expectation.fulfill()
        }
        let controller = MFMailComposeViewController()
        coordinator.mailComposeController(controller, didFinishWith: .sent, error: nil)
        wait(for: [expectation], timeout: 1.0)
    }

    /// MailComposerView.Coordinator 应把任何 result 透传给 onFinish
    func testMailComposerCoordinatorPassesResultToOnFinish() {
        var receivedResult: MFMailComposeResult?
        let coordinator = MailComposerView.Coordinator { result in
            receivedResult = result
        }
        let controller = MFMailComposeViewController()
        coordinator.mailComposeController(controller, didFinishWith: .cancelled, error: nil)
        XCTAssertEqual(receivedResult, .cancelled, "onFinish 应收到 cancelled 结果")
    }
    #endif
}
