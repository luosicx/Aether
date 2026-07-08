# Day 1 实施计划：API 接入与流式对话

> **For agentic workers:** 本计划按 Task 顺序执行，每个 Task 完成后构建一次确认无编译错误。步骤使用 `- [ ]` 复选框跟踪。

**目标：** 让 DeepSeek API 流式对话端到端跑通——输入消息 → 实时打字机效果输出 → 完整回复入库。

**架构：** `ChatView (SwiftUI) → ChatViewModel (@Observable) → DeepSeekClient.chat() → AsyncStream<String> → URLSession.bytes(for:).lines`。流式 token 通过 `streamingText` 状态驱动 UI，完成后落库到 SwiftData。

**技术栈：** SwiftUI / @Observable / SwiftData / AsyncStream / URLSession AsyncBytes

---

## 现状盘点

项目已由前序 agentic run 一次性生成了 Stage 0+1+2 全部代码（共 27 个源文件），所有文件均可编译通过、App 能启动，但 **Day 1 的核心流式对话路径实际不工作**。具体阻塞点：

### 致命 bug：SSE 字节流解析错误
[DeepSeekClient.swift:90-101](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Services/LLM/DeepSeekClient.swift) 使用：
```swift
let (bytes, _) = try await session.bytes(for: request)
for try await byte in bytes {                       // ← byte 是 UInt8
    if let text = String(data: byte, encoding: .utf8),  // ← 单字节解 UTF8 必失败多字节字符
       text.hasPrefix("data: ") {                       // ← 单字节永远不可能以 "data: " 开头
```
`URLSession.AsyncBytes` 的 element 是 `UInt8`。逐字节 `String(data:encoding:)` 对多字节 UTF-8 字符必然解码失败；并且单字节永远不可能 `hasPrefix("data: ")`。结果：流式回调几乎永不触发，用户看不到任何回复。

**正确做法：** 用 `bytes.lines`（`AsyncLineSequence`）按行迭代。

### 阻塞 bug：默认开启 RAG 与 Tools
[ChatViewModel.swift:13-14, 50-62](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift) 中 `ragEnabled = true`，且 `processMessage` 每次都发送 `tools = ToolRegistry.shared.allToolDefs`。按实战计划，RAG 是 Day 3、Tools 是 Day 4。Day 1 必须禁用两者，否则会引入无关失败路径（RAGService 在无文档时可能抛错、ToolRegistry 可能为空数组导致 DeepSeek 返回 400）。

### bug：systemPrompt 未注入 API 请求
[ChatViewModel.swift:50](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift) `apiMessages` 完全来自 `conversation.messages.map { $0.toAPIMessage() }`，从未插入 `conversation.systemPrompt` 作为 system message。结果：设置页改系统提示词毫无效果。

### 体验 bug：流式时不滚动到底部
[ChatView.swift:39-43](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) 仅 `onChange(of: viewModel.messages.count)` 触发滚动。流式期间 `messages.count` 不变（只有 `streamingText` 在变），新内容不会滚动到视野，用户看不到打字机效果。

### 次要：模型名待核实
[APIConfig.swift:7](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Core/Constants/APIConfig.swift) 默认模型 `deepseek-v4-flash`。DeepSeek 官方当前公开模型名为 `deepseek-chat`（V3）和 `deepseek-reasoner`（R1），未见 `deepseek-v4-flash`。需在 Task 4 端到端验证时确认，若 API 返回 400 model not found 则改为 `deepseek-chat`。

---

## 范围与非目标

### 范围（Day 1）
1. 修复 SSE 流式解析（按行读取）
2. 禁用 RAG / Tools，确保走纯对话路径
3. 注入 systemPrompt 到 API 请求
4. 修复流式滚动
5. 端到端验证：填 API Key → 发消息 → 看到打字机效果

### 非目标（明确不做，避免范围蔓延）
- **不动 RAG**（Day 3）—— 仅在 VM 层关闭开关，不改 RAGService
- **不动 Tools / ReAct**（Day 4）—— 仅在 VM 层不传 tools
- **不引入 Combine** —— 项目用 `@Observable` + `AsyncStream`，是 iOS 17+ 现代等价方案，实战计划中"Combine 驱动"应理解为概念而非强制框架
- **不重构 ChatActor**（Day 6 并发隔离）—— 当前 `ChatActor.swift` 引用未定义类型 `ActorIsolated`，但因无人调用故编译通过。Day 1 不动
- **不写 XCTest**（Day 10 才做质量保障）—— 验证方式为端到端手动测试
- **不动 embed()**（Day 3）—— `DeepSeekClient.embed` 用了 `Data(contentsOf: url)` 而非 POST，是 bug，但 Day 1 不调用就先不动

---

## 文件改动清单

| 文件 | 操作 | 改动点 |
|---|---|---|
| `AIBuilder/Services/LLM/DeepSeekClient.swift` | 修改 | `sendRequest` 改用 `bytes.lines` 按行迭代；同步修复 `sendRequestWithTools` |
| `AIBuilder/ViewModels/ChatViewModel.swift` | 修改 | 默认 `ragEnabled = false`；新增 `toolsEnabled` 标志默认 false；`processMessage` 注入 systemPrompt；`toolsEnabled == false` 时走无 tools 的 `chat()` 重载 |
| `AIBuilder/Views/Chat/ChatView.swift` | 修改 | 增加 `onChange(of: viewModel.streamingText)` 触发滚动 |
| `AIBuilder/Core/Constants/APIConfig.swift` | 可能修改 | 仅在 Task 4 验证模型名失败时改 |

---

## Task 1：修复 SSE 按行解析

**文件：**
- 修改：[AIBuilder/Services/LLM/DeepSeekClient.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Services/LLM/DeepSeekClient.swift) 的 `sendRequest`（77-106 行）与 `sendRequestWithTools`（108-136 行）

- [ ] **Step 1：修改 `sendRequest`，从逐字节改为按行迭代**

把：
```swift
do {
    let (bytes, _) = try await session.bytes(for: request)
    for try await byte in bytes {
        if let text = String(data: byte, encoding: .utf8),
           text.hasPrefix("data: ") {
            let jsonStr = String(text.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard jsonStr != "[DONE]" else { break }
            if let data = jsonStr.data(using: .utf8),
               let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
               let content = chunk.choices?.first?.delta?.content {
                continuation.yield(content)
            }
        }
    }
} catch {
    print("SSE error: \(error)")
}
continuation.finish()
```

改为：
```swift
do {
    let (bytes, _) = try await session.bytes(for: request)
    for try await line in bytes.lines {
        guard line.hasPrefix("data: ") else { continue }
        let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }
        guard let data = jsonStr.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
              let content = chunk.choices?.first?.delta?.content else { continue }
        continuation.yield(content)
    }
} catch {
    print("SSE error: \(error)")
}
continuation.finish()
```

- [ ] **Step 2：同步修改 `sendRequestWithTools`，从逐字节改为按行迭代**

把 `sendRequestWithTools` 内的：
```swift
do {
    let (bytes, _) = try await session.bytes(for: request)
    var toolAccum: [Int: AccumulatedToolCall] = [:]
    for try await byte in bytes {
        if let text = String(data: byte, encoding: .utf8),
           text.hasPrefix("data: ") {
            let jsonStr = String(text.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard jsonStr != "[DONE]" else { break }
            if let parsed = parser.parseChunkWithToolAccumulation(from: "data: " + jsonStr, accumulated: &toolAccum) {
                continuation.yield(parsed)
            }
        }
    }
} catch {
    print("SSE error: \(error)")
}
continuation.finish()
```

改为：
```swift
do {
    let (bytes, _) = try await session.bytes(for: request)
    var toolAccum: [Int: AccumulatedToolCall] = [:]
    for try await line in bytes.lines {
        guard line.hasPrefix("data: ") else { continue }
        let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }
        if let parsed = parser.parseChunkWithToolAccumulation(from: line, accumulated: &toolAccum) {
            continuation.yield(parsed)
        }
    }
} catch {
    print("SSE error: \(error)")
}
continuation.finish()
```

注意：传给 `parseChunkWithToolAccumulation` 的是完整 `line`（已含 `data: ` 前缀），与该方法内部 `parseChunk(from:)` 的预期一致。

- [ ] **Step 3：构建验证**

Run: `xcodebuild -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4：Commit**

```bash
git add AIBuilder/Services/LLM/DeepSeekClient.swift
git commit -m "fix(LLM): 修复 SSE 流式解析使用 bytes.lines 按行迭代

原实现逐字节迭代 AsyncBytes，单字节永远不可能 hasPrefix(\"data: \")，导致流式回调永不触发。改为使用 bytes.lines 按行迭代，并同步修复带工具调用的流式路径。"
```

---

## Task 2：禁用 RAG / Tools，注入 systemPrompt

**文件：**
- 修改：[AIBuilder/ViewModels/ChatViewModel.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/ChatViewModel.swift)

- [ ] **Step 1：在 `ChatViewModel` 属性区新增 `toolsEnabled` 开关，并把 `ragEnabled` 默认改为 false**

把：
```swift
var currentToolSteps: [ToolStep] = []
var ragEnabled = true
var tokenLimit = 4000
```

改为：
```swift
var currentToolSteps: [ToolStep] = []
var ragEnabled = false        // Day 3 启用
var toolsEnabled = false      // Day 4 启用
var tokenLimit = 4000
```

- [ ] **Step 2：在 `processMessage` 开头注入 systemPrompt**

把 `processMessage` 开头：
```swift
private func processMessage(_ text: String, conversation: Conversation, modelContext: ModelContext) async {
    var apiMessages = conversation.messages.map { $0.toAPIMessage() }
    if ragEnabled {
```

改为：
```swift
private func processMessage(_ text: String, conversation: Conversation, modelContext: ModelContext) async {
    var apiMessages: [APIMessage] = []
    if !conversation.systemPrompt.isEmpty {
        apiMessages.append(APIMessage(role: "system", content: conversation.systemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil))
    }
    apiMessages.append(contentsOf: conversation.messages.map { $0.toAPIMessage() })
    if ragEnabled {
```

- [ ] **Step 3：根据 `toolsEnabled` 分支选择 `chat()` 重载**

把：
```swift
let tools = ToolRegistry.shared.allToolDefs
let stream = client.chat(messages: apiMessages, config: ChatConfig.default, tools: tools)
var chunkContent = ""
var finalToolCalls: [AccumulatedToolCall]?
for await chunk in stream {
    if let content = chunk.content {
        chunkContent += content
        streamingText = fullResponse + chunkContent
    }
    if let calls = chunk.toolCalls {
        finalToolCalls = calls
    }
}
```

改为：
```swift
let stream: AsyncStream<ParsedChunk>
if toolsEnabled {
    let tools = ToolRegistry.shared.allToolDefs
    stream = client.chat(messages: apiMessages, config: ChatConfig.default, tools: tools)
} else {
    stream = client.chat(messages: apiMessages, config: ChatConfig.default).map { content in
        ParsedChunk(content: content, toolCalls: nil)
    }
}
var chunkContent = ""
var finalToolCalls: [AccumulatedToolCall]?
for await chunk in stream {
    if let content = chunk.content {
        chunkContent += content
        streamingText = fullResponse + chunkContent
    }
    if let calls = chunk.toolCalls {
        finalToolCalls = calls
    }
}
```

注意：`AsyncStream.map` 不存在，需要用 `AsyncStream` 重新包装。改用以下写法：

```swift
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
```

- [ ] **Step 4：构建验证**

Run: `xcodebuild -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5：Commit**

```bash
git add AIBuilder/ViewModels/ChatViewModel.swift
git commit -m "feat(ChatVM): 注入 systemPrompt 并默认关闭 RAG/Tools

- systemPrompt 此前从未进入 API 请求，设置页改了也无效，现作为 system 消息插入 messages 头部
- ragEnabled / toolsEnabled 默认 false，避免 Day 1 引入无关失败路径（Day 3/4 再开）
- toolsEnabled == false 时走无 tools 的 chat() 重载，并把 String 流包装为 ParsedChunk 流"
```

---

## Task 3：修复流式滚动

**文件：**
- 修改：[AIBuilder/Views/Chat/ChatView.swift](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Views/Chat/ChatView.swift) 的 39-43 行

- [ ] **Step 1：增加 `streamingText` 变化的滚动监听**

把：
```swift
.onChange(of: viewModel.messages.count) {
    withAnimation {
        proxy.scrollTo(viewModel.messages.last?.id ?? "streaming", anchor: .bottom)
    }
}
```

改为：
```swift
.onChange(of: viewModel.messages.count) {
    withAnimation {
        proxy.scrollTo(viewModel.messages.last?.id ?? "streaming", anchor: .bottom)
    }
}
.onChange(of: viewModel.streamingText) {
    withAnimation {
        proxy.scrollTo("streaming", anchor: .bottom)
    }
}
```

- [ ] **Step 2：构建验证**

Run: `xcodebuild -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3：Commit**

```bash
git add AIBuilder/Views/Chat/ChatView.swift
git commit -m "fix(ChatView): 流式输出时滚动到底部

原仅 onChange(of: messages.count) 触发滚动，流式期间 messages 不变，打字机效果不可见。新增 onChange(of: streamingText) 监听。"
```

---

## Task 4：端到端验证

**前置条件：** 用户已通过 DeepSeek 平台获取 API Key（https://platform.deepseek.com）。

- [ ] **Step 1：重新构建并安装到模拟器**

Run:
```bash
xcodebuild -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -3 && \
xcrun simctl install booted "$(xcodebuild -scheme AIBuilder -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug -showBuildSettings 2>/dev/null | grep BUILT_PRODUCTS_DIR | head -1 | awk -F' = ' '{print $2}')/AIBuilder.app" && \
xcrun simctl launch booted com.aibuilder.app
```
Expected: `BUILD SUCCEEDED` + `com.aibuilder.app: <pid>`

- [ ] **Step 2：填入 API Key**

在模拟器中：点右上角齿轮 → 在 "API Key" 输入框粘贴 DeepSeek API Key → 点 "保存 API Key" → 看到 "API Key 已保存" → 点 "完成"。

- [ ] **Step 3：发送测试消息**

在输入框输入 `你好，请用一句话介绍你自己` → 点发送按钮。

**预期：**
- 输入框清空，发送按钮变灰
- 出现 typing indicator（三个跳动小圆点）
- 1-3 秒内 typing indicator 消失，开始逐字显示 AI 回复（打字机效果）
- 回复期间自动滚动到底部
- 回复结束后消息固定显示，发送按钮恢复可用

- [ ] **Step 4：验证多轮对话**

接着输入 `我刚才问了你什么？` → 发送。

**预期：** AI 能正确回答 "你刚才问我介绍自己"，证明对话上下文（messages 数组）正确传递。

- [ ] **Step 5：验证 systemPrompt 注入**

回到设置 → 系统提示词改为 `你只能用一句话回答，且必须以"喵~"结尾。` → 完成 → 输入 `介绍巴黎` → 发送。

**预期：** AI 回复只有一句话且以 "喵~" 结尾，证明 systemPrompt 已注入。

- [ ] **Step 6：（条件）修复模型名**

若 Step 3 中 AI 不回复，且 Xcode console 出现 `SSE error:` 或 HTTP 400，则：
- 在 [APIConfig.swift:7](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/Core/Constants/APIConfig.swift) 把 `static let defaultModel = "deepseek-v4-flash"` 改为 `static let defaultModel = "deepseek-chat"`
- 在 [SettingsViewModel.swift:12](file:///Users/xuchen/Documents/AIBuiler/AIBuilder/ViewModels/SettingsViewModel.swift) 把 `availableModels = ["deepseek-v4-flash", "deepseek-v4", "deepseek-v3"]` 改为 `availableModels = ["deepseek-chat", "deepseek-reasoner"]`
- 重新构建并回到 Step 3 验证

- [ ] **Step 7：（若一切正常）Commit 端到端验证记录**

无需改代码则跳过本步。若改了模型名：
```bash
git add AIBuilder/Core/Constants/APIConfig.swift AIBuilder/ViewModels/SettingsViewModel.swift
git commit -m "fix(config): 修正 DeepSeek 模型名为官方公开的 deepseek-chat / deepseek-reasoner"
```

---

## 验收标准

Day 1 完成的判定：
1. ✅ 能在模拟器中填入 API Key 并保存（Keychain）
2. ✅ 发送消息后看到打字机效果（流式逐字输出）
3. ✅ 多轮对话有上下文记忆
4. ✅ systemPrompt 改动生效
5. ✅ 流式输出时自动滚动到底部
6. ✅ 回复完整后正确入库（重启 App 后历史仍在）

## 风险与应对

| 风险 | 应对 |
|---|---|
| DeepSeek API 在国内网络偶发不稳 | 若 Step 3 失败，先检查 API Key 是否有效；若网络问题，重试一次 |
| 模型名 `deepseek-v4-flash` 不存在 | Task 4 Step 6 已提供 fallback |
| SwiftData 在 Swift 6 严格并发下报警告 | Day 1 仅做功能验证，并发改造是 Day 12 |
| `bytes.lines` 在长连接中断时 hang 住 | 当前未处理，Day 6 工程优化时加 timeout |

---

## 执行顺序总览

Task 1 → Task 2 → Task 3 → Task 4 端到端验证 → 完成

每个 Task 一个 commit，便于回滚。
