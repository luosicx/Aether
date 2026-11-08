import XCTest
@testable import Aether

/// v3.0: AI Workflow 自动化测试（工作流引擎 + 节点模型）
final class WorkflowEngineTests: XCTestCase {

    // MARK: - WorkflowNode 测试

    func testNodeInit() {
        let node = WorkflowNode(type: .actionLLM, name: "LLM调用")
        XCTAssertEqual(node.type, .actionLLM)
        XCTAssertEqual(node.name, "LLM调用")
        XCTAssertEqual(node.config.count, 0)
        XCTAssertNotNil(node.id)
    }

    func testNodeWithConfig() {
        let node = WorkflowNode(
            type: .actionTool,
            name: "计算器",
            config: ["toolName": "calculator", "args": "1+1"]
        )
        XCTAssertEqual(node.config["toolName"], "calculator")
        XCTAssertEqual(node.config["args"], "1+1")
    }

    func testNodeTypeIsTrigger() {
        XCTAssertTrue(WorkflowNode.NodeType.triggerTimer.isTrigger)
        XCTAssertTrue(WorkflowNode.NodeType.triggerManual.isTrigger)
        XCTAssertTrue(WorkflowNode.NodeType.triggerEvent.isTrigger)
        XCTAssertFalse(WorkflowNode.NodeType.actionLLM.isTrigger)
        XCTAssertFalse(WorkflowNode.NodeType.output.isTrigger)
    }

    func testNodeCodable() throws {
        let node = WorkflowNode(type: .conditionIfElse, name: "条件", config: ["condition": "error"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkflowNode.self, from: data)
        XCTAssertEqual(decoded.type, .conditionIfElse)
        XCTAssertEqual(decoded.name, "条件")
        XCTAssertEqual(decoded.config["condition"], "error")
    }

    // MARK: - WorkflowEdge 测试

    func testEdgeInit() {
        let sourceId = UUID()
        let targetId = UUID()
        let edge = WorkflowEdge(sourceId: sourceId, targetId: targetId)
        XCTAssertEqual(edge.sourceId, sourceId)
        XCTAssertEqual(edge.targetId, targetId)
        XCTAssertNil(edge.condition)
    }

    func testEdgeWithCondition() {
        let edge = WorkflowEdge(sourceId: UUID(), targetId: UUID(), condition: "true")
        XCTAssertEqual(edge.condition, "true")
    }

    // MARK: - Workflow 测试

    func testWorkflowInit() {
        let workflow = Workflow(name: "测试工作流")
        XCTAssertEqual(workflow.name, "测试工作流")
        XCTAssertEqual(workflow.nodeCount, 0)
        XCTAssertEqual(workflow.edgeCount, 0)
        XCTAssertTrue(workflow.enabled)
        XCTAssertNil(workflow.triggerNode)
    }

    func testWorkflowTriggerNode() {
        let trigger = WorkflowNode(type: .triggerManual, name: "手动触发")
        let action = WorkflowNode(type: .actionLLM, name: "LLM")
        let workflow = Workflow(name: "测试", nodes: [trigger, action])
        XCTAssertEqual(workflow.triggerNode?.id, trigger.id)
    }

    func testWorkflowNodeAndEdgeCount() {
        let n1 = WorkflowNode(type: .triggerManual, name: "t")
        let n2 = WorkflowNode(type: .actionLLM, name: "a")
        let n3 = WorkflowNode(type: .output, name: "o")
        let e1 = WorkflowEdge(sourceId: n1.id, targetId: n2.id)
        let e2 = WorkflowEdge(sourceId: n2.id, targetId: n3.id)
        let workflow = Workflow(name: "线性", nodes: [n1, n2, n3], edges: [e1, e2])
        XCTAssertEqual(workflow.nodeCount, 3)
        XCTAssertEqual(workflow.edgeCount, 2)
    }

    func testWorkflowToJSON() throws {
        let workflow = Workflow(
            name: "JSON测试",
            nodes: [WorkflowNode(type: .triggerManual, name: "触发")]
        )
        let json = try workflow.toJSON()
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("JSON测试"))
    }

    func testWorkflowFromJSON() throws {
        let workflow = Workflow(
            name: "导入测试",
            nodes: [WorkflowNode(type: .triggerManual, name: "t")]
        )
        let json = try workflow.toJSON()
        let imported = try Workflow.fromJSON(json)
        XCTAssertEqual(imported.name, "导入测试")
        XCTAssertEqual(imported.nodeCount, 1)
    }

    func testWorkflowFromInvalidJSON() {
        XCTAssertThrowsError(try Workflow.fromJSON("invalid json")) { error in
            guard case WorkflowError.invalidJSON = error else {
                XCTFail("应抛出 invalidJSON 错误")
                return
            }
        }
    }

    // MARK: - WorkflowEngine 验证

    func testValidateNoTrigger() {
        let engine = WorkflowEngine()
        let workflow = Workflow(
            name: "无触发器",
            nodes: [WorkflowNode(type: .actionLLM, name: "LLM")]
        )
        XCTAssertThrowsError(try engine.validate(workflow)) { error in
            guard case WorkflowError.noTriggerNode = error else {
                XCTFail("应抛出 noTriggerNode 错误")
                return
            }
        }
    }

    func testValidateMaxNodesExceeded() {
        let engine = WorkflowEngine(maxNodes: 3)
        let nodes = (0..<5).map { WorkflowNode(type: .triggerManual, name: "n\($0)") }
        let workflow = Workflow(name: "超限", nodes: nodes)
        XCTAssertThrowsError(try engine.validate(workflow)) { error in
            guard case WorkflowError.maxNodesExceeded = error else {
                XCTFail("应抛出 maxNodesExceeded 错误")
                return
            }
        }
    }

    func testValidateCycleDetected() {
        let engine = WorkflowEngine()
        let n1 = WorkflowNode(type: .triggerManual, name: "n1")
        let n2 = WorkflowNode(type: .actionLLM, name: "n2")
        let n3 = WorkflowNode(type: .output, name: "n3")
        // 构造循环：n1 → n2 → n3 → n1
        let edges = [
            WorkflowEdge(sourceId: n1.id, targetId: n2.id),
            WorkflowEdge(sourceId: n2.id, targetId: n3.id),
            WorkflowEdge(sourceId: n3.id, targetId: n1.id)
        ]
        let workflow = Workflow(name: "循环", nodes: [n1, n2, n3], edges: edges)
        XCTAssertThrowsError(try engine.validate(workflow)) { error in
            guard case WorkflowError.cycleDetected = error else {
                XCTFail("应抛出 cycleDetected 错误")
                return
            }
        }
    }

    func testValidateValidWorkflow() throws {
        let engine = WorkflowEngine()
        let n1 = WorkflowNode(type: .triggerManual, name: "触发")
        let n2 = WorkflowNode(type: .actionLLM, name: "LLM")
        let n3 = WorkflowNode(type: .output, name: "输出")
        let edges = [
            WorkflowEdge(sourceId: n1.id, targetId: n2.id),
            WorkflowEdge(sourceId: n2.id, targetId: n3.id)
        ]
        let workflow = Workflow(name: "有效", nodes: [n1, n2, n3], edges: edges)
        XCTAssertNoThrow(try engine.validate(workflow))
    }

    // MARK: - WorkflowEngine 执行

    func testExecuteLinearWorkflow() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let llm = WorkflowNode(type: .actionLLM, name: "LLM")
        let output = WorkflowNode(type: .output, name: "输出")
        let edges = [
            WorkflowEdge(sourceId: trigger.id, targetId: llm.id),
            WorkflowEdge(sourceId: llm.id, targetId: output.id)
        ]
        let workflow = Workflow(name: "线性", nodes: [trigger, llm, output], edges: edges)
        let result = await engine.execute(workflow, input: "测试输入")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.nodeResults.count, 3, "应执行 3 个节点")
        XCTAssertNotNil(result.finalOutput)
    }

    func testExecuteWithToolNode() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let tool = WorkflowNode(type: .actionTool, name: "工具", config: ["toolName": "calculator"])
        let edges = [WorkflowEdge(sourceId: trigger.id, targetId: tool.id)]
        let workflow = Workflow(name: "工具", nodes: [trigger, tool], edges: edges)
        let result = await engine.execute(workflow)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.nodeResults[1].output.contains("calculator"))
    }

    func testExecuteWithAgentNode() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let agent = WorkflowNode(type: .actionAgent, name: "Agent", config: ["agentRole": "executor"])
        let edges = [WorkflowEdge(sourceId: trigger.id, targetId: agent.id)]
        let workflow = Workflow(name: "Agent", nodes: [trigger, agent], edges: edges)
        let result = await engine.execute(workflow)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.nodeResults[1].output.contains("executor"))
    }

    func testExecuteWithConditionNode() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let condition = WorkflowNode(type: .conditionIfElse, name: "条件", config: ["condition": "error"])
        let edges = [WorkflowEdge(sourceId: trigger.id, targetId: condition.id)]
        let workflow = Workflow(name: "条件", nodes: [trigger, condition], edges: edges)
        let result = await engine.execute(workflow, input: "this is an error message")
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.nodeResults[1].output.contains("条件满足"))
    }

    func testExecuteConditionNotMet() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let condition = WorkflowNode(type: .conditionIfElse, name: "条件", config: ["condition": "error"])
        let edges = [WorkflowEdge(sourceId: trigger.id, targetId: condition.id)]
        let workflow = Workflow(name: "条件", nodes: [trigger, condition], edges: edges)
        let result = await engine.execute(workflow, input: "normal message")
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.nodeResults[1].output.contains("条件不满足"))
    }

    func testExecuteSingleTriggerOnly() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let workflow = Workflow(name: "单节点", nodes: [trigger])
        let result = await engine.execute(workflow, input: "hello")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.nodeResults.count, 1)
        XCTAssertEqual(result.finalOutput, "hello")
    }

    func testExecuteDurationIsNonNegative() async {
        let engine = WorkflowEngine()
        let trigger = WorkflowNode(type: .triggerManual, name: "触发")
        let workflow = Workflow(name: "计时", nodes: [trigger])
        let result = await engine.execute(workflow)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0)
    }

    // MARK: - WorkflowError 测试

    func testErrorNoTriggerNode() {
        XCTAssertEqual(WorkflowError.noTriggerNode.errorDescription, "工作流缺少触发器节点")
    }

    func testErrorCycleDetected() {
        XCTAssertEqual(WorkflowError.cycleDetected.errorDescription, "检测到循环依赖")
    }

    func testErrorNodeNotFound() {
        let id = UUID()
        let error = WorkflowError.nodeNotFound(id)
        XCTAssertTrue(error.errorDescription?.contains(id.uuidString) == true)
    }

    func testErrorInvalidJSON() {
        XCTAssertEqual(WorkflowError.invalidJSON.errorDescription, "JSON 格式无效")
    }

    func testErrorMaxNodesExceeded() {
        XCTAssertEqual(WorkflowError.maxNodesExceeded.errorDescription, "节点数超过上限")
    }
}
