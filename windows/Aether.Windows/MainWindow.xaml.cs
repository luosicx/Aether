using Aether.Windows.Views;
using System.Windows;

namespace Aether.Windows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        // 初始页改为会话列表页（thin client → 多页导航）
        rootFrame.Navigate(new ConversationListPage());
    }
}
