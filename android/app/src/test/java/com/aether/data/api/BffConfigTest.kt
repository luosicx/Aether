package com.aether.data.api

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.aether.app.BuildConfig
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * BffConfig 与 BffConfigStore 测试。
 * 使用 Robolectric 提供 Android Context（DataStore 需要）。
 *
 * 注意：依赖 EncryptedSharedPreferences 的用例（storeSetAndGetBaseUrl /
 * storeSetAndGetUserToken）在 Robolectric（本地与 CI）环境下因 AndroidKeyStore
 * 不可用而跳过；该路径的覆盖由 iOS/macOS Keychain 测试保障。
 */
@RunWith(RobolectricTestRunner::class)
class BffConfigTest {

    companion object {
        // Robolectric 不提供 AndroidKeyStore Provider，EncryptedSharedPreferences 创建必失败。
        private val canUseAndroidKeyStore: Boolean by lazy {
            try {
                java.security.KeyStore.getInstance("AndroidKeyStore")
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    @Test
    fun bffConfigDefaultsFromBuildConfig() {
        val config = BffConfig()
        assertEquals(BuildConfig.BFF_BASE_URL, config.baseUrl)
        assertEquals("", config.userToken)
    }

    @Test
    fun bffConfigCustomValues() {
        val config = BffConfig(baseUrl = "https://custom.example.com", userToken = "tok-123")
        assertEquals("https://custom.example.com", config.baseUrl)
        assertEquals("tok-123", config.userToken)
    }

    @Test
    fun storeSetAndGetBaseUrl() = runTest {
        assumeTrue("Skip: AndroidKeyStore not available under Robolectric", canUseAndroidKeyStore)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = BffConfigStore(context)
        store.setBaseUrl("https://test.example.com")
        val config = store.config.first()
        assertEquals("https://test.example.com", config.baseUrl)
    }

    @Test
    fun storeSetAndGetUserToken() = runTest {
        assumeTrue("Skip: AndroidKeyStore not available under Robolectric", canUseAndroidKeyStore)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = BffConfigStore(context)
        store.setUserToken("token-abc")
        val config = store.config.first()
        assertEquals("token-abc", config.userToken)
    }

    @Test
    fun storeDefaultModelIsDeepseek() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = BffConfigStore(context)
        val model = store.defaultModel.first()
        assertEquals("deepseek-chat", model)
    }

    @Test
    fun storeSetAndGetDefaultModel() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = BffConfigStore(context)
        store.setDefaultModel("gpt-4")
        val model = store.defaultModel.first()
        assertEquals("gpt-4", model)
    }

    @Test
    fun storeDefaultAccentColor() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = BffConfigStore(context)
        val accent = store.accentColor.first()
        assertEquals("purple", accent)
    }
}
