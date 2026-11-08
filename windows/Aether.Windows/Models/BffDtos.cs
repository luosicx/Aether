using System.Text.Json.Serialization;

namespace Aether.Windows.Models;

/// <summary>
/// BFF 线协议 DTO：Worker 返回 snake_case 字段且使用 envelope。
/// 仅用于网络层，通过 ToModel() 映射为界面使用的领域模型。
/// </summary>
public sealed class ConversationsEnvelope
{
    [JsonPropertyName("conversations")] public List<ConversationDto> Conversations { get; set; } = new();
}

public sealed class ConversationEnvelope
{
    [JsonPropertyName("conversation")] public ConversationDto? Conversation { get; set; }
}

public sealed class ConversationDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("system_prompt")] public string? SystemPrompt { get; set; }
    [JsonPropertyName("parent_id")] public string? ParentId { get; set; }
    [JsonPropertyName("created_at")] public long CreatedAt { get; set; }
    [JsonPropertyName("updated_at")] public long UpdatedAt { get; set; }
    [JsonPropertyName("last_message_preview")] public string? LastMessagePreview { get; set; }
    [JsonPropertyName("is_pinned")] public int IsPinned { get; set; }

    public Conversation ToModel() => new()
    {
        Id = Id,
        Title = Title,
        SystemPrompt = SystemPrompt ?? "你是一个有帮助的AI助手。",
        ParentId = ParentId,
        CreatedAt = CreatedAt,
        UpdatedAt = UpdatedAt,
        LastMessagePreview = LastMessagePreview ?? "",
        IsPinned = IsPinned != 0
    };
}

public sealed class MessagesEnvelope
{
    [JsonPropertyName("messages")] public List<MessageDto> Messages { get; set; } = new();
}

public sealed class MessageDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("conversation_id")] public string ConversationId { get; set; } = "";
    [JsonPropertyName("role")] public string Role { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("created_at")] public long CreatedAt { get; set; }

    public ChatMessage ToModel() => new()
    {
        Id = Id,
        ConversationId = ConversationId,
        Role = Role,
        Content = Content,
        CreatedAt = CreatedAt
    };
}

public sealed class MemoriesEnvelope
{
    [JsonPropertyName("memories")] public List<MemoryDto> Memories { get; set; } = new();
}

public sealed class MemoryEnvelope
{
    [JsonPropertyName("memory")] public MemoryDto? Memory { get; set; }
}

public sealed class MemoryDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("category")] public string? Category { get; set; }
    [JsonPropertyName("importance")] public double Importance { get; set; } = 0.5;
    [JsonPropertyName("created_at")] public long CreatedAt { get; set; }

    public Memory ToModel() => new()
    {
        Id = Id,
        Content = Content,
        Category = Category ?? "context",
        Importance = Importance,
        CreatedAt = CreatedAt
    };
}
