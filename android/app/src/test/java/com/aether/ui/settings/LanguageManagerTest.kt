package com.aether.ui.settings

import android.app.Activity
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.aether.data.api.BffConfigStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * LanguageManager 单元测试。
 *
 * 覆盖：
 * - 初始状态（默认语言 zh-Hans）
 * - setLanguage 持久化与 StateFlow 联动
 * - 非法语言代码回退到默认
 * - activity 为 null 时的空安全（recreate=true/false）
 * - activity 非空时 recreate 回调触发
 * - resourceSuffixFor 资源目录映射
 * - isSupported 语言代码校验
 *
 * 使用 Robolectric 提供 Android Context（DataStore 需要）。
 * Dispatchers.setMain(Unconfined) 使 LanguageManager 内部 scope.launch 同步执行。
 */
@RunWith(RobolectricTestRunner::class)
class LanguageManagerTest {

    private lateinit var context: Context
    private lateinit var store: BffConfigStore

    @Before
    fun setup() {
        Dispatchers.setMain(Dispatchers.Unconfined)
        context = ApplicationProvider.getApplicationContext()
        store = BffConfigStore(context)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ===== resourceSuffixFor 资源目录映射测试 =====

    @Test
    fun resourceSuffixForZhHansReturnsEmpty() {
        val manager = LanguageManager(store, context, null)
        // 简体中文对应默认 values/ 目录，无后缀
        assertEquals("", manager.resourceSuffixFor("zh-Hans"))
    }

    @Test
    fun resourceSuffixForZhHantReturnsZhRTW() {
        val manager = LanguageManager(store, context, null)
        // 繁体中文映射到 res/values-zh-rTW
        assertEquals("zh-rTW", manager.resourceSuffixFor("zh-Hant"))
    }

    @Test
    fun resourceSuffixForSimpleLanguageReturnsSameCode() {
        val manager = LanguageManager(store, context, null)
        assertEquals("en", manager.resourceSuffixFor("en"))
        assertEquals("ja", manager.resourceSuffixFor("ja"))
        assertEquals("ko", manager.resourceSuffixFor("ko"))
        assertEquals("fr", manager.resourceSuffixFor("fr"))
        assertEquals("de", manager.resourceSuffixFor("de"))
        assertEquals("es", manager.resourceSuffixFor("es"))
    }

    @Test
    fun resourceSuffixForUnknownCodeReturnsCodeAsIs() {
        val manager = LanguageManager(store, context, null)
        // 未知代码原样返回（仅用于调试/测试断言）
        assertEquals("xyz", manager.resourceSuffixFor("xyz"))
    }

    // ===== isSupported 语言代码校验测试 =====

    @Test
    fun isSupportedReturnsTrueForAllSupportedLanguages() {
        val manager = LanguageManager(store, context, null)
        BffConfigStore.SUPPORTED_LANGUAGES.forEach { code ->
            assertTrue("$code 应为受支持语言", manager.isSupported(code))
        }
    }

    @Test
    fun isSupportedReturnsFalseForUnsupportedCodes() {
        val manager = LanguageManager(store, context, null)
        assertFalse(manager.isSupported("invalid"))
        assertFalse(manager.isSupported(""))
        assertFalse(manager.isSupported("zh"))
        assertFalse(manager.isSupported("english"))
        // 大小写敏感
        assertFalse(manager.isSupported("ZH-HANS"))
        assertFalse(manager.isSupported("EN"))
    }

    // ===== 初始状态测试 =====

    @Test
    fun initialLanguageIsDefault() = runTest {
        val manager = LanguageManager(store, context, null)
        // StateFlow 初始值为 DEFAULT_LANGUAGE（zh-Hans）
        assertEquals(BffConfigStore.DEFAULT_LANGUAGE, manager.currentLanguage.value)
        assertEquals("zh-Hans", manager.currentLanguage.value)
    }

    // ===== 持久化与 StateFlow 联动测试 =====

    @Test
    fun currentLanguageReflectsPersistedValue() = runTest {
        // 先持久化非默认语言
        store.setLanguage("en")
        // 创建 manager，init 块应收集到持久化的值
        val manager = LanguageManager(store, context, null)
        // 等待 init collector 同步持久化值到 StateFlow
        assertEquals("en", manager.currentLanguage.first { it == "en" })
    }

    @Test
    fun setLanguageWithValidCodePersistsAndUpdatesState() = runTest {
        val manager = LanguageManager(store, context, null)
        assertEquals("zh-Hans", manager.currentLanguage.value)

        manager.setLanguage("en", recreate = false)
        // 等待 StateFlow 更新为 "en"（证明 setLanguage 协程已完成）
        assertEquals("en", manager.currentLanguage.first { it == "en" })
        // 验证持久化
        assertEquals("en", store.language.first())
    }

    @Test
    fun setLanguageWithInvalidCodeFallsBackToDefault() = runTest {
        val manager = LanguageManager(store, context, null)
        // 先切换到非默认语言，确保后续回退能被检测到
        manager.setLanguage("en", recreate = false)
        assertEquals("en", manager.currentLanguage.first { it == "en" })

        // 设置非法代码，应回退到默认
        manager.setLanguage("invalid-code", recreate = false)
        assertEquals(
            BffConfigStore.DEFAULT_LANGUAGE,
            manager.currentLanguage.first { it == BffConfigStore.DEFAULT_LANGUAGE }
        )
        // 验证持久化也被规范化为默认
        assertEquals(BffConfigStore.DEFAULT_LANGUAGE, store.language.first())
    }

    @Test
    fun setLanguageSwitchesBetweenMultipleLanguages() = runTest {
        val manager = LanguageManager(store, context, null)

        manager.setLanguage("en", recreate = false)
        assertEquals("en", manager.currentLanguage.first { it == "en" })

        manager.setLanguage("ja", recreate = false)
        assertEquals("ja", manager.currentLanguage.first { it == "ja" })

        manager.setLanguage("zh-Hant", recreate = false)
        assertEquals("zh-Hant", manager.currentLanguage.first { it == "zh-Hant" })

        // 验证最终持久化值
        assertEquals("zh-Hant", store.language.first())
    }

    @Test
    fun setLanguagePersistsAllSupportedLanguages() = runTest {
        val manager = LanguageManager(store, context, null)
        BffConfigStore.SUPPORTED_LANGUAGES.forEach { code ->
            manager.setLanguage(code, recreate = false)
            assertEquals(code, manager.currentLanguage.first { it == code })
            assertEquals(code, store.language.first())
        }
    }

    // ===== 空安全测试（activity = null）=====

    @Test
    fun setLanguageWithNullActivityAndRecreateTrueDoesNotCrash() = runTest {
        val manager = LanguageManager(store, context, null)
        manager.setLanguage("en", recreate = true)
        // activity?.recreate() 安全跳过，无 NPE
        assertEquals("en", manager.currentLanguage.first { it == "en" })
    }

    @Test
    fun setLanguageWithNullActivityAndRecreateFalseDoesNotCrash() = runTest {
        val manager = LanguageManager(store, context, null)
        manager.setLanguage("en", recreate = false)
        assertEquals("en", manager.currentLanguage.first { it == "en" })
    }

    // ===== Activity recreate 回调测试 =====

    @Test
    fun setLanguageWithRecreateTrueCallsActivityRecreate() = runTest {
        val activity = RecreateTrackingActivity()
        val manager = LanguageManager(store, context, activity)
        manager.setLanguage("en", recreate = true)
        // 等待 StateFlow 更新（证明 store.setLanguage 与 _currentLanguage.value 已执行）
        assertEquals("en", manager.currentLanguage.first { it == "en" })
        // first{} 返回时 recreate() 可能尚未调用：init collector 可能先于 setLanguage
        // 协程的 recreate() 调用更新 _currentLanguage，需等待协程继续执行到 recreate()
        awaitRecreateCount(activity, 1)
        assertEquals("recreate 应被调用一次", 1, activity.recreateCount)
    }

    @Test
    fun setLanguageWithRecreateFalseDoesNotCallActivityRecreate() = runTest {
        val activity = RecreateTrackingActivity()
        val manager = LanguageManager(store, context, activity)
        manager.setLanguage("en", recreate = false)
        assertEquals("en", manager.currentLanguage.first { it == "en" })
        assertEquals("recreate 不应被调用", 0, activity.recreateCount)
    }

    @Test
    fun setLanguageMultipleTimesCallsRecreateEachTime() = runTest {
        val activity = RecreateTrackingActivity()
        val manager = LanguageManager(store, context, activity)

        manager.setLanguage("en", recreate = true)
        assertEquals("en", manager.currentLanguage.first { it == "en" })

        manager.setLanguage("ja", recreate = true)
        assertEquals("ja", manager.currentLanguage.first { it == "ja" })

        // 两次 setLanguage 协程的 recreate() 可能滞后于 first{} 返回，需等待两次均执行
        awaitRecreateCount(activity, 2)
        assertEquals("recreate 应被调用两次", 2, activity.recreateCount)
    }

    @Test
    fun setLanguageWithInvalidCodeStillCallsRecreate() = runTest {
        val activity = RecreateTrackingActivity()
        val manager = LanguageManager(store, context, activity)
        // 非法代码回退到默认，但 recreate 仍应被调用
        manager.setLanguage("invalid", recreate = true)
        // 等待 StateFlow 更新为默认值（证明协程已执行到 _currentLanguage.value 赋值）
        assertEquals(
            BffConfigStore.DEFAULT_LANGUAGE,
            manager.currentLanguage.first { it == BffConfigStore.DEFAULT_LANGUAGE }
        )
        // first{} 返回时 recreate() 可能尚未调用，需等待协程继续执行到 recreate()
        awaitRecreateCount(activity, 1)
        assertEquals("recreate 应被调用一次", 1, activity.recreateCount)
    }

    /**
     * 轮询等待 [activity.recreateCount] 达到 [expected]，最多等待 [timeoutMs] 毫秒。
     *
     * 背景：[LanguageManager.setLanguage] 协程内执行顺序为
     * `store.setLanguage → _currentLanguage.value = code → activity?.recreate()`。
     * 另外 init 块的 collector 会从 `store.language` 同步状态到 `_currentLanguage`，
     * 可能在 setLanguage 协程执行到 `recreate()` 之前就触发测试的 `first { }` 收集器返回。
     *
     * 因此 `first { }` 返回时 `recreate()` 可能尚未调用，直接断言会因时序竞争失败。
     * 此处通过轮询（[Thread.sleep] 让出 CPU 使 setLanguage 协程得以继续执行到 recreate）
     * 等待 `recreateCount` 达到预期值，稳定测试时序。
     *
     * 注意：[recreateCount] 标记为 `@Volatile`，保证跨线程可见性
     * （recreate() 可能在 DataStore IO 线程上执行）。
     */
    private fun awaitRecreateCount(
        activity: RecreateTrackingActivity,
        expected: Int,
        timeoutMs: Long = 2000L
    ) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (activity.recreateCount < expected && System.currentTimeMillis() < deadline) {
            Thread.sleep(10)
        }
    }

    /**
     * 自定义 Activity：追踪 recreate() 调用次数。
     *
     * 不调用 super.recreate() 以避免 Robolectric 生命周期重建的复杂度，
     * 仅记录调用次数用于断言。
     */
    private class RecreateTrackingActivity : Activity() {
        @Volatile var recreateCount: Int = 0
        override fun recreate() {
            recreateCount++
        }
    }
}
