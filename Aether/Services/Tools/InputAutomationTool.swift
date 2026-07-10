/// 输入自动化工具（macOS only）
///
/// 通过 CoreGraphics 的 CGEvent 模拟鼠标和键盘输入，包括鼠标移动/点击/拖拽、
/// 键盘文本输入、快捷键组合、滚轮滚动。
/// 调用方式：execute(arguments: ["action": "...", ...])，action 为必填参数。
/// 主要 action：mouse_move/mouse_click/mouse_drag/key_type/key_combo/scroll。
#if os(macOS)
import Foundation
import CoreGraphics

/// macOS 输入自动化工具：模拟鼠标移动/点击/拖拽、键盘输入、滚轮滚动
final class InputAutomationTool: ToolProtocol {
    /// 工具定义
    /// - name: `simulate_input`
    /// - parameters: `action`（必填，String）— 操作类型；坐标、文本、按键、修饰键等按需传入
    var definition: ToolDefinition {
        ToolDefinition(
            name: "simulate_input",
            description: "模拟输入：鼠标移动/点击/拖拽、键盘输入、快捷键、滚轮",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作：mouse_move/mouse_click/mouse_drag/key_type/key_combo/scroll"],
                    "x": ["type": "integer", "description": "X 坐标"],
                    "y": ["type": "integer", "description": "Y 坐标"],
                    "from_x": ["type": "integer", "description": "拖拽起点 X"],
                    "from_y": ["type": "integer", "description": "拖拽起点 Y"],
                    "to_x": ["type": "integer", "description": "拖拽终点 X"],
                    "to_y": ["type": "integer", "description": "拖拽终点 Y"],
                    "text": ["type": "string", "description": "要输入的文本（key_type）"],
                    "key": ["type": "string", "description": "按键名称（key_combo）"],
                    "modifiers": ["type": "array", "description": "修饰键列表：command/shift/option/control"],
                    "delta_y": ["type": "integer", "description": "滚轮 Y 方向增量（scroll）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// 执行输入模拟操作
    ///
    /// - Parameter arguments: 含 `action` 及其所需坐标/文本/按键参数的字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "mouse_move": return mouseMove(arguments)
        case "mouse_click": return mouseClick(arguments)
        case "mouse_drag": return mouseDrag(arguments)
        case "key_type": return keyType(arguments)
        case "key_combo": return keyCombo(arguments)
        case "scroll": return scroll(arguments)
        default: return "错误：不支持的操作，支持 mouse_move/mouse_click/mouse_drag/key_type/key_combo/scroll"
        }
    }

    /// 移动鼠标到指定坐标：构造 mouseMoved 事件并 post 到 HID 事件层
    private func mouseMove(_ arguments: [String: Any]) -> String {
        guard let x = arguments["x"] as? Int, let y = arguments["y"] as? Int else {
            return "错误：请提供 x 和 y 参数"
        }
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)), mouseButton: .left)
        event?.post(tap: .cghidEventTap)
        return "已移动鼠标到 (\(x), \(y))"
    }

    /// 在指定坐标点击鼠标：依次 post 按下与抬起事件
    private func mouseClick(_ arguments: [String: Any]) -> String {
        guard let x = arguments["x"] as? Int, let y = arguments["y"] as? Int else {
            return "错误：请提供 x 和 y 参数"
        }
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
        return "已在 (\(x), \(y)) 点击"
    }

    /// 从起点拖拽到终点：按下 -> 拖拽 -> 抬起 三个事件
    private func mouseDrag(_ arguments: [String: Any]) -> String {
        guard let fromX = arguments["from_x"] as? Int, let fromY = arguments["from_y"] as? Int,
              let toX = arguments["to_x"] as? Int, let toY = arguments["to_y"] as? Int else {
            return "错误：请提供 from_x, from_y, to_x, to_y 参数"
        }
        let startPoint = CGPoint(x: CGFloat(fromX), y: CGFloat(fromY))
        let endPoint = CGPoint(x: CGFloat(toX), y: CGFloat(toY))
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: startPoint, mouseButton: .left)
        let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: endPoint, mouseButton: .left)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: endPoint, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap)
        dragEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
        return "已从 (\(fromX), \(fromY)) 拖拽到 (\(toX), \(toY))"
    }

    /// 逐字符输入文本：每个字符查键码后 post 按下/抬起事件
    private func keyType(_ arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else {
            return "错误：请提供 text 参数"
        }
        for char in text {
            if let keyCode = charToKeyCode(char) {
                let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
                let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
                downEvent?.post(tap: .cghidEventTap)
                upEvent?.post(tap: .cghidEventTap)
            }
        }
        return "已输入文本：\(text)"
    }

    /// 执行快捷键组合：将修饰键名称转为 CGEventFlags，与按键一同 post
    private func keyCombo(_ arguments: [String: Any]) -> String {
        guard let key = arguments["key"] as? String else {
            return "错误：请提供 key 参数"
        }
        guard let keyCode = stringToKeyCode(key) else {
            return "错误：未知按键：\(key)"
        }
        let modifiers = arguments["modifiers"] as? [String] ?? []
        // 将修饰键名称列表合并为 CGEventFlags 位掩码
        let flags = modifiers.reduce(CGEventFlags.maskNonCoalesced) { result, mod in
            switch mod.lowercased() {
            case "command": return result.union(.maskCommand)
            case "shift": return result.union(.maskShift)
            case "option": return result.union(.maskAlternate)
            case "control": return result.union(.maskControl)
            default: return result
            }
        }
        let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        downEvent?.flags = flags
        let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        upEvent?.flags = flags
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
        let modStr = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "+"
        return "已执行快捷键：\(modStr)\(key)"
    }

    /// 滚轮滚动：按像素单位 post 滚轮事件
    private func scroll(_ arguments: [String: Any]) -> String {
        guard let deltaY = arguments["delta_y"] as? Int else {
            return "错误：请提供 delta_y 参数"
        }
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(deltaY), wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
        return "已滚动 \(deltaY) 像素"
    }

    /// 单字符到 virtualKey 的映射（字母 + 空格 + 回车）
    private func charToKeyCode(_ char: Character) -> CGKeyCode? {
        // 简化映射：字母和数字
        let mapping: [Character: CGKeyCode] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
            "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
            "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
            "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
            " ": 49, "\n": 36
        ]
        return mapping[char.lowercased().first ?? char]
    }

    /// 按键名称到 virtualKey 的映射（含功能键、方向键、数字等）
    private func stringToKeyCode(_ key: String) -> CGKeyCode? {
        let mapping: [String: CGKeyCode] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
            "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
            "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
            "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
            "return": 36, "enter": 36, "space": 49, "tab": 48,
            "escape": 53, "esc": 53, "delete": 51, "forwarddelete": 117,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "leftarrow": 123, "rightarrow": 124, "downarrow": 125, "uparrow": 126,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25
        ]
        return mapping[key.lowercased()]
    }
}
#endif
