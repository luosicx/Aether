#if os(visionOS)
import Foundation
import AetherFoundation

/// v2.0 visionOS 工具注册扩展。
///
/// 注册策略：
/// - 跨平台工具（与 iOS 共用的 14 个）已在 ToolRegistry.shared 基类 init() 中注册，visionOS 直接复用，无需重复注册。
/// - 不注册 macOS 独有工具（AppleScript / Screenshot / OCR / Terminal / Window / App / File / Finder / Safari / SystemControl / InputAutomation）。
/// - 新增 3 个空间化工具占位：SpatialTool / PinchTool / GazeTool（仅定义，不实现具体逻辑）。
///
/// 调用时机：visionOS App init() 中，在 ToolRegistry.shared 初始化后调用
/// ToolRegistry.shared.registerVisionOSTools()。
extension ToolRegistry {
    /// 注册 visionOS 空间化工具（3 个占位）。
    /// 跨平台工具（14 个）已在基类 init 注册，macOS 独有工具不注册。
    func registerVisionOSTools() {
        register(tool: SpatialTool())
        register(tool: PinchTool())
        register(tool: GazeTool())

        // 注册完成后重新恢复启用状态（包含新增工具的默认值）
        restoreEnabledStates()
    }

    /// visionOS 空间化工具名集合，便于测试与设置页过滤
    static let visionOSToolNames: Set<String> = [
        "spatial_action",
        "pinch_gesture",
        "gaze_focus"
    ]
}

// MARK: - 空间化工具占位（仅定义，不实现具体逻辑）

/// 空间动作工具占位：捕获 visionOS 空间手势 / 姿态触发动作。具体逻辑待 v2.0 后续实现。
final class SpatialTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name / description / parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "spatial_action",
            description: "空间动作工具（占位）：捕获 visionOS 空间手势触发动作，具体逻辑待实现",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "空间动作类型，占位"]
                ],
                "required": []
            ]
        )
    }

    /// 占位实现：返回未实现提示，不执行具体逻辑
    func execute(arguments: [String: Any]) async throws -> String {
        "spatial_action 占位：具体逻辑待 v2.0 后续实现"
    }
}

/// 捏合手势工具占位：识别 visionOS 捏合手势并触发对应操作。具体逻辑待 v2.0 后续实现。
final class PinchTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name / description / parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "pinch_gesture",
            description: "捏合手势工具（占位）：识别 visionOS 捏合手势并触发操作，具体逻辑待实现",
            parameters: [
                "type": "object",
                "properties": [
                    "target": ["type": "string", "description": "捏合目标标识，占位"]
                ],
                "required": []
            ]
        )
    }

    /// 占位实现：返回未实现提示，不执行具体逻辑
    func execute(arguments: [String: Any]) async throws -> String {
        "pinch_gesture 占位：具体逻辑待 v2.0 后续实现"
    }
}

/// 凝视工具占位：识别用户视线焦点并返回聚焦对象。具体逻辑待 v2.0 后续实现。
final class GazeTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name / description / parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "gaze_focus",
            description: "凝视工具（占位）：识别 visionOS 用户视线焦点并返回聚焦对象，具体逻辑待实现",
            parameters: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "凝视持续时长（秒），占位"]
                ],
                "required": []
            ]
        )
    }

    /// 占位实现：返回未实现提示，不执行具体逻辑
    func execute(arguments: [String: Any]) async throws -> String {
        "gaze_focus 占位：具体逻辑待 v2.0 后续实现"
    }
}
#endif
