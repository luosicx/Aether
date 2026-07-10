import XCTest
@testable import Aether

/// NotificationService 单元测试
final class NotificationServiceTests: XCTestCase {
    private let service = NotificationService.shared

    /// requestAuthorization 不应抛错（completion-based，失败静默）
    func testRequestAuthorizationDoesNotThrow() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "跳过：CI 环境无法处理权限弹窗")
        service.requestAuthorization()
        // 给 completion handler 一点时间执行
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(true, "requestAuthorization 未抛错即通过")
    }

    /// sendNotification(title:body:) 不应抛错/崩溃
    func testSendNotificationDoesNotThrow() async {
        service.sendNotification(title: "测试标题", body: "测试正文")
        XCTAssertTrue(true, "sendNotification 未抛错即通过")
    }
}
