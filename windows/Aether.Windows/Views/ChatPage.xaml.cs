using Aether.Windows.Services;
using Aether.Windows.ViewModels;
using System.Windows.Controls;
using System.Windows.Input;

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
        this.DataContext = this;
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
}
