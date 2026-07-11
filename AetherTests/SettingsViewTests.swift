import XCTest
@testable import Aether

/// SettingsView 单元测试：覆盖 SettingsSection 枚举的 title/icon 计算属性、
/// CaseIterable/Identifiable/Hashable 一致性，以及 DebugInfo / ToolCallDebug 值类型。
/// 注：SettingsView 本体的 section 渲染方法与生命周期回调均为 private，
/// 故仅测试文件内 internal 的枚举与值类型，不修改实现代码。
final class SettingsViewTests: XCTestCase {

    // MARK: - SettingsSection: CaseIterable

    /// 验证 SettingsSection 包含全部 6 个分类，顺序与声明一致。
    func testSettingsSectionAllCasesCount() {
        XCTAssertEqual(SettingsSection.allCases.count, 6, "应包含 6 个分类")
        XCTAssertEqual(
            SettingsSection.allCases,
            [.provider, .inference, .voice, .features, .health, .about],
            "allCases 顺序应与声明一致"
        )
    }

    // MARK: - SettingsSection: title

    /// 验证每个 case 的 title 非空（确保 switch 无遗漏分支）。
    func testTitleNonEmptyForAllCases() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty, "title 不应为空：\(section)")
        }
    }

    /// 验证每个 case 的 title 返回预期文案。
    func testTitleExpectedValues() {
        XCTAssertEqual(SettingsSection.provider.title, "API 与模型")
        XCTAssertEqual(SettingsSection.inference.title, "推理配置")
        XCTAssertEqual(SettingsSection.voice.title, "语音朗读")
        XCTAssertEqual(SettingsSection.features.title, "功能与偏好")
        XCTAssertEqual(SettingsSection.health.title, "健康")
        XCTAssertEqual(SettingsSection.about.title, "关于")
    }

    /// 验证不同 case 的 title 互不相同（避免复制粘贴导致重复）。
    func testTitlesAreUnique() {
        let titles = SettingsSection.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "所有 title 应互不相同")
    }

    // MARK: - SettingsSection: icon

    /// 验证每个 case 的 icon 非空（确保 switch 无遗漏分支）。
    func testIconNonEmptyForAllCases() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.icon.isEmpty, "icon 不应为空：\(section)")
        }
    }

    /// 验证每个 case 的 icon 返回预期 SF Symbol 名称。
    func testIconExpectedValues() {
        XCTAssertEqual(SettingsSection.provider.icon, "network")
        XCTAssertEqual(SettingsSection.inference.icon, "cpu")
        XCTAssertEqual(SettingsSection.voice.icon, "speaker.wave.2")
        XCTAssertEqual(SettingsSection.features.icon, "switch.2")
        XCTAssertEqual(SettingsSection.health.icon, "heart.text.square")
        XCTAssertEqual(SettingsSection.about.icon, "info.circle")
    }

    /// 验证不同 case 的 icon 互不相同。
    func testIconsAreUnique() {
        let icons = SettingsSection.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count, "所有 icon 应互不相同")
    }

    // MARK: - SettingsSection: Identifiable

    /// 验证 id 等于 rawValue（Identifiable 一致性）。
    func testIdEqualsRawValue() {
        for section in SettingsSection.allCases {
            XCTAssertEqual(section.id, section.rawValue, "id 应等于 rawValue：\(section)")
        }
    }

    /// 验证 rawValue 为 case 名字符串（String 原始值枚举约定）。
    func testRawValuesAreCaseNames() {
        XCTAssertEqual(SettingsSection.provider.rawValue, "provider")
        XCTAssertEqual(SettingsSection.inference.rawValue, "inference")
        XCTAssertEqual(SettingsSection.voice.rawValue, "voice")
        XCTAssertEqual(SettingsSection.features.rawValue, "features")
        XCTAssertEqual(SettingsSection.health.rawValue, "health")
        XCTAssertEqual(SettingsSection.about.rawValue, "about")
    }

    /// 验证 rawValue 可反向初始化回对应 case。
    func testInitFromRawValueRoundTrip() {
        for section in SettingsSection.allCases {
            let restored = SettingsSection(rawValue: section.rawValue)
            XCTAssertEqual(restored, section, "rawValue 往返应还原原 case：\(section.rawValue)")
        }
    }

    // MARK: - SettingsSection: Hashable / Equatable

    /// 验证相同 case 相等、不同 case 不等。
    func testEquatableSameAndDifferentCases() {
        XCTAssertEqual(SettingsSection.provider, SettingsSection.provider)
        XCTAssertNotEqual(SettingsSection.provider, SettingsSection.inference)
        XCTAssertNotEqual(SettingsSection.health, SettingsSection.about)
    }

    /// 验证可放入 Set 去重（Hashable 一致性）。
    func testHashableSetDeduplication() {
        let duplicates: [SettingsSection] = [.provider, .provider, .voice, .voice, .about]
        let unique = Set(duplicates)
        XCTAssertEqual(unique.count, 3, "Set 应去重为 3 个 case")
        XCTAssertTrue(unique.contains(.provider))
        XCTAssertTrue(unique.contains(.voice))
        XCTAssertTrue(unique.contains(.about))
    }

    // MARK: - SettingsSection: title 与 icon 覆盖对齐

    /// 验证每个 case 同时拥有 title 与 icon（无任一缺失）。
    func testEveryCaseHasBothTitleAndIcon() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty, "title 缺失：\(section)")
            XCTAssertFalse(section.icon.isEmpty, "icon 缺失：\(section)")
        }
    }

    // MARK: - DebugInfo

    /// 验证 DebugInfo 各字段正确存储。
    func testDebugInfoStoresFields() {
        let toolCall = DebugInfo.ToolCallDebug(
            toolName: "weather",
            arguments: "{\"city\":\"上海\"}",
            result: "晴 28℃"
        )
        let info = DebugInfo(
            promptJSON: "{}",
            apiResponse: "ok",
            embeddingDimension: 1024,
            toolCalls: [toolCall],
            provider: "deepseek",
            fallbackUsed: false
        )
        XCTAssertEqual(info.promptJSON, "{}")
        XCTAssertEqual(info.apiResponse, "ok")
        XCTAssertEqual(info.embeddingDimension, 1024)
        XCTAssertEqual(info.toolCalls.count, 1)
        XCTAssertEqual(info.toolCalls.first?.toolName, "weather")
        XCTAssertEqual(info.provider, "deepseek")
        XCTAssertFalse(info.fallbackUsed)
    }

    /// 验证 DebugInfo 支持空 toolCalls 与可选 provider 为 nil。
    func testDebugInfoAllowsEmptyToolCallsAndNilProvider() {
        let info = DebugInfo(
            promptJSON: "",
            apiResponse: "",
            embeddingDimension: 0,
            toolCalls: [],
            provider: nil,
            fallbackUsed: false
        )
        XCTAssertTrue(info.toolCalls.isEmpty)
        XCTAssertNil(info.provider)
        XCTAssertEqual(info.embeddingDimension, 0)
    }

    // MARK: - DebugInfo.ToolCallDebug

    /// 验证 ToolCallDebug 每个实例拥有独立 id（Identifiable 一致性）。
    func testToolCallDebugHasUniqueId() {
        let a = DebugInfo.ToolCallDebug(toolName: "a", arguments: "", result: "")
        let b = DebugInfo.ToolCallDebug(toolName: "a", arguments: "", result: "")
        XCTAssertNotEqual(a.id, b.id, "两个 ToolCallDebug 实例 id 应不同")
        XCTAssertEqual(a.toolName, "a")
    }

    /// 验证 ToolCallDebug 字段正确存储。
    func testToolCallDebugStoresFields() {
        let call = DebugInfo.ToolCallDebug(
            toolName: "calculator",
            arguments: "{\"expr\":\"1+1\"}",
            result: "2"
        )
        XCTAssertEqual(call.toolName, "calculator")
        XCTAssertEqual(call.arguments, "{\"expr\":\"1+1\"}")
        XCTAssertEqual(call.result, "2")
    }
}
