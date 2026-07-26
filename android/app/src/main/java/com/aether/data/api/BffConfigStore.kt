package com.aether.data.api

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.aether.app.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

// 顶层 DataStore 实例（仅存非敏感数据：base_url / model / accent）
private val Context.bffDataStore by preferencesDataStore(name = "bff_config")

// 加密 SharedPreferences 文件名（仅存 user_token）
private const val ENCRYPTED_PREFS_NAME = "bff_secure_prefs"

/**
 * BFF 配置持久化：
 * - 非敏感数据（base_url / default_model / accent_color）使用 DataStore Preferences
 * - 敏感数据（user_token）使用 EncryptedSharedPreferences 加密存储
 */
class BffConfigStore(private val context: Context) {

    companion object {
        private val KEY_BASE_URL = stringPreferencesKey("base_url")
        private val KEY_MODEL = stringPreferencesKey("default_model")
        private val KEY_ACCENT = stringPreferencesKey("accent_color")
        private val KEY_LANGUAGE = stringPreferencesKey("language")
        private const val KEY_USER_TOKEN = "user_token"

        // 支持的语言代码列表（与 res/values-* 目录一一对应）
        val SUPPORTED_LANGUAGES: List<String> = listOf(
            "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"
        )

        // 默认语言（系统跟随 / 无配置时回退到简体中文）
        const val DEFAULT_LANGUAGE: String = "zh-Hans"
    }

    // EncryptedSharedPreferences 实例（懒加载）
    private val encryptedPrefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            ENCRYPTED_PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    val config: Flow<BffConfig> = context.bffDataStore.data.map { prefs ->
        BffConfig(
            baseUrl = prefs[KEY_BASE_URL] ?: BuildConfig.BFF_BASE_URL,
            userToken = encryptedPrefs.getString(KEY_USER_TOKEN, "") ?: ""
        )
    }

    val defaultModel: Flow<String> = context.bffDataStore.data.map { prefs ->
        prefs[KEY_MODEL] ?: "deepseek-chat"
    }

    // 主题色（简化版）：purple / blue / glow
    val accentColor: Flow<String> = context.bffDataStore.data.map { prefs ->
        prefs[KEY_ACCENT] ?: "purple"
    }

    // 当前语言代码（如 "zh-Hans" / "en" / "ja" 等）
    val language: Flow<String> = context.bffDataStore.data.map { prefs ->
        prefs[KEY_LANGUAGE] ?: DEFAULT_LANGUAGE
    }

    suspend fun setBaseUrl(url: String) {
        context.bffDataStore.edit { it[KEY_BASE_URL] = url }
    }

    fun setUserToken(token: String) {
        encryptedPrefs.edit().putString(KEY_USER_TOKEN, token).apply()
    }

    suspend fun setDefaultModel(model: String) {
        context.bffDataStore.edit { it[KEY_MODEL] = model }
    }

    suspend fun setAccentColor(accent: String) {
        context.bffDataStore.edit { it[KEY_ACCENT] = accent }
    }

    /**
     * 持久化语言选择。传入代码需在 [SUPPORTED_LANGUAGES] 列表中。
     * 调用后需重启 Activity 才能让 res/values-* 资源生效。
     */
    suspend fun setLanguage(code: String) {
        val normalized = if (code in SUPPORTED_LANGUAGES) code else DEFAULT_LANGUAGE
        context.bffDataStore.edit { it[KEY_LANGUAGE] = normalized }
    }
}
