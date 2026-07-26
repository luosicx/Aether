using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.Json;
using Aether.Windows.Models;
using Aether.Windows.Services;
using Aether.Windows.ViewModels;
using Xunit;

namespace Aether.Windows.Tests;

/// <summary>ConversationListViewModel 单元测试：加载、创建、删除、置顶。</summary>
public class ConversationListViewModelTest
{
    private const string SampleBaseUrl = "https://api.example.com";
    private const string SampleToken = "test-token";

    /// <summary>通过反射将 stub HttpClient 注入 AetherApiClient，避免真实网络调用。</summary>
    private static AetherApiClient CreateClientWithStubHttp(HttpClient stubHttp)
    {
        var client = new AetherApiClient(SampleBaseUrl, SampleToken);
        var field = typeof(AetherApiClient).GetField("_http", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.NotNull(field);
        field!.SetValue(client, stubHttp);
        return client;
    }

    [Fact]
    public async Task LoadAsync_PopulatesConversations_SortedByPinnedThenUpdatedAt()
    {
        var conversations = new List<Conversation>
        {
            new() { Id = "c1", Title = "对话1", IsPinned = false, UpdatedAt = 200 },
            new() { Id = "c2", Title = "对话2", IsPinned = true, UpdatedAt = 100 },
            new() { Id = "c3", Title = "对话3", IsPinned = false, UpdatedAt = 300 }
        };
        var json = JsonSerializer.Serialize(conversations);
        var handler = new StubHandler(_ => json);
        var api = CreateClientWithStubHttp(new HttpClient(handler));

        string? navigatedId = null;
        var vm = new ConversationListViewModel(api, id => navigatedId = id, () => { });

        await vm.LoadAsync();

        Assert.Equal(3, vm.Conversations.Count);
        // 置顶的排前面
        Assert.Equal("c2", vm.Conversations[0].Id);
        // 非置顶按 UpdatedAt 降序
        Assert.Equal("c3", vm.Conversations[1].Id);
        Assert.Equal("c1", vm.Conversations[2].Id);
        Assert.Equal("", vm.ErrorMessage);
        Assert.False(vm.IsLoading);
        Assert.Null(navigatedId);
    }

    [Fact]
    public async Task LoadAsync_ApiError_SetsErrorMessage()
    {
        var handler = new StubHandler(_ => throw new HttpRequestException("网络错误"));
        var api = CreateClientWithStubHttp(new HttpClient(handler));

        var vm = new ConversationListViewModel(api, _ => { }, () => { });

        await vm.LoadAsync();

        Assert.Contains("加载会话失败", vm.ErrorMessage);
        Assert.False(vm.IsLoading);
    }

    [Fact]
    public async Task CreateAsync_NavigatesToNewConversation()
    {
        var newConv = new Conversation { Id = "new-123", Title = "新会话" };
        var handler = new StubHandler(_ => JsonSerializer.Serialize(newConv));
        var api = CreateClientWithStubHttp(new HttpClient(handler));

        string? navigatedId = null;
        var vm = new ConversationListViewModel(api, id => navigatedId = id, () => { });

        await vm.CreateAsync();

        Assert.Equal("new-123", navigatedId);
        Assert.Equal("", vm.ErrorMessage);
    }

    [Fact]
    public async Task DeleteAsync_RemovesConversationFromList()
    {
        var conversations = new List<Conversation>
        {
            new() { Id = "c1", Title = "对话1" },
            new() { Id = "c2", Title = "对话2" }
        };
        var json = JsonSerializer.Serialize(conversations);
        var handler = new StubHandler(_ => json);
        var api = CreateClientWithStubHttp(new HttpClient(handler));

        var vm = new ConversationListViewModel(api, _ => { }, () => { });
        await vm.LoadAsync();
        Assert.Equal(2, vm.Conversations.Count);

        await vm.DeleteAsync("c1");

        Assert.Single(vm.Conversations);
        Assert.Equal("c2", vm.Conversations[0].Id);
    }

    [Fact]
    public async Task TogglePinAsync_TogglesIsPinnedAndReorders()
    {
        var conversations = new List<Conversation>
        {
            new() { Id = "c1", Title = "对话1", IsPinned = false, UpdatedAt = 200 },
            new() { Id = "c2", Title = "对话2", IsPinned = false, UpdatedAt = 100 }
        };
        var json = JsonSerializer.Serialize(conversations);
        var handler = new StubHandler(_ => json);
        var api = CreateClientWithStubHttp(new HttpClient(handler));

        var vm = new ConversationListViewModel(api, _ => { }, () => { });
        await vm.LoadAsync();

        // 初始：c1 在前（UpdatedAt 更大）
        Assert.Equal("c1", vm.Conversations[0].Id);
        Assert.False(vm.Conversations[0].IsPinned);

        // 置顶 c2
        await vm.TogglePinAsync("c2");

        // c2 置顶后应排在前面
        Assert.Equal("c2", vm.Conversations[0].Id);
        Assert.True(vm.Conversations[0].IsPinned);
        Assert.Equal("c1", vm.Conversations[1].Id);
        Assert.False(vm.Conversations[1].IsPinned);

        // 取消置顶 c2
        await vm.TogglePinAsync("c2");

        Assert.False(vm.Conversations.First(c => c.Id == "c2").IsPinned);
    }

    [Fact]
    public void OpenSettingsCommand_InvokesNavigateToSettings()
    {
        var api = CreateClientWithStubHttp(new HttpClient(new StubHandler(_ => "")));
        bool settingsNavigated = false;
        var vm = new ConversationListViewModel(api, _ => { }, () => settingsNavigated = true);

        vm.OpenSettingsCommand.Execute(null);

        Assert.True(settingsNavigated);
    }

    [Fact]
    public void OpenConversationCommand_InvokesNavigateToChat()
    {
        var api = CreateClientWithStubHttp(new HttpClient(new StubHandler(_ => "")));
        string? navigatedId = null;
        var vm = new ConversationListViewModel(api, id => navigatedId = id, () => { });

        vm.OpenConversationCommand.Execute("conv-456");

        Assert.Equal("conv-456", navigatedId);
    }

    /// <summary>返回固定响应字符串的 HttpMessageHandler stub。</summary>
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, string> _responder;

        public StubHandler(Func<HttpRequestMessage, string> responder)
        {
            _responder = responder;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            try
            {
                var content = _responder(request);
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(content, Encoding.UTF8, "application/json")
                });
            }
            catch (Exception ex)
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.InternalServerError)
                {
                    Content = new StringContent(ex.Message)
                });
            }
        }
    }
}
