# `AetherTool`

The protocol for custom tool extensions.

## Overview

Third-party developers implement `AetherTool` to expose custom capabilities to the LLM.
Each tool has:

1. A ``definition`` describing its name, description, and JSON Schema parameters
2. An ``execute(arguments:)`` method that performs the actual work

Tools are registered with ``AetherClient/register(tool:)`` and can be invoked by the LLM
during a chat or stream conversation.

## Example

```swift
struct CalculatorTool: AetherTool {
    let definition = AetherToolDefinition(
        name: "calculate",
        description: "Evaluate a math expression",
        parameters: [
            "type": "object",
            "properties": [
                "expression": ["type": "string", "description": "Math expression, e.g. 1+2*3"]
            ],
            "required": ["expression"]
        ]
    )

    func execute(arguments: [String: Any]) async throws -> String {
        guard let expr = arguments["expression"] as? String else {
            return "Error: missing expression"
        }
        // ... evaluate expr ...
        return "42"
    }
}

let client = try AetherClient(config: config)
client.register(tool: CalculatorTool())
```

## Permissions

Each tool has a ``ToolPermission`` controlling whether the LLM can invoke it:

- `.alwaysAllow` (default): LLM can invoke without user confirmation
- `.requireApproval`: Sensitive tools that need user confirmation
- `.deny`: Tool is disabled and hidden from the LLM

```swift
client.setToolPermission(name: "calculate", .requireApproval)
```

## Topics

### Protocol and Types

- ``AetherTool``
- ``AetherToolDefinition``
- ``ToolPermission``
- ``AetherToolRegistry``
