package com.aether.data.api

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.aether.app.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

// 顶层 DataStore 实例（每个 Context 单例）
private val Context.bffDataStore by preferencesDataStore(name = "bff_config")

/**
 * BFF 配置持久化：使用 DataStore Preferences 保存端点 URL、Token 与默认模型。
 */
class BffConfigStore(private val context: Context) {

    companion object {
        private val KEY_BASE_URL = stringPreferencesKey("base_url")
        private val KEY_USER_TOKEN = stringPreferencesKey("user_token")
        private val KEY_MODEL = stringPreferencesKey("default_model")
        private val KEY_ACCENT = stringPreferencesKey("accent_color")
    }

    val config: Flow<BffConfig> = context.bffDataStore.data.map { prefs ->
        BffConfig(
            baseUrl = prefs[KEY_BASE_URL] ?: BuildConfig.BFF_BASE_URL,
            userToken = prefs[KEY_USER_TOKEN] ?: ""
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

    suspend fun setUserToken(token: String) {
        context.bffDataStore.edit { it[KEY_USER_TOKEN] = token }
    }

    suspend fun setDefaultModel(model: String) {
        context.bffDataStore.edit { it[KEY_MODEL] = model }
    }

    suspend fun setAccentColor(accent: String) {
        context.bffDataStore.edit { it[KEY_ACCENT] = accent }
    }
}
