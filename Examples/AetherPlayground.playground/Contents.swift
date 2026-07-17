import AetherSDK
import Foundation

// Welcome to Aether Playground!
// This playground demonstrates the basic AetherSDK API.
// Replace the API key below with your actual DeepSeek API key to run live.

let apiKey = "sk-your-api-key"

// MARK: - 1. Configuration

let config = AetherConfig(
    provider: .deepSeek,
    apiKey: apiKey,
    cache: .default,
    auth: .apiKey,
    retryPolicy: .default
)

do {
    let client = try AetherClient(config: config)

    // MARK: - 2. Single-turn Chat

    Task {
        let response = try await client.chat(messages: [
            .system("You are a concise assistant."),
            .user("What is 2 + 2?")
        ])
        print("Chat response: \(response)")
    }

    // MARK: - 3. Streaming

    Task {
        print("Streaming: ", terminator: "")
        let stream = client.stream(messages: [.user("Count from 1 to 5.")])
        for await chunk in stream {
            if let content = chunk.content {
                print(content, terminator: "")
            }
        }
        print()
    }

    // MARK: - 4. Embedding

    Task {
        let vectors = try await client.embed(texts: ["hello", "world"])
        print("Embedding dimensions: \(vectors.first?.count ?? 0)")
        print("First vector prefix: \(vectors.first?.prefix(5) ?? [])")
    }

    // MARK: - 5. Custom Tool

    struct EchoTool: AetherTool {
        let definition = AetherToolDefinition(
            name: "echo",
            description: "Echo back the input text",
            parameters: [
                "type": "object",
                "properties": ["text": ["type": "string"]],
                "required": ["text"]
            ]
        )

        func execute(arguments: [String: Any]) async throws -> String {
            "echo: \(arguments["text"] ?? "")"
        }
    }

    client.register(tool: EchoTool())
    print("Registered tools: \(client.registeredToolNames)")

    // Keep playground alive for async tasks
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))

} catch {
    print("Failed to create client: \(error)")
}
