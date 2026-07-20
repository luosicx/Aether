# Android 构建指南

本指南说明如何构建 Aether Android 客户端。

---

## 1. 概述

Aether Android 客户端使用 **Kotlin + Jetpack Compose + Room** 技术栈：

- **UI**：Jetpack Compose + Material 3 + Navigation Compose
- **网络**：Ktor（HTTP + SSE 流式响应）
- **持久化**：Room（本地数据库）+ DataStore（偏好设置）
- **序列化**：kotlinx.serialization
- **最低 SDK**：29（Android 10），**目标 SDK**：34（Android 14）

源码位于 `android/` 目录。

---

## 2. 环境要求

| 项 | 要求 | 说明 |
|----|------|------|
| JDK | 17 | `sourceCompatibility` / `targetCompatibility` 均为 17 |
| Android SDK | 35 | Build Tools 35.0.0 |
| Gradle | 8.7 | **已随仓库提交 `gradlew`，无需手动安装** Gradle |

> 仓库已提交 `android/gradlew` / `android/gradlew.bat` / `android/gradle/wrapper/gradle-wrapper.jar`，所有构建均通过 wrapper 执行，无需本机预装 Gradle，也无需运行 `gradle wrapper` 现场生成。

---

## 3. 快速开始

### 3.1 使用 make（推荐）

在项目根目录执行：

```bash
make build-android
```

### 3.2 直接调用脚本

```bash
./scripts/build-android.sh build-android
```

脚本会自动检测 Android SDK 路径并生成 `android/local.properties`（若不存在），然后执行 `./gradlew assembleDebug`。

### 3.3 构建产物

```
android/app/build/outputs/apk/debug/app-debug.apk
```

Debug APK 已使用 debug 签名，可直接 `adb install` 到设备或模拟器。

### 3.4 其他子命令

| 子命令 | 说明 |
|--------|------|
| `./scripts/build-android.sh build-android` | 构建 Debug APK（`assembleDebug`） |
| `./scripts/build-android.sh build-android-release` | 构建 Release APK（`assembleRelease`） |
| `./scripts/build-android.sh test-android` | 运行 Debug 单元测试（`testDebugUnitTest`） |
| `./scripts/build-android.sh clean` | 清理 Android 构建产物 |

---

## 4. gradlew 说明

仓库已提交 Gradle Wrapper 全套文件：

- `android/gradlew`（Unix shell 脚本）
- `android/gradlew.bat`（Windows 批处理脚本）
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`（指定 Gradle 8.10）

因此：

- **无需**在本机安装 Gradle
- **无需**运行 `gradle wrapper --gradle-version 8.10` 现场生成
- 构建脚本统一通过 `./gradlew --no-daemon` 调用，保证版本一致

---

## 5. SDK 路径配置

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

## 6. 签名配置

- **Debug**：当前默认使用 Android 标准 debug 签名，构建出的 APK 可直接安装调试，无需额外配置。
- **Release**：发布版本需配置自有 keystore。在 `android/app/build.gradle.kts` 的 `signingConfigs` 中添加 release 签名配置，并将 keystore 文件与凭证通过环境变量或未提交的 `keystore.properties` 注入。

---

## 7. BFF 端点配置

Android 客户端通过 BFF（Backend For Frontend）代理访问 LLM 服务，端点在 `android/app/build.gradle.kts` 中以 `buildConfigField` 注入：

```kotlin
buildConfigField("String", "BFF_BASE_URL", "\"https://aether-bff.example.com\"")
```

> **当前 `BFF_BASE_URL` 为占位符**（`aether-bff.example.com`），正式构建前需替换为真实部署的 BFF 地址。可在 `build.gradle.kts` 中直接修改，或通过 product flavor / 命令行 `-PBFF_BASE_URL=...` 覆盖。

代码中通过 `BuildConfig.BFF_BASE_URL` 读取。

---

## 8. 已知限制与集成状态

- **Rust JNI 已集成**：Android 端已集成 Rust core 的 JNI 桥接（SSE 解析 + 向量数学）。
  - Kotlin 桥接代码位于 `com.aether.rust` 包：`SseBridge`（SSE 解析）、`VectorMath`（余弦相似度）。
  - `.so` 产物由 CI `rust` job 通过 `cargo-ndk` 构建（`aarch64-linux-android` + `x86_64-linux-android`），上传为 artifact `aether-core-android-so`。
  - `android-build` CI job 下载 `.so` 并放入 `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/`，通过 Gradle jniLibs 打包进 APK。
  - `ChatStreamClient` SSE 解析优先走 Rust JNI（`BuildConfig.USE_RUST_SSE = true`），JNI 不可用时自动回退到纯 Kotlin 实现。
- **基础单元测试已覆盖**：Android 端已新增基础单元测试，CI 执行 `testDebugUnitTest`：
  - `ModelsTest`：Conversation / ChatMessage / Memory JSON 序列化与默认值。
  - `BffConfigTest`：BffConfig 默认值 + BffConfigStore 读写（Robolectric + DataStore）。
  - `ConversationRepositoryTest`：Room DAO CRUD + 排序 + 级联删除（Room in-memory database）。
  - `SseBridgeTest`：JNI 不可用时的 Kotlin 回退路径。
  - `VectorMathTest`：JNI 不可用时的 `cosineF64Safe` 回退（返回 0.0）。
- **JNI 在纯 JVM 测试中不可用**：单元测试运行在 JVM（无 `.so`），`SseBridge` / `VectorMath` 的 native 方法不可调用，测试覆盖回退路径而非 native 路径。Native 路径需在真机/模拟器插桩测试中验证。
