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
        private const val KEY_USER_TOKEN = "user_token"
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
}
