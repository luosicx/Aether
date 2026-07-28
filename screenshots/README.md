# 截图目录

本目录存放 Aether App 的截图，用于文档与 App Store 展示。

## 截图清单

### iOS / macOS 核心截图

| 文件名 | 平台 | 内容 | 状态 |
|--------|------|------|------|
| `ios_chat_main.png` | iOS | 主对话页（流式回复 + Markdown 渲染） | 已补充 |
| `ios_settings.png` | iOS | 设置页（API Key / 模型选择 / 系统提示词） | 已补充 |
| `ios_knowledge_base.png` | iOS | 知识库（文档导入 + 分块预览） | 已补充 |
| `ios_health_insight.png` | iOS | 健康洞察（授权 + 洞察列表） | 已补充 |
| `ios_ondevice_model.png` | iOS | 端侧推理（模型下载与管理） | 已补充 |
| `ios_preset_prompts.png` | iOS | 预设提示词（11 个角色选择） | 已补充 |
| `macos_chat.png` | macOS | 主对话页（NavigationSplitView 双栏） | 已补充 |
| `macos_settings.png` | macOS | 设置页 | 已补充 |

### 新功能截图（待补充）

| 文件名 | 平台 | 内容 | 状态 |
|--------|------|------|------|
| `ios_language_switch.png` | iOS | 多语言切换（9 选项：跟随系统 + 8 种语言） | 待补充 |
| `ios_theme_switch.png` | iOS | 主题切换（深空 / 黎明 / 极光） | 待补充 |
| `ios_bubble_styles.png` | iOS | 气泡样式（液态玻璃 / 极简 / 卡片） | 待补充 |
| `watch_quick_chat.png` | watchOS | Watch App 快速对话标签 | 待补充（需 Watch target） |
| `watch_health_insight.png` | watchOS | Watch App 健康洞察标签 | 待补充（需 Watch target） |
| `widget_quick_chat.png` | iOS | QuickChat Widget（桌面快捷提问） | 待补充（需 Widget target） |
| `widget_health_insight.png` | iOS | HealthInsight Widget（桌面健康洞察） | 待补充（需 Widget target） |
| `widget_recent_conversations.png` | iOS | RecentConversations Widget（桌面最近会话） | 待补充（需 Widget target） |

### Windows 端截图（v1.5.0，待补充）

v1.5.0 已交付 Windows 端（WPF .NET 8），但截图尚未补充。预期截图清单：

| 文件名 | 平台 | 内容 | 状态 |
|--------|------|------|------|
| `windows_chat_main.png` | Windows | 主对话页（流式回复 + Markdown 渲染） | 待补充 |
| `windows_settings.png` | Windows | 设置页（BFF Token / 模型 / 语言） | 待补充 |
| `windows_conversation_list.png` | Windows | 会话列表页 | 待补充 |

### Android 端截图（v1.5.0，待补充）

v1.5.0 已交付 Android 端（Kotlin + Jetpack Compose），但截图尚未补充。预期截图清单：

| 文件名 | 平台 | 内容 | 状态 |
|--------|------|------|------|
| `android_chat_main.png` | Android | 主对话页（流式回复 + Markdown 渲染） | 待补充 |
| `android_settings.png` | Android | 设置页（BFF Token / 模型 / 语言） | 待补充 |
| `android_rag_search.png` | Android | 知识库检索 | 待补充 |
| `android_health_insight.png` | Android | 健康洞察 | 待补充 |
| `android_conversation_list.png` | Android | 会话列表页 | 待补充 |

## 截图方法

### iOS 模拟器截图
```bash
# 启动模拟器并运行 App 后，使用 Xcode 截图：
# Xcode → Debug → View Debugging → Capture View Hierarchy
# 或直接使用模拟器菜单：File → Save Screen
xcrun simctl io "iPhone 17" screenshot ios_chat_main.png
```

### macOS 截图
```bash
# 运行 macOS App 后，使用 screencapture：
screencapture -o macos_chat.png
```

### watchOS 模拟器截图
```bash
# 启动 watchOS 模拟器并运行 Watch App 后：
xcrun simctl io "Apple Watch Series 10 (46mm)" screenshot watch_quick_chat.png
```

### Widget 截图
```bash
# 在 iOS 模拟器主屏幕添加 Widget 后：
xcrun simctl io "iPhone 17" screenshot widget_quick_chat.png
```

## 注意事项

- 截图分辨率：iOS 使用 iPhone 17（6.7"）全屏；macOS 使用 1000x700 窗口；watchOS 使用 Apple Watch Series 10 (46mm)
- 截图内容不应包含真实 API Key 或用户隐私数据
- 截图用于文档（README.md / USAGE.md）与 App Store 展示
- 多语言截图需切换语言后重新截取（每种语言至少 1 张主对话页）
- Watch / Widget 截图需先在 Xcode 中创建对应 target
