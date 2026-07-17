import SwiftUI
import AetherDesign
#if os(iOS)
import UIKit
#endif

/// Task 12: 为 MessageSnapshot 添加 Hashable 支持，用于 Diffable Data Source 项标识。
/// 仅以 id 作为哈希依据；相等性仍由合成 Equatable（全字段比较）决定。
/// 同一 id 但内容变化的快照会触发对应 Cell 的重载。
extension MessageSnapshot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Task 12: 虚拟化消息列表
/// - iOS: 使用 UICollectionView + UIHostingConfiguration 实现 Cell 复用，支持 500+ 消息流畅滚动
/// - macOS: 回退到 SwiftUI ScrollView + LazyVStack（LazyVStack 已具备按需渲染能力）
struct VirtualizedMessageList<Message: Identifiable & Hashable, Content: View, Footer: View>: View {
    /// 消息数据
    let messages: [Message]
    /// 当此值变化时触发自动滚动到底部
    let autoScrollTrigger: AnyHashable?
    /// 当此值变化时强制重新配置所有消息 Cell（用于 prefs / reduceMotion 等状态变更）
    let contentRefreshTrigger: AnyHashable?
    /// 滚动是否使用动画
    let scrollAnimated: Bool
    /// 单条消息的渲染闭包
    let content: (Message) -> Content
    /// 底部追加内容（流式气泡、引用、工具步骤、加载状态等）
    let footer: Footer

    /// 创建虚拟化消息列表
    /// - Parameters:
    ///   - messages: 消息数据
    ///   - autoScrollTrigger: 当此值变化时触发自动滚动到底部
    ///   - contentRefreshTrigger: 当此值变化时强制刷新所有消息 Cell
    ///   - scrollAnimated: 滚动是否使用动画
    ///   - content: 单条消息的渲染闭包
    ///   - footer: 底部追加内容
    init(
        messages: [Message],
        autoScrollTrigger: AnyHashable?,
        contentRefreshTrigger: AnyHashable?,
        scrollAnimated: Bool = true,
        @ViewBuilder content: @escaping (Message) -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.messages = messages
        self.autoScrollTrigger = autoScrollTrigger
        self.contentRefreshTrigger = contentRefreshTrigger
        self.scrollAnimated = scrollAnimated
        self.content = content
        self.footer = footer()
    }

    var body: some View {
        #if os(iOS)
        _IOSVirtualizedList(
            messages: messages,
            autoScrollTrigger: autoScrollTrigger,
            contentRefreshTrigger: contentRefreshTrigger,
            scrollAnimated: scrollAnimated,
            content: content,
            footer: AnyView(footer)
        )
        #else
        _MacVirtualizedList(
            messages: messages,
            autoScrollTrigger: autoScrollTrigger,
            scrollAnimated: scrollAnimated,
            content: content,
            footer: footer
        )
        #endif
    }
}

// MARK: - macOS 实现

#if !os(iOS)
/// macOS 回退实现：ScrollView + LazyVStack（LazyVStack 自身已具备按需渲染能力）
private struct _MacVirtualizedList<Message: Identifiable & Hashable, Content: View, Footer: View>: View {
    let messages: [Message]
    let autoScrollTrigger: AnyHashable?
    let scrollAnimated: Bool
    let content: (Message) -> Content
    let footer: Footer

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(messages) { message in
                        content(message)
                            .id(message.id)
                    }
                    footer
                        .id("footer")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: autoScrollTrigger) {
                if scrollAnimated {
                    withAnimation(AnimationTokens.messageBubble) {
                        scrollToBottom(proxy: proxy)
                    }
                } else {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    /// 滚动到最后一条消息，若无消息则滚动到 Footer
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        } else {
            proxy.scrollTo("footer", anchor: .bottom)
        }
    }
}
#endif

// MARK: - iOS 实现

#if os(iOS)
/// iOS Diffable Data Source 项类型：消息或底部 Footer
private enum _ListItem<Message: Hashable>: Hashable {
    case message(Message)
    case footer
}

/// iOS UICollectionView 包装器，通过 UIViewRepresentable 暴露给 SwiftUI。
/// 使用 UICollectionViewCompositionalLayout.list + NSDiffableDataSourceSnapshot 实现高效 Cell 复用。
private struct _IOSVirtualizedList<Message: Identifiable & Hashable, Content: View>: UIViewRepresentable {
    let messages: [Message]
    let autoScrollTrigger: AnyHashable?
    let contentRefreshTrigger: AnyHashable?
    let scrollAnimated: Bool
    let content: (Message) -> Content
    let footer: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, footer: footer)
    }

    func makeUIView(context: Context) -> UICollectionView {
        // SubTask 12.2: 使用 UICollectionViewCompositionalLayout.list 创建列表布局
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
            // 消息间距 18pt，与原 LazyVStack spacing 一致
            section.interItemSpacing = .fixed(18)
            // 内边距与原 padding(.horizontal, 16) / padding(.vertical, 14) 一致
            section.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            return section
        }

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        // Task 3: 向下滑动消息列表时交互式收起键盘
        collectionView.keyboardDismissMode = .interactive

        // SubTask 12.4: 消息 Cell 注册——使用 UIHostingConfiguration（UIContentConfiguration）包装 SwiftUI 视图
        // Cell 复用由 UICollectionView 管理，注册闭包中仅做轻量 contentConfiguration 赋值，不做重计算
        let messageRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Message> { cell, _, message in
            cell.contentConfiguration = UIHostingConfiguration {
                context.coordinator.content(message)
            }
            .margins(.all, 0)
        }

        // Footer Cell 注册——渲染流式气泡、引用、工具步骤等底部内容
        let footerRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, _ListItem<Message>> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                context.coordinator.footerView
            }
            .margins(.all, 0)
        }

        // SubTask 12.2: 使用 NSDiffableDataSourceSnapshot 进行 diffable data source
        let dataSource = UICollectionViewDiffableDataSource<Int, _ListItem<Message>>(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .message(let message):
                return cv.dequeueConfiguredReusableCell(using: messageRegistration, for: indexPath, item: message)
            case .footer:
                return cv.dequeueConfiguredReusableCell(using: footerRegistration, for: indexPath, item: .footer)
            }
        }

        context.coordinator.dataSource = dataSource
        context.coordinator.collectionView = collectionView

        // 应用初始快照
        context.coordinator.applySnapshot(
            messages: messages,
            animatingDifferences: false,
            reconfigureMessages: true,
            reconfigureFooter: true
        )

        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        // 检测 content 闭包是否需要刷新（prefs / reduceMotion 等状态变化）
        let needsContentRefresh = context.coordinator.lastContentRefreshTrigger != contentRefreshTrigger
        if needsContentRefresh {
            context.coordinator.lastContentRefreshTrigger = contentRefreshTrigger
            // 更新 Coordinator 中的 content 闭包，使后续 Cell 注册闭包调用使用最新闭包
            context.coordinator.content = content
        }

        // 更新 Coordinator 中存储的 footer 视图（每次 SwiftUI 重渲染都会传入最新 footer）
        context.coordinator.footerView = footer

        // 判断是否需要自动滚动
        let shouldScroll = context.coordinator.lastScrollTrigger != autoScrollTrigger
        if shouldScroll {
            context.coordinator.lastScrollTrigger = autoScrollTrigger
        }

        // 应用最新快照；Footer 始终刷新（流式更新），消息仅在 content 闭包变化时刷新
        context.coordinator.applySnapshot(
            messages: messages,
            animatingDifferences: true,
            reconfigureMessages: needsContentRefresh,
            reconfigureFooter: true
        )

        // SubTask 12.2: 支持自动滚动到底部——在快照应用后的下一个主线程周期执行
        if shouldScroll {
            let animated = scrollAnimated
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                coordinator.scrollToBottom(animated: animated)
            }
        }
    }

    /// Coordinator：持有 content 闭包、footer 视图与 data source 引用
    final class Coordinator {
        // 使用 var 以便 contentRefreshTrigger 变化时替换为最新闭包
        var content: (Message) -> Content
        var footerView: AnyView
        var dataSource: UICollectionViewDiffableDataSource<Int, _ListItem<Message>>?
        weak var collectionView: UICollectionView?
        var lastScrollTrigger: AnyHashable?
        var lastContentRefreshTrigger: AnyHashable?

        init(content: @escaping (Message) -> Content, footer: AnyView) {
            self.content = content
            self.footerView = footer
        }

        /// 构建并应用 Diffable Data Source 快照
        /// - Parameters:
        ///   - messages: 当前消息列表
        ///   - animatingDifferences: 是否动画过渡
        ///   - reconfigureMessages: 是否强制刷新所有消息 Cell（prefs 等变化时需要）
        ///   - reconfigureFooter: 是否强制刷新 Footer Cell（流式更新时需要）
        func applySnapshot(
            messages: [Message],
            animatingDifferences: Bool,
            reconfigureMessages: Bool = false,
            reconfigureFooter: Bool = false
        ) {
            var snapshot = NSDiffableDataSourceSnapshot<Int, _ListItem<Message>>()
            snapshot.appendSections([0])
            let messageItems = messages.map { _ListItem<Message>.message($0) }
            snapshot.appendItems(messageItems, toSection: 0)
            snapshot.appendItems([.footer], toSection: 0)
            // iOS 15+: reconfigureItems 仅重新调用 Cell 注册闭包，不触发插入/删除动画
            if reconfigureMessages {
                snapshot.reconfigureItems(messageItems)
            }
            if reconfigureFooter {
                snapshot.reconfigureItems([.footer])
            }
            dataSource?.apply(snapshot, animatingDifferences: animatingDifferences)
        }

        /// 滚动到最后一个 Cell（消息或 Footer）
        func scrollToBottom(animated: Bool) {
            guard let collectionView = collectionView else { return }
            let lastSection = collectionView.numberOfSections - 1
            guard lastSection >= 0 else { return }
            let lastItem = collectionView.numberOfItems(inSection: lastSection) - 1
            guard lastItem >= 0 else { return }
            collectionView.scrollToItem(
                at: IndexPath(item: lastItem, section: lastSection),
                at: .bottom,
                animated: animated
            )
        }
    }
}
#endif
