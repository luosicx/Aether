using Aether.Windows.ViewModels;
using System.Windows.Controls;
using System.Windows.Input;

namespace Aether.Windows.Views;

/// <summary>会话列表页：展示所有会话，支持新建、删除、置顶及导航到聊天页 / 设置页。</summary>
public sealed partial class ConversationListPage : Page
{
    public ConversationListViewModel ViewModel { get; }

    public ConversationListPage()
    {
        InitializeComponent();

        var api = App.Current.ApiClient;
        ViewModel = new ConversationListViewModel(
            api,
            navigateToChat: id => NavigationService.Navigate(new ChatPage(id)),
            navigateToSettings: () => NavigationService.Navigate(new SettingsPage()));
        DataContext = this;

        // 页面加载时自动拉取会话列表
        Loaded += async (_, _) => await ViewModel.LoadAsync();
    }

    /// <summary>点击会话内容区域时打开对应聊天页。</summary>
    private void OnConversationClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.DataContext is Models.Conversation conv)
        {
            ViewModel.OpenConversationCommand.Execute(conv.Id);
        }
    }
}
