using System.Runtime.InteropServices;
using System.Text.Json;

namespace Aether.Windows.Native;

/// <summary>
/// Rust core (aether-core-ffi) 的 P/Invoke 桥接。
/// 所有 native 调用均做 DllNotFoundException 安全处理：DLL 不存在时返回 null/0/原值，
/// 调用方可据此回退到托管实现。
/// </summary>
public static class AetherNativeBridge
{
    private const string DllName = "aether_core_ffi";

    // ===== 原始 P/Invoke 声明（对应 rust/aether-core-ffi/src/lib.rs 的 extern "C" 导出）=====

    /// <summary>解析单行 SSE，返回 content 的 JSON 串（null / "..."）。非 data 行或失败返回空指针。</summary>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr aether_sse_parse_chunk(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string line);

    /// <summary>f32 余弦相似度。空指针或长度不等返回 0。</summary>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern float aether_cosine_f32(
        float[] a, UIntPtr a_len,
        float[] b, UIntPtr b_len);

    /// <summary>对输入字符串脱敏。返回新分配的 NUL 结尾 UTF-8 字符串，需用 aether_free_string 释放。</summary>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr aether_redact(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    /// <summary>释放由上述函数返回的字符串。空指针安全。</summary>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern void aether_free_string(IntPtr ptr);

    // ===== C# 友好封装 =====

    /// <summary>
    /// 解析单行 SSE，返回 content 字符串。
    /// 非 data 行 / 解析失败 / content 为 null 返回 null；content 有值时返回该字符串。
    /// DLL 不可用时返回 null（调用方应回退到托管解析）。
    /// </summary>
    public static string? ParseSseChunk(string line)
    {
        if (string.IsNullOrEmpty(line)) return null;

        IntPtr ptr;
        try
        {
            ptr = aether_sse_parse_chunk(line);
        }
        catch (DllNotFoundException)
        {
            return null;
        }

        if (ptr == IntPtr.Zero) return null;
        try
        {
            // Rust 侧返回 JSON 编码的字符串："null"（无 content）或 "\"...\""（有 content）
            var json = Marshal.PtrToStringUTF8(ptr);
            if (string.IsNullOrEmpty(json)) return null;
            // 反序列化 JSON 字符串得到实际 content（"null" → null，"\"hello\"" → hello）
            return JsonSerializer.Deserialize<string?>(json);
        }
        finally
        {
            aether_free_string(ptr);
        }
    }

    /// <summary>
    /// f32 向量余弦相似度。长度不等或 DLL 不可用时返回 0。
    /// </summary>
    public static float CosineF32(float[] a, float[] b)
    {
        if (a is null || b is null || a.Length == 0 || b.Length == 0) return 0f;
        if (a.Length != b.Length) return 0f;

        try
        {
            return aether_cosine_f32(a, (UIntPtr)a.Length, b, (UIntPtr)b.Length);
        }
        catch (DllNotFoundException)
        {
            return 0f;
        }
    }

    /// <summary>
    /// 对输入字符串脱敏（UUID/邮箱/URL/Token/密码字段/路径）。
    /// DLL 不可用时原样返回输入。
    /// </summary>
    public static string Redact(string input)
    {
        if (string.IsNullOrEmpty(input)) return input ?? string.Empty;

        IntPtr ptr;
        try
        {
            ptr = aether_redact(input);
        }
        catch (DllNotFoundException)
        {
            return input;
        }

        if (ptr == IntPtr.Zero) return input;
        try
        {
            return Marshal.PtrToStringUTF8(ptr) ?? input;
        }
        finally
        {
            aether_free_string(ptr);
        }
    }
}
