# PlantUML 图表说明

本目录存放 Aether 项目的 PlantUML 源文件（`.puml`），用于本地详细查看系统架构与关键流程。

## 文件清单

| 文件 | 类型 | 描述 |
|------|------|------|
| `architecture-overview.puml` | 类图（分层架构） | 表现层 / 领域层 / 服务层 / 数据层四层架构总览，展示模块间依赖关系 |
| `react-loop.puml` | 时序图（sequenceDiagram） | ReAct 工具调用循环：缓存查询 → RAG 检索 → LLM 调用 → 工具执行 → 循环收尾，最大 5 轮 |
| `rag-dataflow.puml` | 活动图（activity） | RAG 知识库数据流：文档导入 → 分块 → 嵌入 → 存储；查询检索 → 相似度匹配 → prompt 注入 |
| `provider-fallback.puml` | 状态图（stateDiagram） | Provider 降级流程：SmartRouter 路由 → 主 Provider 调用 → 失败检测 → Fallback 降级；网络监听自动切换 |

## PlantUML 与 Mermaid 的分工

Aether 项目同时使用两种图表工具：

- **Mermaid（在 `ARCHITECTURE.md` 中）**：用于 GitHub / GitLab 原生渲染，无需安装额外工具即可在浏览器中查看。适合快速浏览的整体架构概览。
- **PlantUML（本目录）**：用于本地详细查看，支持更丰富的图类型（状态图、活动图等）和更精细的样式控制。适合深度设计评审与本地文档生成。

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

- [ARCHITECTURE.md](../ARCHITECTURE.md) — 架构总览与模块职责（Mermaid 图表）
- [API.md](../API.md) — API 契约文档
