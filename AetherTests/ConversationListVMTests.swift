import XCTest
import SwiftData
@testable import Aether

/// ConversationListVM 单元测试
@MainActor
final class ConversationListVMTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var vm: ConversationListVM!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
        vm = ConversationListVM()
        vm.load(modelContext: context)  // 必须先 load 才会初始化 storage
    }

    override func tearDownWithError() throws {
        vm = nil
        context = nil
        container = nil
    }

    /// createConversation 默认标题应为「新对话」
    func testLoadAndCreateConversation() {
        let conv = vm.createConversation()
        XCTAssertEqual(conv?.title, "新对话", "createConversation 默认标题应为「新对话」")
        XCTAssertEqual(vm.conversations.count, 1, "vm.conversations 应包含新建会话")
        XCTAssertEqual(vm.conversations.first?.title, "新对话")
    }

    /// 创建 2 条会话，togglePin 第二条后排序变化（置顶在前）
    func testTogglePinChangesSortOrder() {
        // A：createdAt 旧；B：createdAt 新
        let a = vm.createConversation(title: "A")!
        a.createdAt = Date(timeIntervalSince1970: 1000)
        let b = vm.createConversation(title: "B")!
        b.createdAt = Date(timeIntervalSince1970: 2000)

        // 重新 load 让排序按 createdAt 降序生效
        // 跳过 cleanup，避免测试中无消息的会话被清理导致断言失败
        vm.load(modelContext: context, cleanupEmpty: false)
        XCTAssertEqual(vm.conversations.map(\.title), ["B", "A"],
                       "初始应按 createdAt 降序：B 在前")

        // 置顶 A（旧的那条）后，A 应排到前面
        vm.togglePin(a)
        XCTAssertEqual(vm.conversations.map(\.title), ["A", "B"],
                       "置顶 A 后 A 应排到前面")
        XCTAssertTrue(vm.conversations.first?.isPinned ?? false,
                      "置顶后 isPinned 应为 true")
    }

    /// 首条用户消息长度 30 → 标题 prefix(20) + 「…」
    func testAutoTitleIfNeededLongTitle() {
        let conv = vm.createConversation()!
        let longContent = String(repeating: "a", count: 30)
        let msg = ChatMessage(role: "user", content: longContent)
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        let expectedPrefix = String(repeating: "a", count: 20)
        XCTAssertEqual(conv.title, expectedPrefix + "…",
                       "长度 30 应截断为 prefix(20) + 「…」")
    }

    /// 首条用户消息长度 15 → 标题不加「…」
    func testAutoTitleIfNeededShortTitle() {
        let conv = vm.createConversation()!
        let shortContent = String(repeating: "b", count: 15)
        let msg = ChatMessage(role: "user", content: shortContent)
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, String(repeating: "b", count: 15),
                       "长度 15 等于 prefix(20) 的实际长度，不应加「…」")
    }

    /// 标题已是「新对话」之外时不应被覆盖
    func testAutoTitleIfNeededDoesNotOverwriteExistingTitle() {
        let conv = vm.createConversation(title: "已有标题")!
        let msg = ChatMessage(role: "user", content: "some content that should not become title")
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, "已有标题",
                       "标题非「新对话」时 autoTitleIfNeeded 不应覆盖")
    }

    // MARK: - deleteConversation

    /// deleteConversation 应从 conversations 列表移除指定会话
    func testDeleteConversationRemovesFromList() {
        let conv1 = vm.createConversation(title: "会话1")!
        let conv2 = vm.createConversation(title: "会话2")!
        XCTAssertEqual(vm.conversations.count, 2)

        vm.deleteConversation(conv1)

        XCTAssertEqual(vm.conversations.count, 1, "删除后应剩 1 个会话")
        XCTAssertEqual(vm.conversations.first?.id, conv2.id, "剩余应为会话2")
        XCTAssertFalse(vm.conversations.contains { $0.id == conv1.id }, "被删除的会话不应在列表中")
    }

    /// deleteConversation 删除最后一个会话后列表应为空
    func testDeleteLastConversationResultsInEmptyList() {
        let conv = vm.createConversation(title: "唯一会话")!
        XCTAssertEqual(vm.conversations.count, 1)

        vm.deleteConversation(conv)

        XCTAssertEqual(vm.conversations.count, 0, "删除最后一个会话后列表应为空")
    }

    // MARK: - deleteConversations 批量删除

    /// deleteConversations 批量删除多个会话
    func testDeleteConversationsBatchRemovesAll() {
        let conv1 = vm.createConversation(title: "A")!
        let conv2 = vm.createConversation(title: "B")!
        let conv3 = vm.createConversation(title: "C")!
        XCTAssertEqual(vm.conversations.count, 3)

        vm.deleteConversations([conv1, conv3])

        XCTAssertEqual(vm.conversations.count, 1, "批量删除后应剩 1 个会话")
        XCTAssertEqual(vm.conversations.first?.id, conv2.id, "剩余应为 B")
    }

    /// deleteConversations 传空数组应为 no-op
    func testDeleteConversationsEmptyArrayIsNoOp() {
        _ = vm.createConversation(title: "A")!
        _ = vm.createConversation(title: "B")!
        XCTAssertEqual(vm.conversations.count, 2)

        vm.deleteConversations([])

        XCTAssertEqual(vm.conversations.count, 2, "传空数组删除应为 no-op")
    }

    /// deleteConversations 删除全部会话后列表应为空
    func testDeleteConversationsAllResultsInEmptyList() {
        let conv1 = vm.createConversation(title: "A")!
        let conv2 = vm.createConversation(title: "B")!

        vm.deleteConversations([conv1, conv2])

        XCTAssertEqual(vm.conversations.count, 0, "删除全部后列表应为空")
    }

    // MARK: - renameConversation

    /// renameConversation 应更新会话标题
    func testRenameConversationUpdatesTitle() {
        let conv = vm.createConversation(title: "旧标题")!

        vm.renameConversation(conv, to: "新标题")

        XCTAssertEqual(conv.title, "新标题", "renameConversation 应更新标题")
    }

    /// renameConversation 重命名为空字符串应生效（不阻止空标题）
    func testRenameConversationToEmptyString() {
        let conv = vm.createConversation(title: "有标题")!

        vm.renameConversation(conv, to: "")

        XCTAssertEqual(conv.title, "", "重命名为空字符串应生效")
    }

    // MARK: - createConversation 自定义参数

    /// createConversation 自定义标题与系统提示词应正确设置
    func testCreateConversationWithCustomTitleAndSystemPrompt() {
        let conv = vm.createConversation(title: "自定义标题", systemPrompt: "自定义系统提示")

        XCTAssertEqual(conv?.title, "自定义标题", "标题应为自定义值")
        XCTAssertEqual(conv?.systemPrompt, "自定义系统提示", "systemPrompt 应为自定义值")
        XCTAssertEqual(vm.conversations.first?.title, "自定义标题", "列表首项应为自定义标题会话")
    }

    /// createConversation 新建的会话应插入到列表头部（index 0）
    func testCreateConversationInsertsAtHead() {
        _ = vm.createConversation(title: "第一个")!
        let second = vm.createConversation(title: "第二个")!

        XCTAssertEqual(vm.conversations.first?.id, second.id, "新建会话应插入到列表头部")
    }

    // MARK: - autoTitleIfNeeded 边界情况

    /// autoTitleIfNeeded 无用户消息时应保持原标题
    func testAutoTitleIfNeededNoUserMessages() {
        let conv = vm.createConversation()!
        // 不添加任何消息

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, "新对话", "无用户消息时标题应保持「新对话」")
    }

    /// autoTitleIfNeeded 仅含 assistant 消息时应保持原标题
    func testAutoTitleIfNeededWithAssistantMessageOnly() {
        let conv = vm.createConversation()!
        let msg = ChatMessage(role: "assistant", content: "AI 回复内容")
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, "新对话", "仅含 assistant 消息时标题应保持「新对话」")
    }

    /// autoTitleIfNeeded 用户消息内容为空时应保持原标题
    func testAutoTitleIfNeededEmptyUserMessage() {
        let conv = vm.createConversation()!
        let msg = ChatMessage(role: "user", content: "")
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, "新对话", "用户消息内容为空时标题应保持「新对话」")
    }

    /// autoTitleIfNeeded 用户消息恰好 20 字符时不应加「…」
    func testAutoTitleIfNeededExactly20Chars() {
        let conv = vm.createConversation()!
        let content20 = String(repeating: "c", count: 20)
        let msg = ChatMessage(role: "user", content: content20)
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, content20, "恰好 20 字符时不应加「…」")
        XCTAssertFalse(conv.title.contains("…"), "恰好 20 字符时标题不应含「…」")
    }

    /// autoTitleIfNeeded 用户消息 21 字符时应加「…」（边界值）
    func testAutoTitleIfNeeded21CharsHasEllipsis() {
        let conv = vm.createConversation()!
        let content21 = String(repeating: "d", count: 21)
        let msg = ChatMessage(role: "user", content: content21)
        msg.conversation = conv
        conv.messages.append(msg)

        vm.autoTitleIfNeeded(for: conv)

        let expected = String(repeating: "d", count: 20) + "…"
        XCTAssertEqual(conv.title, expected, "21 字符应截断为 prefix(20) + 「…」")
    }

    /// autoTitleIfNeeded 应取首条 user 消息（跳过 assistant 消息）
    func testAutoTitleIfNeededTakesFirstUserMessage() {
        let conv = vm.createConversation()!
        let assistantMsg = ChatMessage(role: "assistant", content: "AI 先说话")
        assistantMsg.conversation = conv
        conv.messages.append(assistantMsg)
        let userMsg = ChatMessage(role: "user", content: "用户后说话的较长内容")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        vm.autoTitleIfNeeded(for: conv)

        XCTAssertEqual(conv.title, "用户后说话的较长内容", "应取首条 user 消息作为标题")
    }

    // MARK: - togglePin

    /// togglePin 再次翻转应取消置顶
    func testTogglePinOff() {
        let conv = vm.createConversation(title: "测试")!

        // 置顶
        vm.togglePin(conv)
        XCTAssertTrue(conv.isPinned, "首次 togglePin 应置顶")

        // 取消置顶
        vm.togglePin(conv)
        XCTAssertFalse(conv.isPinned, "再次 togglePin 应取消置顶")
    }

    // MARK: - load cleanupEmpty

    /// load 默认 cleanupEmpty=true 应清理无消息的空对话
    func testLoadCleanupEmptyRemovesEmptyConversations() {
        let conv1 = vm.createConversation(title: "有消息")!
        let msg = ChatMessage(role: "user", content: "hello")
        msg.conversation = conv1
        conv1.messages.append(msg)
        try? context.save()

        let conv2 = vm.createConversation(title: "空对话")!
        // conv2 无消息
        try? context.save()

        // 重新 load（默认 cleanupEmpty=true），空对话应被清理
        vm.load(modelContext: context)

        XCTAssertEqual(vm.conversations.count, 1, "空对话应被清理，只剩 1 个有消息的会话")
        XCTAssertEqual(vm.conversations.first?.title, "有消息", "剩余应为有消息的会话")
        XCTAssertFalse(vm.conversations.contains { $0.id == conv2.id }, "空对话不应在列表中")
    }

    /// load cleanupEmpty=false 时空对话应保留
    func testLoadWithoutCleanupKeepsEmptyConversations() {
        _ = vm.createConversation(title: "空对话")!
        try? context.save()

        // load 跳过 cleanup
        vm.load(modelContext: context, cleanupEmpty: false)

        XCTAssertEqual(vm.conversations.count, 1, "cleanupEmpty=false 时空对话应保留")
        XCTAssertEqual(vm.conversations.first?.title, "空对话")
    }

    // MARK: - storage 未初始化时的行为

    /// 未调用 load 前调用 createConversation 应返回 nil（storage 为 nil）
    func testCreateConversationReturnsNilBeforeLoad() {
        let newVM = ConversationListVM()
        // 不调用 load，storage 为 nil

        let conv = newVM.createConversation(title: "测试")

        XCTAssertNil(conv, "未 load 前 createConversation 应返回 nil")
        XCTAssertTrue(newVM.conversations.isEmpty, "未 load 前 conversations 应为空")
    }

    /// 未调用 load 前调用 deleteConversation 应为 no-op（不崩溃）
    func testDeleteConversationBeforeLoadIsNoOp() {
        let newVM = ConversationListVM()
        // 构造一个不在 storage 中的 Conversation
        let conv = Conversation(title: "测试", systemPrompt: "test")

        // 不应崩溃
        newVM.deleteConversation(conv)

        XCTAssertTrue(newVM.conversations.isEmpty, "未 load 前 conversations 应保持空")
    }

    /// 未调用 load 前调用 renameConversation 应为 no-op（不崩溃，标题不被 storage 修改）
    func testRenameConversationBeforeLoadIsNoOp() {
        let newVM = ConversationListVM()
        let conv = Conversation(title: "原标题", systemPrompt: "test")

        newVM.renameConversation(conv, to: "新标题")

        // storage 为 nil，storage?.renameConversation 被跳过，title 未被修改
        XCTAssertEqual(conv.title, "原标题", "storage 为 nil 时 title 不应被修改")
    }

    /// 未调用 load 前调用 togglePin 应为 no-op（不崩溃，不更新 conversations）
    func testTogglePinBeforeLoadIsNoOp() {
        let newVM = ConversationListVM()
        let conv = Conversation(title: "测试", systemPrompt: "test")

        newVM.togglePin(conv)

        // storage 为 nil，togglePin 不应崩溃
        // conversations 不会被更新（因为 storage?.fetchConversations() 返回 nil → []）
        XCTAssertTrue(newVM.conversations.isEmpty, "未 load 前 conversations 应保持空")
    }

    // MARK: - load 排序

    /// load 后多个会话应按 createdAt 降序排列
    func testLoadSortsByCreatedAtDescending() {
        let a = vm.createConversation(title: "A")!
        a.createdAt = Date(timeIntervalSince1970: 1000)
        let b = vm.createConversation(title: "B")!
        b.createdAt = Date(timeIntervalSince1970: 3000)
        let c = vm.createConversation(title: "C")!
        c.createdAt = Date(timeIntervalSince1970: 2000)

        vm.load(modelContext: context, cleanupEmpty: false)

        XCTAssertEqual(vm.conversations.map(\.title), ["B", "C", "A"],
                       "应按 createdAt 降序：B(3000) → C(2000) → A(1000)")
    }

    /// 多个置顶会话应按 createdAt 降序排列在同组内
    func testLoadMultiplePinnedSortsByCreatedAtDescending() {
        let a = vm.createConversation(title: "A")!
        a.createdAt = Date(timeIntervalSince1970: 1000)
        a.isPinned = true
        let b = vm.createConversation(title: "B")!
        b.createdAt = Date(timeIntervalSince1970: 2000)
        b.isPinned = true

        vm.load(modelContext: context, cleanupEmpty: false)

        // 两个都置顶，应按 createdAt 降序：B 在前
        XCTAssertEqual(vm.conversations.map(\.title), ["B", "A"],
                       "置顶会话之间应按 createdAt 降序排列")
        XCTAssertTrue(vm.conversations.allSatisfy { $0.isPinned }, "所有会话应均置顶")
    }

    // MARK: - Day 23: reorder 拖拽排序

    /// reorder 应将指定会话从源位置移动到目标位置
    func testReorderMovesConversation() {
        _ = vm.createConversation(title: "A")!
        _ = vm.createConversation(title: "B")!
        _ = vm.createConversation(title: "C")!
        vm.load(modelContext: context, cleanupEmpty: false)
        // 初始顺序：C, B, A（按 createdAt 降序）
        XCTAssertEqual(vm.conversations.map(\.title), ["C", "B", "A"])

        // 将 C（index 0）移到末尾（toOffset 3 = 末尾）
        vm.reorder(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(vm.conversations.map(\.title), ["B", "A", "C"],
                       "reorder 后 C 应移到末尾")
    }

    /// reorder 后重新 load 应保持新顺序（order 持久化）
    func testReorderPersistsAfterReload() {
        _ = vm.createConversation(title: "A")!
        _ = vm.createConversation(title: "B")!
        _ = vm.createConversation(title: "C")!
        vm.load(modelContext: context, cleanupEmpty: false)
        XCTAssertEqual(vm.conversations.map(\.title), ["C", "B", "A"])

        // 将 C 移到末尾
        vm.reorder(from: IndexSet(integer: 0), to: 3)

        // 重新 load 验证 order 持久化
        vm.load(modelContext: context, cleanupEmpty: false)
        XCTAssertEqual(vm.conversations.map(\.title), ["B", "A", "C"],
                       "reorder 后重新 load 应保持新顺序")
    }

    /// reorder 中间移动：将 A（index 2）移到 index 0（头部）
    func testReorderMoveToHead() {
        _ = vm.createConversation(title: "A")!
        _ = vm.createConversation(title: "B")!
        _ = vm.createConversation(title: "C")!
        vm.load(modelContext: context, cleanupEmpty: false)
        XCTAssertEqual(vm.conversations.map(\.title), ["C", "B", "A"])

        // 将 A（index 2）移到头部（toOffset 0）
        vm.reorder(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(vm.conversations.map(\.title), ["A", "C", "B"],
                       "reorder 后 A 应移到头部")
    }
}
