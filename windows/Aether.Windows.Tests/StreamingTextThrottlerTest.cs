using Aether.Windows.ViewModels;
using Xunit;

namespace Aether.Windows.Tests;

public class StreamingTextThrottlerTest
{
    private sealed class FakeClock
    {
        public long Ticks { get; set; } = 1_000_000;
        public void AdvanceMs(int ms) => Ticks += TimeSpan.FromMilliseconds(ms).Ticks;
    }

    [Fact]
    public void FirstChunk_EmitsImmediately()
    {
        var clock = new FakeClock();
        var throttler = new StreamingTextThrottler(nowTicks: () => clock.Ticks);
        var emitted = new List<string>();

        throttler.Append("你", emitted.Add);

        Assert.Equal(new[] { "你" }, emitted);
    }

    [Fact]
    public void ChunksWithinWindow_AreMergedIntoOneEmit()
    {
        var clock = new FakeClock();
        var throttler = new StreamingTextThrottler(nowTicks: () => clock.Ticks);
        var emitted = new List<string>();

        throttler.Append("你", emitted.Add);
        clock.AdvanceMs(10);
        throttler.Append("好", emitted.Add);
        clock.AdvanceMs(10);
        throttler.Append("！", emitted.Add);

        // 只有首个 token 触发更新，后面的增量等到窗口到期
        Assert.Equal(new[] { "你" }, emitted);
        Assert.Equal("你好！", throttler.Flush());
    }

    [Fact]
    public void ChunkAfterWindow_EmitsCumulativeSnapshot()
    {
        var clock = new FakeClock();
        var throttler = new StreamingTextThrottler(nowTicks: () => clock.Ticks);
        var emitted = new List<string>();

        throttler.Append("你", emitted.Add);
        clock.AdvanceMs(100);
        throttler.Append("好", emitted.Add);

        Assert.Equal(new[] { "你", "你好" }, emitted);
    }

    [Fact]
    public void Flush_IncludesTailNotYetEmitted()
    {
        var clock = new FakeClock();
        var throttler = new StreamingTextThrottler(nowTicks: () => clock.Ticks);

        throttler.Append("a", _ => { });
        clock.AdvanceMs(1);
        throttler.Append("b", _ => { });

        Assert.Equal("ab", throttler.Flush());
    }

    [Fact]
    public void NonPositiveInterval_Throws()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new StreamingTextThrottler(0));
    }
}
