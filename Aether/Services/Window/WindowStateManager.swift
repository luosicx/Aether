#if os(macOS)
import Foundation
import CoreGraphics
import os

/// v2.0 macOS 多窗口窗口状态。
///
/// 记录单个对话窗口的位置、大小、聚焦状态及最近活跃时间，
/// 通过 JSON 编码持久化到 UserDefaults，用于多窗口场景下恢复窗口布局。
struct WindowState: Codable, Equatable, Sendable {
    /// 对话 ID，唯一标识窗口所属会话
    let conversationId: UUID
    /// 窗口 frame（位置与大小）
    let frame: CGRect
    /// 是否为当前聚焦窗口
    let isFocused: Bool
    /// 最近活跃时间，用于排序与恢复最近使用的窗口
    let lastActiveAt: Date
}

/// v2.0 macOS 多窗口状态管理器。
///
/// 维护对话 ID 到窗口状态的映射，通过 UserDefaults（JSON 编码）持久化，
/// 支持窗口位置、大小、聚焦状态的保存与恢复。`@MainActor` 隔离保证并发安全，
/// 适用于 UI 层在窗口创建/移动/关闭时同步更新状态。
///
/// 存储 key 使用 "aether.window." 前缀 + conversationId UUID 字符串，
/// 每个窗口状态独立持久化，避免与其他模块冲突。
@MainActor
final class WindowStateManager {
    /// 单例，使用 `UserDefaults.standard` 持久化
    static let shared = WindowStateManager()

    /// 对话 ID 到窗口状态的映射（内存缓存，与 UserDefaults 保持同步）
    private(set) var windowStates: [UUID: WindowState] = [:]

    /// UserDefaults 存储实例（默认 `.standard`，测试可注入隔离实例）
    private let userDefaults: UserDefaults

    /// 存储 key 前缀，避免与其他模块冲突
    private let keyPrefix = "aether.window."

    /// 初始化管理器并加载已有窗口状态到内存。
    /// - Parameter userDefaults: 持久化存储实例，默认 `.standard`
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadAllWindowStates()
    }

    // MARK: - 公开接口

    /// 保存指定对话的窗口状态，覆盖已有状态并刷新 `lastActiveAt`。
    /// - Parameters:
    ///   - conversationId: 对话 ID
    ///   - frame: 窗口 frame（位置与大小）
    ///   - isFocused: 是否为当前聚焦窗口
    func saveWindowState(conversationId: UUID, frame: CGRect, isFocused: Bool) {
        let state = WindowState(
            conversationId: conversationId,
            frame: frame,
            isFocused: isFocused,
            lastActiveAt: Date()
        )
        windowStates[conversationId] = state
        persist(state)
        // Logger 不支持直接插值 CGRect，且为避免引入 AppKit，手动拼接 frame 字符串
        let frameDescription = "(\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height))"
        Logger.window.debug("已保存窗口状态 conversationId=\(conversationId.uuidString, privacy: .public) frame=\(frameDescription, privacy: .public) isFocused=\(isFocused, privacy: .public)")
    }

    /// 加载指定对话的窗口状态。
    /// - Parameter conversationId: 对话 ID
    /// - Returns: 已保存的窗口状态；不存在时返回 nil
    func loadWindowState(conversationId: UUID) -> WindowState? {
        windowStates[conversationId]
    }

    /// 移除指定对话的窗口状态，同时清除 UserDefaults 中的持久化数据。
    /// - Parameter conversationId: 对话 ID
    func removeWindowState(conversationId: UUID) {
        windowStates.removeValue(forKey: conversationId)
        userDefaults.removeObject(forKey: key(for: conversationId))
        Logger.window.debug("已移除窗口状态 conversationId=\(conversationId.uuidString, privacy: .public)")
    }

    /// 获取所有已保存的窗口状态。
    /// - Returns: 全部窗口状态数组（顺序不保证）
    func getAllWindowStates() -> [WindowState] {
        Array(windowStates.values)
    }

    // MARK: - 私有 helper

    /// 生成指定对话 ID 对应的 UserDefaults key。
    /// - Parameter id: 对话 ID
    /// - Returns: "aether.window.<uuid>" 格式的 key
    private func key(for id: UUID) -> String {
        keyPrefix + id.uuidString
    }

    /// 将单个窗口状态 JSON 编码后写入 UserDefaults。
    /// 编码失败时记录日志并保留内存缓存（不影响后续读取）。
    /// - Parameter state: 待持久化的窗口状态
    private func persist(_ state: WindowState) {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: key(for: state.conversationId))
        } catch {
            Logger.window.error("窗口状态持久化失败 conversationId=\(state.conversationId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 初始化时从 UserDefaults 加载所有 "aether.window." 前缀的窗口状态到内存。
    /// 解码失败的条目静默跳过，避免单个坏数据阻塞整体恢复。
    private func loadAllWindowStates() {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            guard let data = userDefaults.data(forKey: key) else { continue }
            do {
                let state = try JSONDecoder().decode(WindowState.self, from: data)
                windowStates[state.conversationId] = state
            } catch {
                Logger.window.warning("窗口状态解码失败 key=\(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Logger 扩展

/// 窗口模块日志分类，沿用项目 subsystem "com.aether.app"。
private extension Logger {
    static let window = Logger(subsystem: "com.aether.app", category: "window")
}
#endif
