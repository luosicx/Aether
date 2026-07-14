using Aether.Windows.Views;
using System.Windows;

namespace Aether.Windows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        rootFrame.Navigate(typeof(ChatPage));
    }
}
