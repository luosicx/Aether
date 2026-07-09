# 截图目录

本目录存放 AIBuilder App 的截图，用于文档与 App Store 展示。

## 截图清单

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

## 注意事项

- 截图分辨率：iOS 使用 iPhone 17（6.7"）全屏；macOS 使用 1000x700 窗口
- 截图内容不应包含真实 API Key 或用户隐私数据
- 截图用于文档（README.md / USAGE.md）与 App Store 展示
