# `AetherConfig`

The top-level configuration for ``AetherClient``.

## Overview

`AetherConfig` carries all the settings needed to construct an `AetherClient`:

- `provider`: LLM backend (DeepSeek / Qwen / BFF / OnDevice)
- `apiKey`: API key or OAuth token
- `baseURL`: Optional custom endpoint
- `cache`: Semantic cache configuration
- `rag`: RAG knowledge base configuration
- `rateLimit`: QPS and concurrency limits
- `auth`: Authentication scheme
- `retryPolicy`: Retry behavior

## Example

```swift
let config = AetherConfig(
    provider: .deepSeek,
    apiKey: "sk-your-key",
    baseURL: URL(string: "https://api.deepseek.com"),
    cache: CacheConfig(enabled: true, ttl: 3600, similarityThreshold: 0.92),
    rag: RAGConfig(knowledgeBaseID: "my-kb", topK: 5),
    rateLimit: RateLimitConfig(qps: 10, maxConcurrent: 4),
    auth: .apiKey,
    retryPolicy: .default
)
```

## Validation

`AetherConfig.validate()` checks the configuration and returns a `String?` describing
the first issue found, or `nil` if the config is valid:

```swift
if let issue = config.validate() {
    fatalError("Invalid config: \(issue)")
}
```

## Topics

### Sub-Configurations

- ``AetherProvider``
- ``CacheConfig``
- ``RAGConfig``
- ``RateLimitConfig``
- ``AuthConfig``
- ``RetryPolicy``
