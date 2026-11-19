using System.Text;

namespace Aether.Windows.ViewModels;

/// <summary>
/// 流式文本节流器：把 token 级增量合并成最多每 <see cref="DefaultIntervalMs"/> 毫秒一次的 UI 更新。
/// 没有它时每个 token 都要把整段文本 ToString 一次并触发 PropertyChanged，长回复会持续重排 TextBlock。
/// 节流窗口内只累积，不分配整段快照；窗口到期的下一次追加才产出快照。
/// </summary>
public sealed class StreamingTextThrottler
{
    public const int DefaultIntervalMs = 100;

    private readonly StringBuilder _buffer = new();
    private readonly long _intervalTicks;
    private readonly Func<long> _nowTicks;
    private long _lastEmitTicks = long.MinValue;

    /// <param name="intervalMs">最小更新间隔（毫秒），默认与 Apple 端一致的 100ms。</param>
    /// <param name="nowTicks">时间源（UTC ticks），测试注入假时钟以获得确定性。</param>
    public StreamingTextThrottler(int intervalMs = DefaultIntervalMs, Func<long>? nowTicks = null)
    {
        if (intervalMs <= 0) throw new ArgumentOutOfRangeException(nameof(intervalMs));
        _intervalTicks = TimeSpan.FromMilliseconds(intervalMs).Ticks;
        _nowTicks = nowTicks ?? (() => DateTime.UtcNow.Ticks);
    }

    /// <summary>累积一段增量；仅在节流窗口到期时调用 <paramref name="emit"/> 输出快照。</summary>
    public void Append(string chunk, Action<string> emit)
    {
        ArgumentNullException.ThrowIfNull(chunk);
        ArgumentNullException.ThrowIfNull(emit);

        _buffer.Append(chunk);
        var now = _nowTicks();
        if (_lastEmitTicks == long.MinValue || now - _lastEmitTicks >= _intervalTicks)
        {
            _lastEmitTicks = now;
            emit(_buffer.ToString());
        }
    }

    /// <summary>返回累积的完整文本（包含尚未到节流窗口的尾部）。</summary>
    public string Flush() => _buffer.ToString();
}
