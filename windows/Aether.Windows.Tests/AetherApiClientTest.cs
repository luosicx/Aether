using System.Net;
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
        var json = JsonSerializer.Serialize(new List<Conversation>
        {
            new() { Id = "c1", Title = "对话1" },
            new() { Id = "c2", Title = "对话2" }
        });
        var handler = new StubHandler(json, "application/json");
        var http = new HttpClient(handler);
        var client = CreateClientWithStubHttp(http, SampleBaseUrl, SampleToken);

        var result = await client.GetConversationsAsync();

        Assert.NotNull(result);
        Assert.Equal(2, result!.Count);
        Assert.Equal("c1", result[0].Id);
        Assert.Equal("对话1", result[0].Title);
        Assert.Equal("c2", result[1].Id);
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
