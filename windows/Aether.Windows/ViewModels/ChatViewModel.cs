using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text;
using System.Windows.Input;
using Aether.Windows.Models;
using Aether.Windows.Services;

namespace Aether.Windows.ViewModels;

public class ChatViewModel : INotifyPropertyChanged
{
    private readonly AetherApiClient _api;
    private string _conversationId = "";
    private string _streamingText = "";
    private bool _isLoading = false;
    private string _errorMessage = "";

    public ObservableCollection<ChatMessage> Messages { get; } = new();

    public string ConversationId
    {
        get => _conversationId;
        set { _conversationId = value; OnPropertyChanged(); }
    }

    public string StreamingText
    {
        get => _streamingText;
        set { _streamingText = value; OnPropertyChanged(); }
    }

    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; OnPropertyChanged(); }
    }

    public string ErrorMessage
    {
        get => _errorMessage;
        set { _errorMessage = value; OnPropertyChanged(); }
    }

    public ICommand SendCommand { get; }

    public ChatViewModel(AetherApiClient api)
    {
        _api = api;
        SendCommand = new RelayCommand(Send);
    }

    public async Task LoadMessagesAsync(string conversationId)
    {
        ConversationId = conversationId;
        try
        {
            Messages.Clear();
            var messages = await _api.GetMessagesAsync(conversationId);
            if (messages != null)
            {
                foreach (var msg in messages) Messages.Add(msg);
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"加载消息失败：{ex.Message}";
        }
    }

    private async void Send(object? parameter)
    {
        if (parameter is not string text || string.IsNullOrWhiteSpace(text)) return;
        if (string.IsNullOrEmpty(ConversationId))
        {
            ErrorMessage = "未选择会话";
            return;
        }

        IsLoading = true;
        ErrorMessage = "";
        StreamingText = "";

        Messages.Add(new ChatMessage
        {
            Id = Guid.NewGuid().ToString(),
            ConversationId = ConversationId,
            Role = "user",
            Content = text,
            CreatedAt = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        });

        try
        {
            var request = new ChatRequest
            {
                Message = text,
                ConversationId = ConversationId
            };
            var fullResponse = new StringBuilder();
            await foreach (var chunk in _api.StreamChatAsync(request))
            {
                fullResponse.Append(chunk);
                StreamingText = fullResponse.ToString();
            }
            Messages.Add(new ChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                ConversationId = ConversationId,
                Role = "assistant",
                Content = fullResponse.ToString(),
                CreatedAt = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            });
            StreamingText = "";
        }
        catch (Exception ex)
        {
            ErrorMessage = $"发送失败：{ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public class RelayCommand : ICommand
{
    private readonly Action<object?> _execute;
    private readonly Func<object?, bool>? _canExecute;

    public RelayCommand(Action<object?> execute, Func<object?, bool>? canExecute = null)
    {
        _execute = execute;
        _canExecute = canExecute;
    }

    public bool CanExecute(object? parameter) => _canExecute?.Invoke(parameter) ?? true;
    public void Execute(object? parameter) => _execute(parameter);
    public event EventHandler? CanExecuteChanged;
}
