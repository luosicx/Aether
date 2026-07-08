# Day 2 实施计划：多轮对话与上下文记忆

> **For agentic workers:** 本计划按 Task 顺序执行，每个 Task 完成后构建一次确认无编译错误。步骤使用 `- [ ]` 复选框跟踪。

**目标：** 让多轮对话+上下文记忆端到端跑通——发消息立即落库 → 切换会话不串数据 → 编辑 system prompt 立即影响当前对话 → 会话列表可新建/切换/删除/重命名。

**架构：** `ChatView (SwiftUI) → ChatViewModel (@Observable) → ChatStorage (SwiftData) + Conversation/ChatMessage (@Model)`。systemPrompt 与 Conversation 强绑定（非全局），切换会话时清理 ViewModel 状态防止串数据。

**技术栈：** SwiftUI / @Observable / SwiftData / @Bindable / @Model

---

## 现状盘点

项目在 Day 1 已修复 SSE 流式 + 布局。Day 2 的三大目标骨架已存在，但有多个致命 bug 需修复。

### Bug 1：Settings 中的 systemPrompt 与 Conversation 脱节
[SettingsView.swift:23-26](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Settings/SettingsView.swift) 编辑 `settingsVM.systemPrompt`，但 [SettingsViewModel.swift:8](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/SettingsViewModel.swift) 的 systemPrompt 是 VM 内局部状态，**完全不会回写到当前 Conversation.systemPrompt**。结果：用户改了 system prompt，下次发消息仍用旧值（来自 Conversation）。Conversation.systemPrompt 是发送时真正使用的来源（[ChatViewModel.swift:52-54](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift)）。

### Bug 2：切换会话时 ViewModel 状态未清理
[ChatView.swift:39-43](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) onSelect 回调只做 `viewModel.messages = conv.messages`，但 `streamingText`、`isLoading`、`currentToolSteps` 都没清理。如果切换时正在流式输出，旧 Task 会继续把 token 写到 `streamingText`，且 `sendMessage` 内的 `Task` 仍持有旧 `conversation` 引用——结果数据错乱。

### Bug 3：用户消息持久化时机过晚
[ChatViewModel.swift:36-47](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift) `sendMessage` append 用户消息后没 `modelContext.save()`，只在 `processMessage` 最末尾 `try? modelContext.save()`（[第 130 行](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift)）。如果流式中途 App 崩溃，用户消息可能丢失（SwiftData 上下文未保存）。

### Bug 4：会话列表无重命名 UI、无消息预览
[ConversationListVM.swift:28-30](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ConversationListVM.swift) 有 `renameConversation` 方法但 UI 没暴露。[ConversationRow.swift:10-16](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Conversation/ConversationRow.swift) 只显示标题和创建时间，不显示最后一条消息预览，体验差。新建对话默认标题 "新对话"，无法识别。

### Bug 5：新建对话不应用 Settings 中的 systemPrompt
[ChatView.swift:59](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) `conversationListVM.createConversation()` 用默认参数，新建的对话 systemPrompt 永远是 "你是一个有帮助的AI助手。"，即使用户在 Settings 里改过。

### Bug 6：ChatViewModel 内部残留无用的 currentConversation
[ChatViewModel.swift:20](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift) 有 `private var currentConversation: Conversation?` 但从未赋值、从未读取，是死代码。

---

## 文件结构

| 文件 | 责任 | 操作 |
|------|------|------|
| `AIBuilder/ViewModels/ChatViewModel.swift` | 流式发送 + 状态管理 | 修改 |
| `AIBuilder/ViewModels/SettingsViewModel.swift` | 全局 Settings 状态 | 修改 |
| `AIBuilder/ViewModels/ConversationListVM.swift` | 会话列表增删改查 | 修改 |
| `AIBuilder/Views/Chat/ChatView.swift` | 主聊天界面 | 修改 |
| `AIBuilder/Views/Settings/SettingsView.swift` | 设置面板 | 修改 |
| `AIBuilder/Views/Conversation/ConversationList.swift` | 会话列表 UI | 修改 |
| `AIBuilder/Views/Conversation/ConversationRow.swift` | 会话列表项 | 修改 |
| `AIBuilder/Services/Storage/ChatStorage.swift` | SwiftData 持久化层 | 修改 |

---

## Task 1：修复 ChatViewModel 状态管理 + 立即持久化用户消息

**目标：** 切换会话时彻底清理 streamingText / isLoading / currentToolSteps；用户消息 append 后立即 save；删除死代码。

**Files:**
- Modify: `AIBuilder/ViewModels/ChatViewModel.swift`

- [ ] **Step 1：替换 ChatViewModel.swift 整体内容**

用以下内容替换 [ChatViewModel.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift) 全文（保留 Day 1 的 SSE 修复与 systemPrompt 注入逻辑，仅做以下改动：删除 `private var currentConversation` 死代码；`sendMessage` 内 append 用户消息后立即 `try? modelContext.save()`；新增 `switchTo(conversation:)` 方法清理状态）：

```swift
import Foundation
import SwiftData

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false
    var streamingText = ""
    var errorMessage: String?
    var currentToolSteps: [ToolStep] = []
    var ragEnabled = false        // Day 3 启用
    var toolsEnabled = false      // Day 4 启用
    var tokenLimit = 4000

    private let client = DeepSeekClient()
    private let ragService = RAGService()
    private let cache = SemanticCache()
    private var streamingTask: Task<Void, Never>?
    private let maxReActLoops = 5

    struct ToolStep: Identifiable {
        let id = UUID()
        let toolName: String
        var status: ToolStepStatus
        var result: String?
    }

    enum ToolStepStatus {
        case running, completed, failed
    }

    /// 切换到指定会话：清理流式状态、加载该会话消息
    func switchTo(conversation: Conversation) {
        streamingTask?.cancel()
        streamingTask = nil
        streamingText = ""
        isLoading = false
        currentToolSteps = []
        errorMessage = nil
        inputText = ""
        messages = conversation.messages
    }

    func sendMessage(in conversation: Conversation, modelContext: ModelContext) {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userMessage = ChatMessage(role: "user", content: inputText)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        messages.append(userMessage)
        let userInput = inputText
        inputText = ""
        isLoading = true
        streamingText = ""
        currentToolSteps = []
        // 立即持久化用户消息，防止流式中途崩溃丢失
        try? modelContext.save()
        streamingTask = Task {
            await processMessage(userInput, conversation: conversation, modelContext: modelContext)
        }
    }

    private func processMessage(_ text: String, conversation: Conversation, modelContext: ModelContext) async {
        var apiMessages: [APIMessage] = []
        if !conversation.systemPrompt.isEmpty {
            apiMessages.append(APIMessage(role: "system", content: conversation.systemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil))
        }
        apiMessages.append(contentsOf: conversation.messages.map { $0.toAPIMessage() })
        if ragEnabled {
            if let context = try? ragService.buildAugmentedContext(query: text, modelContext: modelContext), !context.isEmpty {
                apiMessages.insert(APIMessage(role: "system", content: context, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil), at: 1)
            }
        }
        apiMessages = limitTokens(apiMessages, max: tokenLimit)
        var loopCount = 0
        var fullResponse = ""
        while loopCount < maxReActLoops {
            loopCount += 1
            let stream: AsyncStream<ParsedChunk>
            if toolsEnabled {
                let tools = ToolRegistry.shared.allToolDefs
                stream = client.chat(messages: apiMessages, config: ChatConfig.default, tools: tools)
            } else {
                let raw = client.chat(messages: apiMessages, config: ChatConfig.default)
                stream = AsyncStream { cont in
                    Task {
                        for await content in raw {
                            cont.yield(ParsedChunk(content: content, toolCalls: nil))
                        }
                        cont.finish()
                    }
                }
            }
            var chunkContent = ""
            var finalToolCalls: [AccumulatedToolCall]?
            for await chunk in stream {
                if Task.isCancelled { return }
                if let content = chunk.content {
                    chunkContent += content
                    streamingText = fullResponse + chunkContent
                }
                if let calls = chunk.toolCalls {
                    finalToolCalls = calls
                }
            }
            fullResponse += chunkContent
            if let toolCalls = finalToolCalls, !toolCalls.isEmpty {
                let assistantMsg = ChatMessage(role: "assistant", content: chunkContent)
                assistantMsg.conversation = conversation
                conversation.messages.append(assistantMsg)
                messages.append(assistantMsg)
                try? modelContext.save()
                var toolResults: [APIMessage] = []
                for tc in toolCalls {
                    let step = ToolStep(toolName: tc.name, status: .running)
                    currentToolSteps.append(step)
                    do {
                        let argsData = tc.arguments.data(using: .utf8) ?? Data()
                        let args = try JSONSerialization.jsonObject(with: argsData) as? [String: Any] ?? [:]
                        let result = try await ToolRegistry.shared.execute(name: tc.name, arguments: args)
                        currentToolSteps[currentToolSteps.count - 1].status = .completed
                        currentToolSteps[currentToolSteps.count - 1].result = result
                        toolResults.append(APIMessage(role: "tool", content: result, images: nil, toolCallId: tc.id, toolName: tc.name, toolCalls: nil))
                        let toolMsg = ChatMessage(role: "tool", content: result, toolCallId: tc.id, toolName: tc.name)
                        toolMsg.conversation = conversation
                        conversation.messages.append(toolMsg)
                        messages.append(toolMsg)
                        try? modelContext.save()
                    } catch {
                        currentToolSteps[currentToolSteps.count - 1].status = .failed
                        currentToolSteps[currentToolSteps.count - 1].result = error.localizedDescription
                    }
                }
                apiMessages = conversation.messages.map { $0.toAPIMessage() }
                continue
            } else {
                break
            }
        }
        let assistantMsg = ChatMessage(role: "assistant", content: fullResponse)
        assistantMsg.conversation = conversation
        conversation.messages.append(assistantMsg)
        messages.append(assistantMsg)
        streamingText = ""
        isLoading = false
        try? modelContext.save()
    }

    private func limitTokens(_ messages: [APIMessage], max: Int) -> [APIMessage] {
        var total = 0
        var result: [APIMessage] = []
        for msg in messages.reversed() {
            let tokens = msg.content.estimatedTokens
            if total + tokens > max { break }
            result.insert(msg, at: 0)
            total += tokens
        }
        return result
    }
}
```

- [ ] **Step 2：构建验证无编译错误**

Run:
```bash
rm -rf /tmp/AIBuilderDD && xcodebuild -project AIBuilder.xcodeproj -scheme AIBuilder -sdk iphonesimulator -destination 'id=4B94324D-BC73-4EB8-9BA5-0DC073DD8B65' -derivedDataPath /tmp/AIBuilderDD build 2>&1 | grep -E "error:|BUILD"
```
Expected: 仅有 `** BUILD SUCCEEDED **`

- [ ] **Step 3：Commit**

```bash
git add AIBuilder/ViewModels/ChatViewModel.swift
git commit -m "day2: 修复 ViewModel 状态管理与持久化时机"
```

---

## Task 2：system prompt 与 Conversation 强绑定

**目标：** Settings 中的 systemPrompt 改为"当前会话人设"的镜像——加载时从当前会话读取，编辑时立即回写到当前会话；新建对话时用 Settings 中的 systemPrompt 作为初始值。

**Files:**
- Modify: `AIBuilder/ViewModels/SettingsViewModel.swift`
- Modify: `AIBuilder/Views/Settings/SettingsView.swift`
- Modify: `AIBuilder/Views/Chat/ChatView.swift`

- [ ] **Step 1：改造 SettingsViewModel，绑定到当前会话**

用以下内容替换 [SettingsViewModel.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/SettingsViewModel.swift) 全文（新增 `currentConversation` 引用 + `loadSystemPrompt(from:)` + `updateSystemPrompt(_:)`，移除内联 systemPrompt 默认值逻辑）：

```swift
import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {
    var apiKey: String = ""
    var selectedModel: String = APIConfig.defaultModel
    var systemPrompt: String = "你是一个有帮助的AI助手。"
    var isSaving = false
    var saveMessage: String?

    /// 默认人设（新建对话时使用，不与具体会话绑定）
    static let defaultSystemPrompt = "你是一个有帮助的AI助手。"

    let availableModels = ["deepseek-v4-flash", "deepseek-v4", "deepseek-v3"]

    init() {
        apiKey = KeychainManager.shared.getAPIKey() ?? ""
    }

    func saveAPIKey() {
        do {
            try KeychainManager.shared.saveAPIKey(apiKey)
            saveMessage = "API Key 已保存"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        KeychainManager.shared.deleteAPIKey()
        apiKey = ""
        saveMessage = "API Key 已删除"
    }

    /// 从指定会话加载 systemPrompt 到本地（用于显示与编辑）
    func loadSystemPrompt(from conversation: Conversation?) {
        if let conv = conversation {
            systemPrompt = conv.systemPrompt
        } else {
            systemPrompt = Self.defaultSystemPrompt
        }
    }

    /// 把当前 systemPrompt 回写到会话并持久化
    func updateSystemPrompt(in conversation: Conversation?, modelContext: ModelContext?) {
        guard let conv = conversation else { return }
        conv.systemPrompt = systemPrompt
        try? modelContext?.save()
    }
}
```

- [ ] **Step 2：改造 SettingsView，dismiss 时回写 systemPrompt**

用以下内容替换 [SettingsView.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Settings/SettingsView.swift) 全文（新增 `conversation` + `modelContext` 参数；"完成"按钮和 systemPrompt 编辑都触发 `updateSystemPrompt`）：

```swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var settingsVM: SettingsViewModel
    let conversation: Conversation?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("API 配置") {
                    SecureField("API Key", text: $settingsVM.apiKey)
                    Button("保存 API Key") { settingsVM.saveAPIKey() }
                    Button("删除 API Key", role: .destructive) { settingsVM.deleteAPIKey() }
                }
                Section("模型选择") {
                    Picker("模型", selection: $settingsVM.selectedModel) {
                        ForEach(settingsVM.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextEditor(text: $settingsVM.systemPrompt)
                        .frame(minHeight: 100)
                } header: {
                    Text("系统提示词（当前会话）")
                } footer: {
                    Text("修改后立即生效于当前会话。新建对话将沿用此值作为初始人设。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let msg = settingsVM.saveMessage {
                    Section {
                        Text(msg).foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        settingsVM.updateSystemPrompt(in: conversation, modelContext: modelContext)
                        dismiss()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3：改造 ChatView，传 conversation 给 SettingsView，打开 Settings 前加载 systemPrompt**

修改 [ChatView.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) 中的 `.sheet(isPresented: $showSettings)`（约第 48-50 行）：

把这段：
```swift
            .sheet(isPresented: $showSettings) {
                SettingsView(settingsVM: settingsVM)
            }
```
替换为：
```swift
            .sheet(isPresented: $showSettings) {
                SettingsView(settingsVM: settingsVM, conversation: currentConversation)
                    .onAppear {
                        settingsVM.loadSystemPrompt(from: currentConversation)
                    }
            }
```

- [ ] **Step 4：改造新建对话逻辑，传入 Settings 的 systemPrompt**

修改 [ChatView.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) 中 `.sheet(isPresented: $showConversationList)` 内的 `onCreate:` 回调（约第 42-45 行）：

把这段：
```swift
                }, onCreate: {
                    if let conv = conversationListVM.createConversation() {
                        currentConversation = conv
                    }
                })
```
替换为：
```swift
                }, onCreate: {
                    if let conv = conversationListVM.createConversation(
                        title: "新对话",
                        systemPrompt: settingsVM.systemPrompt
                    ) {
                        currentConversation = conv
                        settingsVM.loadSystemPrompt(from: conv)
                        viewModel.switchTo(conversation: conv)
                    }
                })
```

同时修改 ChatView 中 `onAppear` 末尾的默认创建逻辑（约第 59-61 行），把：
```swift
            .onAppear {
                conversationListVM.load(modelContext: modelContext)
                if currentConversation == nil {
                    currentConversation = conversationListVM.createConversation()
                }
            }
```
替换为：
```swift
            .onAppear {
                conversationListVM.load(modelContext: modelContext)
                if currentConversation == nil {
                    if let conv = conversationListVM.createConversation(
                        title: "新对话",
                        systemPrompt: settingsVM.systemPrompt
                    ) {
                        currentConversation = conv
                        settingsVM.loadSystemPrompt(from: conv)
                    }
                } else {
                    settingsVM.loadSystemPrompt(from: currentConversation)
                }
            }
```

- [ ] **Step 5：构建验证无编译错误**

Run:
```bash
rm -rf /tmp/AIBuilderDD && xcodebuild -project AIBuilder.xcodeproj -scheme AIBuilder -sdk iphonesimulator -destination 'id=4B94324D-BC73-4EB8-9BA5-0DC073DD8B65' -derivedDataPath /tmp/AIBuilderDD build 2>&1 | grep -E "error:|BUILD"
```
Expected: 仅有 `** BUILD SUCCEEDED **`

- [ ] **Step 6：Commit**

```bash
git add AIBuilder/ViewModels/SettingsViewModel.swift AIBuilder/Views/Settings/SettingsView.swift AIBuilder/Views/Chat/ChatView.swift
git commit -m "day2: systemPrompt 与 Conversation 强绑定"
```

---

## Task 3：会话列表完善（切换时清理状态 + 消息预览 + 重命名 + 自动标题）

**目标：** 切换会话时调用 `viewModel.switchTo(conversation:)` 清理状态；ConversationRow 显示最后一条消息预览；新增长按重命名；首条用户消息后自动生成会话标题。

**Files:**
- Modify: `AIBuilder/ViewModels/ConversationListVM.swift`
- Modify: `AIBuilder/Views/Conversation/ConversationList.swift`
- Modify: `AIBuilder/Views/Conversation/ConversationRow.swift`
- Modify: `AIBuilder/Views/Chat/ChatView.swift`
- Modify: `AIBuilder/Services/Storage/ChatStorage.swift`

- [ ] **Step 1：扩展 ConversationListVM，支持带 systemPrompt 的创建 + 自动标题生成**

用以下内容替换 [ConversationListVM.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ConversationListVM.swift) 全文（`createConversation` 增加可选 systemPrompt 参数；新增 `autoTitleIfNeeded(for:)` 在首条用户消息后自动改标题）：

```swift
import Foundation
import SwiftData

@Observable
@MainActor
final class ConversationListVM {
    var conversations: [Conversation] = []
    private var storage: ChatStorage?

    func load(modelContext: ModelContext) {
        storage = ChatStorage(modelContext: modelContext)
        conversations = storage?.fetchConversations() ?? []
    }

    func createConversation(title: String = "新对话", systemPrompt: String = SettingsViewModel.defaultSystemPrompt) -> Conversation? {
        let conv = storage?.createConversation(title: title, systemPrompt: systemPrompt)
        if let conv = conv {
            conversations.insert(conv, at: 0)
        }
        return conv
    }

    func deleteConversation(_ conversation: Conversation) {
        storage?.deleteConversation(conversation)
        conversations.removeAll { $0.id == conversation.id }
    }

    func renameConversation(_ conversation: Conversation, to title: String) {
        storage?.renameConversation(conversation, to: title)
    }

    /// 若会话标题仍为"新对话"且有用户消息，用首条用户消息前 20 字作为新标题
    func autoTitleIfNeeded(for conversation: Conversation) {
        guard conversation.title == "新对话",
              let firstUserMsg = conversation.messages.first(where: { $0.role == "user" }),
              !firstUserMsg.content.isEmpty else { return }
        let prefix = String(firstUserMsg.content.prefix(20))
        let newTitle = prefix.count < firstUserMsg.content.count ? "\(prefix)…" : prefix
        renameConversation(conversation, to: newTitle)
    }
}
```

- [ ] **Step 2：改造 ChatView，切换会话时调 switchTo + autoTitle**

修改 [ChatView.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) 中 `.sheet(isPresented: $showConversationList)` 内的 `onSelect:` 回调（约第 39-43 行）。

把这段：
```swift
                onSelect: { conv in
                    currentConversation = conv
                    viewModel.messages = conv.messages
                    showConversationList = false
                }
```
替换为：
```swift
                onSelect: { conv in
                    conversationListVM.autoTitleIfNeeded(for: conv)
                    currentConversation = conv
                    settingsVM.loadSystemPrompt(from: conv)
                    viewModel.switchTo(conversation: conv)
                    showConversationList = false
                }
```

- [ ] **Step 3：改造 ConversationRow，显示最后一条消息预览**

用以下内容替换 [ConversationRow.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Conversation/ConversationRow.swift) 全文：

```swift
import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation

    private var lastMessage: ChatMessage? {
        conversation.messages.last
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                if let msg = lastMessage {
                    Text(msg.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(conversation.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 4：改造 ConversationList，加重命名菜单 + 空状态**

用以下内容替换 [ConversationList.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Conversation/ConversationList.swift) 全文（新增 `@State renamingConv` 与 `@State newTitle`，长按行调出 `.rename` 菜单，空状态显示"还没有对话"）：

```swift
import SwiftUI
import SwiftData

struct ConversationList: View {
    @Bindable var conversationListVM: ConversationListVM
    let onSelect: (Conversation) -> Void
    let onCreate: () -> Void

    @State private var renamingConv: Conversation?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if conversationListVM.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("还没有对话")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button {
                            onCreate()
                        } label: {
                            Label("新建对话", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(conversationListVM.conversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                ConversationRow(conversation: conversation)
                            }
                            .contextMenu {
                                Button {
                                    renamingConv = conversation
                                    newTitle = conversation.title
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    conversationListVM.deleteConversation(conversation)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                conversationListVM.deleteConversation(conversationListVM.conversations[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("对话列表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCreate()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("重命名对话", isPresented: Binding(
                get: { renamingConv != nil },
                set: { if !$0 { renamingConv = nil } }
            )) {
                TextField("新标题", text: $newTitle)
                Button("取消", role: .cancel) { renamingConv = nil }
                Button("确定") {
                    if let conv = renamingConv, !newTitle.isEmpty {
                        conversationListVM.renameConversation(conv, to: newTitle)
                    }
                    renamingConv = nil
                }
            }
        }
    }
}
```

- [ ] **Step 5：构建验证无编译错误**

Run:
```bash
rm -rf /tmp/AIBuilderDD && xcodebuild -project AIBuilder.xcodeproj -scheme AIBuilder -sdk iphonesimulator -destination 'id=4B94324D-BC73-4EB8-9BA5-0DC073DD8B65' -derivedDataPath /tmp/AIBuilderDD build 2>&1 | grep -E "error:|BUILD"
```
Expected: 仅有 `** BUILD SUCCEEDED **`

- [ ] **Step 6：Commit**

```bash
git add AIBuilder/ViewModels/ConversationListVM.swift AIBuilder/Views/Chat/ChatView.swift AIBuilder/Views/Conversation/ConversationRow.swift AIBuilder/Views/Conversation/ConversationList.swift
git commit -m "day2: 会话列表完善（预览/重命名/自动标题）"
```

---

## Task 4：端到端验证

**目标：** 验证 Day 2 三大目标全部工作。

- [ ] **Step 1：构建并安装到模拟器**

Run:
```bash
rm -rf /tmp/AIBuilderDD && xcodebuild -project AIBuilder.xcodeproj -scheme AIBuilder -sdk iphonesimulator -destination 'id=4B94324D-BC73-4EB8-9BA5-0DC073DD8B65' -derivedDataPath /tmp/AIBuilderDD build 2>&1 | grep -E "error:|BUILD"
xcrun simctl install 4B94324D-BC73-4EB8-9BA5-0DC073DD8B65 /tmp/AIBuilderDD/Build/Products/Debug-iphonesimulator/AIBuilder.app
xcrun simctl launch 4B94324D-BC73-4EB8-9BA5-0DC073DD8B65 com.aibuilder.app
```
Expected: `** BUILD SUCCEEDED **` + `com.aibuilder.app: <pid>`

- [ ] **Step 2：验证 systemPrompt 与会话绑定**

1. 打开 Settings，把 systemPrompt 改为 "你只能用一句话回答，且必须以'喵~'结尾。"，点"完成"
2. 发送消息 "介绍你自己"
3. 验证回复以 "喵~" 结尾（说明 systemPrompt 已回写并生效）
4. 在 Settings 改回 "你是一个有帮助的AI助手。"，发新消息验证回复正常

- [ ] **Step 3：验证会话切换不串数据**

1. 当前会话 A 发消息 "我的名字是张三"
2. 等回复完成后，点击左上 list.bullet 新建对话 B
3. 在 B 中发消息 "我叫什么名字？"
4. 验证 B 回复表示不知道（说明上下文未串）
5. 切回 A，发消息 "我刚才告诉你我叫什么？"
6. 验证 A 能回答 "张三"（说明 A 的上下文已持久化）

- [ ] **Step 4：验证会话管理**

1. 点击左上 list.bullet 打开会话列表
2. 验证列表项显示最后一条消息预览（不是只有标题）
3. 长按任一会话，选择"重命名"，改名为 "测试会话"，验证列表更新
4. 在某会话发首条消息后，回到列表验证标题已自动从 "新对话" 变为消息前 20 字
5. 长按会话选"删除"或左滑删除，验证列表更新

- [ ] **Step 5：验证持久化**

1. 在会话中发几条消息
2. 通过 `xcrun simctl terminate` 杀掉 App，再 launch
3. 重新打开 App，验证对话列表与消息历史仍在（说明 SwiftData 已持久化）

Run:
```bash
xcrun simctl terminate 4B94324D-BC73-4EB8-9BA5-0DC073DD8B65 com.aibuilder.app
xcrun simctl launch 4B94324D-BC73-4EB8-9BA5-0DC073DD8B65 com.aibuilder.app
```
Expected: App 重启后历史对话与消息全部保留

- [ ] **Step 6：Commit（如上一步骤中发现并修复了 bug）**

如有修复，按 fix 单独 commit；否则跳过。

---

## 自检（Self-Review）

### Spec 覆盖度
- ✅ SwiftData 持久化聊天记录：Task 1 修复 save 时机（用户消息立即 save，AI 消息流式完成 save，tool 消息立即 save）
- ✅ 支持 system prompt 设定：Task 2 让 Settings.systemPrompt 与 Conversation.systemPrompt 强绑定（双向同步）
- ✅ 会话管理（新建/切换/删除）：Task 3 完善切换状态清理 + 重命名 + 自动标题 + 消息预览 + 空状态

### 类型一致性
- `switchTo(conversation: Conversation)` 在 ChatViewModel 中定义，在 ChatView 中调用 — 一致
- `createConversation(title:systemPrompt:)` 在 ConversationListVM 中签名与 ChatView 调用一致
- `loadSystemPrompt(from: Conversation?)` 与 `updateSystemPrompt(in:modelContext:)` 在 SettingsViewModel 中定义，在 SettingsView 与 ChatView 中调用 — 一致
- `autoTitleIfNeeded(for:)` 在 ConversationListVM 中定义，在 ChatView onSelect 中调用 — 一致
- `SettingsViewModel.defaultSystemPrompt` 是 static let，在 ConversationListVM 与 SettingsViewModel.init 中引用 — 一致

### 风险点
- Task 2 修改 ChatView 的 `.sheet(isPresented: $showConversationList)` 与 `.sheet(isPresented: $showSettings)` 与 `.onAppear` 三处。每处给出 old → new 对照，避免误改。
- Task 3 ConversationList 用 `@Bindable`（Day 1 已修），新代码沿用。
