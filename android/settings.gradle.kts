pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        // AGP 9 自带 Kotlin 编译支持（built-in Kotlin），不再单独声明 kotlin.android
        id("com.android.application") version "9.5.1"
        id("org.jetbrains.kotlin.plugin.compose") version "2.4.21"
        id("org.jetbrains.kotlin.plugin.serialization") version "2.4.21"
        id("com.google.devtools.ksp") version "2.3.14"
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Aether"
include(":app")
