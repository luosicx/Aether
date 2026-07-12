import XCTest
@testable import Aether

/// ToolConfirmationService 单元测试
@MainActor
final class ToolConfirmationServiceTests: XCTestCase {

    // MARK: - ImmediateToolConfirmationService

    func testImmediateServiceReturnsAllowOnce() async {
        let service = ImmediateToolConfirmationService(decision: .allowOnce)
        let decision = await service.requestConfirmation(toolName: "test", summary: "summary")
        XCTAssertEqual(decision, .allowOnce)
    }

    func testImmediateServiceReturnsDeny() async {
        let service = ImmediateToolConfirmationService(decision: .deny)
        let decision = await service.requestConfirmation(toolName: "test", summary: "summary")
        XCTAssertEqual(decision, .deny)
    }

    func testImmediateServiceReturnsAlwaysAllow() async {
        let service = ImmediateToolConfirmationService(decision: .alwaysAllow)
        let decision = await service.requestConfirmation(toolName: "test", summary: "summary")
        XCTAssertEqual(decision, .alwaysAllow)
    }

    // MARK: - SwiftUIToolConfirmationService

    func testSwiftUIServiceAllowOnce() async {
        let service = SwiftUIToolConfirmationService()
        Task { @MainActor in
            service.complete(decision: .allowOnce)
        }
        let decision = await service.requestConfirmation(toolName: "run_terminal_command", summary: "execute command")
        XCTAssertEqual(decision, .allowOnce)
        XCTAssertNil(service.pendingRequest, "完成后 pendingRequest 应置空")
    }

    func testSwiftUIServiceAlwaysAllow() async {
        let service = SwiftUIToolConfirmationService()
        Task { @MainActor in
            service.complete(decision: .alwaysAllow)
        }
        let decision = await service.requestConfirmation(toolName: "run_applescript", summary: "run script")
        XCTAssertEqual(decision, .alwaysAllow)
    }

    func testSwiftUIServiceDeny() async {
        let service = SwiftUIToolConfirmationService()
        Task { @MainActor in
            service.complete(decision: .deny)
        }
        let decision = await service.requestConfirmation(toolName: "manage_file", summary: "delete file")
        XCTAssertEqual(decision, .deny)
    }

    func testSwiftUIServiceCancelIsDeny() async {
        let service = SwiftUIToolConfirmationService()
        Task { @MainActor in
            service.cancel()
        }
        let decision = await service.requestConfirmation(toolName: "simulate_input", summary: "simulate input")
        XCTAssertEqual(decision, .deny)
    }

    func testSwiftUIServicePendingRequestIsSet() async {
        let service = SwiftUIToolConfirmationService()
        Task { @MainActor in
            XCTAssertNotNil(service.pendingRequest, "请求后应设置 pendingRequest")
            service.complete(decision: .deny)
        }
        _ = await service.requestConfirmation(toolName: "control_safari", summary: "run js")
    }
}
