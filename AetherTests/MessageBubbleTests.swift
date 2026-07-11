import XCTest
import SwiftUI
@testable import Aether

/// MessageBubble 及 MessageSnapshot 单元测试
///
/// 可测试内容：
/// - MessageSnapshot（internal struct，Identifiable + Equatable）
/// - ToolbarItemPlacement 跨平台扩展（topBarTrailingCompat / topBarLeadingCompat）
/// - MessageBubble View 构造（internal init，含默认参数）
///
/// 注意：`platformImage(from:)` 为 private，无法直接测试；
/// `isUser` / `isTool` / `isAssistant` / `canSpeak` 为 private 计算属性，无法直接测试。
@MainActor
final class MessageBubbleTests: XCTestCase {

    // MARK: - MessageSnapshot 创建与字段

    /// 验证所有字段在创建后被正确保留
    func testMessageSnapshotCreationWithAllFields() {
        let id = UUID()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let attachedImage = Data([0xFF, 0xD8, 0xFF])

        let snapshot = MessageSnapshot(
            id: id,
            role: "user",
            content: "Hello",
            imageData: imageData,
            isStreaming: false,
            attachedImage: attachedImage
        )
        XCTAssertEqual(snapshot.id, id)
        XCTAssertEqual(snapshot.role, "user")
        XCTAssertEqual(snapshot.content, "Hello")
        XCTAssertEqual(snapshot.imageData, imageData)
        XCTAssertFalse(snapshot.isStreaming)
        XCTAssertEqual(snapshot.attachedImage, attachedImage)
    }

    /// 可选字段为 nil 时创建正常
    func testMessageSnapshotCreationWithNilOptionals() {
        let snapshot = MessageSnapshot(
            id: UUID(),
            role: "assistant",
            content: "",
            imageData: nil,
            isStreaming: true,
            attachedImage: nil
        )
        XCTAssertNil(snapshot.imageData)
        XCTAssertNil(snapshot.attachedImage)
        XCTAssertTrue(snapshot.isStreaming)
    }

    /// 空内容创建正常
    func testMessageSnapshotCreationWithEmptyContent() {
        let snapshot = MessageSnapshot(
            id: UUID(),
            role: "user",
            content: "",
            imageData: nil,
            isStreaming: false,
            attachedImage: nil
        )
        XCTAssertTrue(snapshot.content.isEmpty)
    }

    // MARK: - MessageSnapshot 各种角色

    /// 用户角色可正确创建
    func testMessageSnapshotUserRole() {
        let snapshot = makeSnapshot(role: "user")
        XCTAssertEqual(snapshot.role, "user")
    }

    /// AI 助手角色可正确创建
    func testMessageSnapshotAssistantRole() {
        let snapshot = makeSnapshot(role: "assistant")
        XCTAssertEqual(snapshot.role, "assistant")
    }

    /// 系统角色可正确创建
    func testMessageSnapshotSystemRole() {
        let snapshot = makeSnapshot(role: "system")
        XCTAssertEqual(snapshot.role, "system")
    }

    /// 工具角色可正确创建
    func testMessageSnapshotToolRole() {
        let snapshot = makeSnapshot(role: "tool")
        XCTAssertEqual(snapshot.role, "tool")
    }

    // MARK: - MessageSnapshot Equatable：所有字段相等时应相等

    /// 所有字段相同时两个 snapshot 应相等
    func testMessageSnapshotEqualWhenAllFieldsMatch() {
        let id = UUID()
        let data = Data([0x01, 0x02])
        let s1 = MessageSnapshot(id: id, role: "user", content: "hi",
                                imageData: data, isStreaming: true, attachedImage: data)
        let s2 = MessageSnapshot(id: id, role: "user", content: "hi",
                                imageData: data, isStreaming: true, attachedImage: data)
        XCTAssertEqual(s1, s2, "所有字段相同时应相等")
    }

    // MARK: - MessageSnapshot Equatable：任一字段不同时应不相等

    /// id 不同时应不相等
    func testMessageSnapshotNotEqualWhenIdDiffers() {
        let s1 = makeSnapshot(id: UUID())
        let s2 = makeSnapshot(id: UUID())
        XCTAssertNotEqual(s1, s2, "id 不同时应不相等")
    }

    /// role 不同时应不相等
    func testMessageSnapshotNotEqualWhenRoleDiffers() {
        let id = UUID()
        let s1 = makeSnapshot(id: id, role: "user")
        let s2 = makeSnapshot(id: id, role: "assistant")
        XCTAssertNotEqual(s1, s2, "role 不同时应不相等")
    }

    /// content 不同时应不相等
    func testMessageSnapshotNotEqualWhenContentDiffers() {
        let id = UUID()
        let s1 = makeSnapshot(id: id, content: "a")
        let s2 = makeSnapshot(id: id, content: "b")
        XCTAssertNotEqual(s1, s2, "content 不同时应不相等")
    }

    /// imageData 不同时应不相等
    func testMessageSnapshotNotEqualWhenImageDataDiffers() {
        let id = UUID()
        let s1 = MessageSnapshot(id: id, role: "user", content: "x",
                                 imageData: Data([1]), isStreaming: false, attachedImage: nil)
        let s2 = MessageSnapshot(id: id, role: "user", content: "x",
                                 imageData: Data([2]), isStreaming: false, attachedImage: nil)
        XCTAssertNotEqual(s1, s2, "imageData 不同时应不相等")
    }

    /// isStreaming 不同时应不相等
    func testMessageSnapshotNotEqualWhenIsStreamingDiffers() {
        let id = UUID()
        let s1 = makeSnapshot(id: id, isStreaming: false)
        let s2 = makeSnapshot(id: id, isStreaming: true)
        XCTAssertNotEqual(s1, s2, "isStreaming 不同时应不相等")
    }

    /// attachedImage 不同时应不相等
    func testMessageSnapshotNotEqualWhenAttachedImageDiffers() {
        let id = UUID()
        let s1 = MessageSnapshot(id: id, role: "user", content: "x",
                                 imageData: nil, isStreaming: false, attachedImage: Data([1]))
        let s2 = MessageSnapshot(id: id, role: "user", content: "x",
                                 imageData: nil, isStreaming: false, attachedImage: Data([2]))
        XCTAssertNotEqual(s1, s2, "attachedImage 不同时应不相等")
    }

    /// imageData nil 与非 nil 应不相等
    func testMessageSnapshotNotEqualWhenImageDataNilVsNonNil() {
        let id = UUID()
        let s1 = makeSnapshot(id: id, imageData: nil)
        let s2 = MessageSnapshot(id: id, role: "user", content: "x",
                                 imageData: Data([1]), isStreaming: false, attachedImage: nil)
        XCTAssertNotEqual(s1, s2, "imageData nil 与非 nil 应不相等")
    }

    /// attachedImage nil 与非 nil 应不相等
    func testMessageSnapshotNotEqualWhenAttachedImageNilVsNonNil() {
        let id = UUID()
        let s1 = makeSnapshot(id: id, attachedImage: nil)
        let s2 = MessageSnapshot(id: id, role: "user", content: "x",
                                 imageData: nil, isStreaming: false, attachedImage: Data([1]))
        XCTAssertNotEqual(s1, s2, "attachedImage nil 与非 nil 应不相等")
    }

    // MARK: - MessageSnapshot Identifiable

    /// Identifiable.id 应返回构造时传入的 id
    func testMessageSnapshotIdentifiableUsesGivenId() {
        let id = UUID()
        let snapshot = makeSnapshot(id: id)
        XCTAssertEqual(snapshot.id, id, "Identifiable.id 应与构造时传入的 id 一致")
    }

    // MARK: - ToolbarItemPlacement 跨平台扩展

    /// topBarTrailingCompat 可正常访问，不崩溃
    func testTopBarTrailingCompatAccessible() {
        _ = ToolbarItemPlacement.topBarTrailingCompat
    }

    /// topBarLeadingCompat 可正常访问，不崩溃
    func testTopBarLeadingCompatAccessible() {
        _ = ToolbarItemPlacement.topBarLeadingCompat
    }

    // MARK: - MessageBubble View 构造

    /// 使用默认参数构造 MessageBubble，message 字段正确保留
    func testMessageBubbleConstructionWithDefaults() {
        let snapshot = makeSnapshot(role: "user", content: "你好")
        let bubble = MessageBubble(message: snapshot)
        XCTAssertEqual(bubble.message.role, "user")
        XCTAssertEqual(bubble.message.content, "你好")
        XCTAssertFalse(bubble.isSpeaking, "默认 isSpeaking 应为 false")
        XCTAssertNil(bubble.feedbackState, "默认 feedbackState 应为 nil")
    }

    /// 使用全部参数构造 MessageBubble，字段正确保留
    func testMessageBubbleConstructionWithAllParameters() {
        let snapshot = makeSnapshot(role: "assistant", content: "回复内容")
        var speakCalled = false
        var feedbackValue: Bool?

        let bubble = MessageBubble(
            message: snapshot,
            isSpeaking: true,
            onToggleSpeak: { speakCalled = true },
            feedbackState: true,
            onFeedback: { feedbackValue = $0 },
            onCopy: {},
            onResend: {}
        )
        XCTAssertTrue(bubble.isSpeaking, "isSpeaking 应为 true")
        XCTAssertEqual(bubble.feedbackState, true, "feedbackState 应为 true")
        XCTAssertEqual(bubble.message.role, "assistant")

        // 验证传入的回调可被正常调用
        bubble.onToggleSpeak()
        XCTAssertTrue(speakCalled, "onToggleSpeak 回调应被触发")

        bubble.onFeedback(false)
        XCTAssertEqual(feedbackValue, false, "onFeedback 回调应传入正确的值")
    }

    /// 各种角色的 MessageBubble 均可正常构造
    func testMessageBubbleConstructionWithVariousRoles() {
        for role in ["user", "assistant", "system", "tool"] {
            let snapshot = makeSnapshot(role: role)
            let bubble = MessageBubble(message: snapshot)
            XCTAssertEqual(bubble.message.role, role, "角色 \(role) 的 Bubble 应正确构造")
        }
    }

    /// 流式消息和非流式消息均可正常构造
    func testMessageBubbleConstructionWithStreamingStates() {
        let streamingSnapshot = makeSnapshot(role: "assistant", isStreaming: true)
        let bubble1 = MessageBubble(message: streamingSnapshot)
        XCTAssertTrue(bubble1.message.isStreaming)

        let completedSnapshot = makeSnapshot(role: "assistant", isStreaming: false)
        let bubble2 = MessageBubble(message: completedSnapshot)
        XCTAssertFalse(bubble2.message.isStreaming)
    }

    // MARK: - iOS 专属：RoundedCornerShape

    #if os(iOS)
    /// RoundedCornerShape（仅 iOS）可正常构造
    func testRoundedCornerShapeConstruction() {
        let shape = RoundedCornerShape(radius: 12, corners: .allCorners)
        _ = shape
    }

    /// RoundedCornerShape path 在不同 rect 下均可生成
    func testRoundedCornerShapePathGeneration() {
        let shape = RoundedCornerShape(radius: 8, corners: [.topLeft, .topRight])
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty, "在有效 rect 内 path 不应为空")
    }
    #endif

    // MARK: - BlinkingCursor

    /// BlinkingCursor 可正常构造
    func testBlinkingCursorConstruction() {
        let cursor = BlinkingCursor()
        _ = cursor
    }

    // MARK: - Helpers

    /// 创建 MessageSnapshot 测试辅助方法
    private func makeSnapshot(
        id: UUID = UUID(),
        role: String = "user",
        content: String = "test",
        imageData: Data? = nil,
        isStreaming: Bool = false,
        attachedImage: Data? = nil
    ) -> MessageSnapshot {
        MessageSnapshot(
            id: id,
            role: role,
            content: content,
            imageData: imageData,
            isStreaming: isStreaming,
            attachedImage: attachedImage
        )
    }
}
