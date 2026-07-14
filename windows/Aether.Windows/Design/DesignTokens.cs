using Windows.UI;
using Windows.UI.Text;
using Windows.UI.Xaml.Media;

namespace Aether.Windows.Design
{
    /// <summary>
    /// Auto-generated from tokens.json. Do not edit manually.
    /// 单一真相源：DesignTokens/tokens.json
    /// 生成脚本：scripts/gen_csharp_tokens.py
    /// </summary>
    public static class DesignTokens
    {
        #region Color
        /// <summary>深空黑/浅空白基底</summary>
        public static Color DeepSpaceColor => Color.FromArgb(255, 10, 14, 26);
        /// <summary>神秘紫强调色</summary>
        public static Color AetherPurpleColor => Color.FromArgb(255, 124, 58, 237);
        /// <summary>电光蓝交互色</summary>
        public static Color ElectricBlueColor => Color.FromArgb(255, 0, 212, 255);
        /// <summary>液态玻璃卡片基底（带 alpha）</summary>
        public static Color LiquidGlassColor => Color.FromArgb(128, 28, 28, 46);
        /// <summary>星云光晕高光</summary>
        public static Color NebulaGlowColor => Color.FromArgb(255, 255, 229, 180);
        /// <summary>星光白/夜色文字</summary>
        public static Color StarlightColor => Color.FromArgb(255, 229, 231, 235);
        /// <summary>暮色灰（系统色 fallback）</summary>
        public static Color DuskGrayColor => Color.FromArgb(255, 75, 85, 99);
        #endregion

        #region Typography
        /// <summary>Aether 标题</summary>
        public static double AetherTitleFontSize => 28;
        public static FontWeight AetherTitleFontWeight => FontWeights.SemiBold;
        /// <summary>Aether 展示字体（开屏 Logo / 大标题）</summary>
        public static double AetherDisplayFontSize => 48;
        public static FontWeight AetherDisplayFontWeight => FontWeights.Bold;
        /// <summary>Aether 正文</summary>
        public static double AetherBodyFontSize => 16;
        public static FontWeight AetherBodyFontWeight => FontWeights.Normal;
        #endregion

        #region Spacing
        /// <summary>2pt</summary>
        public static double SpacingXs => 2;
        /// <summary>4pt</summary>
        public static double SpacingSm => 4;
        /// <summary>8pt</summary>
        public static double SpacingMd => 8;
        /// <summary>12pt</summary>
        public static double SpacingLg => 12;
        /// <summary>16pt</summary>
        public static double SpacingXl => 16;
        /// <summary>24pt</summary>
        public static double SpacingXxl => 24;
        /// <summary>32pt</summary>
        public static double SpacingXxxl => 32;
        #endregion

        #region CornerRadius
        /// <summary>小圆角</summary>
        public static double CornerSmall => 12;
        /// <summary>中圆角</summary>
        public static double CornerMedium => 16;
        /// <summary>大圆角</summary>
        public static double CornerLarge => 24;
        /// <summary>胶囊圆角</summary>
        public static double CornerPill => 999;
        #endregion

        #region Animation (duration in ms)
        /// <summary>页面转场 0.25s</summary>
        public static int AnimTransitionMs => 250;
        /// <summary>消息进入 0.2s</summary>
        public static int AnimMessageAppearMs => 200;
        /// <summary>按钮按下 0.1s</summary>
        public static int AnimButtonPressMs => 100;
        #endregion

    }
}
