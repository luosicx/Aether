using Aether.Windows.Services;
using Aether.Windows.ViewModels;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Animation;

namespace Aether.Windows.Views;

/// <summary>聊天页：展示消息气泡（user 右侧 / assistant 左侧）、TypingIndicator、流式响应。</summary>
public sealed partial class ChatPage : Page
{
    public ChatViewModel ViewModel { get; }

    /// <summary>TypingIndicator 闪烁动画引用。</summary>
    private Storyboard? _typingStoryboard;

    /// <summary>构造聊天页并绑定指定会话。</summary>
    /// <param name="conversationId">从会话列表传入的会话 ID。</param>
    public ChatPage(string conversationId)
    {
        InitializeComponent();

        // 从全局 App 获取共享服务（BffConfigStore + AetherApiClient）
        var api = App.Current.ApiClient;
        var configStore = App.Current.ConfigStore;
        ViewModel = new ChatViewModel(api, configStore);
        ViewModel.ConversationId = conversationId;
        DataContext = this;

        // 页面加载时拉取历史消息
        Loaded += async (_, _) => await ViewModel.LoadMessagesAsync(conversationId);

        // 监听 IsLoading 变化以启动 / 停止 TypingIndicator 动画
        ViewModel.PropertyChanged += OnViewModelPropertyChanged;
    }

    /// <summary>IsLoading 变化时启停 TypingIndicator 闪烁动画。</summary>
    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ChatViewModel.IsLoading)) return;

        _typingStoryboard ??= (Storyboard)Resources["TypingBlink"];
        if (ViewModel.IsLoading)
        {
            // 传入 this 作为 namescope 根，使 Storyboard 能按名称定位 dot1/dot2/dot3
            _typingStoryboard.Begin(this);
        }
        else
        {
            _typingStoryboard.Stop(this);
        }
    }

    private void OnInputKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            if (ViewModel.SendCommand.CanExecute(inputBox.Text))
            {
                ViewModel.SendCommand.Execute(inputBox.Text);
                inputBox.Text = "";
            }
        }
    }

    /// <summary>返回按钮：返回会话列表。</summary>
    private void OnBackClick(object sender, RoutedEventArgs e)
    {
        if (NavigationService?.CanGoBack == true)
            NavigationService.GoBack();
    }

    /// <summary>设置按钮：导航到设置页。</summary>
    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        NavigationService?.Navigate(new SettingsPage());
    }
}
