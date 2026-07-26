using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Aether.Windows.Services;

namespace Aether.Windows.ViewModels;

/// <summary>设置页 ViewModel。管理 BFF 配置的编辑、保存与 Token 显示切换，并管理 UI 语言切换。</summary>
public class SettingsViewModel : INotifyPropertyChanged
{
    private readonly BffConfigStore _store;
    private readonly Action _goBack;
    private readonly Action? _onConfigSaved;
    private readonly LanguageService _languageService;
    private string _baseUrl = "";
    private string _userToken = "";
    private string _defaultModel = "deepseek-chat";
    private bool _showToken = false;
    private string _errorMessage = "";
    private string _statusMessage = "";
    private string _selectedLanguageCode = LanguageService.DefaultLanguageCode;

    /// <summary>可选模型列表</summary>
    public List<string> AvailableModels { get; } = new()
    {
        "deepseek-chat",
        "deepseek-reasoner",
        "qwen-plus",
        "qwen-turbo"
    };

    /// <summary>支持的语言列表（Code + DisplayName）。DisplayName 为自描述名称，不随当前语言变化。</summary>
    public List<LanguageOption> AvailableLanguages { get; } = new()
    {
        new() { Code = "zh-Hans", DisplayName = "简体中文" },
        new() { Code = "en", DisplayName = "English" },
        new() { Code = "ja", DisplayName = "日本語" },
        new() { Code = "ko", DisplayName = "한국어" },
        new() { Code = "fr", DisplayName = "Français" },
        new() { Code = "de", DisplayName = "Deutsch" },
        new() { Code = "es", DisplayName = "Español" },
        new() { Code = "zh-Hant", DisplayName = "繁體中文" }
    };

    public string BaseUrl
    {
        get => _baseUrl;
        set { _baseUrl = value; OnPropertyChanged(); }
    }

    public string UserToken
    {
        get => _userToken;
        set { _userToken = value; OnPropertyChanged(); }
    }

    public string DefaultModel
    {
        get => _defaultModel;
        set { _defaultModel = value; OnPropertyChanged(); }
    }

    /// <summary>是否明文显示 Token（PasswordBox / TextBox 切换）</summary>
    public bool ShowToken
    {
        get => _showToken;
        set { _showToken = value; OnPropertyChanged(); }
    }

    public string ErrorMessage
    {
        get => _errorMessage;
        set { _errorMessage = value; OnPropertyChanged(); }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { _statusMessage = value; OnPropertyChanged(); }
    }

    /// <summary>当前选中的语言代码。set 时立即调用 LanguageService.SetLanguage 应用，使 UI 文本立即刷新。</summary>
    public string SelectedLanguageCode
    {
        get => _selectedLanguageCode;
        set
        {
            if (_selectedLanguageCode != value && LanguageService.IsLanguageSupported(value))
            {
                _selectedLanguageCode = value;
                _languageService.SetLanguage(value);
                OnPropertyChanged();
            }
        }
    }

    public ICommand SaveCommand { get; }
    public ICommand BackCommand { get; }
    public ICommand ToggleTokenVisibilityCommand { get; }

    public SettingsViewModel(BffConfigStore store, Action goBack, Action? onConfigSaved = null)
        : this(store, goBack, onConfigSaved, LanguageService.Instance)
    {
    }

    /// <summary>
    /// 测试用构造函数：允许注入 LanguageService 实例。
    /// 生产代码使用上面的单参 / 三参构造函数。
    /// </summary>
    public SettingsViewModel(BffConfigStore store, Action goBack, Action? onConfigSaved, LanguageService languageService)
    {
        _store = store;
        _goBack = goBack;
        _onConfigSaved = onConfigSaved;
        _languageService = languageService;

        // 从配置存储加载当前值到编辑字段
        LoadValues();

        SaveCommand = new RelayCommand(async _ => await SaveAsync());
        BackCommand = new RelayCommand(_ => _goBack());
        ToggleTokenVisibilityCommand = new RelayCommand(_ => ShowToken = !ShowToken);
    }

    /// <summary>从 BffConfigStore 读取配置到编辑字段。</summary>
    private void LoadValues()
    {
        BaseUrl = _store.BaseUrl;
        UserToken = _store.UserToken;
        DefaultModel = _store.DefaultModel;
        var lang = _store.Language;
        _selectedLanguageCode = LanguageService.IsLanguageSupported(lang) ? lang : LanguageService.DefaultLanguageCode;
    }

    /// <summary>保存配置到 BffConfigStore（Token 会经 DPAPI 加密后落盘；Language 同步持久化）。</summary>
    public async Task SaveAsync()
    {
        ErrorMessage = "";
        StatusMessage = "";
        try
        {
            _store.BaseUrl = BaseUrl;
            _store.UserToken = UserToken;
            _store.DefaultModel = DefaultModel;
            _store.Language = _selectedLanguageCode;
            await _store.SaveAsync();

            // 通知外部（App）刷新 AetherApiClient，使新配置立即生效
            _onConfigSaved?.Invoke();

            StatusMessage = "保存成功";
        }
        catch (Exception ex)
        {
            ErrorMessage = $"保存失败：{ex.Message}";
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>语言选项（Code + 显示名称）。用于 SettingsPage 语言 ComboBox 绑定。</summary>
public class LanguageOption
{
    /// <summary>语言代码，如 "zh-Hans" / "en"</summary>
    public string Code { get; set; } = "";
    /// <summary>显示名称（自描述，如 "简体中文" / "English"）</summary>
    public string DisplayName { get; set; } = "";
}
