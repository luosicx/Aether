#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation
import AppKit
import AetherServices
import AetherDesign
import AetherUI

/// Task 2.5: macOS 专属 App 入口。配置窗口大小、菜单栏命令、MenuBarExtra。
@main
struct AetherApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 800, minHeight: 500)
                .task {
                    // 预热语音引擎：触发 speechsynthesisd daemon 启动和音色库加载
                    Task.detached(priority: .background) {
                        _ = AVSpeechSynthesisVoice.speechVoices()
                    }
                    // 延迟 1 秒让首屏先完成渲染，再发起网络请求
                    try? await Task.sleep(for: .seconds(1))
                    await RemoteConfigService.shared.fetch()
                }
                .preferredColorScheme(.dark)
                .environment(ThemeManager.shared)
        }
        .defaultSize(width: 1000, height: 700)
        .modelContainer(AetherApp.sharedModelContainer)
        // Task 4: macOS 菜单栏 —— 新建对话 / 搜索会话 / 设置
        .commands {
            // File → 新建对话 (Cmd+N)
            CommandGroup(replacing: .newItem) {
                Button("新建对话") {
                    NotificationCenter.default.post(name: .newConversationRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                // Task 20: macOS 新建窗口 (Cmd+Shift+N)
                Button("新建窗口") {
                    NotificationCenter.default.post(name: .newWindowRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // Edit → 搜索会话 (Cmd+K)
            CommandGroup(after: .textEditing) {
                Button("搜索会话") {
                    NotificationCenter.default.post(name: .searchRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                // 性能优化：⌘Shift+F 聚焦搜索
                Button("聚焦搜索") {
                    NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            // App → 设置 (Cmd+,)
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    NotificationCenter.default.post(name: .settingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        // Task 20: macOS 多窗口——通过 UUID 参数打开指定对话的新窗口
        WindowGroup("New Conversation", for: UUID.self) { $conversationID in
            RootView()
                .environment(\.conversationID, conversationID)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
                .environment(ThemeManager.shared)
        }
        .defaultSize(width: 1000, height: 700)
        // Task 24: macOS 菜单栏常驻模式
        MenuBarExtra("Aether", systemImage: "sparkles") {
            MenuBarPanel()
                .environment(ThemeManager.shared)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(AetherApp.sharedModelContainer)
    }

    /// macOS 初始化：仅共享初始化逻辑（无 BGTaskScheduler）
    init() {
        sharedInit()
    }
}
#endif
