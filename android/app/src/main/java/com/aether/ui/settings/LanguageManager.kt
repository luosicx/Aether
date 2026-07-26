package com.aether.ui.settings

import android.app.Activity
import android.content.Context
import com.aether.data.api.BffConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * 语言管理器：负责当前语言代码的持久化与运行时状态暴露。
 *
 * - 持久化：通过 [BffConfigStore] 写入 DataStore。
 * - 运行时：以 [StateFlow] 形式向 UI 暴露当前语言代码，便于设置页 RadioButton 联动。
 * - 生效：Android 资源系统按 `values-<lang>` 目录匹配，需重启 Activity 才能让新语言生效，
 *   故 [setLanguage] 在写入后调用 [Activity.recreate]。
 *
 * 支持的语言代码列表见 [BffConfigStore.SUPPORTED_LANGUAGES]。
 *
 * @param store BFF 配置存储
 * @param appContext 应用 Context（保留以便后续扩展，例如注册 Locale 广播）
 * @param activity 可选 Activity，提供后切换语言会自动 [Activity.recreate]
 */
class LanguageManager(
    private val store: BffConfigStore,
    @Suppress("UNUSED_PARAMETER") appContext: Context,
    private val activity: Activity? = null
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // 当前语言代码（运行时镜像，UI 通过此 StateFlow 订阅）
    private val _currentLanguage = MutableStateFlow(BffConfigStore.DEFAULT_LANGUAGE)
    val currentLanguage: StateFlow<String> = _currentLanguage.asStateFlow()

    init {
        // 启动后台收集：DataStore 中的语言代码变化时同步到 _currentLanguage
        scope.launch {
            store.language.distinctUntilChanged().collect { code ->
                _currentLanguage.value = code
            }
        }
    }

    /**
     * 切换语言。
     *
     * @param code 语言代码，需在 [BffConfigStore.SUPPORTED_LANGUAGES] 中（否则回退到默认）
     * @param recreate 是否在写入后调用 [Activity.recreate] 重建 Activity 以让 res/values-* 生效
     */
    fun setLanguage(code: String, recreate: Boolean = true) {
        scope.launch {
            store.setLanguage(code)
            _currentLanguage.value = if (code in BffConfigStore.SUPPORTED_LANGUAGES) code
            else BffConfigStore.DEFAULT_LANGUAGE
            if (recreate) {
                // 繁体中文需映射到 res/values-zh-rTW
                // 简体中文对应默认 values/，无需特殊处理
                activity?.recreate()
            }
        }
    }

    /**
     * 将语言代码映射到 Android 资源目录后缀（仅用于调试 / 测试断言）。
     * - "zh-Hans" -> "" (默认 values/)
     * - "zh-Hant" -> "zh-rTW"
     * - "en" / "ja" / "ko" / "fr" / "de" / "es" -> 同名
     */
    fun resourceSuffixFor(code: String): String = when (code) {
        "zh-Hans" -> ""
        "zh-Hant" -> "zh-rTW"
        else -> code
    }

    /**
     * 该语言代码是否受支持。
     */
    fun isSupported(code: String): Boolean = code in BffConfigStore.SUPPORTED_LANGUAGES
}
