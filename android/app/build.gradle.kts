plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")  // Kotlin 2.x 起 Compose 编译器随 Kotlin 版本发布
    id("org.jetbrains.kotlin.plugin.serialization")  // 为 @Serializable 模型生成序列化器
    id("com.google.devtools.ksp")  // Room 用 KSP 代替 kapt
}

android {
    namespace = "com.aether.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.aether.app"
        minSdk = 29
        targetSdk = 36
        versionCode = 100
        versionName = "1.0.0"
        // BFF 端点配置（可在 build.gradle 中覆盖）
        buildConfigField("String", "BFF_BASE_URL", "\"https://aether-bff.example.com\"")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // jniLibs 目录：CI 构建的 Rust .so 产物放置于此，打包进 APK
    sourceSets["main"].jniLibs.directories.add("src/main/jniLibs")

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

// built-in Kotlin 下 android.kotlinOptions 已移除，改用顶层 kotlin.compilerOptions
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// 排除 JetBrains annotations 的 java5 变体，避免与 annotations:23.0.0 重复类冲突
// （annotations-java5:17.0.0 由部分依赖（如 Robolectric）传递引入，与 Kotlin stdlib 的 annotations:23.0.0 同名类冲突）
configurations.all {
    exclude(group = "org.jetbrains", module = "annotations-java5")
}

// Robolectric 运行时默认用 MavenArtifactFetcher 现场访问 Maven Central 下载 android-all jar，
// CI 上偶发 404 会让全部 Robolectric 用例一起失败。改由 Gradle 解析（带重试和构建缓存）
// 预置到本地目录，测试进程只读本地文件，不再触网。
// 每个 SDK 版本一个 configuration：同一 module 无法同时解析两个版本。
val robolectricSdkJars = listOf(
    "14-robolectric-10818077-i7",  // sdk=34（robolectric.properties）
    "15-robolectric-12650502-i7",  // targetSdk=35
).mapIndexed { index, version ->
    configurations.create("robolectricSdk$index") {
        isCanBeConsumed = false
        isCanBeResolved = true
        isTransitive = false
    }.also { dependencies.add(it.name, "org.robolectric:android-all-instrumented:$version") }
}

dependencies {
    // Compose BOM
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.0")
    implementation("androidx.navigation:navigation-compose:2.7.7")

    // Ktor (网络 + SSE)
    implementation("io.ktor:ktor-client-okhttp:2.3.12")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.12")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.12")
    implementation("io.ktor:ktor-client-logging:2.3.12")

    // DataStore (偏好设置)
    implementation("androidx.datastore:datastore-preferences:1.1.0")

    // Jetpack Security (加密存储敏感数据，如 BFF Token)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Room (本地持久化)；2.7+ 才完整支持 KSP2
    implementation("androidx.room:room-runtime:2.8.5")
    implementation("androidx.room:room-ktx:2.8.5")
    ksp("androidx.room:room-compiler:2.8.5")

    // Kotlinx Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Markwon (Markdown 渲染：core + 表格 + 任务列表 + 删除线 + 链接 + 语法高亮)
    implementation("io.noties.markwon:core:4.6.2")
    implementation("io.noties.markwon:ext-tables:4.6.2")
    implementation("io.noties.markwon:ext-tasklist:4.6.2")
    implementation("io.noties.markwon:ext-strikethrough:4.6.2")
    implementation("io.noties.markwon:linkify:4.6.2")
    implementation("io.noties.markwon:syntax-highlight:4.6.2")
    implementation("io.noties:prism4j:2.0.0")

    // ===== 单元测试依赖 =====
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
    testImplementation("androidx.room:room-testing:2.8.5")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("io.ktor:ktor-client-mock:2.3.12")
    testImplementation("io.ktor:ktor-http:2.3.12")
    testImplementation("androidx.test:core:1.5.0")
}

val robolectricJarsDir = layout.buildDirectory.dir("robolectric-jars")

val syncRobolectricJars by tasks.registering(Sync::class) {
    robolectricSdkJars.forEach { from(it) }
    into(robolectricJarsDir)
}

// Robolectric 需要在 user.home 创建 .robolectric-download-lock 锁文件，
// TRAE IDE 沙箱可能阻止在真实 home 目录写入，重定向到 build 目录
tasks.withType<Test> {
    dependsOn(syncRobolectricJars)
    val robolectricHome = layout.buildDirectory.dir("robolectric-home").get().asFile
    doFirst { robolectricHome.mkdirs() }
    systemProperty("user.home", robolectricHome.absolutePath)
    systemProperty("robolectric.dependency.dir", robolectricJarsDir.get().asFile.absolutePath)
}
