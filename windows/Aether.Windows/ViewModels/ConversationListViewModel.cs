using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Aether.Windows.Models;
using Aether.Windows.Services;

namespace Aether.Windows.ViewModels;

/// <summary>会话列表页 ViewModel。管理会话的加载、创建、删除、置顶及导航。</summary>
public class ConversationListViewModel : INotifyPropertyChanged
{
    private readonly AetherApiClient _api;
    private readonly Action<string> _navigateToChat;
    private readonly Action _navigateToSettings;
    private string _errorMessage = "";
    private bool _isLoading = false;

    /// <summary>会话列表（置顶的排前面）</summary>
    public ObservableCollection<Conversation> Conversations { get; } = new();

    public string ErrorMessage
    {
        get => _errorMessage;
        set { _errorMessage = value; OnPropertyChanged(); }
    }

    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; OnPropertyChanged(); }
    }

    public ICommand LoadCommand { get; }
    public ICommand CreateCommand { get; }
    public ICommand DeleteCommand { get; }
    public ICommand TogglePinCommand { get; }
    public ICommand OpenConversationCommand { get; }
    public ICommand OpenSettingsCommand { get; }

    public ConversationListViewModel(
        AetherApiClient api,
        Action<string> navigateToChat,
        Action navigateToSettings)
    {
        _api = api;
        _navigateToChat = navigateToChat;
        _navigateToSettings = navigateToSettings;

        LoadCommand = new RelayCommand(async _ => await LoadAsync());
        CreateCommand = new RelayCommand(async _ => await CreateAsync());
        DeleteCommand = new RelayCommand(async p => await DeleteAsync(p));
        TogglePinCommand = new RelayCommand(async p => await TogglePinAsync(p));
        OpenConversationCommand = new RelayCommand(p =>
        {
            if (p is string id && !string.IsNullOrEmpty(id))
            {
                _navigateToChat(id);
            }
        });
        OpenSettingsCommand = new RelayCommand(_ => _navigateToSettings());
    }

    /// <summary>加载会话列表，置顶会话排在前面。</summary>
    public async Task LoadAsync()
    {
        IsLoading = true;
        ErrorMessage = "";
        try
        {
            var conversations = await _api.GetConversationsAsync();
            Conversations.Clear();
            if (conversations != null)
            {
                // 置顶的排前面，再按 UpdatedAt 降序
                foreach (var conv in conversations
                             .OrderByDescending(c => c.IsPinned)
                             .ThenByDescending(c => c.UpdatedAt))
                {
                    Conversations.Add(conv);
                }
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"加载会话失败：{ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    /// <summary>新建会话，创建成功后自动导航到聊天页。</summary>
    public async Task CreateAsync()
    {
        ErrorMessage = "";
        try
        {
            var conv = await _api.CreateConversationAsync("新会话");
            if (conv != null)
            {
                _navigateToChat(conv.Id);
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"创建会话失败：{ex.Message}";
        }
    }

    /// <summary>删除指定会话。</summary>
    public async Task DeleteAsync(object? parameter)
    {
        if (parameter is not string id || string.IsNullOrEmpty(id)) return;
        ErrorMessage = "";
        try
        {
            await _api.DeleteConversationAsync(id);
            // 从本地集合中移除
            var target = Conversations.FirstOrDefault(c => c.Id == id);
            if (target != null)
            {
                Conversations.Remove(target);
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"删除会话失败：{ex.Message}";
        }
    }

    /// <summary>切换会话置顶状态。</summary>
    public async Task TogglePinAsync(object? parameter)
    {
        if (parameter is not string id || string.IsNullOrEmpty(id)) return;
        ErrorMessage = "";
        try
        {
            var conv = Conversations.FirstOrDefault(c => c.Id == id);
            if (conv == null) return;

            conv.IsPinned = !conv.IsPinned;
            await _api.UpdateConversationAsync(conv);

            // 重新排序：置顶的排前面
            var sorted = Conversations
                .OrderByDescending(c => c.IsPinned)
                .ThenByDescending(c => c.UpdatedAt)
                .ToList();
            Conversations.Clear();
            foreach (var c in sorted) Conversations.Add(c);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"置顶失败：{ex.Message}";
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
