# Android 构建指南

本指南说明如何构建 Aether Android 客户端。

---

## 1. 概述

Aether Android 客户端使用 **Kotlin + Jetpack Compose + Room** 技术栈：

- **UI**：Jetpack Compose + Material 3 + Navigation Compose
- **网络**：Ktor（HTTP + SSE 流式响应）
- **持久化**：Room（本地数据库）+ DataStore（偏好设置）
- **序列化**：kotlinx.serialization
- **最低 SDK**：29（Android 10），**目标 SDK**：35（Android 15）

源码位于 `android/` 目录。

---

## 2. 环境要求

| 项 | 要求 | 说明 |
|----|------|------|
| IDE | Android Studio Hedgehog+ | 推荐 IDE |
| JDK | 17 (temurin) | `sourceCompatibility` / `targetCompatibility` 均为 17 |
| Android SDK | API 29+ | `minSdk=29`，`targetSdk=35`，Build Tools 35.0.0 |
| Android NDK | r25+ | Rust 交叉编译 `.so` 所需 |
| Kotlin | 1.9+ | Compose 编译器 1.5.14 |
| Gradle | 8.10 | **已随仓库提交 `gradlew`，无需手动安装** |
| Rust | 1.75+（可选） | 构建 `libaether_core_ffi.so` 所需；不构建 `.so` 时可省略 |
| cargo-ndk | 最新 | `cargo install cargo-ndk` |
| Rust target | aarch64-linux-android + x86_64-linux-android | `rustup target add aarch64-linux-android x86_64-linux-android` |

> 仓库已提交 `android/gradlew` / `android/gradlew.bat` / `android/gradle/wrapper/gradle-wrapper.jar`，所有构建均通过 wrapper 执行，无需本机预装 Gradle，也无需运行 `gradle wrapper` 现场生成。
>
> 下载 Rust：https://rustup.rs

---

## 3. 项目结构

`android/app/src/main/java/com/aether/` 包含 22 个 `.kt` 源文件，按职责拆分：

```
android/app/src/main/java/com/aether/
├── app/
│   └── MainActivity.kt                  # 应用入口
├── data/
│   ├── api/
│   │   ├── AetherApi.kt                 # BFF API 接口
│   │   ├── BffConfig.kt                 # BFF 配置模型
│   │   ├── BffConfigStore.kt            # BFF 配置持久化
│   │   ├── ChatStreamClient.kt          # SSE 流式聊天
│   │   └── HttpClientFactory.kt         # Ktor 客户端工厂
│   ├── db/
│   │   └── AetherDatabase.kt            # Room 数据库
│   ├── model/
│   │   └── Models.kt                    # 数据模型
│   └── repository/
│       ├── ConversationRepository.kt
│       ├── MessageRepository.kt
│       └── RepositorySyncManager.kt
├── rust/                                # Rust JNI 桥接
│   ├── Redact.kt                        # 脱敏 JNI
│   ├── SseBridge.kt                     # SSE 解析 JNI
│   └── VectorMath.kt                    # 向量余弦相似度 JNI
└── ui/
    ├── chat/
    │   ├── ChatScreen.kt
    │   ├── ChatViewModel.kt
    │   └── MarkdownText.kt              # Markwon 封装
    ├── conversation/
    │   ├── ConversationListScreen.kt
    │   └── ConversationListViewModel.kt
    ├── rag/
    │   ├── KnowledgeBaseScreen.kt
    │   └── KnowledgeBaseViewModel.kt
    ├── health/
    │   ├── HealthScreen.kt
    │   └── HealthViewModel.kt
    ├── settings/
    │   ├── LanguageManager.kt
    │   └── SettingsScreen.kt
    ├── navigation/
    │   └── AetherApp.kt                 # Compose Navigation
    └── theme/
        ├── DesignTokens.kt
        └── Theme.kt
```

单元测试位于 `android/app/src/test/java/com/aether/`，共 12 个测试文件、95 个测试用例（JUnit + Robolectric）。

---

## 4. 快速开始

### 4.1 使用 make（推荐）

在项目根目录执行：

```bash
make build-android
```

### 4.2 直接调用脚本

```bash
./scripts/build-android.sh build-android
```

脚本会自动检测 Android SDK 路径并生成 `android/local.properties`（若不存在），然后执行 `./gradlew assembleDebug`。

### 4.3 构建 Rust .so（可选）

若需重建 `libaether_core_ffi.so`（CI 已自动构建并下载，本地无 Rust 环境可跳过）：

```bash
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk

cd rust/aether-core-ffi
cargo ndk -t arm64-v8a -t x86_64 build --release
```

产物路径：

- `rust/target/aarch64-linux-android/release/libaether_core_ffi.so`
- `rust/target/x86_64-linux-android/release/libaether_core_ffi.so`

将 `.so` 分别放入 jniLibs：

```bash
cp rust/target/aarch64-linux-android/release/libaether_core_ffi.so \
   android/app/src/main/jniLibs/arm64-v8a/
cp rust/target/x86_64-linux-android/release/libaether_core_ffi.so \
   android/app/src/main/jniLibs/x86_64/
```

> `android/app/build.gradle.kts` 通过 `sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")` 引用 `.so`，缺失时不影响 Debug APK 构建，JNI 桥接层会在 `UnsatisfiedLinkError` 时回退到纯 Kotlin 实现。

### 4.4 构建 APK

```bash
cd android
./gradlew assembleDebug --no-daemon --stacktrace
```

构建产物：

```
android/app/build/outputs/apk/debug/app-debug.apk
```

Debug APK 已使用 debug 签名，可直接 `adb install` 到设备或模拟器。

### 4.5 运行测试

```bash
cd android
./gradlew testDebugUnitTest --no-daemon --stacktrace
```

### 4.6 其他子命令

| 子命令 | 说明 |
|--------|------|
| `./scripts/build-android.sh build-android` | 构建 Debug APK（`assembleDebug`） |
| `./scripts/build-android.sh build-android-release` | 构建 Release APK（`assembleRelease`） |
| `./scripts/build-android.sh test-android` | 运行 Debug 单元测试（`testDebugUnitTest`） |
| `./scripts/build-android.sh clean` | 清理 Android 构建产物 |

---

## 5. gradlew 说明

仓库已提交 Gradle Wrapper 全套文件：

- `android/gradlew`（Unix shell 脚本）
- `android/gradlew.bat`（Windows 批处理脚本）
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`（指定 Gradle 8.10）

因此：

- **无需**在本机安装 Gradle
- **无需**运行 `gradle wrapper --gradle-version 8.10` 现场生成（CI 会执行此步骤以刷新 wrapper 版本）
- 构建脚本统一通过 `./gradlew --no-daemon` 调用，保证版本一致

---

## 6. SDK 路径配置

Gradle 需要知道本机 Android SDK 路径，通过 `android/local.properties` 配置：

1. 复制示例文件：
   ```bash
   cp android/local.properties.example android/local.properties
   ```
2. 编辑 `android/local.properties`，将 `sdk.dir` 修改为你的实际 SDK 路径：
   ```properties
   # macOS
   sdk.dir=/Users/<username>/Library/Android/sdk
   # Linux
   sdk.dir=/home/<username>/Android/Sdk
   # Windows（反斜杠需转义）
   sdk.dir=C:\\Users\\<username>\\AppData\\Local\\Android\\Sdk
   ```

> `local.properties` 已在 `.gitignore` 中，不会提交到仓库。
>
> 若不手动创建，`scripts/build-android.sh` 也会按 `ANDROID_HOME` → `ANDROID_SDK_ROOT` → 平台默认路径的优先级自动检测并生成。

---

## 7. 签名配置

- **Debug**：当前默认使用 Android 标准 debug 签名，构建出的 APK 可直接安装调试，无需额外配置。
- **Release**：发布版本需配置自有 keystore。在 `android/app/build.gradle.kts` 的 `signingConfigs` 中添加 release 签名配置，并将 keystore 文件与凭证通过环境变量或未提交的 `keystore.properties` 注入。

---

## 8. BFF 端点配置

Android 客户端通过 BFF（Backend For Frontend）代理访问 LLM 服务，端点在 `android/app/build.gradle.kts` 中以 `buildConfigField` 注入：

```kotlin
buildConfigField("String", "BFF_BASE_URL", "\"https://aether-bff.example.com\"")
buildConfigField("boolean", "USE_RUST_SSE", "true")
```

> **当前 `BFF_BASE_URL` 为占位符**（`aether-bff.example.com`），正式构建前需替换为真实部署的 BFF 地址。可在 `build.gradle.kts` 中直接修改，或通过 product flavor / 命令行 `-PBFF_BASE_URL=...` 覆盖。

代码中通过 `BuildConfig.BFF_BASE_URL` 与 `BuildConfig.USE_RUST_SSE` 读取。

---

## 9. Rust JNI 集成

Android 端通过 JNI 调用 Rust core，桥接代码位于 `com.aether.rust` 包。Rust 侧暴露 4 个 JNI 函数：

| JNI 函数 | Kotlin 桥接 | 用途 |
|----------|-------------|------|
| `Java_com_aether_rust_SseBridge_parseWithTools` | `SseBridge.kt` | SSE 流式解析（含工具调用） |
| `Java_com_aether_rust_SseBridge_reset` | `SseBridge.kt` | 重置解析器状态 |
| `Java_com_aether_rust_VectorMath_cosineF64` | `VectorMath.kt` | f64 向量余弦相似度 |
| `Java_com_aether_rust_Redact_redact` | `Redact.kt` | 文本脱敏 |

**ABI 与产物**：

- `libaether_core_ffi.so` 由 `cargo build --target aarch64-linux-android` 与 `x86_64-linux-android` 构建
- 支持两个 ABI：`arm64-v8a`（真机）+ `x86_64`（模拟器）
- `.so` 放置于 `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/`，通过 Gradle jniLibs 打包进 APK

**回退机制**：

`ChatStreamClient` SSE 解析优先走 Rust JNI（`BuildConfig.USE_RUST_SSE = true`），JNI 不可用时自动回退到纯 Kotlin 实现。`VectorMath.cosineF64Safe` / `Redact.redactSafe` 同样提供 `*Safe` 回退路径。

---

## 10. 已实现功能（v1.5）

- **RAG 知识库 UI + Health UI**：新增 `KnowledgeBaseScreen` + `HealthScreen` + 2 个 ViewModel，API 已有的 `searchDocuments` / `uploadHealthSummary` / `getHealthSummary` 端点终于有 UI。
- **Rust Redact JNI 暴露 + 消息长按菜单**：新增 `Redact.kt`（JNI 桥接 `aether_redact`）+ `jni.rs` 添加 Redact 函数；`ChatScreen` 消息长按弹出复制 / 重发 / 删除菜单。
- **Markdown 渲染（Markwon 4.6.2）**：AI 消息用 `MarkdownText` Composable 渲染（支持标题 / 代码块 / 表格 / 任务列表 / 链接 / 加粗斜体）。
- **Room 生产使用 + i18n**：`ConversationRepository` 改为先 Room 后网络模式；8 种语言 `strings.xml`（values / values-en / values-ja / values-ko / values-fr / values-de / values-es / values-zh-rTW）。
- **Rust JNI 已集成**：Android 端已集成 Rust core 的 JNI 桥接（SSE 解析 + 向量数学 + 脱敏），共 4 个 JNI 函数。
  - Kotlin 桥接代码位于 `com.aether.rust` 包：`SseBridge`（SSE 解析）、`VectorMath`（余弦相似度）、`Redact`（脱敏）。
  - `.so` 产物由 CI `rust` job 通过 `cargo-ndk` 构建（`aarch64-linux-android` + `x86_64-linux-android`），上传为 artifact `aether-core-android-so`。
  - `android-build` CI job 下载 `.so` 并放入 `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/`，通过 Gradle jniLibs 打包进 APK。
  - `ChatStreamClient` SSE 解析优先走 Rust JNI（`BuildConfig.USE_RUST_SSE = true`），JNI 不可用时自动回退到纯 Kotlin 实现。
- **基础单元测试已覆盖**：Android 端已新增 12 个测试文件、95 个测试用例，CI 执行 `testDebugUnitTest`：
  - `ModelsTest`：Conversation / ChatMessage / Memory JSON 序列化与默认值。
  - `BffConfigTest`：BffConfig 默认值 + BffConfigStore 读写（Robolectric + DataStore）。
  - `ConversationRepositoryTest` / `ConversationRepositoryRoomTest`：Room DAO CRUD + 排序 + 级联删除（Room in-memory database）。
  - `SseBridgeTest`：JNI 不可用时的 Kotlin 回退路径。
  - `VectorMathTest`：JNI 不可用时的 `cosineF64Safe` 回退（返回 0.0）。
  - `RedactTest`：JNI 不可用时的 `redactSafe` 回退。
  - `ChatViewModelDeleteTest` / `MarkdownTextTest` / `HealthViewModelTest` / `KnowledgeBaseViewModelTest` / `LanguageManagerTest`：各模块 ViewModel 与 UI 逻辑测试。

### 10.1 功能清单

| 功能 | 状态 | 说明 |
|------|------|------|
| RAG 知识库 UI | ✅ | KnowledgeBaseScreen（搜索 / 结果展示 / 空状态） |
| Health UI | ✅ | HealthScreen（日期选择 / 数据展示 / 上传） |
| Markdown 渲染 | ✅ | Markwon 4.6.2，MarkdownText Composable |
| i18n 国际化 | ✅ | 8 种语言 strings.xml + recreate Activity |
| Room 生产使用 | ✅ | ConversationRepository 先 Room 后网络 |
| Rust Redact JNI | ✅ | Redact.kt + jni.rs，redactSafe 回退 |
| 消息长按菜单 | ✅ | 复制 / 重发 / 删除 DropdownMenu |
| Rust JNI 集成 | ✅ | 4 个 JNI 函数（SSE 解析 + 向量数学 + 脱敏） |
| 单元测试 | ✅ | testDebugUnitTest，12 文件 95 用例 |

---

## 11. 依赖列表

`android/app/build.gradle.kts` 关键依赖：

| 包名 | 版本 | 用途 |
|------|------|------|
| io.noties.markwon:core | 4.6.2 | Markwon 核心，Markdown 解析与渲染 |
| io.noties.markwon:ext-tables | 4.6.2 | 表格语法支持（GFM） |
| io.noties.markwon:ext-tasklist | 4.6.2 | 任务列表语法支持（`- [ ]` / `- [x]`） |
| io.noties.markwon:ext-strikethrough | 4.6.2 | 删除线语法支持 |
| io.noties.markwon:linkify | 4.6.2 | 自动识别链接（Linkify） |
| io.noties.markwon:syntax-highlight | 4.6.2 | 代码块语法高亮（基于 Prism4j） |
| androidx.room:room-runtime | 2.6.1 | Room 本地数据库 |
| androidx.room:room-ktx | 2.6.1 | Room 协程支持 |
| io.ktor:ktor-client-* | 2.3.12 | HTTP + SSE 流式响应 |
| androidx.datastore:datastore-preferences | 1.1.0 | 偏好设置持久化 |
| androidx.security:security-crypto | 1.1.0-alpha06 | 加密存储敏感数据（BFF Token） |

> Kotlin / Compose BOM / kotlinx.serialization 等基础依赖随 `android/app/build.gradle.kts` 配置自动引入，详见该文件。

---

## 12. CI 集成

CI 工作流定义于 `.github/workflows/ci.yml` 的 `android-build` job（第 967-1048 行），运行在 `ubuntu-latest` runner，超时 20 分钟，依赖 `rust` job。

关键步骤：

1. **缓存 Gradle**：`actions/cache@v5` 缓存 `~/.gradle/caches` 与 wrapper
2. **缓存 NDK**：`actions/cache@v5` 缓存 `~/.android/sdk/ndk/*`
3. **Setup JDK 17**：`actions/setup-java@v4` 安装 temurin JDK 17
4. **Setup Android SDK**：`android-actions/setup-android@v3` 安装 `platforms;android-35` + `build-tools;35.0.0`
5. **Setup Gradle**：`gradle/actions/setup-gradle@v3`
6. **Download Rust .so artifacts**：下载 `aether-core-android-so` artifact（含 aarch64 + x86_64 两个 ABI 的 `.so`）
7. **Place .so into jniLibs**：用 `find` 将 `.so` 分别放入 `jniLibs/arm64-v8a/` 与 `jniLibs/x86_64/`
8. **Generate Gradle Wrapper**：`gradle wrapper --gradle-version 8.10`
9. **Build Debug APK**：`./gradlew assembleDebug --no-daemon --stacktrace`
10. **Run unit tests**：`./gradlew testDebugUnitTest --no-daemon --stacktrace`
11. **Upload APK artifact**：上传 `app-debug.apk` 为 artifact `android-apk`

---

## 13. 已知限制与未开放功能

- **无端侧 MLX 推理**：Rust FFI `#[cfg]` 排除 Android，仅依赖 BFF 代理 LLM 服务。
- **无多模态**：未实现 NativeVision / ASR / TTS，无可视化 / 语音能力（`RECORD_AUDIO` 权限已声明但未使用）。
- **无 Health Connect 集成**：HealthScreen 仅展示 BFF 返回数据，未对接 Android Health Connect。
- **无 watchOS / Widget**：Android 平台无对应扩展机制。
- **JNI 在纯 JVM 测试中不可用**：单元测试运行在 JVM（无 `.so`），`SseBridge` / `VectorMath` / `Redact` 的 native 方法不可调用，测试覆盖 `*Safe` 回退路径而非 native 路径。Native 路径需在真机 / 模拟器插桩测试中验证。
- **无工具调用 UI**：工具调用由 BFF 端执行，客户端无独立 UI。
- **无离线模式**：依赖 BFF 在线服务（Room 仅缓存会话列表，消息流仍需在线）。
- **无 UI 自动化测试**：未集成 Espresso / Compose UI Test。
