using System.Windows;
using Aether.Windows.Services;

namespace Aether.Windows;

public partial class App : Application
{
    /// <summary>全局访问点（隐藏基类 Current 并返回强类型 App）。</summary>
    public static new App Current => (App)Application.Current;

    /// <summary>BFF 配置存储（DPAPI 加密 Token）。</summary>
    public BffConfigStore ConfigStore { get; }

    /// <summary>BFF API 客户端（从 BffConfigStore 读取 BaseUrl / Token）。</summary>
    public AetherApiClient ApiClient { get; private set; }

    /// <summary>语言服务（单例，启动时从配置恢复语言设置）。</summary>
    public LanguageService LanguageService { get; }

    public App()
    {
        // 初始化配置存储（同步加载本地文件，文件小不阻塞）
        ConfigStore = new BffConfigStore();
        ConfigStore.Load();

        // 使用配置存储构造 API 客户端
        ApiClient = new AetherApiClient(ConfigStore);

        // 初始化语言服务（从 ConfigStore.Language 读取上次设置，默认 zh-Hans）
        LanguageService = LanguageService.Instance;
        LanguageService.Initialize(ConfigStore);
    }

    /// <summary>设置保存后刷新 ApiClient，使新 BaseUrl / Token 立即生效。</summary>
    public void RefreshApiClient()
    {
        ApiClient.Refresh();
    }
}
