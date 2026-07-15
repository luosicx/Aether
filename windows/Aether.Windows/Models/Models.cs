using System.Text.Json.Serialization;

namespace Aether.Windows.Models;

public class Conversation
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("systemPrompt")] public string SystemPrompt { get; set; } = "你是一个有帮助的AI助手。";
    [JsonPropertyName("parentId")] public string? ParentId { get; set; }
    [JsonPropertyName("createdAt")] public long CreatedAt { get; set; }
    [JsonPropertyName("updatedAt")] public long UpdatedAt { get; set; }
    [JsonPropertyName("lastMessagePreview")] public string LastMessagePreview { get; set; } = "";
    [JsonPropertyName("isPinned")] public bool IsPinned { get; set; }
}

public class ChatMessage
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("conversationId")] public string ConversationId { get; set; } = "";
    [JsonPropertyName("role")] public string Role { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("createdAt")] public long CreatedAt { get; set; }
}

public class ChatRequest
{
    [JsonPropertyName("message")] public string Message { get; set; } = "";
    [JsonPropertyName("conversationId")] public string ConversationId { get; set; } = "";
    [JsonPropertyName("model")] public string Model { get; set; } = "deepseek-chat";
    [JsonPropertyName("memoryEnabled")] public bool MemoryEnabled { get; set; } = true;
}

public class Memory
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("category")] public string Category { get; set; } = "context";
    [JsonPropertyName("importance")] public double Importance { get; set; } = 0.5;
    [JsonPropertyName("createdAt")] public long CreatedAt { get; set; }
}
