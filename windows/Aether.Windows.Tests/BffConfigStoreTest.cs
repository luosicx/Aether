using System.IO;
using Aether.Windows.Services;
using Xunit;

namespace Aether.Windows.Tests;

/// <summary>BffConfigStore 单元测试：DPAPI 加密往返、配置文件读写、默认值。</summary>
public class BffConfigStoreTest
{
    /// <summary>生成临时配置文件路径（每个测试独立，避免相互干扰）。</summary>
    private static string GetTempConfigPath()
    {
        return Path.Combine(Path.GetTempPath(), $"aether_test_{Guid.NewGuid():N}.json");
    }

    [Fact]
    public void Load_FileNotExists_ReturnsDefaults()
    {
        var store = new BffConfigStore(GetTempConfigPath());
        store.Load();

        Assert.Equal("", store.BaseUrl);
        Assert.Equal("", store.UserToken);
        Assert.Equal("deepseek-chat", store.DefaultModel);
        Assert.Equal("", store.AccentColor);
    }

    [Fact]
    public async Task SaveLoad_RoundTrip_PreservesAllFields()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.BaseUrl = "https://api.example.com";
            store.UserToken = "secret-token-123";
            store.DefaultModel = "qwen-plus";
            store.AccentColor = "#7C3AED";
            await store.SaveAsync();

            // 用新的 store 实例从同一文件加载，验证往返
            var store2 = new BffConfigStore(path);
            store2.Load();

            Assert.Equal("https://api.example.com", store2.BaseUrl);
            Assert.Equal("secret-token-123", store2.UserToken);
            Assert.Equal("qwen-plus", store2.DefaultModel);
            Assert.Equal("#7C3AED", store2.AccentColor);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task Save_TokenIsEncrypted_NotPlaintextInFile()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.UserToken = "my-secret-token";
            await store.SaveAsync();

            // 读取原始 JSON 文件，确认明文 Token 不存在
            var fileContent = File.ReadAllText(path);
            Assert.DoesNotContain("my-secret-token", fileContent);
            // 确认文件包含 encryptedToken 字段
            Assert.Contains("encryptedToken", fileContent);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task LoadAsync_RoundTrip_WorksSameAsSync()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.BaseUrl = "https://async.example.com";
            store.UserToken = "async-token";
            await store.SaveAsync();

            var store2 = new BffConfigStore(path);
            await store2.LoadAsync();

            Assert.Equal("https://async.example.com", store2.BaseUrl);
            Assert.Equal("async-token", store2.UserToken);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task Save_EmptyToken_StoresEmptyEncryptedToken()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.BaseUrl = "https://api.example.com";
            store.UserToken = "";
            await store.SaveAsync();

            var store2 = new BffConfigStore(path);
            store2.Load();

            Assert.Equal("", store2.UserToken);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task Save_OverwritesExistingFile()
    {
        var path = GetTempConfigPath();
        try
        {
            // 第一次保存
            var store = new BffConfigStore(path);
            store.BaseUrl = "https://old.example.com";
            store.UserToken = "old-token";
            await store.SaveAsync();

            // 第二次保存（覆盖）
            store.BaseUrl = "https://new.example.com";
            store.UserToken = "new-token";
            await store.SaveAsync();

            // 加载验证是第二次的值
            var store2 = new BffConfigStore(path);
            store2.Load();
            Assert.Equal("https://new.example.com", store2.BaseUrl);
            Assert.Equal("new-token", store2.UserToken);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void Load_CorruptedFile_ReturnsDefaults()
    {
        var path = GetTempConfigPath();
        try
        {
            // 写入损坏的 JSON
            File.WriteAllText(path, "{ invalid json content");

            var store = new BffConfigStore(path);
            store.Load();

            // 解析失败时应回退到默认值
            Assert.Equal("", store.BaseUrl);
            Assert.Equal("", store.UserToken);
            Assert.Equal("deepseek-chat", store.DefaultModel);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
