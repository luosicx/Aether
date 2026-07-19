# AetherSDKSample

Sample applications demonstrating the four core scenarios of **AetherSDK**.

## Scenarios

| Scenario | Description | File |
|----------|-------------|------|
| **Chat** | Single-turn chat conversation | `Chat/ChatSample.swift` |
| **Stream** | Streaming chat with typewriter effect | `Stream/StreamSample.swift` |
| **Tool Registration** | Custom `AetherTool` registration and LLM invocation | `ToolRegistration/ToolRegistrationSample.swift` |
| **RAG** | Retrieval-augmented generation with custom `AetherRAGProvider` | `RAG/RAGSample.swift` |

## Setup

These samples are standalone Swift files. To run them:

### Option 1: Xcode Project (Recommended)

1. Open Xcode → File → New → Project → macOS App (or iOS App)
2. Add the AetherCore SPM package:
   - File → Add Package Dependencies...
   - Enter the local path: `Packages/AetherCore`
   - Select the `AetherSDK` library
3. Copy the relevant sample file into your project
4. Replace `"sk-your-api-key"` with your actual DeepSeek API key
5. Run

### Option 2: Swift Script

```bash
# Requires Swift 5.9+ and the AetherCore package built
cd Examples/AetherSDKSample/Chat
swift run ChatSample.swift \
    -I ../../Packages/AetherCore/.build/debug \
    -L ../../Packages/AetherCore/.build/debug \
    -lAetherSDK
```

## Configuration

All samples use `AetherConfig` to configure the SDK:

```swift
let config = AetherConfig(
    provider: .deepSeek,        // or .qwen / .bff / .onDevice
    apiKey: "sk-your-api-key",  // DeepSeek API key
    cache: .default,            // Enable semantic cache
    auth: .apiKey,              // API Key authentication
    retryPolicy: .default       // 3 attempts, 1s/2s/4s backoff
)
```

## Notes

- The RAG sample uses a mock `SampleRAGProvider`. In production, bridge to your
  SwiftData `DocumentChunk` store or sqlite-vec index.
- The Tool Registration sample uses a mock `WeatherTool`. Replace with real API calls.
- All samples print output to stdout; integrate with SwiftUI/UIKit for UI versions.
