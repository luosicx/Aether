# `AetherClient`

The unified entry point for the Aether SDK.

## Overview

`AetherClient` is the primary class third-party developers interact with. It encapsulates:

- LLM chat completion (single-turn and streaming)
- Batch text embedding
- RAG retrieval (via injected ``AetherRAGProvider``)
- Custom tool registration and execution
- Semantic cache for query deduplication
- Automatic retry with exponential backoff

## Initialization

```swift
import AetherSDK

let config = AetherConfig(
    provider: .deepSeek,
    apiKey: "sk-your-api-key",
    cache: .default,
    auth: .apiKey
)
let client = try AetherClient(config: config)
```

For `onDevice` provider or custom RAG/embedding backends, use the injection initializer:

```swift
let client = try AetherClient(
    config: config,
    provider: myLLMProvider,
    ragProvider: myRAGProvider,
    embeddingProvider: myEmbeddingProvider
)
```

## Chat

```swift
let response = try await client.chat(messages: [
    .system("You are a helpful assistant."),
    .user("What is the capital of France?")
])
print(response) // "Paris"
```

## Streaming

```swift
for await chunk in client.stream(messages: [.user("Tell me a story")]) {
    if let content = chunk.content {
        print(content, terminator: "")
    }
}
```

## Embedding

```swift
let vectors = try await client.embed(texts: ["hello", "world"])
// vectors: [[Float]]
```

## RAG Retrieval

```swift
let docs = try await client.retrieve(query: "machine learning", topK: 5)
for doc in docs {
    print("\(doc.source): \(doc.content) (score: \(doc.score))")
}
```

## Custom Tools

```swift
struct WeatherTool: AetherTool {
    let definition = AetherToolDefinition(
        name: "get_weather",
        description: "Get current weather for a city",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ]
    )

    func execute(arguments: [String: Any]) async throws -> String {
        let city = arguments["city"] as? String ?? "unknown"
        return "Sunny, 22°C in \(city)"
    }
}

client.register(tool: WeatherTool())
client.setToolPermission(name: "get_weather", .alwaysAllow)
```

## Topics

### Core Methods

- ``chat(messages:tools:)``
- ``stream(messages:tools:)``
- ``embed(texts:)``
- ``retrieve(query:topK:)``

### Tool Management

- ``register(tool:)``
- ``unregister(tool:)``
- ``setToolPermission(name:_:)``
