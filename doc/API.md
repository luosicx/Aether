# API 契约文档

本文档描述 Aether 项目的核心 API 契约：LLMProvider 协议、ToolProtocol 协议、ToolDefinition JSON Schema、SSE 响应格式，DeepSeek / Qwen / BFF 三种 endpoint 的请求示例，以及 v1.5.0 起 Windows / Android 跨平台扩展的 BFF HTTP 契约、Rust FFI 契约、数据模型契约与配置契约。所有方法签名与 endpoint 均取自源码，如代码演进请同步更新本文档。

---

## 1. LLMProvider 协议契约

`LLMProvider` 是 LLM 客户端的抽象协议，定义 chat 流式对话（纯文本与带工具两个重载）与 embed 嵌入两个核心能力。

### 1.1 协议定义

```swift
protocol LLMProvider {
    /// 纯文本 chat 流：以 `AsyncStream<String>` 形式逐 chunk yield 文本内容。
    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String>

    /// 带工具调用 chat 流：以 `AsyncStream<ParsedChunk>` 形式 yield，包含 content 与累积后的 toolCalls。
    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk>

    /// 批量文本嵌入，返回按 index 排序的向量数组；HTTP 错误抛 `LLMError`。
    func embed(texts: [String], apiKey: String) async throws -> [[Float]]
}
```

> 注意：协议未标记 `Sendable`；具体实现类各自以 `nonisolated` 或 `@MainActor` 标注以满足跨 actor 调用。

### 1.2 方法说明

| 方法 | 用途 | 返回值 | 备注 |
|------|------|--------|------|
| `chat(messages:config:apiKey:)` | 纯文本流式对话 | `AsyncStream<String>` | 逐 chunk yield 文本片段，不含工具调用 |
| `chat(messages:config:tools:apiKey:)` | 带工具调用流式对话 | `AsyncStream<ParsedChunk>` | `tools` 为非可选 `[ToolDef]`；yield 的 `ParsedChunk` 含累积后的 toolCalls |
| `embed(texts:apiKey:)` | 文本嵌入 | `[[Float]]` | 批量嵌入；空入参短路返回空数组；按 `index` 排序输出 |

### 1.3 实现类

| 类 | endpoint（chat） | 说明 |
|----|------------------|------|
| `DeepSeekClient` | `https://api.deepseek.com/chat/completions` | DeepSeek 直连，`Authorization: Bearer <key>` |
| `QwenClient` | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` | Qwen 走阿里云百炼 DashScope OpenAI 兼容端点 |
| `BFFProxyClient` | `<BFF endpointURL>/v1/chat/completions` | 经 Cloudflare Workers 中转，header 带 `X-BFF-Token` 与 `X-Provider`，不带 Authorization |
| `OfflineLLMProvider` | 本地 MLX 推理（不走 HTTP） | 端侧推理，断网可用；`baseURL` 为空字符串 |
| `FallbackLLMProvider` | 包装 primary + fallback | `init(primary:fallback:primaryProvider:fallbackProvider:)`；primary 失败自动切 fallback |

`BFFProxyClient` 的 chat 路径通过 `config.endpointURL.appending(path: "v1/chat/completions")` 构造，默认 `endpointURL` 为占位地址 `https://aether-bff.example.com`，部署后替换为真实域名。

### 1.4 ParsedChunk 与相关结构

```swift
/// SSEParser 解析后的结果；content 可能为 nil（纯 tool_calls chunk），toolCalls 可能为 nil（纯 content chunk）
struct ParsedChunk: Sendable {
    let content: String?
    let toolCalls: [AccumulatedToolCall]?
}

/// 跨多个 SSE chunk 累积的工具调用（arguments 字段可能分多次到达）
struct AccumulatedToolCall: Sendable {
    let id: String
    let type: String      // 通常为 "function"
    let name: String
    var arguments: String // JSON 字符串，跨 chunk 拼接
}

/// 一次工具调用的完整参数（APIMessage.toolCalls 元素类型）
struct ToolCallParam: Sendable {
    let id: String
    let type: String
    let function: FunctionCall
}

/// 工具调用的函数名与参数
struct FunctionCall: Sendable {
    let name: String
    let arguments: String  // JSON 字符串
}
```

### 1.5 AsyncStream 行为

- `chat` 返回 `AsyncStream`，内部启动 `Task` 异步消费 URLSession `bytes` 流
- 流结束或异常时调用 `continuation.finish()`
- 调用方以 `for await chunk in stream { ... }` 消费
- HTTP 非 2xx 时构造 `LLMError`，经 `MainActor` 发送 `.llmErrorOccurred` 通知（userInfo `["error": err]`），随后 `finish()`
- 网络异常同样转 `LLMError.networkError` 并发通知

---

## 2. ToolProtocol 协议契约

`ToolProtocol` 是工具的抽象协议，定义 `definition`（工具元信息）与 `execute`（执行入口）。

### 2.1 协议定义

```swift
protocol ToolProtocol {
    /// 暴露给 LLM 的工具元信息。
    var definition: ToolDefinition { get }

    /// 执行工具。
    /// - Parameters:
    ///   - arguments: JSON 反序列化后的参数字典。
    /// - Returns: 字符串形式的结果（成功或错误描述）。
    /// - Throws: 执行过程中可能抛出的错误。
    func execute(arguments: [String: Any]) async throws -> String
}
```

### 2.2 ToolDefinition 结构

```swift
/// 工具的元信息（name + description + parameters JSON Schema），用于告知 LLM 可调用的工具。
struct ToolDefinition {
    /// 工具名，需唯一。
    let name: String
    /// 工具描述，供 LLM 判断是否调用。
    let description: String
    /// JSON Schema 字典，符合 OpenAI function calling 规范。
    let parameters: [String: Any]
}
```

> 注意：`ToolDefinition` 本身非 `Codable`（`parameters` 含 `[String: Any]`）。`ToolRegistry.allToolDefs` 通过 `AnyCodable` 包装器将其转为可编码的 `ToolDef` 后再交给请求体序列化。

### 2.3 ToolDef（请求体可编码形式）

`ToolDef` 是发往 LLM 的工具定义结构，定义在 `ChatRequestBody` 同文件，`Codable`：

```swift
struct ToolDef: Codable {
    let type: String          // 固定 "function"
    let function: FunctionDef

    struct FunctionDef: Codable {
        let name: String
        let description: String
        let parameters: [String: AnyCodable]  // AnyCodable 包装动态类型
    }
}
```

### 2.4 execute 方法约定

- **输入**：`arguments: [String: Any]` —— LLM 通过 function calling 传入的参数字典（JSON 反序列化后）
- **返回**：`String` —— 工具执行结果文本，作为 `tool` role 消息回传 LLM
- **错误**：`throw` 任意 Error，部分工具内部以"返回错误字符串"而非抛错的方式处理参数缺失（如 `AlarmTool` 缺 `time` 时返回错误字符串）
- **调用入口**：`ToolRegistry.shared.execute(name:arguments:)`，未注册抛 `NSError`（domain=`ToolRegistry`, code=1）

### 2.5 工具列表

`ToolRegistry` 为 `@MainActor` 单例，初始化时按平台条件注册工具：

**跨平台工具（始终注册）**：
- `AlarmTool`（`create_alarm`）
- `ReminderTool`
- `DateTimeTool`（`get_current_time`）
- `CalculatorTool`（`calculate`）
- `LocationTool`
- `DeviceInfoTool`
- `ReadClipboardTool` / `WriteClipboardTool`
- `OpenURLTool`
- `ContactsTool`
- `WeatherTool`
- `RunShortcutTool` / `ListShortcutsTool` / `CreateShortcutTool`

**macOS 独有工具（`#if os(macOS)` 条件注册）**：
`AppleScriptTool`、`ScreenshotTool`、`OCRTool`、`TerminalCommandTool`、`WindowManagementTool`、`AppManagementTool`、`FileOperationTool`、`FinderTool`、`SafariControlTool`、`SystemControlTool`、`InputAutomationTool`。

详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

---

## 3. ToolDefinition JSON Schema 规范

每个工具通过 `parameters` 字段声明参数 JSON Schema，LLM 据此生成 arguments。

### 3.1 示例：CalculatorTool

```swift
ToolDefinition(
    name: "calculate",
    description: "对数学表达式求值，支持加减乘除、括号、浮点数",
    parameters: [
        "type": "object",
        "properties": [
            "expression": ["type": "string", "description": "数学表达式，如 1 + 2 * 3、(1+2)*3、3.14 * 2"]
        ],
        "required": ["expression"]
    ]
)
```

对应 JSON Schema：

```json
{
  "type": "object",
  "properties": {
    "expression": {
      "type": "string",
      "description": "数学表达式，如 1 + 2 * 3、(1+2)*3、3.14 * 2"
    }
  },
  "required": ["expression"]
}
```

### 3.2 示例：AlarmTool（`create_alarm`）

```json
{
  "type": "object",
  "properties": {
    "time": {
      "type": "string",
      "description": "闹钟时间，格式 HH:mm"
    },
    "label": {
      "type": "string",
      "description": "闹钟标签"
    }
  },
  "required": ["time"]
}
```

### 3.3 示例：DateTimeTool（`get_current_time`）

```json
{
  "type": "object",
  "properties": {
    "timezone": {
      "type": "string",
      "description": "时区标识，如 Asia/Shanghai、America/New_York；不传则用系统时区"
    }
  },
  "required": []
}
```

### 3.4 Schema 约定

- `type` 固定为 `"object"`
- `properties` 列出每个参数的 `type` 与 `description`
- `required` 列出必填参数名（无可传 `[]`）
- `description` 用中文，与工具实际行为一致

---

## 4. SSE 响应格式

LLM 上游返回的 Server-Sent Events 流式响应格式，兼容 OpenAI chat completions。`ChatChunk` 是其 Swift 解码结构。

### 4.1 单 chunk 格式

```
data: {"choices":[{"delta":{"content":"你好"}}]}

data: {"choices":[{"delta":{"content":"！"}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"calculate","arguments":"{\"expression\":\"1+2\"}"}}]}}]}

data: [DONE]
```

### 4.2 ChatChunk 结构

```swift
struct ChatChunk: Codable, Sendable {
    let id: String?
    let choices: [Choice]?
    let usage: Usage?

    struct Choice: Codable, Sendable {
        let delta: Delta?
        let finish_reason: String?
    }

    struct Delta: Codable, Sendable {
        let role: String?
        let content: String?
        let tool_calls: [ToolCallDelta]?
    }

    struct ToolCallDelta: Codable, Sendable {
        let index: Int?
        let id: String?
        let type: String?
        let function: FunctionDelta?
    }

    struct FunctionDelta: Codable, Sendable {
        let name: String?      // 通常仅在首 chunk 出现
        let arguments: String? // 跨多个 chunk 拼接
    }

    struct Usage: Codable, Sendable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}
```

### 4.3 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `choices` | Array? | 选项数组，通常长度为 1 |
| `choices[0].delta.content` | String? | 文本增量（可能为空） |
| `choices[0].delta.tool_calls` | Array? | 工具调用增量，按 `index` 累积 |
| `tool_calls[i].index` | Int? | 工具调用索引（用于累积匹配，缺省按 0 处理） |
| `tool_calls[i].id` | String? | 工具调用 ID（首 chunk 出现，用于回传 tool role 消息） |
| `tool_calls[i].type` | String? | 通常 `"function"` |
| `tool_calls[i].function.name` | String? | 工具名（首 chunk 出现） |
| `tool_calls[i].function.arguments` | String? | 参数 JSON 字符串，跨 chunk 累积 |
| `usage` | Object? | token 用量统计，通常仅在最后 chunk 出现 |

### 4.4 终止符

- 流以 `data: [DONE]` 结尾
- 客户端逐行解析：跳过非 `data: ` 前缀行，遇到 `[DONE]` 跳过并继续（流自然结束）

### 4.5 tool_calls 累积规则

`function.arguments` 是 JSON 字符串，可能跨多个 chunk 拼接。`SSEParser.parseWithToolAccumulation` 负责累积：

- 累积字典 key 为 `index`（`Int`，缺省取 0），value 为 `AccumulatedToolCall`
- 首次见到某 `index` 时，需同时存在 `id` 与 `function.name` 才创建条目
- 后续 chunk 仅 `function.arguments` 字段，按 `index` 追加到 `existing.arguments`
- 每个 `ParsedChunk.toolCalls` 返回当前累积的全部工具调用，按 `id` 字符串升序排序

示例累积过程：
- chunk 1: `arguments = "{\"expression\":\"1` 
- chunk 2: `arguments = "+2\"}"`
- 累积后：`{"expression":"1+2"}`

---

## 5. 三种 endpoint 请求示例

### 5.1 DeepSeek 直连

```bash
curl -X POST https://api.deepseek.com/chat/completions \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [
      {"role": "system", "content": "你是 AI 助手"},
      {"role": "user", "content": "你好"}
    ],
    "stream": true,
    "max_tokens": 2048,
    "temperature": 0.7,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "calculate",
          "description": "对数学表达式求值，支持加减乘除、括号、浮点数",
          "parameters": {
            "type": "object",
            "properties": {
              "expression": {"type": "string", "description": "数学表达式"}
            },
            "required": ["expression"]
          }
        }
      }
    ],
    "tool_choice": "auto"
  }'
```

- 默认对话模型：`deepseek-chat`；推理模型：`deepseek-reasoner`；嵌入模型：`deepseek-embedding`
- chat 路径：`APIConfig.deepseekBaseURL + APIConfig.chatEndpoint` = `https://api.deepseek.com/chat/completions`
- embedding 路径：`https://api.deepseek.com/embeddings`

### 5.2 Qwen DashScope

```bash
curl -X POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions \
  -H "Authorization: Bearer $QWEN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-plus",
    "messages": [
      {"role": "user", "content": "你好"}
    ],
    "stream": true
  }'
```

- 默认对话模型：`qwen-plus`；推理模型：`qwq-32b`；嵌入模型：`text-embedding-v3`
- chat 路径：`provider.baseURL + provider.chatEndpoint` = `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- embedding 路径：`https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings`

### 5.3 BFF 代理

```bash
curl -X POST https://aether-bff.<your-subdomain>.workers.dev/v1/chat/completions \
  -H "X-BFF-Token: $BFF_USER_TOKEN" \
  -H "X-Provider: deepseek" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [
      {"role": "user", "content": "你好"}
    ],
    "stream": true
  }'
```

- 路径由 `config.endpointURL.appending(path: "v1/chat/completions")` 构造，即 `<endpointURL>/v1/chat/completions`
- embedding 路径：`<endpointURL>/v1/embeddings`
- 默认 `endpointURL` 为占位地址 `https://aether-bff.example.com`，部署后替换
- `X-Provider` 取 `ModelProvider.rawValue`：`deepseek` / `qwen` / `onDevice`
- BFF 模式下 `apiKey` 参数不使用（服务端从 Workers secrets 注入上游 key）

**关键差异**：
- DeepSeek / Qwen 直连：`Authorization: Bearer <upstream-api-key>`
- BFF 代理：`X-BFF-Token: <user-token>` + `X-Provider: <deepseek|qwen>`，**不带** `Authorization` header

### 5.4 Embedding 请求

```bash
# DeepSeek embedding
curl -X POST https://api.deepseek.com/embeddings \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-embedding",
    "input": ["文本1", "文本2"]
  }'

# Qwen embedding
curl -X POST https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings \
  -H "Authorization: Bearer $QWEN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-v3",
    "input": ["文本1", "文本2"]
  }'
```

响应结构（`EmbeddingResponse`）：

```json
{
  "data": [
    {"embedding": [0.1, 0.2], "index": 0},
    {"embedding": [0.3, 0.4], "index": 1}
  ],
  "usage": {
    "prompt_tokens": 8,
    "total_tokens": 8
  }
}
```

客户端按 `index` 升序排序后输出 `[[Float]]`。

---

## 6. 错误响应格式

### 6.1 LLM 错误类型

```swift
enum LLMError: Error, Sendable {
    case networkError(String)                 // 网络连接错误
    case apiKeyMissing                        // API Key 缺失
    case apiKeyInvalid                        // API Key 无效（401）
    case apiError(code: Int, message: String) // 其它 API 错误
    case timeout                              // 请求超时
    case unknown(String)                      // 未知错误
    case rateLimited(retryAfter: TimeInterval) // 触发限流（429）
    case llmErrorOccurred(String)             // BFF 通用错误
}
```

上游 LLM 错误响应体（典型）：

```json
{
  "error": {
    "message": "Invalid API key",
    "type": "invalid_request_error",
    "code": "invalid_api_key"
  }
}
```

`LLMError.fromHTTPStatus(_:body:)` 映射：`401 → .apiKeyInvalid`，`429 → .apiError(code:429, ...)`，其它 → `.apiError`。

### 6.2 BFF 错误

`BFFProxyClient.bffError(from:)` 按状态码映射：

| HTTP 状态码 | LLMError case | 用户可见消息 | 说明 |
|------------|---------------|-------------|------|
| 401 | `.llmErrorOccurred` | `BFF Token 无效` | `X-BFF-Token` 不匹配服务端 `BFF_TOKEN` |
| 429 | `.rateLimited(retryAfter:)` | `请求过于频繁，请 N 秒后重试` | 解析 `Retry-After` Header（秒），缺省 60 |
| 500–599 | `.llmErrorOccurred` | `BFF 服务异常` | BFF 服务异常或上游错误 |
| 其他 | `.apiError(code:message:)` | `服务异常（<code>），请稍后再试` | 兜底 |

> 直连 DeepSeek / Qwen 模式下，401 映射为 `.apiKeyInvalid`，429 映射为 `.apiError`，与 BFF 路径不同。

---

## 7. ChatConfig 结构

```swift
struct ChatConfig: Sendable {
    var model: String         // 模型名，如 "deepseek-chat" / "qwen-plus"
    var systemPrompt: String  // 系统提示词（非可选）
    var maxTokens: Int        // 单次响应最大 token 数
    var temperature: Double   // 采样温度，越高越随机

    /// 默认配置：deepseek-chat / "你是一个有帮助的AI助手。" / 2048 / 0.7
    static let `default` = ChatConfig(
        model: APIConfig.defaultModel,
        systemPrompt: "你是一个有帮助的AI助手。",
        maxTokens: 2048,
        temperature: 0.7
    )
}
```

`systemPrompt` 为非可选 `String`；调用方需在请求前将其合并进 `messages` 数组（作为首条 `system` role 消息）。

---

## 8. APIMessage 结构

```swift
struct APIMessage: Sendable {
    let role: String                  // "system" / "user" / "assistant" / "tool"
    let content: String               // 文本内容（非可选）
    let images: [String]?             // base64 编码图片数组（多模态）
    let toolCallId: String?           // tool role 回传的 tool_calls.id
    let toolName: String?            // tool role 对应的工具名
    let toolCalls: [ToolCallParam]?   // assistant role 触发的工具调用列表
}
```

> 注意：`APIMessage.content` 为非可选 `String`；但请求体 `ChatRequestBody.ChatMessageBody.content` 为 `String?`（编码时若为空字符串则按 `encodeIfPresent` 处理）。多模态场景下，`images` 非空时 content 在请求体中改为内容块数组（`[{type:"text",...},{type:"image_url",...}]`），该逻辑由 `DeepSeekClient` / `QwenClient` / `BFFProxyClient` 手动构造 payload 实现（Codable 无法表达"字符串或数组"联合类型）。

---

## 9. MultimodalFacade 多模态 API 契约（v1.3 + v1.4）

`MultimodalFacade` 是端侧多模态能力的统一入口（`public actor`，位于 `Aether/Services/Multimodal/MultimodalFacade.swift`），封装 5 个子引擎（VLM / ASR / TTS / VoiceCloner / ImageGen）并通过依赖注入支持运行时切换。v1.3 提供协议抽象与占位实现，v1.4 默认切换为 Apple 原生引擎（`NativeVisionEngine` / `NativeASREngine` / `NativeTTSEngine`）。

### 9.1 引擎协议契约

#### 9.1.1 VisionInferenceEngine（视觉理解）

```swift
public protocol VisionInferenceEngine: Sendable {
    var isLoaded: Bool { get }
    var loadedModelName: String? { get }
    func loadModel(at modelPath: URL, modelName: String) async throws
    func unloadModel() async
    func describe(image: CGImage, prompt: String) async throws -> String
}
```

| 实现 | 版本 | 说明 |
|------|------|------|
| `PlaceholderVisionEngine` | v1.3 | 占位，未加载抛 `engineNotLoaded`，加载后返回提示字符串 |
| `NativeVisionEngine` | v1.4 | 基于 Vision 框架 5 个请求并发（分类 / 人脸 / 矩形 / 文字 / 条码），`isLoaded` 始终为 `true`，`loadedModelName = "Apple Vision (Native)"`，`loadModel` / `unloadModel` 为 no-op |
| `MLXVisionEngine` | v1.6 计划 | 基于 MLX-VLM（Qwen2-VL-2B Q4 等），`MLXInferenceEngine.generate(prompt:images:)` |

#### 9.1.2 ASREngine（语音识别）

```swift
public protocol ASREngine: Sendable {
    var name: String { get }
    var requiresNetwork: Bool { get }
    var isLoaded: Bool { get }
    func loadModel(at modelPath: URL) async throws
    func transcribe(audioPath: URL, language: String) async throws -> String
}
```

| 实现 | 版本 | 说明 |
|------|------|------|
| `PlaceholderASREngine` | v1.3 | 占位，`name = "PlaceholderASR"`，`requiresNetwork = false`，返回提示字符串 |
| `NativeASREngine` | v1.4 | `name = "NativeASR (SFSpeechRecognizer)"`，`requiresNetwork = true`，基于 `SFSpeechURLRecognitionRequest` 文件识别；支持 wav / caf / m4a / mp3 / aac；CI 环境识别器不可用抛 `asrRecognitionFailed` |
| `WhisperASREngine` | v1.6 计划 | 基于 whisper.cpp Rust 绑定，离线识别 |

#### 9.1.3 TTSEngine（语音合成）

```swift
public protocol TTSEngine: Sendable {
    var name: String { get }
    var isLoaded: Bool { get }
    func loadModel(at modelPath: URL) async throws
    func synthesize(text: String, voiceId: String?) async throws -> Data
}
```

| 实现 | 版本 | 说明 |
|------|------|------|
| `PlaceholderTTSEngine` | v1.3 | 占位，`name = "PlaceholderTTS"`，返回空 `Data()` |
| `NativeTTSEngine` | v1.4 | `name = "NativeTTS (AVSpeechSynthesizer)"`，`isLoaded = true`，基于 `AVSpeechSynthesizer.write(_:toBufferCallback:)` 收集 PCM Buffer 编码为 WAV（44 字节 RIFF/WAVE 头）；CI 环境返回最小空 WAV 头；30s 超时保护 |
| `MLXVoiceTTSEngine` | v1.6 计划 | 基于 MLX-Voice（Kokoro/Matcha-TTS） |

#### 9.1.4 VoiceCloner（语音克隆）

```swift
public protocol VoiceCloner: Sendable {
    var isLoaded: Bool { get }
    var clonedVoices: [ClonedVoice] { get }
    func loadModel(at modelPath: URL) async throws
    func clone(audioPath: URL, voiceName: String) async throws -> ClonedVoice
    func deleteVoice(voiceId: String) async
    func voice(forId voiceId: String) -> ClonedVoice?
}
```

| 实现 | 版本 | 说明 |
|------|------|------|
| `PlaceholderVoiceCloner` | v1.3 | 占位，未加载抛 `engineNotLoaded`；克隆返回 `embeddingBase64 = ""` 的占位音色 |
| `OpenVoiceCloner` | v1.6 计划 | 基于 OpenVoice v2 蒸馏模型，提取音色嵌入存 Keychain |

`ClonedVoice` 结构：

```swift
public struct ClonedVoice: Sendable, Equatable, Identifiable {
    public let id: String          // UUID
    public let name: String        // 用户自定义名
    public let createdAt: Date
    public let sampleAudioPath: URL
    public let embeddingBase64: String  // 音色嵌入（Base64，存 Keychain）
}
```

#### 9.1.5 ImageGenerationEngine（图像生成）

```swift
public protocol ImageGenerationEngine: Sendable {
    var name: String { get }
    var isLoaded: Bool { get }
    func loadModel(at modelPath: URL) async throws
    func unloadModel() async
    func generate(
        prompt: String,
        negativePrompt: String?,
        width: Int,
        height: Int,
        steps: Int,
        seed: UInt64?
    ) async throws -> CGImage
}
```

| 实现 | 版本 | 说明 |
|------|------|------|
| `PlaceholderImageGenerationEngine` | v1.3 | 占位，`name = "PlaceholderImageGen"`，`isLoaded = false`，`generate` 抛 `platformUnsupported` |
| `SDMobileEngine` | v1.6 计划 | 基于 Stable Diffusion Mobile / CoreML 量化 |

### 9.2 MultimodalFacade 公共 API

```swift
public actor MultimodalFacade {
    public static let shared = MultimodalFacade()
    public init()  // v1.4: 默认 NativeVisionEngine / NativeASREngine / NativeTTSEngine + 占位 VoiceCloner / ImageGen
    public init(visionEngine:asrEngine:ttsEngine:voiceCloner:imageGenEngine:budget:)  // 测试可注入

    // 引擎切换（依赖注入）
    public func setVisionEngine(_ engine: VisionInferenceEngine)
    public func setASREngine(_ engine: ASREngine)
    public func setTTSEngine(_ engine: TTSEngine)
    public func setVoiceCloner(_ cloner: VoiceCloner)
    public func setImageGenEngine(_ engine: ImageGenerationEngine)

    // 引擎状态查询
    public var visionEngineName: String { get }
    public var asrEngineName: String { get }
    public var ttsEngineName: String { get }
    public var voiceClonerName: String { get }
    public var imageGenEngineName: String { get }

    // VLM 图像理解
    public func describeImage(at imagePath: URL, prompt: String) async throws -> String
    // ASR 语音识别
    public func transcribeAudio(at audioPath: URL, language: String = "zh") async throws -> String
    // TTS 语音合成
    public func synthesizeSpeech(text: String, voiceId: String? = nil) async throws -> Data
    // 语音克隆
    public func cloneVoice(audioPath: URL, voiceName: String) async throws -> ClonedVoice
    public func clonedVoices() async -> [ClonedVoice]
    public func deleteVoice(voiceId: String) async
    // 图像生成
    public func generateImage(
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 20,
        seed: UInt64? = nil
    ) async throws -> CGImage

    // 内存预算快照
    public func budgetSnapshot() async -> BudgetSnapshot
}
```

### 9.3 工具方法行为约定

| 方法 | 输入校验 | 错误抛出 | 返回值 |
|------|----------|----------|--------|
| `describeImage(at:prompt:)` | `prompt.isEmpty` → `emptyInput`；图片格式不支持（非 JPEG/PNG/HEIC）→ `unsupportedImageFormat` | `MultimodalError` | VLM 生成的中文描述字符串 |
| `transcribeAudio(at:language:)` | 文件不存在 → `emptyInput`；扩展名非 wav/caf/m4a/mp3/aac → `unsupportedAudioFormat`（由 NativeASREngine 抛出） | `MultimodalError` | 识别到的文字（可能为空字符串） |
| `synthesizeSpeech(text:voiceId:)` | `text.isEmpty` → `emptyInput` | `MultimodalError` | WAV 格式 `Data`（至少 44 字节头部，含 RIFF/WAVE 标识） |
| `cloneVoice(audioPath:voiceName:)` | 未加载 → `engineNotLoaded`；音频 <5s → `audioTooShort`；格式不支持 → `unsupportedAudioFormat` | `MultimodalError` | `ClonedVoice`（含 id / name / sampleAudioPath / embeddingBase64） |
| `generateImage(prompt:...)` | `prompt.isEmpty` → `emptyInput`；占位实现 → `platformUnsupported` | `MultimodalError` | `CGImage` |

### 9.4 MultimodalError 错误类型

```swift
public enum MultimodalError: LocalizedError, Sendable, Equatable {
    case engineNotLoaded                       // 引擎未加载模型
    case emptyInput                            // 输入为空
    case unsupportedImageFormat               // 仅支持 JPEG/PNG/HEIC
    case unsupportedAudioFormat               // 仅支持 WAV/CAF/m4a
    case unsupportedSampleRate(actual: Double)
    case audioTooShort(actualSeconds: Double, requiredSeconds: Double)
    case memoryBudgetExceeded(requestedMB: Int, availableMB: Int)
    case deviceCapabilityInsufficient(required: String, actual: String)
    case vlmInferenceFailed(message: String)
    case asrRecognitionFailed(message: String)
    case ttsSynthesisFailed(message: String)
    case voiceCloneFailed(message: String)
    case imageGenerationFailed(message: String)
    case ocrFailed(message: String)
    case modelDownloadFailed(message: String)
    case platformUnsupported                  // 当前平台不支持
}
```

- `errorDescription`：用户友好的本地化描述（NSLocalizedString）
- `diagnosticDescription`：含底层信息的诊断字符串，用于日志输出

### 9.5 MemoryBudget 与 DeviceCapability

#### MemoryBudget

```swift
public actor MemoryBudget {
    public static let shared = MemoryBudget()
    public init()                                  // 按 DeviceCapability.current 自动配置总预算
    public init(totalBudgetMB: Int)                // 测试可注入

    public var total: Int { get }                   // 总预算（MB）
    public var used: Int { get }                    // 已用（MB）
    public var available: Int { get }               // 剩余（MB）
    public var peak: Int { get }                    // 历史峰值（MB）

    public func reserve(mb: Int) async throws -> Int   // 申请内存，返回剩余
    public func release(mb: Int) async -> Int           // 释放内存
    public func reset() async                          // 释放所有（仅测试）
    public func snapshot() async -> BudgetSnapshot      // 状态快照
}
```

#### BudgetSnapshot

```swift
public struct BudgetSnapshot: Sendable, Equatable {
    public let totalMB: Int
    public let usedMB: Int
    public let availableMB: Int
    public let peakMB: Int
    public let utilization: Double            // 0.0 - 1.0
    public var utilizationPercentage: Double  // 0-100，保留 1 位小数
}
```

#### DeviceCapability

```swift
public enum DeviceCapability: String, Sendable, Equatable, CaseIterable {
    case low      // iPhone SE / 14 及以下，仅支持 0.5B
    case medium   // iPhone 15 / 15 Plus，1B
    case high     // iPhone 15 Pro / 16，2B VLM
    case ultra    // iPad Pro M4 / Mac，7B+ 模型

    public var displayName: String
    public var maxVLMScale: Int                // 0 / 1 / 2 / 11
    public var supportsVLM: Bool               // != .low
    public var supportsVoiceClone: Bool         // high / ultra
    public var supportsImageGeneration: Bool   // high / ultra
    public var recommendedMemoryBudgetMB: Int   // 1500 / 2500 / 3000 / 6000

    public static var current: DeviceCapability  // 自动检测
    public static func detect() -> DeviceCapability
}
```

### 9.6 LLM 工具调用入口

`MultimodalFacade` 的 4 个工具方法通过 `ToolRegistry` 注册为 LLM 可调用工具（v1.3 新增）：

| 工具名 | 函数名 | 参数（JSON Schema）| 底层调用 |
|--------|--------|--------------------|----------|
| `DescribeImageTool` | `describe_image` | `image_path: string`（必填）+ `prompt: string`（必填） | `facade.describeImage(at:prompt:)` |
| `TranscribeAudioTool` | `transcribe_audio` | `audio_path: string`（必填）+ `language: string`（默认 "zh"） | `facade.transcribeAudio(at:language:)` |
| `CloneVoiceTool` | `clone_voice` | `audio_path: string`（必填）+ `voice_name: string`（必填） | `facade.cloneVoice(audioPath:voiceName:)` |
| `GenerateImageTool` | `generate_image` | `prompt: string`（必填）+ `negative_prompt` / `width` / `height` / `steps` / `seed`（可选） | `facade.generateImage(prompt:...)` |

工具返回值为字符串形式（成功或错误描述），作为 `tool` role 消息回传 LLM 继续推理。

---

## 10. 跨平台 BFF HTTP 契约（v1.5.0 Windows + Android）

### 10.1 契约概览

v1.5.0 起 Windows 端（`windows/Aether.Windows/Services/AetherApiClient.cs`）与 Android 端（`android/app/src/main/java/com/aether/data/api/AetherApi.kt` + `ChatStreamClient.kt`）复用与 Apple 三端相同的 BFF（Cloudflare Workers）HTTP 契约。两端仅持 `userToken`（通过 `X-BFF-Token` header 注入），不持上游 LLM API Key；上游 Key 仅在 Cloudflare Workers 服务端 secrets 中。

| 端 | 客户端文件 | HTTP 库 | SSE 解析路径 |
|----|-----------|---------|-------------|
| Apple（iOS / iPad / macOS） | `Services/LLM/BFFProxyClient.swift` | `URLSession` | `SSEParser` / `AetherRust/SSE.swift` |
| Windows | `windows/Aether.Windows/Services/AetherApiClient.cs` | `HttpClient` | `JsonDocument`（默认）/ `AetherNativeBridge.ParseSseChunk`（`UseRustSse` 开关） |
| Android | `android/app/src/main/java/com/aether/data/api/{AetherApi,ChatStreamClient}.kt` | Ktor `HttpClient` | `parseLineKotlin`（默认 / 回退）/ `SseBridge.parseWithTools`（`BuildConfig.USE_RUST_SSE` 开关） |

### 10.2 共享 BFF HTTP 端点清单

Windows 与 Android 共享以下 BFF HTTP 端点（路径相对于 `BffConfig.baseUrl`）：

| 方法 | 路径 | 用途 | 请求体 | 响应 |
|------|------|------|--------|------|
| `GET` | `/conversations` | 列出全部会话 | — | `Conversation[]` |
| `POST` | `/conversations` | 创建会话 | `{ "title": string }` | `Conversation` |
| `GET` | `/conversations/{id}` | 获取单个会话 | — | `Conversation` |
| `PATCH` | `/conversations/{id}` | 更新会话（标题 / 置顶） | `{ "title"?: string, "isPinned"?: bool }` | `Conversation` |
| `PUT` | `/conversations/{id}` | 更新会话（全量，Windows 端使用） | `Conversation` | — |
| `DELETE` | `/conversations/{id}` | 删除会话 | — | — |
| `GET` | `/conversations/{id}/messages` | 列出会话消息 | — | `ChatMessage[]` |
| `POST` | `/chat/stream` | SSE 流式聊天 | `ChatRequest` | `text/event-stream` |
| `DELETE` | `/messages/{id}` | 删除消息 | — | — |
| `POST` | `/messages/{id}/feedback` | 提交消息反馈 | `{ "isPositive": bool?, "citations": string[]? }` | — |
| `GET` | `/memory` | 列出全部记忆 | — | `Memory[]` |
| `POST` | `/memory` | 创建记忆 | `{ "content": string, "category": string, "importance": double }` | `Memory` |
| `POST` | `/memory/search` | 搜索记忆 | `{ "query": string, "limit": int }` | `Memory[]` |
| `DELETE` | `/memory/{id}` | 删除记忆 | — | — |
| `POST` | `/rag/search` | RAG 检索 | `{ "query": string, "limit": int }` | `DocumentChunk[]` |
| `POST` | `/health/summary` | 上传健康摘要 | `HealthSummary` | — |
| `GET` | `/health/summary/{date}` | 查询健康摘要 | — | `HealthSummary?` |

> **注**：Apple 端 `BFFProxyClient` 走 `<endpointURL>/v1/chat/completions` 与 `<endpointURL>/v1/embeddings`，与 BFF 内部 `/chat/stream` 路径不同。Windows / Android 直接走 `/chat/stream`（BFF 自定义 SSE 事件格式）。

### 10.3 鉴权约定

所有端点统一通过 `X-BFF-Token` HTTP header 携带 `userToken`：

```
X-BFF-Token: <user-token-from-bff-config-store>
```

- **Windows 端**：`AetherApiClient` 构造时通过 `_http.DefaultRequestHeaders.Add("X-BFF-Token", token)` 注入；`Refresh()` 方法在配置变更后重新读取并更新默认头。
- **Android 端**：`AetherApi.withAuth()` 扩展函数统一 `header("X-BFF-Token", config.userToken)`；`ChatStreamClient.streamChat` 在请求构造时显式注入。

### 10.4 SSE 事件格式

BFF 自定义 SSE 事件格式（与 Apple 端 `BFFProxyClient` 走的 OpenAI 兼容 SSE 不同）：

```
data: {"type":"delta","content":"你好"}

data: {"type":"delta","content":"！"}

data: {"type":"done"}

data: [DONE]
```

| 事件 | 含义 | 客户端处理 |
|------|------|-----------|
| `data: {"type":"delta","content":"..."}` | 文本增量 | 累积到 streamingText，触发 UI 刷新 |
| `data: {"type":"done"}` | 流式完成（BFF 自定义） | 结束流 |
| `data: [DONE]` | 流式终止（OpenAI 兼容） | 结束流 |

### 10.5 Windows 端 API 契约（AetherApiClient.cs）

```csharp
public class AetherApiClient
{
    public AetherApiClient(string baseUrl, string token);
    public AetherApiClient(BffConfigStore configStore);
    public bool UseRustSse { get; set; } = false;  // true 时启用 Rust DLL 解析 SSE
    public void Refresh();  // 配置变更后重新加载 BaseUrl / Token

    // 会话
    public Task<List<Conversation>?> GetConversationsAsync();
    public Task<Conversation?> CreateConversationAsync(string title);
    public Task DeleteConversationAsync(string id);
    public Task UpdateConversationAsync(Conversation conv);  // PUT（全量更新）

    // 消息
    public Task<List<ChatMessage>?> GetMessagesAsync(string conversationId);
    public async IAsyncEnumerable<string> StreamChatAsync(ChatRequest request,
        [EnumeratorCancellation] CancellationToken ct = default);  // SSE 流式
    public Task DeleteMessageAsync(string messageId);
    public Task SubmitFeedbackAsync(string messageId, bool? isPositive, List<string>? citations = null);

    // 记忆
    public Task<List<Memory>?> ListMemoryAsync();
    public Task<Memory?> CreateMemoryAsync(string content, string category = "context", double importance = 0.5);
    public Task<List<Memory>?> SearchMemoryAsync(string query, int limit = 5);
    public Task DeleteMemoryAsync(string id);
}
```

### 10.6 Android 端 API 契约（AetherApi.kt + ChatStreamClient.kt）

```kotlin
class AetherApi(private val client: HttpClient, private val config: BffConfig) {
    // 会话
    suspend fun listConversations(): List<Conversation>
    suspend fun createConversation(title: String): Conversation
    suspend fun getConversation(id: String): Conversation
    suspend fun updateConversation(id: String, title: String? = null, isPinned: Boolean? = null): Conversation  // PATCH（部分更新）
    suspend fun deleteConversation(id: String)

    // 消息
    suspend fun listMessages(conversationId: String): List<ChatMessage>
    suspend fun deleteMessage(messageId: String)
    suspend fun submitFeedback(messageId: String, isPositive: Boolean?, citations: List<String>? = null)

    // 记忆
    suspend fun listMemory(): List<Memory>
    suspend fun createMemory(content: String, category: String = "context", importance: Double = 0.5): Memory
    suspend fun searchMemory(query: String, limit: Int = 5): List<Memory>
    suspend fun deleteMemory(id: String)

    // RAG
    suspend fun searchDocuments(query: String, limit: Int = 3): List<DocumentChunk>

    // 健康
    suspend fun uploadHealthSummary(summary: HealthSummary)
    suspend fun getHealthSummary(date: String): HealthSummary?
}

class ChatStreamClient(private val client: HttpClient, private val config: BffConfig) {
    // SSE 流式聊天，返回 Flow<String>（每 yield 一段 delta content）
    fun streamChat(request: ChatRequest): Flow<String>
}
```

---

## 11. Rust FFI 契约（v1.5.0 Windows P/Invoke + Android JNI）

### 11.1 Windows 端 P/Invoke 契约（AetherNativeBridge.cs）

Windows 端通过 P/Invoke 调用 `aether_core_ffi.dll` 导出的 C ABI 函数。`AetherNativeBridge` 静态类声明原始 P/Invoke 并封装三个友好方法，`DllNotFoundException` 安全处理，DLL 不可用时返回 null / 0 / 原值兜底。

#### 11.1.1 C ABI 导出函数（`aether_core_ffi.dll`）

| C 函数签名 | 返回值 | 用途 |
|-----------|--------|------|
| `aether_sse_parse_chunk(const char* line)` | `char*`（JSON 字符串 `"null"` 或 `"\"...\""`，需 `aether_free_string` 释放） | 解析单行 SSE，返回 content 的 JSON 串；非 data 行或失败返回空指针 |
| `aether_cosine_f32(const float* a, uintptr_t a_len, const float* b, uintptr_t b_len)` | `float` | f32 余弦相似度；空指针或长度不等返回 0 |
| `aether_redact(const char* input)` | `char*`（NUL 结尾 UTF-8 字符串，需 `aether_free_string` 释放） | 对输入字符串脱敏（UUID / 邮箱 / URL / Token / 凭证 / 路径） |
| `aether_free_string(char* ptr)` | `void` | 释放上述函数返回的字符串；空指针安全 |

#### 11.1.2 C# 友好封装（`AetherNativeBridge`）

```csharp
public static class AetherNativeBridge
{
    // 解析单行 SSE，返回 content 字符串。DLL 不可用 / 非 data 行 / 无 content 返回 null。
    public static string? ParseSseChunk(string line);

    // f32 向量余弦相似度。长度不等或 DLL 不可用返回 0。
    public static float CosineF32(float[] a, float[] b);

    // 对输入字符串脱敏。DLL 不可用时原样返回输入。
    public static string Redact(string input);
}
```

**回退约定**：
- `ParseSseChunk` 返回 null 时，`AetherApiClient.StreamChatAsync` 自动回退到托管 `JsonDocument.Parse` 路径。
- `CosineF32` 返回 0 时调用方应视为「相似度不可用」。
- `Redact` 返回原值时调用方仍可继续处理（脱敏降级为不脱敏）。

### 11.2 Android 端 JNI 契约（libaether_core_ffi.so）

Android 端通过 JNI 调用 `libaether_core_ffi.so`，Rust 侧 `rust/aether-core-ffi/src/jni.rs` 暴露 4 个 `Java_com_aether_rust_*` 导出函数，按 `JNI_OnLoad` 的 `System.loadLibrary("aether_core_ffi")` 约定命名。

#### 11.2.1 JNI 导出函数签名

| JNI 函数签名 | 返回值 | 用途 |
|-------------|--------|------|
| `Java_com_aether_rust_SseBridge_parseWithTools(JNIEnv, jclass, jstring line)` | `jstring`（JSON `{"content":"...","toolCalls":[...]}`，解析失败返回空串 `""`） | 解析 SSE 行，使用 thread_local 累积器跨 chunk 累积 tool_calls |
| `Java_com_aether_rust_SseBridge_reset(JNIEnv, jclass)` | `void` | 清空 thread_local 累积器（新会话开始时调用） |
| `Java_com_aether_rust_VectorMath_cosineF64(JNIEnv, jclass, jdoubleArray a, jdoubleArray b)` | `jdouble` | f64 余弦相似度计算；空数组或长度不等返回 0.0 |
| `Java_com_aether_rust_Redact_redact(JNIEnv, jclass, jstring input)` | `jstring`（脱敏后字符串，解析失败返回空串） | 敏感信息脱敏（UUID / 邮箱 / URL / Token / 凭证 / 路径） |

#### 11.2.2 Kotlin 声明（`rust/*.kt`）

```kotlin
object SseBridge {
    init { System.loadLibrary("aether_core_ffi") }
    external fun parseWithTools(line: String): String  // {"content":"...","toolCalls":[...]} 或 ""
    external fun reset()
}

object VectorMath {
    private val nativeLoaded: Boolean = try {
        System.loadLibrary("aether_core_ffi"); true
    } catch (e: UnsatisfiedLinkError) { false }
    external fun cosineF64(a: DoubleArray, b: DoubleArray): Double
    fun cosineF64Safe(a: DoubleArray, b: DoubleArray): Double  // JNI 不可用返回 0.0
}

object Redact {
    private val nativeLoaded: Boolean = try {
        System.loadLibrary("aether_core_ffi"); true
    } catch (e: UnsatisfiedLinkError) { false }
    external fun redact(input: String): String
    fun redactSafe(input: String): String  // JNI 不可用返回原值
}
```

#### 11.2.3 `parseWithTools` 返回格式

```json
{
  "content": "你好",
  "toolCalls": [
    {
      "id": "call_1",
      "type": "function",
      "name": "calculate",
      "arguments": "{\"expression\":\"1+2\"}"
    }
  ]
}
```

- `content`：当前 chunk 的文本增量；无 content 时为 `null`。
- `toolCalls`：累积后的全部工具调用列表（跨 chunk 拼接 `arguments`）；无工具调用时为 `null` 或空数组。
- 解析失败 / 非 data 行返回空串 `""`，调用方据此回退到纯 Kotlin 解析。

#### 11.2.4 回退约定

- `SseBridge`：`init` 块抛 `UnsatisfiedLinkError` 会导致 object 永久初始化失败（后续访问抛 `NoClassDefFoundError`），因此 `VectorMath` / `Redact` 改用 `nativeLoaded` 标记 + `*Safe` 包装方法。
- `ChatStreamClient.parseLine` 捕获 `Throwable` 后回退到 `parseLineKotlin`。
- `VectorMath.cosineF64Safe` / `Redact.redactSafe` 在 `nativeLoaded = false` 时直接返回 0.0 / 原值，不抛异常。

---

## 12. 数据模型契约（v1.5.0 Windows + Android）

### 12.1 Windows 端数据模型（Models.cs）

Windows 端数据模型位于 `windows/Aether.Windows/Models/Models.cs`，使用 `System.Text.Json.Serialization.JsonPropertyName` 特性与 BFF DTO 字段一一对应。

```csharp
public class Conversation
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("systemPrompt")] public string SystemPrompt { get; set; } = "你是一个有帮助的AI助手。";
    [JsonPropertyName("parentId")] public string? ParentId { get; set; }
    [JsonPropertyName("createdAt")] public long CreatedAt { get; set; }
    [JsonPropertyName("updatedAt")] public long UpdatedAt { get; set; }
    [JsonPropertyName("lastMessagePreview")] public string LastMessagePreview { get; set; } = "";
    [JsonPropertyName("isPinned")] public bool IsPinned { get; set; }
}

public class ChatMessage
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("conversationId")] public string ConversationId { get; set; } = "";
    [JsonPropertyName("role")] public string Role { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("createdAt")] public long CreatedAt { get; set; }

    [IgnoreDataMember]  // FlowDocument 不可序列化，仅 UI 层持有
    public FlowDocument? MarkdownDocument { get; set; }
}

public class ChatRequest
{
    [JsonPropertyName("message")] public string Message { get; set; } = "";
    [JsonPropertyName("conversationId")] public string ConversationId { get; set; } = "";
    [JsonPropertyName("model")] public string Model { get; set; } = "deepseek-chat";
    [JsonPropertyName("memoryEnabled")] public bool MemoryEnabled { get; set; } = true;
}

public class Memory
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("category")] public string Category { get; set; } = "context";
    [JsonPropertyName("importance")] public double Importance { get; set; } = 0.5;
    [JsonPropertyName("createdAt")] public long CreatedAt { get; set; }
}
```

### 12.2 Android 端数据模型（Models.kt）

Android 端数据模型位于 `android/app/src/main/java/com/aether/data/model/Models.kt`，使用 `kotlinx.serialization.Serializable` 注解与 BFF DTO 一一对应。

```kotlin
@Serializable
data class Conversation(
    val id: String,
    val title: String,
    val systemPrompt: String = "你是一个有帮助的AI助手。",
    val parentId: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val lastMessagePreview: String = "",
    val isPinned: Boolean = false,
    val unreadCount: Int = 0,
    val order: Int = 0
)

@Serializable
data class ChatMessage(
    val id: String,
    val conversationId: String,
    val role: String,
    val content: String,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val toolName: String? = null,
    val feedback: Int? = null,
    val createdAt: Long
)

@Serializable
data class ToolCall(val id: String, val name: String, val arguments: String)

@Serializable
data class ChatRequest(
    val message: String,
    val conversationId: String,
    val model: String = "deepseek-chat",
    val memoryEnabled: Boolean = true
)

@Serializable
data class Memory(
    val id: String,
    val content: String,
    val category: String = "context",
    val importance: Double = 0.5,
    val createdAt: Long
)

@Serializable
data class MemorySearchRequest(val query: String, val limit: Int = 5)

@Serializable
data class DocumentChunk(
    val id: String,
    val documentId: String? = null,
    val content: String,
    val source: String = "",
    val chunkIndex: Int = 0,
    val weight: Float = 1.0f,
    val createdAt: Long
)

@Serializable
data class RagSearchRequest(val query: String, val limit: Int = 3)

@Serializable
data class HealthSummary(
    val date: String,
    val steps: Int? = null,
    val sleepHours: Double? = null,
    val restingHeartRate: Int? = null
)
```

### 12.3 与 BFF DTO 的映射关系

| 实体 | Windows（Models.cs） | Android（Models.kt） | Apple（SwiftData @Model / DTO） | BFF DTO 字段 |
|------|---------------------|---------------------|-------------------------------|-------------|
| Conversation | `Conversation` class | `Conversation` data class | `Conversation` @Model | `id` / `title` / `systemPrompt` / `parentId` / `createdAt` / `updatedAt` / `lastMessagePreview` / `isPinned` |
| ChatMessage | `ChatMessage` class（+ `MarkdownDocument` UI 字段） | `ChatMessage` data class（含 `toolCalls` / `toolCallId` / `toolName` / `feedback`） | `ChatMessage` @Model | `id` / `conversationId` / `role` / `content` / `createdAt` + 工具调用相关字段 |
| ChatRequest | `ChatRequest` class | `ChatRequest` data class | `ChatRequestBody` | `message` / `conversationId` / `model` / `memoryEnabled` |
| Memory | `Memory` class | `Memory` data class | `Memory` @Model | `id` / `content` / `category` / `importance` / `createdAt` |
| DocumentChunk | —（Windows 端未实现 RAG） | `DocumentChunk` data class | `DocumentChunk` @Model | `id` / `documentId` / `content` / `source` / `chunkIndex` / `weight` / `createdAt` |
| HealthSummary | —（Windows 端未实现 Health） | `HealthSummary` data class | `HealthDailySummary` | `date` / `steps` / `sleepHours` / `restingHeartRate` |

**关键差异**：
- **时间戳**：三端均使用 Unix 毫秒时间戳（`long` / `Int64`），与 BFF 一致。
- **可选字段**：Windows 用 `?` 可空类型 + `= ""` 默认值；Android 用 `? = null` 默认值；Apple 用 Swift Optional。
- **Android 扩展字段**：`Conversation` 包含 `unreadCount` / `order`（UI 排序用），`ChatMessage` 包含 `toolCalls` / `toolCallId` / `toolName` / `feedback`（工具调用与反馈），均为 BFF DTO 的超集。
- **Windows UI 字段**：`ChatMessage.MarkdownDocument`（`FlowDocument?`）用 `[IgnoreDataMember]` 标记，不参与 JSON 序列化，仅 UI 层持有。

---

## 13. 配置持久化契约（v1.5.0 Windows + Android）

### 13.1 Windows 端配置契约（BffConfigStore.cs）

Windows 端 BFF 配置位于 `windows/Aether.Windows/Services/BffConfigStore.cs`，使用 `%LOCALAPPDATA%/Aether/bff_config.json` 存 JSON，UserToken 通过 DPAPI（`ProtectedData.Protect`，`CurrentUser` 范围）加密为 Base64 存储。

#### 13.1.1 配置文件路径

- **目录**：`%LOCALAPPDATA%/Aether/`（即 `Environment.SpecialFolder.LocalApplicationData` + `Aether`）
- **文件**：`bff_config.json`
- **加密**：UserToken 通过 DPAPI `CurrentUser` 范围加密，仅当前 Windows 用户可解密

#### 13.1.2 配置字段

| 字段 | 类型 | JSON 键 | 加密 | 默认值 | 说明 |
|------|------|---------|------|--------|------|
| `BaseUrl` | `string` | `baseUrl` | 否 | `""` | BFF 服务端 URL |
| `UserToken` | `string` | `encryptedToken`（DPAPI 加密后 Base64） | 是 | `""` | BFF 用户 Token（明文仅存内存） |
| `DefaultModel` | `string` | `defaultModel` | 否 | `"deepseek-chat"` | 默认 LLM 模型 |
| `AccentColor` | `string` | `accentColor` | 否 | `""` | 主题色（预留） |
| `Language` | `string` | `language` | 否 | `""`（LanguageService 回退到 `zh-Hans`） | UI 语言代码 |

#### 13.1.3 加密流程

```csharp
// 加密（SaveAsync 时）
var bytes = Encoding.UTF8.GetBytes(plainToken);
var encrypted = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
_data.EncryptedToken = Convert.ToBase64String(encrypted);

// 解密（Load 时）
var bytes = Convert.FromBase64String(encryptedBase64);
var decrypted = ProtectedData.Unprotect(bytes, null, DataProtectionScope.CurrentUser);
_decryptedToken = Encoding.UTF8.GetString(decrypted);
```

#### 13.1.4 公开 API

```csharp
public class BffConfigStore
{
    public BffConfigStore(string? configPath = null);
    public void Load();                          // 同步加载
    public Task LoadAsync();                     // 异步加载
    public Task SaveAsync();                     // 异步保存（UserToken 加密后写入）

    public string BaseUrl { get; set; }
    public string UserToken { get; set; }        // 明文（仅内存）
    public string DefaultModel { get; set; }
    public string AccentColor { get; set; }
    public string Language { get; set; }
}
```

### 13.2 Android 端配置契约（BffConfigStore.kt）

Android 端 BFF 配置位于 `android/app/src/main/java/com/aether/data/api/BffConfigStore.kt`，采用双存储策略：非敏感数据用 `DataStore Preferences`，敏感数据（userToken）用 `EncryptedSharedPreferences`（`AES256-GCM` + `AES256-SIV`）。

#### 13.2.1 存储分层

| 数据类别 | 存储方式 | 文件 / 名称 | 加密 |
|---------|---------|------------|------|
| 非敏感（baseUrl / defaultModel / accentColor / language） | `DataStore Preferences` | `bff_config`（Preferences DataStore 文件名） | 否 |
| 敏感（userToken） | `EncryptedSharedPreferences` | `bff_secure_prefs`（文件名） | 是（`AES256-GCM` 值加密 + `AES256-SIV` 键加密） |

#### 13.2.2 配置字段

| 字段 | 类型 | 存储键 | 存储方式 | 默认值 | 说明 |
|------|------|--------|---------|--------|------|
| `baseUrl` | `String` | `base_url` | DataStore | `BuildConfig.BFF_BASE_URL` | BFF 服务端 URL |
| `userToken` | `String` | `user_token` | EncryptedSharedPreferences | `""` | BFF 用户 Token |
| `defaultModel` | `String` | `default_model` | DataStore | `"deepseek-chat"` | 默认 LLM 模型 |
| `accentColor` | `String` | `accent_color` | DataStore | `"purple"` | 主题色（purple / blue / glow） |
| `language` | `String` | `language` | DataStore | `DEFAULT_LANGUAGE`（`zh-Hans`） | UI 语言代码 |

#### 13.2.3 支持的语言代码

```kotlin
val SUPPORTED_LANGUAGES: List<String> = listOf(
    "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"
)
const val DEFAULT_LANGUAGE: String = "zh-Hans"
```

#### 13.2.4 加密细节

```kotlin
// MasterKey 基于 AES256-GCM
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()

// EncryptedSharedPreferences
val encryptedPrefs = EncryptedSharedPreferences.create(
    context,
    "bff_secure_prefs",
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,    // 键加密
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM   // 值加密
)
```

#### 13.2.5 公开 API

```kotlin
class BffConfigStore(private val context: Context) {
    val config: Flow<BffConfig>          // 订阅配置变化
    val defaultModel: Flow<String>
    val accentColor: Flow<String>
    val language: Flow<String>

    suspend fun setBaseUrl(url: String)
    fun setUserToken(token: String)      // 同步写入 EncryptedSharedPreferences
    suspend fun setDefaultModel(model: String)
    suspend fun setAccentColor(accent: String)
    suspend fun setLanguage(code: String)  // 需在 SUPPORTED_LANGUAGES 列表内
}
```

### 13.3 跨平台配置契约对比

| 维度 | Windows（BffConfigStore.cs） | Android（BffConfigStore.kt） | Apple（BFFConfig.swift） |
|------|-----------------------------|------------------------------|-------------------------|
| 存储位置 | `%LOCALAPPDATA%/Aether/bff_config.json` | DataStore + EncryptedSharedPreferences | UserDefaults（键 `bff_config_cache`） |
| 加密算法 | DPAPI `CurrentUser` | `AES256-GCM` + `AES256-SIV` | 无（Keychain 单独存 API Key） |
| 配置形态 | 单 JSON 文件 | 双存储（DataStore + EncryptedPrefs） | JSON 编码后存 UserDefaults |
| 异步 API | `LoadAsync` / `SaveAsync`（Task） | `Flow<*>` 订阅 + `suspend` 写入 | 同步（`@MainActor`） |
| 字段集 | BaseUrl / UserToken / DefaultModel / AccentColor / Language | BaseUrl / UserToken / DefaultModel / AccentColor / Language | enabled / endpointURL / userToken / chatRateLimitPerMin / embedRateLimitPerMin |
| 语言支持 | 8 种（zh-Hans / zh-Hant / en / ja / ko / fr / de / es） | 8 种（同 Windows） | 9 种（含「跟随系统」选项） |

---

## 相关文档

- [ARCHITECTURE.md](ARCHITECTURE.md) — 架构总览与模块职责
- [USAGE.md](USAGE.md) — 使用指南
- [BFF_DEPLOYMENT.md](BFF_DEPLOYMENT.md) — BFF 代理层部署指南
