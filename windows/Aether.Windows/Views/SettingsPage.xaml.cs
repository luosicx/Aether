using Aether.Windows.ViewModels;
using System.Windows;
using System.Windows.Controls;

namespace Aether.Windows.Views;

/// <summary>设置页：编辑 BFF BaseUrl / Token / 默认模型，保存后通过 DPAPI 加密落盘。</summary>
public sealed partial class SettingsPage : Page
{
    public SettingsViewModel ViewModel { get; }

    /// <summary>防止 PasswordBox 与 TextBox 互相同步导致递归的标志。</summary>
    private bool _syncingToken;

    public SettingsPage()
    {
        InitializeComponent();

        var config = App.Current.ConfigStore;
        ViewModel = new SettingsViewModel(
            config,
            goBack: () =>
            {
                if (NavigationService?.CanGoBack == true) NavigationService.GoBack();
            },
            onConfigSaved: () => App.Current.RefreshApiClient());
        DataContext = this;

        Loaded += OnLoaded;
    }

    /// <summary>页面加载时将 ViewModel 中的 Token 同步到 PasswordBox / TextBox。</summary>
    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _syncingToken = true;
        tokenBox.Password = ViewModel.UserToken;
        tokenText.Text = ViewModel.UserToken;
        _syncingToken = false;
    }

    /// <summary>返回按钮：返回上一页。</summary>
    private void OnBackClick(object sender, RoutedEventArgs e)
    {
        if (NavigationService?.CanGoBack == true)
            NavigationService.GoBack();
    }

    /// <summary>PasswordBox 内容变化时同步到 ViewModel 和 TextBox。</summary>
    private void OnTokenPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (_syncingToken) return;
        _syncingToken = true;
        var pwd = tokenBox.Password;
        ViewModel.UserToken = pwd;
        tokenText.Text = pwd;
        _syncingToken = false;
    }

    /// <summary>TextBox 内容变化时同步到 ViewModel 和 PasswordBox。</summary>
    private void OnTokenTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_syncingToken) return;
        _syncingToken = true;
        var text = tokenText.Text;
        ViewModel.UserToken = text;
        tokenBox.Password = text;
        _syncingToken = false;
    }
}
