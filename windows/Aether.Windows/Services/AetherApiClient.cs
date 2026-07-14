using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using Aether.Windows.Models;

namespace Aether.Windows.Services;

public class AetherApiClient
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _token;

    public AetherApiClient(string baseUrl, string token)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _token = token;
        _http = new HttpClient();
        _http.DefaultRequestHeaders.Add("X-BFF-Token", token);
        _http.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
    }

    // 会话
    public async Task<List<Conversation>?> GetConversationsAsync() =>
        await _http.GetFromJsonAsync<List<Conversation>>($"{_baseUrl}/conversations");

    public async Task<Conversation?> CreateConversationAsync(string title)
    {
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/conversations",
            new { title });
        return await response.Content.ReadFromJsonAsync<Conversation>();
    }

    public async Task DeleteConversationAsync(string id) =>
        await _http.DeleteAsync($"{_baseUrl}/conversations/{id}");

    public async Task<List<ChatMessage>?> GetMessagesAsync(string conversationId) =>
        await _http.GetFromJsonAsync<List<ChatMessage>>($"{_baseUrl}/conversations/{conversationId}/messages");

    // SSE 流式聊天
    public async IAsyncEnumerable<string> StreamChatAsync(ChatRequest request,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var content = new StringContent(
            JsonSerializer.Serialize(request),
            Encoding.UTF8,
            "application/json");

        var response = await _http.PostAsync($"{_baseUrl}/chat/stream", content, ct);
        response.EnsureSuccessStatusCode();

        using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);

        while (!reader.EndOfStream)
        {
            ct.ThrowIfCancellationRequested();
            var line = await reader.ReadLineAsync(ct);
            if (line == null) break;
            if (!line.StartsWith("data: ")) continue;

            var data = line.Substring(6).Trim();
            if (data == "[DONE]") yield break;
            if (string.IsNullOrEmpty(data)) continue;

            try
            {
                using var doc = JsonDocument.Parse(data);
                if (doc.RootElement.TryGetProperty("type", out var typeEl))
                {
                    var type = typeEl.GetString();
                    if (type == "delta" && doc.RootElement.TryGetProperty("content", out var contentEl))
                    {
                        var text = contentEl.GetString();
                        if (!string.IsNullOrEmpty(text)) yield return text;
                    }
                    else if (type == "done") yield break;
                }
            }
            catch (JsonException) { /* 忽略解析错误 */ }
        }
    }

    // 消息
    public async Task DeleteMessageAsync(string messageId) =>
        await _http.DeleteAsync($"{_baseUrl}/messages/{messageId}");

    public async Task SubmitFeedbackAsync(string messageId, bool? isPositive, List<string>? citations = null)
    {
        await _http.PostAsJsonAsync($"{_baseUrl}/messages/{messageId}/feedback",
            new { isPositive, citations });
    }

    // 记忆
    public async Task<List<Memory>?> ListMemoryAsync() =>
        await _http.GetFromJsonAsync<List<Memory>>($"{_baseUrl}/memory");

    public async Task<Memory?> CreateMemoryAsync(string content, string category = "context", double importance = 0.5)
    {
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/memory",
            new { content, category, importance });
        return await response.Content.ReadFromJsonAsync<Memory>();
    }

    public async Task<List<Memory>?> SearchMemoryAsync(string query, int limit = 5)
    {
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/memory/search",
            new { query, limit });
        return await response.Content.ReadFromJsonAsync<List<Memory>>();
    }

    public async Task DeleteMemoryAsync(string id) =>
        await _http.DeleteAsync($"{_baseUrl}/memory/{id}");
}
