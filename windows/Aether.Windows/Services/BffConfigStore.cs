using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Aether.Windows.Services;

/// <summary>
/// BFF 配置持久化存储。使用 %LOCALAPPDATA%/Aether/bff_config.json 保存配置，
/// UserToken 通过 DPAPI（CurrentUser 范围）加密后存储。
/// </summary>
public class BffConfigStore
{
    /// <summary>配置文件默认目录：%LOCALAPPDATA%/Aether</summary>
    private static readonly string DefaultConfigDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Aether");

    /// <summary>配置文件默认路径：%LOCALAPPDATA%/Aether/bff_config.json</summary>
    private static readonly string DefaultConfigPath = Path.Combine(DefaultConfigDir, "bff_config.json");

    private readonly string _configPath;
    private readonly string _configDir;

    /// <summary>内存中的配置 DTO（EncryptedToken 为 Base64 编码的密文）</summary>
    private BffConfigData _data = new();

    /// <summary>解密后的 UserToken 明文（仅存内存，不落盘）</summary>
    private string _decryptedToken = "";

    public BffConfigStore(string? configPath = null)
    {
        _configPath = configPath ?? DefaultConfigPath;
        _configDir = Path.GetDirectoryName(_configPath) ?? DefaultConfigDir;
    }

    /// <summary>BFF BaseUrl</summary>
    public string BaseUrl
    {
        get => _data.BaseUrl;
        set => _data.BaseUrl = value;
    }

    /// <summary>User Token 明文（加解密在 Load/Save 时自动处理）</summary>
    public string UserToken
    {
        get => _decryptedToken;
        set => _decryptedToken = value;
    }

    /// <summary>默认模型</summary>
    public string DefaultModel
    {
        get => _data.DefaultModel;
        set => _data.DefaultModel = value;
    }

    /// <summary>强调色（主题色，预留字段）</summary>
    public string AccentColor
    {
        get => _data.AccentColor;
        set => _data.AccentColor = value;
    }

    /// <summary>UI 语言代码（如 "zh-Hans" / "en"），由 LanguageService 读取 / 写入</summary>
    public string Language
    {
        get => _data.Language;
        set => _data.Language = value;
    }

    /// <summary>同步加载配置文件。文件不存在时返回默认值。</summary>
    public void Load()
    {
        try
        {
            if (!File.Exists(_configPath))
            {
                ResetToDefaults();
                return;
            }

            var json = File.ReadAllText(_configPath);
            _data = JsonSerializer.Deserialize<BffConfigData>(json) ?? new BffConfigData();
            _decryptedToken = DecryptToken(_data.EncryptedToken);
        }
        catch
        {
            // 读取失败时回退到默认值，避免阻塞启动
            ResetToDefaults();
        }
    }

    /// <summary>异步加载配置文件。</summary>
    public async Task LoadAsync()
    {
        await Task.Run(Load);
    }

    /// <summary>异步保存配置文件。UserToken 会通过 DPAPI 加密后写入。</summary>
    public async Task SaveAsync()
    {
        _data.EncryptedToken = EncryptToken(_decryptedToken);
        Directory.CreateDirectory(_configDir);
        var options = new JsonSerializerOptions { WriteIndented = true };
        var json = JsonSerializer.Serialize(_data, options);
        await File.WriteAllTextAsync(_configPath, json);
    }

    /// <summary>重置为默认值（首次启动或读取失败时使用）</summary>
    private void ResetToDefaults()
    {
        _data = new BffConfigData();
        _decryptedToken = "";
    }

    /// <summary>使用 DPAPI CurrentUser 范围加密 Token，返回 Base64 字符串。</summary>
    private static string EncryptToken(string plain)
    {
        if (string.IsNullOrEmpty(plain)) return "";
        var bytes = Encoding.UTF8.GetBytes(plain);
        var encrypted = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
        return Convert.ToBase64String(encrypted);
    }

    /// <summary>使用 DPAPI CurrentUser 范围解密 Token。失败时返回空字符串。</summary>
    private static string DecryptToken(string encryptedBase64)
    {
        if (string.IsNullOrEmpty(encryptedBase64)) return "";
        try
        {
            var bytes = Convert.FromBase64String(encryptedBase64);
            var decrypted = ProtectedData.Unprotect(bytes, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(decrypted);
        }
        catch
        {
            return "";
        }
    }
}

/// <summary>配置文件 JSON 序列化 DTO。EncryptedToken 为 DPAPI 加密后的 Base64 字符串。</summary>
internal class BffConfigData
{
    public string BaseUrl { get; set; } = "";
    public string EncryptedToken { get; set; } = "";
    public string DefaultModel { get; set; } = "deepseek-chat";
    public string AccentColor { get; set; } = "";
    /// <summary>UI 语言代码（如 "zh-Hans"），默认空字符串，LanguageService 会回退到 zh-Hans</summary>
    public string Language { get; set; } = "";
}
