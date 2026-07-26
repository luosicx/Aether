using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Threading;
using Aether.Windows.Properties;

namespace Aether.Windows.Services;

/// <summary>
/// 语言服务：管理当前 UI 文化、切换语言并对外发布 LanguageChanged 事件。
/// 单例模式，App 启动时初始化，默认 zh-Hans。
/// </summary>
public sealed class LanguageService : INotifyPropertyChanged
{
    /// <summary>支持的语言代码列表（用于设置页 ComboBox）</summary>
    public static readonly string[] SupportedLanguages =
    {
        "zh-Hans",
        "en",
        "ja",
        "ko",
        "fr",
        "de",
        "es",
        "zh-Hant"
    };

    /// <summary>默认语言代码</summary>
    public const string DefaultLanguageCode = "zh-Hans";

    private static LanguageService? _instance;

    /// <summary>全局单例。App 启动时构造一次。</summary>
    public static LanguageService Instance => _instance ??= new LanguageService();

    private string _currentLanguage = DefaultLanguageCode;

    /// <summary>当前语言代码（如 "zh-Hans" / "en"）。变化时触发 PropertyChanged + LanguageChanged。</summary>
    public string CurrentLanguage
    {
        get => _currentLanguage;
        private set
        {
            if (_currentLanguage != value)
            {
                _currentLanguage = value;
                OnPropertyChanged();
                LanguageChanged?.Invoke(this, EventArgs.Empty);
            }
        }
    }

    /// <summary>当前 CultureInfo（基于 CurrentLanguage 构造）。可用于格式化等场景。</summary>
    public CultureInfo CurrentCulture => new(CurrentLanguage);

    /// <summary>语言切换事件。订阅者可用于强制刷新页面 / 重新绑定 x:Static 文本。</summary>
    public event EventHandler? LanguageChanged;

    private LanguageService()
    {
        // 默认 zh-Hans，但尊重系统已设置的文化（如启动时从配置恢复）
        ApplyCulture(DefaultLanguageCode);
    }

    /// <summary>
    /// 初始化 LanguageService：从 BffConfigStore 读取上次保存的语言设置。
    /// App 启动时调用一次。
    /// </summary>
    /// <param name="configStore">配置存储，可空时使用默认 zh-Hans</param>
    public void Initialize(BffConfigStore? configStore)
    {
        var code = configStore?.Language;
        if (!string.IsNullOrEmpty(code) && IsLanguageSupported(code))
        {
            ApplyCulture(code);
        }
        else
        {
            ApplyCulture(DefaultLanguageCode);
        }
    }

    /// <summary>
    /// 切换语言并立即应用到当前线程。配置持久化由调用方负责（如 SettingsViewModel.SaveAsync）。
    /// </summary>
    /// <param name="code">语言代码，如 "zh-Hans" / "en" / "ja"</param>
    /// <returns>true 表示切换成功；false 表示不支持的语言代码。</returns>
    public bool SetLanguage(string code)
    {
        if (!IsLanguageSupported(code)) return false;
        ApplyCulture(code);
        return true;
    }

    /// <summary>判断指定语言代码是否被支持。</summary>
    public static bool IsLanguageSupported(string code)
    {
        if (string.IsNullOrEmpty(code)) return false;
        foreach (var supported in SupportedLanguages)
        {
            if (string.Equals(supported, code, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    /// <summary>
    /// 通过 key 从 ResourceManager 获取本地化字符串。
    /// 内部委托给 Strings.GetString，保证与 x:Static 结果一致。
    /// </summary>
    /// <param name="key">资源 key，如 "AppTitle"</param>
    /// <returns>本地化字符串；找不到时返回空字符串。</returns>
    public string GetString(string key) => Strings.GetString(key);

    /// <summary>
    /// 应用指定文化到当前线程与 Strings.Culture，使后续 ResourceManager 调用返回新语言的字符串。
    /// </summary>
    private void ApplyCulture(string code)
    {
        var culture = new CultureInfo(code);
        Thread.CurrentThread.CurrentCulture = culture;
        Thread.CurrentThread.CurrentUICulture = culture;
        CultureInfo.DefaultThreadCurrentCulture = culture;
        CultureInfo.DefaultThreadCurrentUICulture = culture;
        Strings.Culture = culture;
        CurrentLanguage = code;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
