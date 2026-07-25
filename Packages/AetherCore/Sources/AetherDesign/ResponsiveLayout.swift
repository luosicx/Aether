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

/// v1.2: 响应式布局尺寸档位
/// 综合 horizontalSizeClass 与实际宽度判定，用于视图层精细适配
public enum LayoutSize: Equatable {
    /// 紧凑：iPhone SE / iPhone 竖屏 / compact size class
    case compact
    /// 中等：iPhone Pro Max 横屏 / iPad Mini 竖屏 / regular 但宽度有限
    case medium
    /// 大：iPad Pro 竖屏 / iPad Mini 横屏
    case large
    /// 超大：iPad Pro 横屏 / macOS 超宽屏（≥1440pt）
    case xl

    /// 按宽度与 horizontal size class 联合判定
    /// - Parameters:
    ///   - width: 可用宽度
    ///   - sizeClass: horizontal size class（.compact / .regular / .other）
    public static func resolve(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> LayoutSize {
        if horizontalSizeClass == .compact {
            return width <= 375 ? .compact : .medium
        }
        // regular size class：iPad / macOS
        if width < 768 {
            return .medium
        } else if width < 1024 {
            return .large
        } else if width < 1440 {
            return .large
        } else {
            return .xl
        }
    }

    /// 消息气泡最大宽度建议（pt）
    /// compact 自适应撑满；medium 限 500；large/xl 限 680 防止过宽难读
    public var bubbleMaxWidth: CGFloat {
        switch self {
        case .compact: return .infinity
        case .medium: return 500
        case .large: return 680
        case .xl: return 680
        }
    }

    /// 工具栏是否折叠为 Menu（紧凑空间下折叠，避免图标拥挤）
    public var toolbarCollapseToMenu: Bool {
        switch self {
        case .compact: return true
        case .medium, .large, .xl: return false
        }
    }

    /// 输入框是否单行（紧凑空间折叠多行输入框）
    public var inputBarSingleLine: Bool {
        self == .compact
    }

    /// 是否启用三栏布局（macOS 超宽屏常驻工具面板）
    public var enableThreeColumn: Bool {
        self == .xl
    }
}

/// SwiftUI horizontal size class 的本地封装
public enum UserInterfaceSizeClass {
    case compact
    case regular
    case other
}

/// v1.2: 布局策略协议
/// 抽象布局决策，便于按设备注入不同策略，避免 iPad 分栏与 macOS 三栏共用代码相互耦合
public protocol LayoutStrategy {
    /// 当前布局档位
    var layoutSize: LayoutSize { get }

    /// 是否启用 NavigationSplitView 分栏
    var supportsSplitView: Bool { get }

    /// 分栏可视化模式（.automatic / .balanced / .prominentDetail）
    var splitViewStyle: SplitViewStyle { get }

    /// 是否常驻第三栏（Agent 协作图 / 知识库）
    var persistentThirdColumn: Bool { get }
}

/// 分栏样式枚举
public enum SplitViewStyle: Equatable {
    case automatic
    case balanced
    case prominentDetail
}

/// 默认布局策略：基于 LayoutSize 决策
public struct DefaultLayoutStrategy: LayoutStrategy {
    public let layoutSize: LayoutSize

    public init(layoutSize: LayoutSize) {
        self.layoutSize = layoutSize
    }

    public var supportsSplitView: Bool {
        // medium 及以上启用分栏（iPad Mini 横屏以上）
        layoutSize != .compact
    }

    public var splitViewStyle: SplitViewStyle {
        switch layoutSize {
        case .compact: return .automatic
        case .medium: return .balanced
        case .large, .xl: return .prominentDetail
        }
    }

    public var persistentThirdColumn: Bool {
        // 仅 macOS 超宽屏常驻第三栏
        layoutSize == .xl
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
