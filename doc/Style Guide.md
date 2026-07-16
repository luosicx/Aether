基于“Aether（以太）”这个充满哲学与科技感的名字，我为你构思了一套完整的视觉方案。核心是围绕 **“液态玻璃（Liquid Glass）”** 和 **“深邃太空”** 的意象展开，让App看起来像是系统原生功能的一种自然延伸，既高级又神秘。

---

### ✨ 品牌视觉理念：无形、无处不在、智能

“Aether”的核心概念是**无形、无处不在**。在UI中，这种“无形”可以表现为**通透的毛玻璃效果**，让背景内容若隐若现，界面层次更丰富；而“智能”则通过**动态光泽**和**微妙的渐变光效**来体现，让界面仿佛有生命力。整体基调是 **“Intelligent Calm”（智能的静谧感）** 。

---

### 🖼️ 图标设计（App Icon）

#### 设计概念：多维的“A”
设计一个极简的、由发光的线条或几何体构成的**字母“A”**，并让它看起来是悬浮在深邃空间中的一个多维物体。

#### 分层结构（参考visionOS）
可采用**三层结构**：
*   **背景层**：一个微妙的、带有星云感的深色渐变球体。
*   **中间层**：半透明的毛玻璃圆盘，带有动态光泽。
*   **前景层**：发光、立体的“A”字或抽象几何符号。

#### 配色方案
*   **主色调**：**深邃的太空黑/深蓝**，营造神秘与无限感。
*   **强调色**：**神秘的紫色**，代表智慧与灵性。
*   **点缀色**：**冷色调的电光蓝**，代表科技与未来感。

#### AI生成提示词（供参考）
> **英文提示词**: `A minimalist app icon for "Aether", a glowing, three-dimensional letter "A" made of translucent Liquid Glass, floating in deep space, surrounded by a subtle nebula of purple and electric blue light, frosted glass effect, dynamic lighting, high quality, 3D render, iOS app icon style, white background --ar 1:1`
>
> **中文提示词**: `一个极简的App图标，名称为“Aether”，一个发光的、三维的字母“A”，由半透明的液态玻璃构成，悬浮在深邃的太空中，周围环绕着紫色和电光蓝的微妙星云，毛玻璃效果，动态光照，高品质，3D渲染，iOS应用图标风格，白色背景 --ar 1:1`

---

### 🎨 UI主体风格

#### 设计语言：液态玻璃（Liquid Glass）
这不仅是设计趋势，更是**苹果官方在WWDC25上推出的全新设计语言**。采用此风格能让App获得：
*   **半透明与浮动感**：界面元素仿佛漂浮在内容之上，层次丰富。
*   **动态光泽**：控件会像真实玻璃一样反射光线，营造真实的物理质感。
*   **圆形与柔和感**：整体风格更圆润、友好。

#### 色彩系统
*   **基础色**：以**深色模式为默认**，使用近乎黑色的深灰蓝作为基底，创造沉浸感。
*   **强调色**：使用**紫色**作为主要强调色，**电光蓝**用于可交互元素。
*   **渐变**：在关键UI元素上使用**紫-蓝渐变**，体现Aether的能量感。

> **Design Token 落地（`Packages/AetherCore/Sources/AetherDesign/ColorTokens.swift`）**：以下语义颜色 token 已在 AetherDesign SPM 模块中统一定义，所有视图应直接引用这些 token，不硬编码 `Color.red` / `Color(.systemGray5)`。
>
> | Token | 说明 |
> |------|------|
> | `Color.deepSpace` | 深空黑/浅空白基底 |
> | `Color.aetherPurple` | 神秘紫强调色 |
> | `Color.electricBlue` | 电光蓝交互色 |
> | `Color.liquidGlass` | 液态玻璃卡片基底 |
> | `Color.nebulaGlow` | 星云光晕高光 |
> | `Color.starlight` | 星光白/夜色文字 |
> | `Color.duskGray` | 暮色灰（系统色 fallback） |

> **aetherGradient 使用说明**：品牌主渐变 `Color.aetherGradient` 已封装为 `LinearGradient(colors: [aetherPurple, electricBlue], startPoint: .topLeading, endPoint: .bottomTrailing)`，在关键 UI 元素（如开屏 Logo、主按钮、标题强调）上直接使用 `.background(Color.aetherGradient)` 即可获得紫→电光蓝的能量感渐变。

#### 字体系统
*   **西文**：使用无衬线字体，强调清晰与自信。
*   **中文**：可搭配`苹方`或`思源黑体`，保持同样的现代感。
*   **排版**：采用**大标题、强对比**的策略。

> **字体 Token 落地（`Packages/AetherCore/Sources/AetherDesign/TypographyTokens.swift`）**：以下 Aether 品牌字体 token 已在 AetherDesign SPM 模块中统一定义，中文由系统 PingFang SC 自动 fallback，无需显式指定。
>
> | Token | 说明 |
> |------|------|
> | `Font.aetherTitle` | Aether 标题（28pt semibold） |
> | `Font.aetherDisplay` | Aether 展示字体，开屏 Logo / 大标题（48pt bold） |
> | `Font.aetherBody` | Aether 正文（16pt regular） |
> | `Font.bodyAI` | AI 对话正文（`.body`） |
> | `Font.subheadlineAI` | AI 副标题（`.subheadline`） |
> | `Font.captionAI` | AI 注释（`.caption2`） |
> | `Font.headlineAI` | AI 标题（`.headline`） |
> | `Font.titleAI` | AI 大标题（`.title2`） |
> | `Font.emptyStateTitle` | 空状态大标题（34pt light） |
> | `Font.monoAI` | 等宽字体（工具消息 / 代码） |
> | `Font.toolLabel` | 工具标签（caption2 medium） |

#### 圆角系统
> **圆角 Token 落地（`Packages/AetherCore/Sources/AetherDesign/DesignTokens.swift` 中的 `CornerRadius`）**：以下圆角 token 已在 AetherDesign SPM 模块中统一定义，适配液态玻璃的圆润感。
>
> | Token | 值 | 说明 |
> |------|----|------|
> | `CornerRadius.small` | 12 | 小元素（按钮、标签） |
> | `CornerRadius.medium` | 16 | 中等元素（卡片、输入框） |
> | `CornerRadius.large` | 24 | 大元素（弹窗、面板） |
> | `CornerRadius.pill` | 999 | 胶囊形（全圆角） |

#### 液态玻璃实现说明
> SwiftUI 中通过系统 Material 实现毛玻璃效果。`Color.bubbleAI` 已设为 `liquidGlass`，配合以下修饰符使用：
> *   `.ultraThinMaterial`：用于**轻量毛玻璃**（气泡背景、悬浮输入栏），通透感最强。
> *   `.regularMaterial`：用于**标准毛玻璃**（设置卡片、StepCard），层次与可读性更平衡。
>
> 示例：助手气泡 `ConversationRow` 使用 `.background(.ultraThinMaterial)` 叠加 `Color.bubbleAI` 实现液态玻璃质感。

---

### 📱 核心界面设计

*   **对话界面**：使用**毛玻璃效果的气泡**替代纯色气泡，AI的回复可带有微弱的紫蓝渐变光晕。
*   **输入框**：设计为**悬浮式毛玻璃输入栏**，固定在屏幕底部。
*   **Agent步骤卡片**：保留步骤卡片，但采用**毛玻璃质感**，步骤之间用发光连线表示进度。
*   **设置与记忆界面**：信息以**毛玻璃卡片**分组，配以柔和光效，**记忆条目**可设计为悬浮的发光小球或标签。

---

### 🛠️ 落地建议

1.  **从官方起步**：仔细研究Apple官方WWDC25关于Liquid Glass的**设计规范与开发工具**。
2.  **善用系统控件**：优先使用UIKit/SwiftUI中已适配Liquid Glass效果的**原生控件**。
3.  **先深色，后浅色**：Liquid Glass在深色模式下效果最惊艳，可以此为起点。
4.  **构建组件库**：在Figma中构建一套包含颜色、字体、毛玻璃效果和核心组件的设计系统。
5.  **迭代与测试**：在不同光线条件和设备上测试毛玻璃效果的可读性与视觉效果。

---

### ⌚ Watch App 设计规范

Watch App 遵循 watchOS HIG，在 Aether 液态玻璃视觉语言基础上做适配简化。

#### 布局原则
- **TabView 三标签**：快速对话 / 健康洞察 / 设置，底部 TabBar 使用 SF Symbols
- **容器相对尺寸**：使用 `.containerRelativeFrame(.horizontal)` 适配各表盘尺寸，不硬编码宽度
- **紧凑信息密度**：表盘空间有限，每屏仅展示核心信息（最近 1 条洞察 / 最近 3 条会话标题）

#### 视觉适配
- **背景**：使用 `.containerBackground` 适配 watchOS 深色模式
- **字体**：使用 watchOS 系统语义字体（`.font(.headline)` / `.font(.caption)`），不使用 Aether 自定义 Token
- **色彩**：仅保留 `aetherPurple` 作为强调色，其余使用 watchOS 系统色

---

### 📐 Widget 设计规范

Widget 遵循 WidgetKit 设计规范，保持 Aether 视觉一致性。

#### 三个 Widget 视觉说明

| Widget | 尺寸 | 视觉要素 |
|--------|------|----------|
| QuickChatWidget | medium | 紫蓝渐变标题 + 输入框占位 + 发送按钮图标 |
| HealthInsightWidget | medium | 健康图标 + 最新洞察摘要（最多 2 行） + 时间戳 |
| RecentConversationsWidget | medium | 会话图标 + 最近 3 条会话标题 + 时间戳 |

#### 视觉适配
- **背景**：使用 `Color.deepSpace` + `.containerBackground` 适配深色模式
- **圆角**：使用系统 Widget 圆角（不使用 Aether CornerRadius Token）
- **字体**：使用系统语义字体（`.font(.headline)` / `.font(.caption2)`）
- **强调色**：QuickChatWidget 发送按钮使用 `aetherGradient`