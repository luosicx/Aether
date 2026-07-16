# 引入 Rust 核心 — 可行性分析报告

> 配套文档：实施计划见 [2026-07-15-rust-core-introduction.md](./2026-07-15-rust-core-introduction.md)
> 编制日期：2026-07-15
> 评估范围：Aether 多端仓库（Swift iOS/macOS、Android Kotlin、Windows C#、Cloudflare Workers JS）

---

## 一、结论摘要（TL;DR）

**总体可行性：高（建议推进）。** 引入 Rust 作为跨端共享核心，技术上成熟、生态完备、风险可控。建议采用"渐进式移植 + 单一 Rust 核心多端 FFI"架构，以 **SSE 流解析器作为首个端到端落地单元**（4 端重复实现、内存敏感、收益明确），验证全链路后再按路线图扩展。

| 维度 | 评级 | 关键依据 |
|---|---|---|
| 技术可行性 | ✅ 高 | Rust 官方支持全部 5 个目标平台；FFI 成熟（C ABI/JNI/wasm-bindgen） |
| 收益（安全/内存/性能） | ✅ 高 | 4 端 SSE 重复消除、`#![forbid(unsafe_code)]`、SIMD 算力热点明确 |
| 风险 | ⚠️ 中 | xcframework 二进制体积、调试符号链路、Workers WASM 冷启动 |
| 成本 | ⚠️ 中 | 首个落地单元工作量可控；全量移植（含插件沙箱/端侧推理）成本高 |
| CI 就绪度 | ✅ 高 | 现有 macOS/Ubuntu runner 可直接复用，仅新增 Rust job |

**核心决策：** 不做全量重写，而是"新增 Rust 核心 + 按模块渐进替换热点"，每个模块独立成计划、可独立交付、可回退。

---

## 二、现状问题诊断（为什么要引入 Rust）

通过代码审查发现三类问题，Rust 针对性解决：

### 2.1 安全缺陷

| 问题 | 现状文件 | 风险 |
|---|---|---|
| 插件沙箱"形同虚设" | [PluginSandbox.swift](file:///workspace/Packages/AetherCore/Sources/AetherServices/Plugin/PluginSandbox.swift) | 仅声明式权限检查，`maxExecutionTime=30s`/`maxMemoryMB=50` 为未强制常量，无真正隔离 |
| 注入检测仅客户端有 | [PromptInjectionDetector.swift](file:///workspace/Packages/AetherCore/Sources/AetherServices/Security/PromptInjectionDetector.swift) | BFF/Android/Windows 均无，服务端可被绕过 |
| 遥测脱敏仅客户端有 | [TelemetrySanitizer.swift](file:///workspace/Packages/AetherCore/Sources/AetherServices/Telemetry/TelemetrySanitizer.swift) | 服务端日志可能泄露 `sk-`/`Bearer` 凭证 |
| BFF token 比较非常量时间 | [auth.js](file:///workspace/CloudflareWorkers/src/lib/auth.js) | KV 字符串直接比较，理论上可时序侧信道 |

### 2.2 内存问题

| 问题 | 现状文件 | 风险 |
|---|---|---|
| SSE 缓冲无界累积 | 4 端各自实现（Swift 2 处 + JS + Kotlin） | 恶意流可致内存膨胀；部分事件边界处理 bug |
| PDF 整文件入 String | [PDFExtractor.swift](file:///workspace/Aether/Services/RAG/PDFExtractor.swift) | 大 PDF 内存尖峰 |
| 端侧模型文件哈希 | [MLXInferenceEngine.swift:176-190](file:///workspace/Aether/Services/OnDevice/MLXInferenceEngine.swift) | 手写流式 SHA-256，已较小心但可更稳 |
| Swift String 索引 O(n) | 文档分块等 | 超大文档处理性能不可预测 |

### 2.3 运算速度

| 热点 | 现状文件 | 问题 |
|---|---|---|
| 余弦相似度线性扫 | [SemanticCache.swift](file:///workspace/Packages/AetherCore/Sources/AetherServices/Cache/SemanticCache.swift) | `@MainActor` 串行、标量循环、100 项 |
| RAG 检索暴力扫 | [RAGService.swift](file:///workspace/Aether/Services/RAG/RAGService.swift) | O(N×D) 全量扫，无 ANN 索引，cosine 函数重复实现 |
| token 计数粗估 | [String+TokenCount.swift](file:///workspace/Packages/AetherCore/Sources/AetherFoundation/Extensions/String+TokenCount.swift) | `asciiWords×1.3 + nonASCII×1.5`，CJK 误差大 |
| 跨端逻辑重复 | SSE（4 份）、cosine（2 份）、chunking（2 份） | 行为发散、维护成本高 |

---

## 三、技术可行性 — 分平台评估

### 3.1 Rust 工具链与目标平台支持

| 目标 | triple | 官方支持 | 成熟度 | 备注 |
|---|---|---|---|---|
| iOS (device) | `aarch64-apple-ios` | ✅ Tier 2 | 高 | 已有大量生产案例 |
| iOS (sim) | `aarch64-apple-ios-sim` / `x86_64-apple-ios` | ✅ | 高 | |
| macOS (arm/x86) | `aarch64-apple-darwin` / `x86_64-apple-darwin` | ✅ Tier 1 | 高 | |
| Windows | `x86_64-pc-windows-msvc` | ✅ Tier 1 | 高 | |
| Android | `aarch64-linux-android` / `x86_64-linux-android` | ✅ Tier 2 | 高 | 需 NDK + `cargo-ndk` |
| Workers WASM | `wasm32-unknown-unknown` | ✅ Tier 2 | 高 | `wasm-pack -t web` |

> 结论：6 类目标平台均获 Rust 官方 Tier 1/2 支持，无平台不可达风险。

### 3.2 Swift / iOS / macOS 接入可行性 — ✅ 高

- **SPM `binaryTarget`** 接入 `xcframework` 是官方推荐路径，[Package.swift](file:///workspace/Packages/AetherCore/Package.swift) 当前 **零外部依赖**，引入一个二进制 target 不会与任何现有依赖冲突。
- C ABI 通过 `cbindgen` 生成头 + `module.modulemap` 暴露给 Swift，模式成熟（Mozilla/1Password 等均采用）。
- iOS 17 / macOS 14 最低版本完全支持 Rust 1.75 静态库链接。
- **风险点**：`xcframework` 二进制需提交仓库（或 CI 产物），增加仓库体积；调试时 Rust 栈帧需配置符号。可通过 `git-lfs` 或 CI 产物缓存缓解。

### 3.3 Cloudflare Workers 接入可行性 — ✅ 高

- 现有 [worker.js](file:///workspace/CloudflareWorkers/worker.js) 是纯 JS ES module，`wasm-pack -t web` 产出的 `wasm-bindgen` 模块可由 `import` 直接加载，无需改写入口。
- D1/KV 绑定保留在 JS 侧（运行时绑定），Rust 仅负责纯计算（SSE 解析、后续的脱敏/注入检测），**职责边界清晰**。
- **替代方案对比**：`workers-rs`（Rust 原生 Worker）需全量重写且绑定生态不如 JS 成熟；本方案"JS 壳 + Rust WASM 计算"风险更低。
- **风险点**：WASM 首次加载冷启动延迟（~1-5ms，可接受）；Workers 体积限制 1MB（压缩后），SSE 解析模块远低于此。

### 3.4 Android 接入可行性 — ✅ 中高

- [build.gradle.kts](file:///workspace/android/app/build.gradle.kts) 当前 **无 NDK/JNI 配置**，需新增 `rust-android-gradle` 插件或 `cargo-ndk` 构建 `.so`。
- `jni` crate（0.21）或 `uniffi` 可生成 Kotlin 绑定；`external fun` 声明标准。
- minSdk 29（Android 10），NDK r25+ 完全支持。
- **风险点**：.so 体积（arm64+x86_64 两架构约增 1-3MB）；需维护 ABI 分包。首个落地单元可暂只编译 arm64。

### 3.5 Windows 接入可行性 — ✅ 高（最简单）

- [Aether.Windows.csproj](file:///workspace/windows/Aether.Windows/Aether.Windows.csproj) 当前 **无任何 native 依赖**，.NET 8 + P/Invoke 接入 `cdylib` 是标准模式。
- `csbindgen` 可直接生成 C# P/Invoke 声明，无需手写。
- **风险点**：DLL 加载路径需配置（`NativeLibrary.Load` 或同目录部署）。

### 3.6 FFI 绑定技术选型对比

| 方案 | 跨端一致性 | 学习成本 | 维护成本 | 本计划选择 |
|---|---|---|---|---|
| 手写 C ABI + `cbindgen`/`csbindgen`/`wasm-bindgen`/`jni` | 高 | 中 | 中 | ✅ 采用 |
| `uniffi`（统一生成多端绑定） | 很高 | 低 | 低 | ⏳ 后续可演进 |
| `swift-bridge`（仅 Swift） | 仅 Swift | 低 | 中 | ❌ 不跨端 |
| `cbindgen` + 各端手写 wrapper | 高 | 中 | 中 | ✅ 首期采用 |

> 决策：首期采用"手写 C ABI + 各端原生 wrapper"，成熟可控；后续若绑定膨胀可迁移到 `uniffi`。

---

## 四、收益分析

### 4.1 安全收益（量化）

| 收益 | 量化指标 |
|---|---|
| `unsafe` 收敛 | 核心逻辑 crate `#![forbid(unsafe_code)]`，全部 unsafe 集中在 FFI 层，可审计 |
| 内存安全 | 消除 4 处 SSE 缓冲无界累积；FFI 显式 `aether_free_string` 释放，空指针检查 |
| 安全逻辑统一 | 注入检测/脱敏可服务端强制（当前 BFF 无），消除客户端绕过路径 |
| 沙箱真隔离（后续） | `wasmtime` 嵌入可强制 CPU/内存/时间限额（当前仅声明式） |

### 4.2 性能收益（预估）

| 模块 | 现状 | Rust 后预估 | 依据 |
|---|---|---|---|
| SSE 解析 | 4 套 JS/Swift/Kotlin | 单一 Rust，解析速度持平或略优 | 解析非算力热点，收益主要在统一与内存安全 |
| 余弦相似度（100×1536） | Swift 标量循环 @MainActor | Rust + SIMD，2-5× | `wide`/`std::simd` AVX2/NEON 自动向量化 |
| RAG 检索（N×D 暴力扫） | O(N×D) | + ANN 索引后近 O(log N) | `usearch`/`instant-distance` |
| token 计数 | 粗估公式 | `tiktoken-rs` 精确 BPE | 误差从 ~30% 降至 ~0 |
| SHA-256（模型文件） | CryptoKit | `sha2` crate | 持平，主收益在跨端 |

### 4.3 工程/维护收益

- **去重**：SSE 4 份→1 份、cosine 2 份→1 份、chunking 2 份→1 份。
- **跨端一致**：行为以 Rust 为单一事实来源，消除"客户端有注入检测、服务端没有"等缺口。
- **可测**：Rust 单测快（ms 级），无需模拟器；CI 反馈快。
- **可演进**：为后续插件真沙箱、跨端端侧推理铺路。

---

## 五、风险评估与缓解

| # | 风险 | 等级 | 概率 | 缓解措施 |
|---|---|---|---|---|
| R1 | xcframework 二进制增大仓库体积 | 中 | 高 | 用 CI 产物 + SPM binaryTarget 远程 URL，或 git-lfs；不提交源码 |
| R2 | Rust/Swift 混合栈调试符号链路 | 中 | 中 | 配置 `.dSYM` + Rust PDB；CI 构建保留符号 |
| R3 | Workers WASM 冷启动延迟 | 低 | 中 | 懒加载 + 单例；实测 <5ms 可接受 |
| R4 | Android .so 体积/ABI 维护 | 中 | 中 | 首期仅 arm64；后续按需补 x86_64；启用 strip |
| R5 | FFI 边界内存泄漏（忘记 free） | 中 | 中 | 用 RAII 包装（Swift `deinit`/C# `Dispose`）；加 leak sanitizer 到 CI |
| R6 | JSON 跨 FFI 序列化开销 | 低 | 中 | 本计划 SSE 用 JSON 简单传递，开销可忽略；高频路径后续可改直接结构体 |
| R7 | 团队 Rust 熟练度 | 中 | — | 首期代码量小（SSE ~80 行），可由 1 人主导 + review；后续逐步扩散 |
| R8 | 行为回归（移植后语义变化） | 中 | 中 | TDD：Rust 单测 + 各端回归测试双保险；保留旧实现可回退 |
| R9 | 工具链版本漂移 | 低 | 低 | `rust-toolchain.toml` 固定 1.75 + CI 缓存 |
| R10 | 插件沙箱/端侧推理（Tier 3）成本高 | 高 | — | 不在本计划范围；独立评估，分阶段决策 |

> 综合风险评级：**中**。无致命风险，所有风险均有成熟缓解手段。最大不确定性在 R7（团队技能）与 R8（回归），通过小步快跑、可回退、双测试缓解。

---

## 六、成本与工作量评估

> 说明：本节按"首个落地单元（SSE）"与"全量路线图"分层评估，不含工时承诺。

### 6.1 首个落地单元（SSE 解析器，本计划）

| 工作项 | 复杂度 | 说明 |
|---|---|---|
| Rust workspace + SSE 实现 + 测试 | 低 | ~80 行 Rust，7 个单测 |
| FFI crate（C ABI + WASM + JNI） | 中 | 模板化，集中 unsafe |
| Apple SPM 接入 + SSEParser 转发 | 中 | binaryTarget + modulemap + wrapper |
| Workers llm.js 改 WASM | 低 | sync→async 改造 |
| CI Rust job | 低 | 复用现有 runner |
| 测试与回归 | 中 | 各端测试 |

**首个单元可独立交付、可回退**，是验证全链路的最小可行投入。

### 6.2 全量路线图（9 模块，后续）

| Tier | 模块 | 复杂度 | 备注 |
|---|---|---|---|
| Tier 1 | 向量数学/语义缓存 | 中 | SIMD + 可选 ANN |
| Tier 1 | token 计数 | 低 | `tiktoken-rs` |
| Tier 1 | 安全正则 | 低-中 | `regex` crate |
| Tier 2 | 文档分块 | 低 | `unicode-segmentation` |
| Tier 2 | SHA-256 | 低 | `sha2` crate |
| Tier 2 | PDF 抽取 | 高 | PDF 解析复杂 |
| Tier 3 | 插件沙箱（wasmtime） | 高 | 真隔离 |
| Tier 3 | 端侧推理（candle） | 高 | 跨端 LLM |
| Tier 3 | 速率限制 | 低 | 一致性收益为主 |

> Tier 3 的插件沙箱与端侧推理属战略级投入，需单独立项评估，不在当前推进范围。

---

## 七、替代方案对比（为何是 Rust）

| 方案 | 跨端共享 | 安全 | 性能 | 生态 | 本项目适配 | 结论 |
|---|---|---|---|---|---|---|
| **Rust + FFI/WASM/JNI** | ✅ 全 5 端 | ✅ 内存安全 | ✅ 高 | ✅ 成熟 | ✅ 高 | **推荐** |
| C++ | ✅ | ❌ 手动内存 | ✅ 高 | ✅ | ⚠️ 团队负担重 | 不推荐 |
| Zig | ⚠️ 生态新 | ⚠️ 手动但更安全 | ✅ 高 | ❌ 不成熟 | ❌ | 不推荐 |
| Kotlin Multiplatform | ⚠️ 不覆盖 iOS/Workers | ✅ | ⚠️ JVM | ✅ | ❌ 不覆盖 Apple/Workers | 不适配 |
| 全员重写为 Swift（Workers 用 Swift CGI） | ❌ Workers 不支持 | ✅ | ✅ | ⚠️ | ❌ 成本极高 | 不推荐 |
| 保持现状（不引入 Rust） | ❌ 重复持续 | ❌ 沙箱仍假 | ❌ 主线程热点 | — | ❌ | 不解决核心问题 |
| **uniffi 统一生成** | ✅ | ✅ | ✅ | ✅ 渐成熟 | ✅ 后续演进 | **二期可选** |

> 结论：Rust 是唯一同时满足"全 5 端覆盖 + 内存安全 + 高性能 + 成熟生态"的方案。

---

## 八、CI 就绪度评估

现有 [.github/workflows/ci.yml](file:///workspace/.github/workflows/ci.yml) 已包含 9 个 job，关键资源：

| 现有资源 | 可复用情况 |
|---|---|
| `macos-15` runner（iOS/macOS 单测+UIT+安全测试+SonarQube） | ✅ 直接用于 `xcframework` 构建（Rust Apple targets） |
| `ubuntu-latest` runner（Android APK 构建） | ✅ 直接用于 Rust test + wasm-pack + Android 交叉编译 |
| `windows-latest` runner（.NET 构建） | ✅ 可用于 Rust `x86_64-pc-windows-msvc` + Windows 测试 |
| `actions/upload-artifact@v7` | ✅ 上传 xcframework/WASM 产物 |
| SonarQube 集成 | ⚠️ Rust 代码需额外配置 `sonar-rust` 插件（可选） |

**新增成本**：仅 1 个 `rust` job（约 3-5 分钟运行时），与现有 job 并行。无新基础设施投入。

**覆盖率门槛影响**：现有 85% 覆盖率门槛仅统计 Swift `.swift` 文件（`EXCLUDE_PATTERNS`），Rust 代码不纳入该门槛，**不会拖累现有质量门禁**。Rust 侧独立用 `cargo tarpaulin`/`cargo llvm-cov` 统计（可选，后续）。

---

## 九、决策矩阵

| 维度 | 权重 | Rust 方案 | 保持现状 | C++ | KMP |
|---|---|---|---|---|---|
| 安全收益 | 25% | 5 | 1 | 2 | 4 |
| 性能收益 | 20% | 5 | 2 | 5 | 3 |
| 跨端覆盖 | 20% | 5 | 1 | 4 | 2 |
| 实施风险（低为好） | 15% | 4 | 5 | 2 | 3 |
| 维护成本（低为好） | 10% | 3 | 4 | 2 | 3 |
| 生态成熟度 | 10% | 5 | 5 | 5 | 3 |
| **加权总分** | | **4.75** | **2.35** | **3.25** | **3.05** |

> Rust 方案加权总分最高（4.75/5），显著优于保持现状。

---

## 十、推进建议

### 10.1 分阶段策略

1. **Phase 1（本计划）**：Rust 基础设施 + SSE 解析器端到端落地。验证 FFI/WASM/JNI 全链路、CI、可回退机制。
2. **Phase 2**：Tier 1 模块（向量数学/语义缓存、token 计数、安全正则）—— 收益最直接。
3. **Phase 3**：Tier 2 模块（文档分块、SHA-256、PDF）—— 去 Apple-only 依赖。
4. **Phase 4（战略，单独立项）**：Tier 3 模块（插件真沙箱、跨端端侧推理）。

### 10.2 验收门槛（Phase 1 完成）

- [ ] `rust/` workspace 编译通过，7 个 Rust 单测绿
- [ ] Apple `AetherRust` target 接入，`SSEParserRustTests` 4 个用例绿
- [ ] 既有 SSE 相关测试无回归
- [ ] Workers `parseSSEEvent` 改调 WASM，4 个 vitest 用例绿
- [ ] CI Rust job 绿
- [ ] 4 端 SSE 行为统一（同一输入同一输出）

### 10.3 回退预案

- 每个模块移植保留旧实现（仅转发到 Rust，旧代码不删），出问题可一行 `import` 切回。
- `xcframework`/WASM 产物版本化，支持按版本回滚。
- CI 在 Rust job 红时不阻塞 Apple/Android/Windows 主构建（独立 job）。

---

## 十一、开放问题（需用户决策）

1. **xcframework 产物托管方式**：提交仓库（简单但增体积）vs CI 产物 + 远程 binaryTarget URL（推荐但需配置）？
2. **Android 首期架构范围**：仅 arm64（快）vs arm64+x86_64（全）？
3. **Rust 代码所有权**：由谁主导 review？是否需要建立 Rust 编码规范文档？
4. **Tier 3（插件沙箱/端侧推理）是否纳入长期 roadmap**？还是仅推进 Tier 1-2？

---

*本报告与实施计划 [2026-07-15-rust-core-introduction.md](./2026-07-15-rust-core-introduction.md) 配套使用。请审阅两份文档后确认是否启动 Phase 1 执行。*
