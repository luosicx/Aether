import XCTest
@testable import Aether

/// ToolRegistry 单元测试
@MainActor
final class ToolRegistryTests: XCTestCase {
    private let registry = ToolRegistry.shared

    /// register 同名工具应覆盖：getTool 返回新工具
    func testRegisterOverridesSameName() async throws {
        defer { registry.register(tool: CalculatorTool()) } // 恢复默认工具
        registry.register(tool: DummyTool(name: "calculate", result: "OVERRIDE"))
        let tool = registry.getTool(named: "calculate")
        XCTAssertNotNil(tool, "覆盖后应能取到工具")
        let result = try await tool!.execute(arguments: [:])
        XCTAssertEqual(result, "OVERRIDE", "同名注册应返回新工具")
    }

    /// getTool("calculate") 应返回非 nil
    func testGetToolFound() {
        XCTAssertNotNil(registry.getTool(named: "calculate"), "已注册的 calculate 工具应可取到")
    }

    /// getTool("non_existent") 应返回 nil
    func testGetToolNotFoundReturnsNil() {
        XCTAssertNil(registry.getTool(named: "non_existent"), "未注册的工具应返回 nil")
    }

    /// execute 未注册工具应抛 NSError（domain = "ToolRegistry"，code = 1）
    func testExecuteNotRegisteredThrowsNSError() async {
        do {
            _ = try await registry.execute(name: "non_existent", arguments: [:])
            XCTFail("未注册工具应抛错")
        } catch {
            let nserror = error as NSError
            XCTAssertEqual(nserror.domain, "ToolRegistry", "错误 domain 应为 ToolRegistry")
            XCTAssertEqual(nserror.code, 1, "错误 code 应为 1")
        }
    }

    /// init 后 allToolDefs 应含正确数量的工具（跨平台 14 个，macOS 额外 11 个共 25 个）
    func testAllToolDefsCount() {
        #if os(macOS)
        let expected = 25
        #else
        let expected = 14
        #endif
        XCTAssertEqual(registry.allToolDefs.count, expected,
                       "默认应注册 \(expected) 个工具")
    }

    /// ToolDef 应可序列化为 JSON，且 JSON 含 "name" 与 "parameters" 字段
    func testToolDefSerialization() throws {
        guard let def = registry.allToolDefs.first else {
            return XCTFail("allToolDefs 不应为空")
        }
        let data = try JSONEncoder().encode(def)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"name\""), "JSON 应含 name 字段")
        XCTAssertTrue(json.contains("\"parameters\""), "JSON 应含 parameters 字段")
    }

    // MARK: - 工具执行确认框架集成测试

    /// 危险工具在 confirmationService 拒绝时应抛 NSError（domain = "ToolRegistry"，code = 2）
    func testExecuteDangerousToolDeniedThrowsCode2() async {
        let originalService = registry.confirmationService
        defer { registry.confirmationService = originalService }
        registry.confirmationService = DenyAllConfirmationService()

        // 临时将 calculate 替换为危险工具，测试结束后恢复
        let originalCalculator = registry.getTool(named: "calculate")
        defer {
            if let originalCalculator = originalCalculator {
                registry.register(tool: originalCalculator)
            }
        }
        registry.register(tool: DummyTool(name: "calculate", result: "BOOM", riskLevel: .dangerous))

        do {
            _ = try await registry.execute(name: "calculate", arguments: [:])
            XCTFail("危险工具被拒绝确认后应抛错")
        } catch {
            let nserror = error as NSError
            XCTAssertEqual(nserror.domain, "ToolRegistry", "错误 domain 应为 ToolRegistry")
            XCTAssertEqual(nserror.code, 2, "错误 code 应为 2")
        }
    }

    /// 普通工具无需确认即可执行成功
    func testExecuteNormalToolDoesNotRequireConfirmation() async throws {
        let originalService = registry.confirmationService
        defer { registry.confirmationService = originalService }
        registry.confirmationService = DenyAllConfirmationService()

        let result = try await registry.execute(name: "calculate", arguments: ["expression": "1 + 1"])
        XCTAssertEqual(result, "2", "普通工具不应要求确认")
    }
}

/// 测试用占位工具：name、result 与 riskLevel 可配置，execute 返回固定字符串
private final class DummyTool: ToolProtocol {
    private let _definition: ToolDefinition
    private let result: String
    private let _riskLevel: ToolRiskLevel

    init(name: String, result: String, riskLevel: ToolRiskLevel = .normal) {
        self._definition = ToolDefinition(name: name, description: "test dummy", parameters: [:])
        self.result = result
        self._riskLevel = riskLevel
    }

    var definition: ToolDefinition { _definition }
    var riskLevel: ToolRiskLevel { _riskLevel }

    func execute(arguments: [String: Any]) async throws -> String {
        result
    }
}

/// 测试用确认服务：总是拒绝，用于验证敏感/危险工具会被取消执行
private final class DenyAllConfirmationService: ToolConfirmationService {
    func confirm(tool: ToolProtocol, arguments: [String: Any]) async -> Bool {
        false
    }
}
