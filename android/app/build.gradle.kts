plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")  // 为 @Serializable 模型生成序列化器
    id("com.google.devtools.ksp")  // Room 用 KSP 代替 kapt
}

android {
    namespace = "com.aether.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.aether.app"
        minSdk = 29
        targetSdk = 34
        versionCode = 100
        versionName = "1.0.0"
        // BFF 端点配置（可在 build.gradle 中覆盖）
        buildConfigField("String", "BFF_BASE_URL", "\"https://aether-bff.example.com\"")
        // 启用 Rust SSE 解析路径（JNI 不可用时自动回退到 Kotlin 实现）
        buildConfigField("boolean", "USE_RUST_SSE", "true")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    // jniLibs 目录：CI 构建的 Rust .so 产物放置于此，打包进 APK
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

dependencies {
    // Compose BOM
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
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

    // Room (本地持久化)
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // Kotlinx Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // ===== 单元测试依赖 =====
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
    testImplementation("androidx.room:room-testing:2.6.1")
    testImplementation("org.robolectric:robolectric:4.12.2")
    testImplementation("io.ktor:ktor-client-mock:2.3.12")
}
