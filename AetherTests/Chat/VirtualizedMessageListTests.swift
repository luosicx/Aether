import XCTest
import SwiftUI
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

final class VirtualizedMessageListTests: XCTestCase {

    // MARK: - 辅助方法

    /// 构造一个用于测试的 MessageSnapshot
    private func makeSnapshot(
        id: UUID = UUID(),
        role: String = "user",
        content: String = "hello",
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

    // MARK: - MessageSnapshot.Hashable 语义测试

    /// 同 id 不同内容：哈希值应相同（仅用 id 哈希）
    func testHashableSameIDDifferentContentHasEqualHash() {
        let id = UUID()
        let snapshotA = makeSnapshot(id: id, content: "first")
        let snapshotB = makeSnapshot(id: id, content: "second")
        // MessageSnapshot.hash(into:) 仅 combine id，故同 id 哈希值一致
        let hasherA = Hasher()
        let hasherB = Hasher()
        snapshotA.hash(into: hasherA)
        snapshotB.hash(into: hasherB)
        XCTAssertEqual(hasherA.finalize(), hasherB.finalize())
    }

    /// 同 id 不同内容：相等性应为 false（合成 Equatable 全字段比较）
    func testHashableSameIDDifferentContentNotEqual() {
        let id = UUID()
        let snapshotA = makeSnapshot(id: id, content: "first")
        let snapshotB = makeSnapshot(id: id, content: "second")
        // 合成 Equatable 比较全部字段，content 不同故不相等
        XCTAssertNotEqual(snapshotA, snapshotB)
    }

    /// 不同 id 相同内容：哈希值应不同
    func testHashableDifferentIDSameContentHasDifferentHash() {
        let snapshotA = makeSnapshot(id: UUID(), content: "same")
        let snapshotB = makeSnapshot(id: UUID(), content: "same")
        let hasherA = Hasher()
        let hasherB = Hasher()
        snapshotA.hash(into: hasherA)
        snapshotB.hash(into: hasherB)
        // id 不同，哈希值（极大概率）不同
        XCTAssertNotEqual(hasherA.finalize(), hasherB.finalize())
    }

    /// 不同 id 相同内容：相等性应为 false
    func testHashableDifferentIDSameContentNotEqual() {
        let snapshotA = makeSnapshot(id: UUID(), content: "same")
        let snapshotB = makeSnapshot(id: UUID(), content: "same")
        // id 不同故不相等
        XCTAssertNotEqual(snapshotA, snapshotB)
    }

    /// 同 id 同内容：哈希值与相等性都为 true
    func testHashableSameIDSameContentHashAndEqualBothTrue() {
        let id = UUID()
        let snapshotA = makeSnapshot(id: id, content: "identical")
        let snapshotB = makeSnapshot(id: id, content: "identical")
        // 哈希相等
        XCTAssertEqual(snapshotA.hashValue, snapshotB.hashValue)
        // 相等性也成立（全字段相同）
        XCTAssertEqual(snapshotA, snapshotB)
    }

    /// 验证 MessageSnapshot 可放入 Set（Hashable 协议）
    func testMessageSnapshotCanBeStoredInSet() {
        let id = UUID()
        let snapshotA = makeSnapshot(id: id, content: "a")
        let snapshotB = makeSnapshot(id: id, content: "b")
        let snapshotC = makeSnapshot(id: UUID(), content: "c")
        // 同 id 但内容不同的快照：哈希相同但 == 为 false，Set 会保留两者
        let set: Set<MessageSnapshot> = [snapshotA, snapshotB, snapshotC]
        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(snapshotA))
        XCTAssertTrue(set.contains(snapshotB))
        XCTAssertTrue(set.contains(snapshotC))
    }

    /// 验证 MessageSnapshot 可作为 Dictionary key
    func testMessageSnapshotCanBeUsedAsDictionaryKey() {
        let snapshot = makeSnapshot(content: "value")
        var dict: [MessageSnapshot: String] = [:]
        dict[snapshot] = "payload"
        // 能存入并取出
        XCTAssertEqual(dict[snapshot], "payload")
    }

    // MARK: - VirtualizedMessageList 初始化测试

    /// 创建实例不崩溃（传入空消息数组）
    func testInitWithEmptyMessagesDoesNotCrash() {
        let list = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [],
            autoScrollTrigger: nil,
            contentRefreshTrigger: nil,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        XCTAssertEqual(list.messages.count, 0)
        XCTAssertNil(list.autoScrollTrigger)
        XCTAssertNil(list.contentRefreshTrigger)
        // scrollAnimated 默认值为 true
        XCTAssertTrue(list.scrollAnimated)
    }

    /// 创建实例不崩溃（传入单条消息）
    func testInitWithSingleMessageDoesNotCrash() {
        let snapshot = makeSnapshot(content: "single")
        let list = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [snapshot],
            autoScrollTrigger: nil,
            contentRefreshTrigger: nil,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        XCTAssertEqual(list.messages.count, 1)
        XCTAssertEqual(list.messages.first, snapshot)
    }

    /// 创建实例不崩溃（传入多条消息）
    func testInitWithMultipleMessagesDoesNotCrash() {
        let snapshots = (0..<10).map { index in
            makeSnapshot(content: "msg-\(index)")
        }
        let list = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: snapshots,
            autoScrollTrigger: nil,
            contentRefreshTrigger: nil,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        XCTAssertEqual(list.messages.count, 10)
        XCTAssertEqual(list.messages, snapshots)
    }

    /// 不同 autoScrollTrigger 值的实例创建
    func testInitWithDifferentAutoScrollTriggers() {
        let triggerA: AnyHashable? = 1
        let triggerB: AnyHashable? = "scroll"
        let listA = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [],
            autoScrollTrigger: triggerA,
            contentRefreshTrigger: nil,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        let listB = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [],
            autoScrollTrigger: triggerB,
            contentRefreshTrigger: nil,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        XCTAssertEqual(listA.autoScrollTrigger, triggerA)
        XCTAssertEqual(listB.autoScrollTrigger, triggerB)
        XCTAssertNotEqual(listA.autoScrollTrigger, listB.autoScrollTrigger)
    }

    /// 不同 scrollAnimated 值的实例创建
    func testInitWithDifferentScrollAnimatedValues() {
        let listAnimated = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [],
            autoScrollTrigger: nil,
            contentRefreshTrigger: nil,
            scrollAnimated: true,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        let listNotAnimated = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [],
            autoScrollTrigger: nil,
            contentRefreshTrigger: nil,
            scrollAnimated: false,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        XCTAssertTrue(listAnimated.scrollAnimated)
        XCTAssertFalse(listNotAnimated.scrollAnimated)
    }

    // MARK: - iOS 专属测试

    #if os(iOS)
    /// iOS 专属：间接验证 _ListItem 枚举的 Hashable 语义
    /// 注意：_ListItem 是 private，无法直接访问，通过创建 iOS 列表实例间接验证
    /// 其 Hashable 约束满足编译（_IOSVirtualizedList 内部使用 _ListItem 作为 diffable 项）
    func testIOSListItemHashableIndirectly() {
        // 创建多条消息，触发 _IOSVirtualizedList 内部 _ListItem.message 的构造
        let snapshots = (0..<3).map { index in
            makeSnapshot(content: "ios-msg-\(index)")
        }
        let list = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: snapshots,
            autoScrollTrigger: "trigger",
            contentRefreshTrigger: nil,
            scrollAnimated: false,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        // 验证实例创建成功，间接确认 _ListItem 的 Hashable 约束满足编译
        XCTAssertEqual(list.messages.count, 3)
        XCTAssertNotNil(list.autoScrollTrigger)
    }

    /// iOS 专属：验证不同 contentRefreshTrigger 值的实例创建
    func testIOSInitWithContentRefreshTrigger() {
        let refresh: AnyHashable? = "refresh-token"
        let list = VirtualizedMessageList<MessageSnapshot, EmptyView, EmptyView>(
            messages: [],
            autoScrollTrigger: nil,
            contentRefreshTrigger: refresh,
            content: { _ in EmptyView() },
            footer: { EmptyView() }
        )
        XCTAssertEqual(list.contentRefreshTrigger, refresh)
    }
    #endif
}
