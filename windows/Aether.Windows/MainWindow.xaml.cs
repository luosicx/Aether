using Aether.Windows.Views;

namespace Aether.Windows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        rootFrame.Navigate(typeof(ChatPage));
    }
}
