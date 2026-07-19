# `AetherError`

The unified error type for the Aether SDK.

## Overview

`AetherError` covers eight categories of errors that can occur during SDK operations:

| Case | When | Retryable |
|------|------|-----------|
| ``AetherError/authFailed(reason:)`` | HTTP 401, invalid token | No |
| ``AetherError/rateLimited(retryAfter:)`` | HTTP 429 | Yes |
| ``AetherError/providerError(code:message:)`` | Upstream 4xx/5xx | 502/503/504 only |
| ``AetherError/networkUnreachable`` | Offline, DNS failure | Yes |
| ``AetherError/toolExecutionFailed(name:errorDescription:)`` | Tool threw an error | No |
| ``AetherError/ragRetrievalFailed(reason:)`` | RAG provider error | No |
| ``AetherError/invalidConfig(reason:)`` | Bad configuration | No |
| ``AetherError/onDeviceInferenceFailed(error:)`` | Local inference failure | No |

## Retry Behavior

Use ``AetherError/isRetryable`` to check whether ``RetryPolicy`` will retry the error:

```swift
do {
    let response = try await client.chat(messages: [.user("hi")])
} catch let error as AetherError {
    if error.isRetryable {
        // SDK will automatically retry per RetryPolicy
    } else {
        // Non-retryable; surface to user
    }
}
```

## Conversion from LLMError

Use ``AetherError/from(_:)`` to convert from the underlying `LLMError`:

```swift
do {
    let result = try await provider.embed(texts: ["hi"], apiKey: key)
} catch let error as LLMError {
    let aetherError = AetherError.from(error)
    // handle aetherError
}
```

## Topics

### Error Cases

- ``AetherError/authFailed(reason:)``
- ``AetherError/rateLimited(retryAfter:)``
- ``AetherError/providerError(code:message:)``
- ``AetherError/networkUnreachable``
- ``AetherError/toolExecutionFailed(name:errorDescription:)``
- ``AetherError/ragRetrievalFailed(reason:)``
- ``AetherError/invalidConfig(reason:)``
- ``AetherError/onDeviceInferenceFailed(error:)``

### Properties

- ``AetherError/isRetryable``
- ``AetherError/errorDescription``
