// AetherSDKSample — Tool Registration Scenario
//
// Demonstrates how to define a custom AetherTool, register it with AetherClient,
// and let the LLM call it during a conversation.

import AetherSDK
import Foundation

/// A sample tool that returns current weather for a city.
/// In production, replace with a real weather API call.
struct WeatherTool: AetherTool {
    let definition = AetherToolDefinition(
        name: "get_weather",
        description: "Get the current weather for a given city",
        parameters: [
            "type": "object",
            "properties": [
                "city": [
                    "type": "string",
                    "description": "City name, e.g. \"Shanghai\", \"Tokyo\""
                ]
            ],
            "required": ["city"]
        ]
    )

    func execute(arguments: [String: Any]) async throws -> String {
        let city = arguments["city"] as? String ?? "unknown"
        // Mock response — replace with OpenWeather API or similar
        return "Sunny, 22°C, humidity 65% in \(city)"
    }
}

@main
struct ToolRegistrationSample {
    static func main() async throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-your-api-key")
        let client = try AetherClient(config: config)

        // Register the custom tool
        client.register(tool: WeatherTool())
        // Sensitive tool: require user approval (UI layer enforces this)
        client.setToolPermission(name: "get_weather", .requireApproval)

        print("Registered tools: \(client.registeredToolNames)")

        let messages: [AetherMessage] = [
            .system("You can use the get_weather tool to answer weather questions."),
            .user("What's the weather in Shanghai?")
        ]

        let response = try await client.chat(messages: messages, tools: [WeatherTool()])
        print("Assistant: \(response)")
    }
}
