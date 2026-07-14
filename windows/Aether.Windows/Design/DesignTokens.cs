// 从 tokens.json 生成（Phase 3），适配 WPF
using System.Windows.Media;

namespace Aether.Windows.Design;

/// <summary>设计令牌：品牌色</summary>
public static class AetherColors
{
    public static SolidColorBrush DeepSpace => new(Color.FromArgb(0xFF, 0x0A, 0x0E, 0x1A));
    public static SolidColorBrush AetherPurple => new(Color.FromArgb(0xFF, 0x7C, 0x3A, 0xED));
    public static SolidColorBrush ElectricBlue => new(Color.FromArgb(0xFF, 0x00, 0xD4, 0xFF));
    public static SolidColorBrush LiquidGlass => new(Color.FromArgb(0x80, 0x1C, 0x1C, 0x2E));
    public static SolidColorBrush NebulaGlow => new(Color.FromArgb(0xFF, 0xFF, 0xE5, 0xB4));
    public static SolidColorBrush Starlight => new(Color.FromArgb(0xFF, 0xE5, 0xE7, 0xEB));
    public static SolidColorBrush DuskGray => new(Color.FromArgb(0xFF, 0x4B, 0x55, 0x63));
}

/// <summary>设计令牌：圆角</summary>
public static class AetherCornerRadius
{
    public static int Small => 12;
    public static int Medium => 16;
    public static int Large => 24;
    public static int Pill => 999;
}

/// <summary>设计令牌：间距</summary>
public static class AetherSpacing
{
    public static int Xs => 2;
    public static int Sm => 4;
    public static int Md => 8;
    public static int Lg => 12;
    public static int Xl => 16;
    public static int Xxl => 24;
    public static int Xxxl => 32;
}
