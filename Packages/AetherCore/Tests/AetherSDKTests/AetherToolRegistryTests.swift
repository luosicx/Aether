import XCTest
@testable import AetherSDK
import AetherFoundation

/// Task 24 阶段 3: AetherTool 协议与注册测试
final class AetherToolRegistryTests: XCTestCase {

    // MARK: - AetherToolDefinition

    func testToolDefinitionFromDict() {
        let def = AetherToolDefinition(
            name: "calc",
            description: "计算器",
            parameters: [
                "type": "object",
                "properties": [
                    "expression": ["type": "string"]
                ],
                "required": ["expression"]
            ]
        )
        XCTAssertEqual(def.name, "calc")
        XCTAssertEqual(def.description, "计算器")
        // parametersJSON 应为合法 JSON
        let params = def.parameters()
        XCTAssertEqual(params["type"] as? String, "object")
        XCTAssertNotNil(params["properties"])
        XCTAssertNotNil(params["required"])
    }

    func testToolDefinitionFromJSONString() {
        let def = AetherToolDefinition(
            name: "echo",
            description: "回显",
            parametersJSON: """
            {"type": "object", "properties": {"text": {"type": "string"}}}
            """
        )
        let params = def.parameters()
        XCTAssertEqual(params["type"] as? String, "object")
    }

    func testToolDefinitionInvalidJSONReturnsEmptyDict() {
        let def = AetherToolDefinition(
            name: "broken",
            description: "bad json",
            parametersJSON: "not valid json {"
        )
        // [String: Any] 不能直接 Equatable 比较；改用 isEmpty 判空
        XCTAssertTrue(def.parameters().isEmpty)
    }

    // MARK: - AetherToolRegistry

    func testRegisterTool() {
        let registry = AetherToolRegistry()
        XCTAssertEqual(registry.count, 0)
        registry.register(tool: EchoTool())
        XCTAssertEqual(registry.count, 1)
        XCTAssertTrue(registry.toolNames.contains("echo"))
    }

    func testRegisterOverwritesSameName() {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        registry.register(tool: EchoTool()) // 同名覆盖
        XCTAssertEqual(registry.count, 1)
    }

    func testUnregisterTool() {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        XCTAssertEqual(registry.count, 1)
        registry.unregister(name: "echo")
        XCTAssertEqual(registry.count, 0)
        XCTAssertNil(registry.getTool(named: "echo"))
    }

    func testUnregisterNonExistentNoOp() {
        let registry = AetherToolRegistry()
        registry.unregister(name: "nonexistent") // 不应崩溃
        XCTAssertEqual(registry.count, 0)
    }

    func testDefaultPermissionIsAlwaysAllow() {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        XCTAssertEqual(registry.permission(for: "echo"), .alwaysAllow)
    }

    func testSetPermission() {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        registry.setPermission(name: "echo", .requireApproval)
        XCTAssertEqual(registry.permission(for: "echo"), .requireApproval)
        registry.setPermission(name: "echo", .deny)
        XCTAssertEqual(registry.permission(for: "echo"), .deny)
    }

    func testPermissionForNonExistent() {
        let registry = AetherToolRegistry()
        XCTAssertEqual(registry.permission(for: "missing"), .alwaysAllow)
    }

    func testAvailableDefinitionsExcludesDenied() {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        registry.register(tool: CalculatorTool())
        XCTAssertEqual(registry.availableDefinitions().count, 2)

        registry.setPermission(name: "echo", .deny)
        let defs = registry.availableDefinitions()
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(defs[0].name, "calculate")
    }

    // MARK: - 执行

    func testExecuteTool() async throws {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        let result = try await registry.execute(name: "echo", arguments: ["text": "hi"])
        XCTAssertEqual(result, "echo: hi")
    }

    func testExecuteNonExistentThrows() async throws {
        let registry = AetherToolRegistry()
        do {
            _ = try await registry.execute(name: "missing", arguments: [:])
            XCTFail("应抛出 toolExecutionFailed")
        } catch let error as AetherError {
            if case .toolExecutionFailed(let name, _) = error {
                XCTAssertEqual(name, "missing")
            } else {
                XCTFail("期望 toolExecutionFailed，实际：\(error)")
            }
        }
    }

    func testExecuteDeniedThrows() async throws {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        registry.setPermission(name: "echo", .deny)
        do {
            _ = try await registry.execute(name: "echo", arguments: [:])
            XCTFail("应抛出 toolExecutionFailed")
        } catch let error as AetherError {
            if case .toolExecutionFailed(let name, _) = error {
                XCTAssertEqual(name, "echo")
            } else {
                XCTFail("期望 toolExecutionFailed，实际：\(error)")
            }
        }
    }

    func testExecutePropagatesError() async throws {
        let registry = AetherToolRegistry()
        registry.register(tool: FailingTool())
        do {
            _ = try await registry.execute(name: "fail", arguments: [:])
            XCTFail("应抛出 toolExecutionFailed")
        } catch let error as AetherError {
            if case .toolExecutionFailed(let name, let desc) = error {
                XCTAssertEqual(name, "fail")
                XCTAssertTrue(desc.contains("boom"))
            } else {
                XCTFail("期望 toolExecutionFailed，实际：\(error)")
            }
        }
    }

    // MARK: - 批量注册

    func testRegisterBatch() {
        let registry = AetherToolRegistry()
        registry.registerBatch(tools: [EchoTool(), CalculatorTool()])
        XCTAssertEqual(registry.count, 2)
    }

    func testClear() {
        let registry = AetherToolRegistry()
        registry.register(tool: EchoTool())
        registry.register(tool: CalculatorTool())
        registry.clear()
        XCTAssertEqual(registry.count, 0)
    }

    // MARK: - AetherClient 集成

    func testClientRegisterTool() throws {
        let mock = MockLLMProvider()
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        XCTAssertEqual(client.registeredToolCount, 0)
        client.register(tool: EchoTool())
        XCTAssertEqual(client.registeredToolCount, 1)
    }

    func testClientSetToolPermission() throws {
        let mock = MockLLMProvider()
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        client.register(tool: EchoTool())
        XCTAssertEqual(client.toolPermission(for: "echo"), .alwaysAllow)
        client.setToolPermission(name: "echo", .deny)
        XCTAssertEqual(client.toolPermission(for: "echo"), .deny)
    }

    // MARK: - ToolPermission 枚举

    func testToolPermissionRawValues() {
        XCTAssertEqual(ToolPermission.alwaysAllow.rawValue, "alwaysAllow")
        XCTAssertEqual(ToolPermission.requireApproval.rawValue, "requireApproval")
        XCTAssertEqual(ToolPermission.deny.rawValue, "deny")
    }
}

// MARK: - Test Tools

struct CalculatorTool: AetherTool {
    let definition = AetherToolDefinition(
        name: "calculate",
        description: "数学表达式求值",
        parameters: [
            "type": "object",
            "properties": [
                "expression": ["type": "string"]
            ],
            "required": ["expression"]
        ]
    )

    func execute(arguments: [String: Any]) async throws -> String {
        "42"
    }
}

struct FailingTool: AetherTool {
    let definition = AetherToolDefinition(
        name: "fail",
        description: "总是失败",
        parametersJSON: "{}"
    )

    func execute(arguments: [String: Any]) async throws -> String {
        struct CustomError: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        throw CustomError()
    }
}
