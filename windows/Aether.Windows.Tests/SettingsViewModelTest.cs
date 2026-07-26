using System.IO;
using Aether.Windows.Services;
using Aether.Windows.ViewModels;
using Xunit;

namespace Aether.Windows.Tests;

/// <summary>SettingsViewModel 单元测试：配置保存、加载、Token 显示切换。</summary>
public class SettingsViewModelTest
{
    private static string GetTempConfigPath()
    {
        return Path.Combine(Path.GetTempPath(), $"aether_settings_test_{Guid.NewGuid():N}.json");
    }

    [Fact]
    public void Constructor_LoadsValuesFromStore()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.BaseUrl = "https://api.example.com";
            store.UserToken = "token-123";
            store.DefaultModel = "qwen-plus";
            // 不调用 store.Load()：Load() 会因文件不存在而 ResetToDefaults，覆盖已设置的值。
            // 此测试验证 ViewModel 从 store 内存状态读取，而非从文件加载。

            var vm = new SettingsViewModel(store, () => { }, () => { });

            Assert.Equal("https://api.example.com", vm.BaseUrl);
            Assert.Equal("token-123", vm.UserToken);
            Assert.Equal("qwen-plus", vm.DefaultModel);
            Assert.False(vm.ShowToken);
            Assert.Equal("", vm.ErrorMessage);
            Assert.Equal("", vm.StatusMessage);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task SaveAsync_PersistsConfigAndInvokesCallback()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.Load();

            bool callbackCalled = false;
            var vm = new SettingsViewModel(store, () => { }, () => callbackCalled = true);
            vm.BaseUrl = "https://new.example.com";
            vm.UserToken = "new-token";
            vm.DefaultModel = "deepseek-reasoner";

            await vm.SaveAsync();

            Assert.True(callbackCalled);
            Assert.Equal("保存成功", vm.StatusMessage);
            Assert.Equal("", vm.ErrorMessage);

            // 验证已持久化到文件
            var store2 = new BffConfigStore(path);
            store2.Load();
            Assert.Equal("https://new.example.com", store2.BaseUrl);
            Assert.Equal("new-token", store2.UserToken);
            Assert.Equal("deepseek-reasoner", store2.DefaultModel);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void ToggleTokenVisibility_TogglesShowToken()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            var vm = new SettingsViewModel(store, () => { });

            Assert.False(vm.ShowToken);

            vm.ToggleTokenVisibilityCommand.Execute(null);
            Assert.True(vm.ShowToken);

            vm.ToggleTokenVisibilityCommand.Execute(null);
            Assert.False(vm.ShowToken);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void AvailableModels_ContainsAllExpectedModels()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            var vm = new SettingsViewModel(store, () => { });

            Assert.Equal(4, vm.AvailableModels.Count);
            Assert.Contains("deepseek-chat", vm.AvailableModels);
            Assert.Contains("deepseek-reasoner", vm.AvailableModels);
            Assert.Contains("qwen-plus", vm.AvailableModels);
            Assert.Contains("qwen-turbo", vm.AvailableModels);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task SaveAsync_EmptyToken_PersistsSuccessfully()
    {
        var path = GetTempConfigPath();
        try
        {
            var store = new BffConfigStore(path);
            store.Load();

            var vm = new SettingsViewModel(store, () => { }, () => { });
            vm.BaseUrl = "https://api.example.com";
            vm.UserToken = "";
            vm.DefaultModel = "deepseek-chat";

            await vm.SaveAsync();

            Assert.Equal("保存成功", vm.StatusMessage);

            var store2 = new BffConfigStore(path);
            store2.Load();
            Assert.Equal("", store2.UserToken);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
