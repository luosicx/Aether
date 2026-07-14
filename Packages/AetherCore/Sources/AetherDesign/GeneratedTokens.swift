import SwiftUI

// Auto-generated from tokens.json. Do not edit manually.
// 单一真相源：DesignTokens/tokens.json
// 生成脚本：scripts/gen_swift_tokens.py

public extension Color {
    /// 深空黑/浅空白基底
    static let genDeepSpace = Color(red: 0.039216, green: 0.054902, blue: 0.101961, opacity: 1.0)
    /// 神秘紫强调色
    static let genAetherPurple = Color(red: 0.486275, green: 0.227451, blue: 0.929412, opacity: 1.0)
    /// 电光蓝交互色
    static let genElectricBlue = Color(red: 0.0, green: 0.831373, blue: 1.0, opacity: 1.0)
    /// 液态玻璃卡片基底（带 alpha）
    static let genLiquidGlass = Color(red: 0.109804, green: 0.109804, blue: 0.180392, opacity: 0.501961)
    /// 星云光晕高光
    static let genNebulaGlow = Color(red: 1.0, green: 0.898039, blue: 0.705882, opacity: 1.0)
    /// 星光白/夜色文字
    static let genStarlight = Color(red: 0.898039, green: 0.905882, blue: 0.921569, opacity: 1.0)
    /// 暮色灰（系统色 fallback）
    static let genDuskGray = Color(red: 0.294118, green: 0.333333, blue: 0.388235, opacity: 1.0)
}

public extension Font {
    /// Aether 标题
    static let genAetherTitle = .system(size: 28, weight: .semibold)
    /// Aether 展示字体（开屏 Logo / 大标题）
    static let genAetherDisplay = .system(size: 48, weight: .bold)
    /// Aether 正文
    static let genAetherBody = .system(size: 16, weight: .regular)
}

public enum GeneratedSpacing {
    /// 2pt
    public static let xs: CGFloat = 2.0
    /// 4pt
    public static let sm: CGFloat = 4.0
    /// 8pt
    public static let md: CGFloat = 8.0
    /// 12pt
    public static let lg: CGFloat = 12.0
    /// 16pt
    public static let xl: CGFloat = 16.0
    /// 24pt
    public static let xxl: CGFloat = 24.0
    /// 32pt
    public static let xxxl: CGFloat = 32.0
}

public enum GeneratedCornerRadius {
    /// 小圆角
    public static let small: CGFloat = 12.0
    /// 中圆角
    public static let medium: CGFloat = 16.0
    /// 大圆角
    public static let large: CGFloat = 24.0
    /// 胶囊圆角
    public static let pill: CGFloat = 999.0
}

public enum GeneratedAnimation {
    /// 页面转场 0.25s
    public static let transition: Animation = .easeInOut(duration: 0.25)
    /// 消息进入 0.2s
    public static let messageAppear: Animation = .easeInOut(duration: 0.2)
    /// 按钮按下 0.1s
    public static let buttonPress: Animation = .easeInOut(duration: 0.1)
}
