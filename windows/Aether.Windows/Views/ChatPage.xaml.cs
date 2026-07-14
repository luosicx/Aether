using Aether.Windows.Services;
using Aether.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Aether.Windows.Views;

public sealed partial class ChatPage : Page
{
    public ChatViewModel ViewModel { get; }

    public ChatPage()
    {
        InitializeComponent();
        // TODO: 从配置读取 baseUrl 和 token
        var api = new AetherApiClient("https://aether-bff.example.com", "");
        ViewModel = new ChatViewModel(api);
        // TODO: 设置 ConversationId（从导航参数获取）
    }

    private void OnInputKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            if (ViewModel.SendCommand.CanExecute(inputBox.Text))
            {
                ViewModel.SendCommand.Execute(inputBox.Text);
                inputBox.Text = "";
            }
        }
    }
}
