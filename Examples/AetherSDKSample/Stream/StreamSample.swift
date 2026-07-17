// AetherSDKSample — Stream Scenario
//
// Demonstrates streaming chat using AetherClient.stream().
// Each chunk is printed as it arrives, simulating a typewriter effect.

import AetherSDK
import Foundation

@main
struct StreamSample {
    static func main() async throws {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-your-api-key"
        )
        let client = try AetherClient(config: config)

        print("Assistant: ", terminator: "")
        let stream = client.stream(messages: [.user("Write a haiku about Swift programming.")])
        for await chunk in stream {
            if let content = chunk.content {
                print(content, terminator: "")
                fflush(stdout)
            }
        }
        print() // newline
    }
}
