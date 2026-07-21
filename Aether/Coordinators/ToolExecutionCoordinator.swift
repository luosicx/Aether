import Foundation
import SwiftData
import AetherFoundation
import AetherServices
import os

/// P2-6 Task 10: ToolExecutionCoordinator —— ReAct 工具执行循环协调器。
///
/// 从 ChatViewModel 抽取的 ReAct 工具调用执行职责，承担：
/// - 编码 toolCalls 持久化 assistant 消息（含 toolCallData）
/// - 逐个执行工具（启用检查 / 授权确认 / 超时保护 / 审计日志 / 成功通知 / 失败埋点）
/// - 追加 tool 结果消息（成功 / 失败均构造 ChatMessage(role: "tool", ...)）
/// - 重置下一轮 apiMessages 为最新会话消息序列
///
/// 设计要点：
/// - 类型迁移：`ToolStep` / `ToolStepStatus` 从 ChatViewModel 迁移至本类，
///   ChatViewModel 通过 `typealias ToolStep = ToolExecutionCoordinator.ToolStep` 保持兼容。
/// - 状态同步：通过闭包回调更新 ChatViewModel 的 @Observable 属性
///   （currentToolSteps append / update、messages append、errorMessage set）。
/// - 服务复用：ToolRegistry / ToolAuthorization / ToolAuditLogger / NotificationService /
///   TelemetryService 均使用 shared 单例，与原 ChatViewModel.handleToolCalling 实现一致。
/// - 并发隔离：本类标注 `@MainActor`，所有闭包在主 actor 上调用；
///   超时保护通过 `withThrowingTaskGroup` 实现，超时不中断 ReAct 主循环。
///
/// 与 Agent 模块 `AgentToolExecutionCoordinator`（actor，DAG 串行化）的区别：
/// - 本类是 ChatViewModel ReAct 循环的子模块，每轮 LLM 输出 toolCalls 时被调用一次
/// - Agent 版本是 DAGExecutionEngine 的工具调用串行化器，跨节点共享
/// - 两者职责不同，命名已分离以避免同模块同名冲突
@MainActor
final class ToolExecutionCoordinator: Coordinator {

    // MARK: - 迁移类型（ChatViewModel 通过 typealias 引用）

    /// 单个工具调用步骤的 UI 状态
    /// Task 8: 标记 Sendable，所有成员均为 Sendable 类型，可安全跨 actor 传递。
    struct ToolStep: Identifiable, Sendable {
        /// 唯一标识
        let id = UUID()
        /// 工具名
        let toolName: String
        /// 步骤状态
        var status: ToolStepStatus
        /// 工具执行结果
        var result: String?
        /// Day 8: assistant 此轮的决策文本（Thought 段）。可能为 nil（AI 仅返回 tool_calls 无文本）
        var thought: String?
        /// Day 8: 工具调用的参数 JSON 字符串（Action 段）
        var arguments: String
        /// Day 8: 当前 ReAct 轮次序号（从 1 开始）
        var loopIndex: Int
    }

    /// 工具步骤状态
    /// Task 8: 标记 Sendable，无关联值的简单枚举自动满足 Sendable。
    enum ToolStepStatus: Sendable {
        case running, completed, failed
    }

    // MARK: - 配置与依赖

    /// Day 8: 单工具执行超时（秒）。超时不中断 ReAct 循环，标记失败后继续下一轮。
    private let toolTimeout: TimeInterval

    // MARK: - 与 ChatViewModel 的闭包通信

    /// 追加新 ToolStep 到 ChatViewModel.currentToolSteps（@Observable）
    private let onToolStepAppend: (ToolStep) -> Void
    /// 更新指定索引 ToolStep 的 status 与 result（@Observable）
    private let onToolStepUpdate: (Int, ToolStepStatus, String?) -> Void
    /// 追加 ChatMessage 到 ChatViewModel.messages（@Observable）
    private let onMessageAppend: (ChatMessage) -> Void
    /// 设置 ChatViewModel.errorMessage（@Observable）
    private let onErrorMessageChange: (String?) -> Void

    // MARK: - Init

    /// 创建 ToolExecutionCoordinator
    /// - Parameters:
    ///   - toolTimeout: 单工具执行超时秒数（默认 15，与 ChatViewModel 原值一致）
    ///   - onToolStepAppend: ToolStep 追加回调（更新 ChatViewModel.currentToolSteps）
    ///   - onToolStepUpdate: ToolStep 状态更新回调（更新指定索引的 status / result）
    ///   - onMessageAppend: ChatMessage 追加回调（更新 ChatViewModel.messages）
    ///   - onErrorMessageChange: errorMessage 设置回调（更新 ChatViewModel.errorMessage）
    init(toolTimeout: TimeInterval = 15,
         onToolStepAppend: @escaping (ToolStep) -> Void,
         onToolStepUpdate: @escaping (Int, ToolStepStatus, String?) -> Void,
         onMessageAppend: @escaping (ChatMessage) -> Void,
         onErrorMessageChange: @escaping (String?) -> Void) {
        self.toolTimeout = toolTimeout
        self.onToolStepAppend = onToolStepAppend
        self.onToolStepUpdate = onToolStepUpdate
        self.onMessageAppend = onMessageAppend
        self.onErrorMessageChange = onErrorMessageChange
    }

    // MARK: - 主入口（ReAct 工具调用阶段）

    /// SubTask 6.6 → Task 10: ReAct 工具调用阶段——编码 toolCalls 持久化助手消息（含 toolCallData）、
    /// 逐个执行工具（启用检查 / 授权确认 / 超时保护 / 审计日志 / 成功通知 / 失败埋点）、
    /// 追加 tool 结果消息、重置 apiMessages 为最新会话消息序列供下一轮流式使用。
    ///
    /// - Parameters:
    ///   - toolCalls: 本轮 LLM 解析出的工具调用列表
    ///   - lastChunkContent: 本轮流式输出累积的 chunk 文本（用作 assistant 消息内容与 thought）
    ///   - loopCount: 当前 ReAct 轮次（从 1 开始，用于 ToolStep.loopIndex）
    ///   - conversation: 当前会话（用于追加 assistant / tool 消息）
    ///   - modelContext: SwiftData 上下文（用于持久化）
    /// - Returns: 重置后的 apiMessages 数组（供下一轮 LLM 请求使用）
    func handle(toolCalls: [AccumulatedToolCall],
                lastChunkContent: String,
                loopCount: Int,
                conversation: Conversation,
                modelContext: ModelContext) async -> [APIMessage] {
        let chunkContent = lastChunkContent
        let toolCallsData: Data? = {
            struct StoredToolCall: Codable {
                let id: String
                let type: String
                let name: String
                let arguments: String
            }
            let stored = toolCalls.map { StoredToolCall(id: $0.id, type: $0.type, name: $0.name, arguments: $0.arguments) }
            do {
                return try JSONEncoder().encode(stored)
            } catch {
                // toolCalls 编码失败：toolCallData 留空，LLM 多轮调用上下文丢失
                Logger.chat.error("持久化 assistant 消息: toolCalls 编码失败: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }()
        let assistantMsg = ChatMessage(role: "assistant", content: chunkContent, toolCallData: toolCallsData)
        assistantMsg.conversation = conversation
        conversation.messages.append(assistantMsg)
        onMessageAppend(assistantMsg)
        do { try modelContext.save() } catch { Logger.chat.error("工具调用助手消息保存失败: \(error.localizedDescription, privacy: .public)") }
        // Day 8: thought 为 chunkContent（非空时显示思维链）
        let thought = chunkContent.isEmpty ? nil : chunkContent
        for tc in toolCalls {
            let step = ToolStep(
                toolName: tc.name,
                status: .running,
                result: nil,
                thought: thought,
                arguments: tc.arguments,
                loopIndex: loopCount
            )
            // 先获取 stepIdx（与 ChatViewModel.currentToolSteps 的实际索引一致），
            // 再触发 onToolStepAppend 闭包更新 ChatViewModel.currentToolSteps。
            // 内部计数器 toolStepsCount 与 ChatViewModel.currentToolSteps.count 同步自增。
            let stepIdx = nextStepIndex()
            onToolStepAppend(step)
            // Day 14: 记录工具执行开始时间，用于计算 duration
            let toolStartTime = Date()
            let argsData = tc.arguments.data(using: .utf8) ?? Data()
            let parsedArgs = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
            let argsSummary = parsedArgs.keys.sorted().joined(separator: ", ")
            var toolAuthorized = false
            do {
                // Task 4: 调用前检查启用状态与运行时授权
                guard ToolRegistry.shared.isEnabled(name: tc.name) else {
                    throw NSError(domain: "ToolRegistry", code: 3, userInfo: [NSLocalizedDescriptionKey: "工具 \(tc.name) 未启用"])
                }
                if ToolRegistry.shared.requiresAuthorization(name: tc.name) {
                    let authResult: ToolAuthorizationResult
                    if ToolRegistry.shared.defaultDisabledTools.contains(tc.name) {
                        let details = "工具：\(tc.name)\n参数：\(tc.arguments)"
                        authResult = await ToolAuthorization.shared.presentConfirmation(toolName: tc.name, details: details)
                    } else {
                        let purpose = ToolRegistry.shared.getTool(named: tc.name)?.definition.description ?? ""
                        authResult = await ToolAuthorization.shared.presentSensitiveAccessConfirmation(toolName: tc.name, purpose: purpose)
                    }
                    guard case .authorized = authResult else {
                        throw NSError(domain: "ToolAuthorization", code: 2, userInfo: [NSLocalizedDescriptionKey: "用户拒绝了 \(tc.name) 工具调用"])
                    }
                    toolAuthorized = true
                } else {
                    toolAuthorized = true
                }
                // Day 8: 单工具超时保护，超时抛错不中断循环
                // 说明：withThrowingTaskGroup + 超时 Task 抛错，第一个完成的 Task 胜出；
                //       超时后标记 failed 继续下一轮，保证 ReAct 不因单工具卡死而中断。
                let result = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        try await ToolRegistry.shared.execute(name: tc.name, arguments: parsedArgs)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(self.toolTimeout * 1_000_000_000))
                        throw NSError(domain: "ToolTimeout", code: -1, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("工具执行超时（%ds）", comment: ""), Int(self.toolTimeout))])
                    }
                    let first = try await group.next() ?? ""
                    group.cancelAll()
                    return first
                }
                onToolStepUpdate(stepIdx, .completed, result)
                // Day 14: 工具执行成功埋点
                let toolDurationMs = Int(Date().timeIntervalSince(toolStartTime) * 1000)
                let toolName = tc.name
                Task.detached { await TelemetryService.shared.track(.toolCall(toolName: toolName, success: true, durationMs: toolDurationMs)) }
                // Task 7: 记录工具调用审计日志（仅记录参数键，不记录完整内容）
                ToolAuditLogger.shared.log(toolName: tc.name, argumentsSummary: argsSummary, authorized: toolAuthorized, timestamp: toolStartTime)
                // 补充 D：工具执行成功后发本地通知
                NotificationService.shared.sendNotification(
                    title: NSLocalizedString("工具调用成功", comment: ""),
                    body: String(format: NSLocalizedString("%@ 已完成：%@", comment: ""), tc.name, result)
                )
                let toolMsg = ChatMessage(role: "tool", content: result, toolCallId: tc.id, toolName: tc.name)
                toolMsg.conversation = conversation
                conversation.messages.append(toolMsg)
                onMessageAppend(toolMsg)
                do { try modelContext.save() } catch { Logger.chat.error("工具结果消息保存失败: \(error.localizedDescription, privacy: .public)") }
            } catch {
                // Task 7: 工具调用失败/未授权也记录审计日志
                ToolAuditLogger.shared.log(toolName: tc.name, argumentsSummary: argsSummary, authorized: toolAuthorized, timestamp: toolStartTime)
                // Day 14: 工具执行失败埋点 + 错误埋点
                let toolDurationMs = Int(Date().timeIntervalSince(toolStartTime) * 1000)
                let toolName = tc.name
                let errorType = String(describing: error)
                let errorMsg = String(format: NSLocalizedString("工具 %@ 执行失败: %@", comment: ""), tc.name, error.localizedDescription)
                Task.detached { await TelemetryService.shared.track(.toolCall(toolName: toolName, success: false, durationMs: toolDurationMs)) }
                Task.detached { await TelemetryService.shared.track(.errorOccurred(errorType: errorType, userMessage: errorMsg)) }
                let errMsg = error.localizedDescription
                onToolStepUpdate(stepIdx, .failed, errMsg)
                // Day 8: 超时/失败时也给 AI 一个 tool message，让它知道该工具失败的原因
                let failContent = String(format: NSLocalizedString("工具执行失败: %@", comment: ""), errMsg)
                let toolMsg = ChatMessage(role: "tool", content: failContent, toolCallId: tc.id, toolName: tc.name)
                toolMsg.conversation = conversation
                conversation.messages.append(toolMsg)
                onMessageAppend(toolMsg)
                do { try modelContext.save() } catch { Logger.chat.error("工具失败消息保存失败: \(error.localizedDescription, privacy: .public)") }
                onErrorMessageChange(String(format: NSLocalizedString("工具 %@ 执行失败: %@", comment: ""), tc.name, errMsg))
            }
        }
        return conversation.messages.map { $0.toAPIMessage() }
    }

    // MARK: - 私有辅助

    /// 内部 ToolStep 计数器，与 ChatViewModel.currentToolSteps.count 同步。
    ///
    /// 实现说明：本类不持有 currentToolSteps 状态（状态保留在 ChatViewModel.currentToolSteps，
    /// 保持 @Observable 自动追踪），但需要 stepIdx 来更新指定索引的 status/result。
    /// 通过 `nextStepIndex()` 在每次 onToolStepAppend 调用前自增计数器，保证索引一致。
    private var toolStepsCount: Int = 0

    /// append 前调用：返回当前 step 的索引（与 ChatViewModel.currentToolSteps.count 一致）并自增计数器。
    private func nextStepIndex() -> Int {
        let idx = toolStepsCount
        toolStepsCount += 1
        return idx
    }

    /// 重置内部计数器（ChatViewModel 在 processMessage 入口或会话切换时调用）
    /// 说明：与 ChatViewModel.currentToolSteps = [] 同步调用，保证下一轮 ReAct 计数从 0 开始。
    func resetStepCounter() {
        toolStepsCount = 0
    }
}
