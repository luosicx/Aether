# AetherSDK

**Aether SDK** is the third-party integration entry for the Aether AI assistant platform.

## Overview

AetherSDK exposes a unified `AetherClient` providing four core APIs:

- ``AetherClient/chat(messages:tools:)`` — Single-turn chat
- ``AetherClient/stream(messages:tools:)`` — Streaming chat via `AsyncStream<AetherChunk>`
- ``AetherClient/embed(texts:)`` — Batch text embedding
- ``AetherClient/retrieve(query:topK:)`` — RAG retrieval

The SDK also supports custom tool registration via the ``AetherTool`` protocol,
four authentication schemes via ``AuthConfig``, and automatic retry via ``RetryPolicy``.

## Topics

### Getting Started

- ``AetherClient``
- ``AetherConfig``

### Messages and Streaming

- ``AetherMessage``
- ``AetherChunk``
- ``AetherToolCall``

### Tools

- ``AetherTool``
- ``AetherToolDefinition``
- ``ToolPermission``

### Authentication

- ``AuthConfig``
- ``OAuthCredential``
- ``JWTCredential``

### Errors and Retry

- ``AetherError``
- ``RetryPolicy``

### RAG

- ``AetherDocument``
- ``AetherRAGProvider``
- ``AetherEmbeddingProvider``
