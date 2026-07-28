# PlantUML 图表说明

本目录存放 Aether 项目的 PlantUML 源文件（`.puml`），用于本地详细查看系统架构与关键流程。

## 文件清单

> 下列 PlantUML 图描述的是 **Apple 端（iOS / macOS）** 的架构与关键流程。Windows 与 Android 端的架构图以 Mermaid 形式直接嵌入在 `doc/ARCHITECTURE.md` 中，详见下方「跨平台架构图」章节。

| 文件 | 类型 | 描述 |
|------|------|------|
| `architecture-overview.puml` | 类图（分层架构） | 表现层 / 领域层 / 服务层 / 数据层四层架构总览，展示模块间依赖关系 |
| `react-loop.puml` | 时序图（sequenceDiagram） | ReAct 工具调用循环：缓存查询 → RAG 检索 → LLM 调用 → 工具执行 → 循环收尾，最大 5 轮 |
| `rag-dataflow.puml` | 活动图（activity） | RAG 知识库数据流：文档导入 → 分块 → 嵌入 → 存储；查询检索 → 相似度匹配 → prompt 注入 |
| `provider-fallback.puml` | 状态图（stateDiagram） | Provider 降级流程：SmartRouter 路由 → 主 Provider 调用 → 失败检测 → Fallback 降级；网络监听自动切换 |

## 跨平台架构图

自 v1.5.0 起，Aether 已交付 Windows 与 Android 双端，与 Apple 三端共同构成跨平台架构。Windows 端与 Android 端的架构图使用 Mermaid 形式，直接嵌入在 [`doc/ARCHITECTURE.md`](../ARCHITECTURE.md) 的对应章节中，便于在 GitHub / GitLab 上原生渲染，无需安装额外工具。相关章节如下：

| 章节 | 标题 | 内容 |
|------|------|------|
| [2.0](../ARCHITECTURE.md#20-跨平台架构总览v150-起) | 跨平台架构总览（v1.5.0 起） | Windows + Android + Rust 多形态分发的整体架构 |
| [2.2](../ARCHITECTURE.md#22-windows-端分层架构v150) | Windows 端分层架构（v1.5.0） | Windows 端表现层 / 业务层 / 数据层分层 |
| [2.3](../ARCHITECTURE.md#23-android-端分层架构v150) | Android 端分层架构（v1.5.0） | Android 端 UI 层 / Domain 层 / Data 层分层 |
| [3.8](../ARCHITECTURE.md#38-windows-端模块职责v150) | Windows 端模块职责（v1.5.0） | Windows 端各模块职责划分 |
| [3.9](../ARCHITECTURE.md#39-android-端模块职责v150) | Android 端模块职责（v1.5.0） | Android 端各模块职责划分 |
| [4.11](../ARCHITECTURE.md#411-windows-端数据流v150) | Windows 端数据流（v1.5.0） | Windows 端关键数据流时序 |
| [4.12](../ARCHITECTURE.md#412-android-端数据流v150) | Android 端数据流（v1.5.0） | Android 端关键数据流时序 |

## PlantUML 与 Mermaid 的分工

Aether 项目同时使用两种图表工具：

- **Mermaid（在 `ARCHITECTURE.md` 中）**：用于 GitHub / GitLab 原生渲染，无需安装额外工具即可在浏览器中查看。适合快速浏览的整体架构概览。**Apple 端整体架构图（2.1 节）以及 Windows / Android 端的全部架构图（2.0 / 2.2 / 2.3 / 3.8 / 3.9 / 4.11 / 4.12 节）均以 Mermaid 形式嵌入 `ARCHITECTURE.md`，便于在 GitHub 上直接渲染。**
- **PlantUML（本目录）**：用于本地详细查看，支持更丰富的图类型（状态图、活动图等）和更精细的样式控制。适合深度设计评审与本地文档生成。当前本目录的 PlantUML 图聚焦 Apple 端（iOS / macOS）的架构与关键流程。

两者描述的架构与流程一致，区别仅在渲染工具与详细程度。

## 渲染方法

### 方法一：VS Code PlantUML 插件（推荐）

1. 在 VS Code 中安装 [PlantUML 插件](https://marketplace.visualstudio.com/items?itemName=jebbs.plantuml)（`jebbs.plantuml`）
2. 打开任意 `.puml` 文件
3. 按 `Alt + D`（macOS: `Option + D`）预览图表
4. 或按 `Ctrl + Shift + P` → 输入 `PlantUML: Export Current Diagram` 导出为 PNG / SVG

> 默认使用 PlantUML Web Server 渲染，若需本地渲染请安装 Java + Graphviz 并在设置中将 `plantuml.render` 改为 `Local`。

### 方法二：命令行渲染

```bash
# 安装 Java（如未安装）
brew install java

# 安装 Graphviz（本地渲染依赖）
brew install graphviz

# 下载 plantuml.jar
curl -L -o plantuml.jar https://github.com/plantuml/plantuml/releases/latest/download/plantuml.jar

# 渲染为 PNG
java -jar plantuml.jar architecture-overview.puml

# 渲染为 SVG（矢量图，推荐）
java -jar plantuml.jar -tsvg architecture-overview.puml

# 批量渲染当前目录所有 .puml 文件
java -jar plantuml.jar -tsvg *.puml
```

### 方法三：在线渲染

1. 打开 [PlantUML Online Server](http://www.plantuml.com/plantuml/uml/)
2. 将 `.puml` 文件内容粘贴到输入框
3. 自动渲染并支持导出 PNG / SVG

## 相关文档

- [ARCHITECTURE.md](../ARCHITECTURE.md) — 架构总览与模块职责（含 Apple / Windows / Android 三端 Mermaid 图表）
- [API.md](../API.md) — API 契约文档
- [WINDOWS_BUILD.md](../WINDOWS_BUILD.md) — Windows 端构建与打包说明（v1.5.0）
- [ANDROID_BUILD.md](../ANDROID_BUILD.md) — Android 端构建与打包说明（v1.5.0）
