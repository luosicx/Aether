import XCTest
@testable import AIBuilder

final class PresetPromptsTests: XCTestCase {
    func testPresetCountAtLeast11() {
        XCTAssertGreaterThanOrEqual(PresetPrompts.all.count, 11, "预设角色应至少 11 个")
    }

    func testEachPresetRoleAndPromptNotEmpty() {
        for preset in PresetPrompts.all {
            XCTAssertFalse(preset.role.isEmpty, "角色名不能为空")
            XCTAssertFalse(preset.prompt.isEmpty, "prompt 不能为空")
        }
    }

    func testEachPromptAtLeast150CharsExceptDefault() {
        for preset in PresetPrompts.all {
            // 默认助手允许短一些
            if preset.role == "默认助手" { continue }
            XCTAssertGreaterThanOrEqual(
                preset.prompt.count,
                150,
                "\(preset.role) 的 prompt 应不少于 150 字，实际 \(preset.prompt.count) 字"
            )
        }
    }

    func testPresetRolesUnique() {
        let roles = PresetPrompts.all.map { $0.role }
        XCTAssertEqual(roles.count, Set(roles).count, "角色名不能重复")
    }
}
