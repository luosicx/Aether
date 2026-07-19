// AetherSDKSample — Chat Scenario
//
// Demonstrates a single-turn chat conversation using AetherClient.
// Replace "sk-your-api-key" with your actual DeepSeek API key.

import AetherSDK
import Foundation

@main
struct ChatSample {
    static func main() async throws {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-your-api-key",
            cache: .default,
            auth: .apiKey,
            retryPolicy: .default
        )
        let client = try AetherClient(config: config)

        let messages: [AetherMessage] = [
            .system("You are a helpful assistant who answers concisely."),
            .user("What is the capital of France?")
        ]

        let response = try await client.chat(messages: messages)
        print("Assistant: \(response)")
    }
}
