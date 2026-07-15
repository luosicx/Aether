import SwiftUI

/// 设备类型：按宽度划分五档，用于响应式布局适配
public enum DeviceType: Equatable {
    /// iPhone SE 及更小（width <= 375）
    case iPhoneSE
    /// iPhone 标准宽（width <= 430）
    case iPhone
    /// iPad Mini / iPad（width <= 768）
    case iPadMini
    /// iPad Pro（width <= 1024）
    case iPadPro
    /// macOS 超宽屏（width > 1024）
    case macWide

    /// 按给定宽度判断设备类型
    public static func current(width: CGFloat) -> DeviceType {
        if width <= 375 {
            return .iPhoneSE
        } else if width <= 430 {
            return .iPhone
        } else if width <= 768 {
            return .iPadMini
        } else if width <= 1024 {
            return .iPadPro
        } else {
            return .macWide
        }
    }

    /// 对应的最大内容宽度
    /// iPhone 系列不限制（撑满屏幕）；iPad/macOS 逐级限制以获得更好的阅读宽度
    public var maxContentWidth: CGFloat {
        switch self {
        case .iPhoneSE, .iPhone: return .infinity
        case .iPadMini: return 600
        case .iPadPro: return 800
        case .macWide: return 1000
        }
    }
}

/// 响应式布局修饰器：根据可用宽度自动限制内容最大宽度并居中
/// 使用方式：`content.responsiveLayout()`
public struct ResponsiveModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        GeometryReader { geo in
            let device = DeviceType.current(width: geo.size.width)
            content
                .frame(maxWidth: device.maxContentWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

public extension View {
    /// 应用响应式布局：在大屏设备（iPad/macOS）上限制最大宽度并居中
    func responsiveLayout() -> some View {
        modifier(ResponsiveModifier())
    }
}
