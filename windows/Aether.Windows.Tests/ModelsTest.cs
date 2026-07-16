using System.Text.Json;
using Aether.Windows.Models;
using Xunit;

namespace Aether.Windows.Tests;

public class ModelsTest
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    // ===== Conversation =====

    [Fact]
    public void Conversation_DefaultValues_AreCorrect()
    {
        var conv = new Conversation();
        Assert.Equal(string.Empty, conv.Id);
        Assert.Equal(string.Empty, conv.Title);
        Assert.Equal("你是一个有帮助的AI助手。", conv.SystemPrompt);
        Assert.Null(conv.ParentId);
        Assert.Equal(0L, conv.CreatedAt);
        Assert.Equal(0L, conv.UpdatedAt);
        Assert.Equal(string.Empty, conv.LastMessagePreview);
        Assert.False(conv.IsPinned);
    }

    [Fact]
    public void Conversation_JsonRoundtrip_PreservesAllFields()
    {
        var conv = new Conversation
        {
            Id = "conv-123",
            Title = "测试对话",
            SystemPrompt = "自定义 prompt",
            ParentId = "parent-456",
            CreatedAt = 1700000000,
            UpdatedAt = 1700000100,
            LastMessagePreview = "预览内容",
            IsPinned = true
        };

        var json = JsonSerializer.Serialize(conv);
        var deserialized = JsonSerializer.Deserialize<Conversation>(json, JsonOptions);

        Assert.NotNull(deserialized);
        Assert.Equal(conv.Id, deserialized!.Id);
        Assert.Equal(conv.Title, deserialized.Title);
        Assert.Equal(conv.SystemPrompt, deserialized.SystemPrompt);
        Assert.Equal(conv.ParentId, deserialized.ParentId);
        Assert.Equal(conv.CreatedAt, deserialized.CreatedAt);
        Assert.Equal(conv.UpdatedAt, deserialized.UpdatedAt);
        Assert.Equal(conv.LastMessagePreview, deserialized.LastMessagePreview);
        Assert.Equal(conv.IsPinned, deserialized.IsPinned);
    }

    [Fact]
    public void Conversation_JsonDeserialize_FromRawJson()
    {
        const string json = """
        {
            "id": "c1",
            "title": "Hello",
            "systemPrompt": "sys",
            "parentId": "p1",
            "createdAt": 100,
            "updatedAt": 200,
            "lastMessagePreview": "preview",
            "isPinned": true
        }
        """;

        var conv = JsonSerializer.Deserialize<Conversation>(json, JsonOptions);
        Assert.NotNull(conv);
        Assert.Equal("c1", conv!.Id);
        Assert.Equal("Hello", conv.Title);
        Assert.Equal("sys", conv.SystemPrompt);
        Assert.Equal("p1", conv.ParentId);
        Assert.Equal(100L, conv.CreatedAt);
        Assert.Equal(200L, conv.UpdatedAt);
        Assert.Equal("preview", conv.LastMessagePreview);
        Assert.True(conv.IsPinned);
    }

    // ===== ChatMessage =====

    [Fact]
    public void ChatMessage_DefaultValues_AreCorrect()
    {
        var msg = new ChatMessage();
        Assert.Equal(string.Empty, msg.Id);
        Assert.Equal(string.Empty, msg.ConversationId);
        Assert.Equal(string.Empty, msg.Role);
        Assert.Equal(string.Empty, msg.Content);
        Assert.Equal(0L, msg.CreatedAt);
    }

    [Fact]
    public void ChatMessage_JsonRoundtrip_PreservesAllFields()
    {
        var msg = new ChatMessage
        {
            Id = "msg-1",
            ConversationId = "conv-1",
            Role = "user",
            Content = "你好",
            CreatedAt = 1700000200
        };

        var json = JsonSerializer.Serialize(msg);
        var deserialized = JsonSerializer.Deserialize<ChatMessage>(json, JsonOptions);

        Assert.NotNull(deserialized);
        Assert.Equal(msg.Id, deserialized!.Id);
        Assert.Equal(msg.ConversationId, deserialized.ConversationId);
        Assert.Equal(msg.Role, deserialized.Role);
        Assert.Equal(msg.Content, deserialized.Content);
        Assert.Equal(msg.CreatedAt, deserialized.CreatedAt);
    }

    // ===== ChatRequest =====

    [Fact]
    public void ChatRequest_DefaultValues_AreCorrect()
    {
        var req = new ChatRequest();
        Assert.Equal(string.Empty, req.Message);
        Assert.Equal(string.Empty, req.ConversationId);
        Assert.Equal("deepseek-chat", req.Model);
        Assert.True(req.MemoryEnabled);
    }

    [Fact]
    public void ChatRequest_JsonSerialize_ProducesExpectedFields()
    {
        var req = new ChatRequest
        {
            Message = "测试消息",
            ConversationId = "conv-1",
            Model = "gpt-4",
            MemoryEnabled = false
        };

        var json = JsonSerializer.Serialize(req);
        Assert.Contains("\"message\":\"测试消息\"", json);
        Assert.Contains("\"conversationId\":\"conv-1\"", json);
        Assert.Contains("\"model\":\"gpt-4\"", json);
        Assert.Contains("\"memoryEnabled\":false", json);
    }

    // ===== Memory =====

    [Fact]
    public void Memory_DefaultValues_AreCorrect()
    {
        var mem = new Memory();
        Assert.Equal(string.Empty, mem.Id);
        Assert.Equal(string.Empty, mem.Content);
        Assert.Equal("context", mem.Category);
        Assert.Equal(0.5, mem.Importance);
        Assert.Equal(0L, mem.CreatedAt);
    }

    [Fact]
    public void Memory_JsonRoundtrip_PreservesAllFields()
    {
        var mem = new Memory
        {
            Id = "mem-1",
            Content = "用户偏好",
            Category = "preference",
            Importance = 0.9,
            CreatedAt = 1700000300
        };

        var json = JsonSerializer.Serialize(mem);
        var deserialized = JsonSerializer.Deserialize<Memory>(json, JsonOptions);

        Assert.NotNull(deserialized);
        Assert.Equal(mem.Id, deserialized!.Id);
        Assert.Equal(mem.Content, deserialized.Content);
        Assert.Equal(mem.Category, deserialized.Category);
        Assert.Equal(mem.Importance, deserialized.Importance);
        Assert.Equal(mem.CreatedAt, deserialized.CreatedAt);
    }
}
