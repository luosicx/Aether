using System.Globalization;
using System.IO;
using Aether.Windows.Services;
using Xunit;

namespace Aether.Windows.Tests;

/// <summary>LanguageService 单元测试：语言切换、GetString、默认回退、单例。</summary>
public class LanguageServiceTest
{
    /// <summary>
    /// 获取 LanguageService 单例并重置为默认语言（zh-Hans）。
    /// LanguageService 构造函数为 private（单例模式），测试只能通过 Instance 访问。
    /// 每次调用前重置语言，避免前一个测试的状态泄漏到当前测试。
    /// </summary>
    private static LanguageService CreateService()
    {
        var svc = LanguageService.Instance;
        svc.SetLanguage(LanguageService.DefaultLanguageCode);
        return svc;
    }

    [Fact]
    public void DefaultLanguage_IsZhHans()
    {
        var svc = CreateService();
        Assert.Equal("zh-Hans", svc.CurrentLanguage);
    }

    [Fact]
    public void SupportedLanguages_ContainsAllEightLanguages()
    {
        Assert.Equal(8, LanguageService.SupportedLanguages.Length);
        Assert.Contains("zh-Hans", LanguageService.SupportedLanguages);
        Assert.Contains("en", LanguageService.SupportedLanguages);
        Assert.Contains("ja", LanguageService.SupportedLanguages);
        Assert.Contains("ko", LanguageService.SupportedLanguages);
        Assert.Contains("fr", LanguageService.SupportedLanguages);
        Assert.Contains("de", LanguageService.SupportedLanguages);
        Assert.Contains("es", LanguageService.SupportedLanguages);
        Assert.Contains("zh-Hant", LanguageService.SupportedLanguages);
    }

    [Theory]
    [InlineData("zh-Hans", true)]
    [InlineData("en", true)]
    [InlineData("ja", true)]
    [InlineData("ko", true)]
    [InlineData("fr", true)]
    [InlineData("de", true)]
    [InlineData("es", true)]
    [InlineData("zh-Hant", true)]
    [InlineData("zh", false)]
    [InlineData("invalid", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsLanguageSupported_ReturnsExpected(string? code, bool expected)
    {
        Assert.Equal(expected, LanguageService.IsLanguageSupported(code!));
    }

    [Fact]
    public void SetLanguage_ValidCode_UpdatesCurrentLanguage()
    {
        var svc = CreateService();
        var result = svc.SetLanguage("en");

        Assert.True(result);
        Assert.Equal("en", svc.CurrentLanguage);
    }

    [Fact]
    public void SetLanguage_InvalidCode_ReturnsFalseAndKeepsCurrentLanguage()
    {
        var svc = CreateService();
        var originalLang = svc.CurrentLanguage;
        var result = svc.SetLanguage("invalid-code");

        Assert.False(result);
        Assert.Equal(originalLang, svc.CurrentLanguage);
    }

    [Fact]
    public void SetLanguage_TriggersLanguageChangedEvent()
    {
        var svc = CreateService();
        var eventCount = 0;
        svc.LanguageChanged += (_, _) => eventCount++;

        svc.SetLanguage("en");
        svc.SetLanguage("ja");

        Assert.Equal(2, eventCount);
    }

    [Fact]
    public void SetLanguage_SameCode_DoesNotTriggerEvent()
    {
        var svc = CreateService();
        var eventCount = 0;
        svc.LanguageChanged += (_, _) => eventCount++;

        svc.SetLanguage("zh-Hans"); // 与默认相同

        Assert.Equal(0, eventCount);
    }

    [Fact]
    public void CurrentCulture_ReflectsCurrentLanguage()
    {
        var svc = CreateService();
        svc.SetLanguage("ja");
        Assert.Equal("ja", svc.CurrentCulture.Name);
    }

    [Fact]
    public void SetLanguage_UpdatesThreadUICulture()
    {
        var svc = CreateService();
        svc.SetLanguage("de");
        // SetLanguage 内部应已更新 CurrentThread.CurrentUICulture
        Assert.Equal("de", System.Threading.Thread.CurrentThread.CurrentUICulture.Name);
    }

    [Fact]
    public void GetString_ReturnsLocalizedStringForCurrentLanguage()
    {
        var svc = CreateService();

        // 默认 zh-Hans
        Assert.Equal("以太", svc.GetString("AppTitle"));
        Assert.Equal("发送", svc.GetString("Chat_SendMessage"));

        // 切换到 en
        svc.SetLanguage("en");
        Assert.Equal("Aether", svc.GetString("AppTitle"));
        Assert.Equal("Send", svc.GetString("Chat_SendMessage"));

        // 切换到 ja
        svc.SetLanguage("ja");
        Assert.Equal("アエテル", svc.GetString("AppTitle"));
        Assert.Equal("送信", svc.GetString("Chat_SendMessage"));
    }

    [Fact]
    public void GetString_UnknownKey_ReturnsEmptyString()
    {
        var svc = CreateService();
        var result = svc.GetString("NonExistent_Key_12345");
        Assert.Equal("", result);
    }

    [Fact]
    public void GetString_NullOrEmptyKey_ReturnsEmptyString()
    {
        var svc = CreateService();
        // 空字符串返回空字符串（ResourceManager.GetString 对空 key 返回 null，Strings.Designer 回退为 ""）
        Assert.Equal("", svc.GetString(""));
        // null key 由 ResourceManager 抛出 ArgumentNullException（实现未做 null 防护，测试验证该行为）
        Assert.Throws<ArgumentNullException>(() => svc.GetString(null!));
    }

    [Fact]
    public void Initialize_NullConfigStore_FallsBackToDefaultLanguage()
    {
        var svc = CreateService();
        svc.SetLanguage("en"); // 先改成 en
        // 用 null 调用 Initialize 应回退到默认
        svc.Initialize(null);
        Assert.Equal("zh-Hans", svc.CurrentLanguage);
    }

    [Fact]
    public void Initialize_ConfigStoreWithSupportedLanguage_AppliesLanguage()
    {
        var path = Path.Combine(Path.GetTempPath(), $"aether_lang_test_{Guid.NewGuid():N}.json");
        try
        {
            var store = new BffConfigStore(path);
            store.Load();
            store.Language = "ja";

            var svc = CreateService();
            svc.Initialize(store);
            Assert.Equal("ja", svc.CurrentLanguage);
            Assert.Equal("アエテル", svc.GetString("AppTitle"));
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void Initialize_ConfigStoreWithUnsupportedLanguage_FallsBackToDefault()
    {
        var path = Path.Combine(Path.GetTempPath(), $"aether_lang_test_{Guid.NewGuid():N}.json");
        try
        {
            var store = new BffConfigStore(path);
            store.Load();
            store.Language = "klingon"; // 不支持

            var svc = CreateService();
            svc.Initialize(store);
            Assert.Equal("zh-Hans", svc.CurrentLanguage);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void SetLanguage_AllSupportedLanguages_Succeeds()
    {
        var svc = CreateService();
        foreach (var code in LanguageService.SupportedLanguages)
        {
            var result = svc.SetLanguage(code);
            Assert.True(result, $"无法切换到语言：{code}");
            Assert.Equal(code, svc.CurrentLanguage);
        }
    }

    [Fact]
    public void SetLanguage_PropagatesToPropertyChanged()
    {
        var svc = CreateService();
        var eventCount = 0;
        svc.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(LanguageService.CurrentLanguage))
                eventCount++;
        };

        svc.SetLanguage("en");
        Assert.Equal(1, eventCount);
    }

    [Fact]
    public void Instance_ReturnsSameSingleton()
    {
        var a = LanguageService.Instance;
        var b = LanguageService.Instance;
        Assert.Same(a, b);
    }

    [Fact]
    public async Task BffConfigStore_LanguageRoundTrip()
    {
        var path = Path.Combine(Path.GetTempPath(), $"aether_lang_test_{Guid.NewGuid():N}.json");
        try
        {
            var store = new BffConfigStore(path);
            store.Load();
            store.Language = "ko";
            await store.SaveAsync();

            var store2 = new BffConfigStore(path);
            store2.Load();
            Assert.Equal("ko", store2.Language);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void GetString_AllKeys_ReturnLocalizedZhHansByDefault()
    {
        var svc = CreateService();
        // 验证关键 key 在默认 zh-Hans 下返回预期中文
        Assert.Equal("以太", svc.GetString("AppTitle"));
        Assert.Equal("会话列表", svc.GetString("ConversationList_Title"));
        Assert.Equal("新建会话", svc.GetString("ConversationList_NewConversation"));
        Assert.Equal("设置", svc.GetString("Settings_Title"));
        Assert.Equal("保存", svc.GetString("Settings_Save"));
        Assert.Equal("加载中...", svc.GetString("Common_Loading"));
        Assert.Equal("知识库", svc.GetString("KnowledgeBase_Title"));
        Assert.Equal("健康洞察", svc.GetString("Health_Title"));
    }
}
