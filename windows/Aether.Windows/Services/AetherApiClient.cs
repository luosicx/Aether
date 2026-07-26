using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using Aether.Windows.Models;
using Aether.Windows.Native;

namespace Aether.Windows.Services;

public class AetherApiClient
{
    private readonly HttpClient _http;
    private string _baseUrl;
    private string _token;
    private readonly BffConfigStore? _configStore;

    /// <summary>
    /// 是否使用 Rust native 实现（aether-core-ffi DLL）解析 SSE。
    /// 默认 false（托管 JsonDocument 路径），DLL 不可用时自动回退到托管路径。
    /// </summary>
    public bool UseRustSse { get; set; } = false;

    public AetherApiClient(string baseUrl, string token)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _token = token;
        _configStore = null;
        _http = new HttpClient();
        _http.DefaultRequestHeaders.Add("X-BFF-Token", token);
        _http.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
    }

    /// <summary>
    /// 从 BffConfigStore 动态读取 BaseUrl 与 Token 构造客户端。
    /// 配置变更后可调用 <see cref="Refresh"/> 重新加载。
    /// </summary>
    public AetherApiClient(BffConfigStore configStore)
    {
        _configStore = configStore;
        _baseUrl = (configStore.BaseUrl ?? "").TrimEnd('/');
        _token = configStore.UserToken ?? "";
        _http = new HttpClient();
        if (!string.IsNullOrEmpty(_token))
        {
            _http.DefaultRequestHeaders.Add("X-BFF-Token", _token);
        }
        _http.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
    }

    /// <summary>
    /// 从 BffConfigStore 重新读取 BaseUrl 与 Token，更新 HttpClient 默认头。
    /// 设置页保存配置后调用此方法使新配置立即生效。
    /// </summary>
    public void Refresh()
    {
        if (_configStore == null) return;
        _configStore.Load();
        _baseUrl = (_configStore.BaseUrl ?? "").TrimEnd('/');
        _token = _configStore.UserToken ?? "";

        // 更新 X-BFF-Token 默认请求头
        _http.DefaultRequestHeaders.Remove("X-BFF-Token");
        if (!string.IsNullOrEmpty(_token))
        {
            _http.DefaultRequestHeaders.Add("X-BFF-Token", _token);
        }
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

    /// <summary>更新会话（用于置顶 / 取消置顶等）。</summary>
    public async Task UpdateConversationAsync(Conversation conv)
    {
        await _http.PutAsJsonAsync($"{_baseUrl}/conversations/{conv.Id}", conv);
    }

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

            // Rust 路径：aether_sse_parse_chunk 内部处理 data: 前缀剥离与 [DONE]/ChatChunk 解析。
            // DLL 不可用时 ParseSseChunk 返回 null（不抛异常）；UseRustSse 默认 false，需确保 DLL 存在再启用。
            if (UseRustSse)
            {
                if (line.Contains("[DONE]")) yield break;
                var rustContent = AetherNativeBridge.ParseSseChunk(line);
                if (!string.IsNullOrEmpty(rustContent)) yield return rustContent;
                continue;
            }

            // 托管路径（默认）
            if (!line.StartsWith("data: ")) continue;

            var data = line.Substring(6).Trim();
            if (data == "[DONE]") yield break;
            if (string.IsNullOrEmpty(data)) continue;

            string? textToYield = null;
            try
            {
                using var doc = JsonDocument.Parse(data);
                if (doc.RootElement.TryGetProperty("type", out var typeEl))
                {
                    var type = typeEl.GetString();
                    if (type == "delta" && doc.RootElement.TryGetProperty("content", out var contentEl))
                    {
                        textToYield = contentEl.GetString();
                    }
                    else if (type == "done") yield break;
                }
            }
            catch (JsonException) { /* 忽略解析错误 */ }
            if (!string.IsNullOrEmpty(textToYield)) yield return textToYield;
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
