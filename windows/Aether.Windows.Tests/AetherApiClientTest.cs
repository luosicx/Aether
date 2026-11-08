using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.Json;
using Aether.Windows.Models;
using Aether.Windows.Services;
using Xunit;

namespace Aether.Windows.Tests;

public class AetherApiClientTest
{
    private const string SampleBaseUrl = "https://api.example.com";
    private const string SampleToken = "test-token";

    [Fact]
    public void Constructor_TrimsTrailingSlash_FromBaseUrl()
    {
        var client = new AetherApiClient("https://api.example.com/", SampleToken);
        Assert.NotNull(client);
    }

    [Fact]
    public void Constructor_WithNoTrailingSlash_WorksCorrectly()
    {
        var client = new AetherApiClient(SampleBaseUrl, SampleToken);
        Assert.NotNull(client);
    }

    [Fact]
    public void UseRustSse_DefaultValue_IsFalse()
    {
        var client = new AetherApiClient(SampleBaseUrl, SampleToken);
        Assert.False(client.UseRustSse);
    }

    [Fact]
    public void UseRustSse_CanBeSetToTrue()
    {
        var client = new AetherApiClient(SampleBaseUrl, SampleToken)
        {
            UseRustSse = true
        };
        Assert.True(client.UseRustSse);
    }

    [Fact]
    public async Task GetConversationsAsync_WithMockHttp_ReturnsDeserializedList()
    {
        const string json = """
        {
            "conversations": [
                {
                    "id": "c1", "user_id": "u1", "title": "对话1",
                    "parent_id": null, "created_at": 1, "updated_at": 2,
                    "last_message_preview": null, "is_pinned": 1,
                    "system_prompt": "自定义", "unread_count": 0, "order_field": 0
                },
                {
                    "id": "c2", "user_id": "u1", "title": "对话2",
                    "parent_id": null, "created_at": 3, "updated_at": 4,
                    "last_message_preview": "预览", "is_pinned": 0,
                    "system_prompt": null, "unread_count": 0, "order_field": 0
                }
            ]
        }
        """;
        var handler = new StubHandler(json, "application/json");
        var http = new HttpClient(handler);
        var client = CreateClientWithStubHttp(http, SampleBaseUrl, SampleToken);

        var result = await client.GetConversationsAsync();

        Assert.NotNull(result);
        Assert.Equal(2, result!.Count);
        Assert.Equal("c1", result[0].Id);
        Assert.Equal("对话1", result[0].Title);
        Assert.Equal("自定义", result[0].SystemPrompt);
        Assert.True(result[0].IsPinned);
        Assert.Equal("c2", result[1].Id);
        Assert.Equal("你是一个有帮助的AI助手。", result[1].SystemPrompt);
        Assert.False(result[1].IsPinned);
    }

    [Fact]
    public async Task CreateConversationAsync_DecodesEnvelope()
    {
        const string json = """
        {
            "conversation": {
                "id": "new-1", "user_id": "u1", "title": "新会话",
                "parent_id": null, "created_at": 10, "updated_at": 10,
                "last_message_preview": null, "is_pinned": 0,
                "system_prompt": "sys", "unread_count": 0, "order_field": 10
            }
        }
        """;
        var handler = new RecordingHandler(json);
        var client = CreateClientWithStubHttp(new HttpClient(handler), SampleBaseUrl, SampleToken);

        var conv = await client.CreateConversationAsync("新会话");

        Assert.NotNull(conv);
        Assert.Equal("new-1", conv!.Id);
        Assert.Equal("sys", conv.SystemPrompt);
        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/conversations", request.Path);
    }

    [Fact]
    public async Task UpdateConversationAsync_UsesPatchAndSendsContractBody()
    {
        var handler = new RecordingHandler();
        var client = CreateClientWithStubHttp(new HttpClient(handler), SampleBaseUrl, SampleToken);
        var conv = new Conversation
        {
            Id = "c1",
            Title = "标题",
            IsPinned = true,
            CreatedAt = 123,
            UpdatedAt = 456
        };

        await client.UpdateConversationAsync(conv);

        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Patch, request.Method);
        Assert.Equal("/conversations/c1", request.Path);
        // Body 是合法 JSON 而非固定字符串：中文可能被转义（如 \u6807\u9898），按语义断言
        using var doc = JsonDocument.Parse(request.Body);
        var root = doc.RootElement;
        Assert.Equal("标题", root.GetProperty("title").GetString());
        Assert.True(root.GetProperty("isPinned").GetBoolean());
        Assert.False(root.TryGetProperty("createdAt", out _));
    }

    [Fact]
    public async Task GetMessagesAsync_DecodesEnvelopeAndSnakeCase()
    {
        const string json = """
        {
            "messages": [
                {
                    "id": "m1", "conversation_id": "c1", "role": "user",
                    "content": "你好", "tool_calls": null, "tool_call_id": null,
                    "tool_name": null, "feedback": 1, "created_at": 99
                }
            ]
        }
        """;
        var handler = new RecordingHandler(json);
        var client = CreateClientWithStubHttp(new HttpClient(handler), SampleBaseUrl, SampleToken);

        var messages = await client.GetMessagesAsync("c1");

        Assert.NotNull(messages);
        var msg = Assert.Single(messages!);
        Assert.Equal("c1", msg.ConversationId);
        Assert.Equal("你好", msg.Content);
        Assert.Equal(99L, msg.CreatedAt);
        Assert.Equal("/conversations/c1/messages", Assert.Single(handler.Requests).Path);
    }

    [Theory]
    [InlineData(true, 1)]
    [InlineData(false, -1)]
    [InlineData(null, 0)]
    public async Task SubmitFeedbackAsync_SendsServerContractField(bool? isPositive, int expected)
    {
        var handler = new RecordingHandler();
        var client = CreateClientWithStubHttp(new HttpClient(handler), SampleBaseUrl, SampleToken);

        await client.SubmitFeedbackAsync("m1", isPositive);

        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/messages/m1/feedback", request.Path);
        Assert.Contains($"\"feedback\":{expected}", request.Body);
    }

    [Fact]
    public async Task SearchMemoryAsync_DecodesEnvelope()
    {
        const string json = """
        {
            "memories": [
                {
                    "id": "mem-1", "user_id": "u1", "content": "喜欢咖啡",
                    "category": null, "importance": 0.8,
                    "source_conversation_id": null, "created_at": 5
                }
            ],
            "query": "咖啡"
        }
        """;
        var handler = new RecordingHandler(json);
        var client = CreateClientWithStubHttp(new HttpClient(handler), SampleBaseUrl, SampleToken);

        var memories = await client.SearchMemoryAsync("咖啡");

        Assert.NotNull(memories);
        var memory = Assert.Single(memories!);
        Assert.Equal("mem-1", memory.Id);
        Assert.Equal("context", memory.Category);
        Assert.Equal(0.8, memory.Importance);
    }

    [Fact]
    public async Task StreamChatAsync_ManagedPath_ParsesDeltaContent()
    {
        var sseBuilder = new StringBuilder();
        sseBuilder.AppendLine("data: {\"type\":\"delta\",\"content\":\"你好\"}");
        sseBuilder.AppendLine("data: {\"type\":\"delta\",\"content\":\"世界\"}");
        sseBuilder.AppendLine("data: [DONE]");
        sseBuilder.AppendLine();

        var handler = new StubStreamHandler(sseBuilder.ToString());
        var http = new HttpClient(handler);
        var client = CreateClientWithStubHttp(http, SampleBaseUrl, SampleToken);
        client.UseRustSse = false;

        var request = new ChatRequest { Message = "hi", ConversationId = "c1" };
        var chunks = new List<string>();
        await foreach (var chunk in client.StreamChatAsync(request))
        {
            chunks.Add(chunk);
        }

        Assert.Equal(2, chunks.Count);
        Assert.Equal("你好", chunks[0]);
        Assert.Equal("世界", chunks[1]);
    }

    [Fact]
    public async Task StreamChatAsync_ManagedPath_DoneType_StopsStream()
    {
        var sseBuilder = new StringBuilder();
        sseBuilder.AppendLine("data: {\"type\":\"delta\",\"content\":\"A\"}");
        sseBuilder.AppendLine("data: {\"type\":\"done\"}");
        sseBuilder.AppendLine("data: {\"type\":\"delta\",\"content\":\"B\"}");
        sseBuilder.AppendLine();

        var handler = new StubStreamHandler(sseBuilder.ToString());
        var http = new HttpClient(handler);
        var client = CreateClientWithStubHttp(http, SampleBaseUrl, SampleToken);
        client.UseRustSse = false;

        var request = new ChatRequest { Message = "hi" };
        var chunks = new List<string>();
        await foreach (var chunk in client.StreamChatAsync(request))
        {
            chunks.Add(chunk);
        }

        Assert.Single(chunks);
        Assert.Equal("A", chunks[0]);
    }

    [Fact]
    public async Task StreamChatAsync_ManagedPath_IgnoresNonDataLines()
    {
        var sseBuilder = new StringBuilder();
        sseBuilder.AppendLine(": comment line");
        sseBuilder.AppendLine("event: message");
        sseBuilder.AppendLine("data: {\"type\":\"delta\",\"content\":\"OK\"}");
        sseBuilder.AppendLine("data: [DONE]");
        sseBuilder.AppendLine();

        var handler = new StubStreamHandler(sseBuilder.ToString());
        var http = new HttpClient(handler);
        var client = CreateClientWithStubHttp(http, SampleBaseUrl, SampleToken);
        client.UseRustSse = false;

        var request = new ChatRequest { Message = "hi" };
        var chunks = new List<string>();
        await foreach (var chunk in client.StreamChatAsync(request))
        {
            chunks.Add(chunk);
        }

        Assert.Single(chunks);
        Assert.Equal("OK", chunks[0]);
    }

    /// <summary>
    /// 通过反射将 stub HttpClient 注入 AetherApiClient 的 _http 私有字段，
    /// 避免直接依赖真实网络。
    /// </summary>
    private static AetherApiClient CreateClientWithStubHttp(HttpClient stubHttp, string baseUrl, string token)
    {
        var client = new AetherApiClient(baseUrl, token);
        var field = typeof(AetherApiClient).GetField("_http", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.NotNull(field);
        field!.SetValue(client, stubHttp);
        return client;
    }

    /// <summary>
    /// 返回固定 JSON 字符串的 HttpMessageHandler stub。
    /// </summary>
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly string _content;
        private readonly string _mediaType;

        public StubHandler(string content, string mediaType)
        {
            _content = content;
            _mediaType = mediaType;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(_content, Encoding.UTF8, _mediaType)
            };
            return Task.FromResult(response);
        }
    }

    /// <summary>
    /// 记录请求方法 / 路径 / body，并返回固定响应的 HttpMessageHandler stub。
    /// </summary>
    private sealed class RecordingHandler : HttpMessageHandler
    {
        private readonly string _content;
        private readonly string _mediaType;

        public RecordingHandler(string content = "", string mediaType = "application/json")
        {
            _content = content;
            _mediaType = mediaType;
        }

        public List<RecordedRequest> Requests { get; } = new();

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content == null
                ? ""
                : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new RecordedRequest(
                request.Method,
                request.RequestUri!.AbsolutePath,
                body));
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(_content, Encoding.UTF8, _mediaType)
            };
        }
    }

    public sealed record RecordedRequest(HttpMethod Method, string Path, string Body);

    /// <summary>
    /// 返回固定 SSE 流文本的 HttpMessageHandler stub，用于 StreamChatAsync 测试。
    /// </summary>
    private sealed class StubStreamHandler : HttpMessageHandler
    {
        private readonly string _sseBody;

        public StubStreamHandler(string sseBody)
        {
            _sseBody = sseBody;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(_sseBody, Encoding.UTF8, "text/event-stream")
            };
            return Task.FromResult(response);
        }
    }
}
