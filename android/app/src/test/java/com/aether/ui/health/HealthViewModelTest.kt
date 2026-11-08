package com.aether.ui.health

import com.aether.data.api.AetherApi
import com.aether.data.api.BffConfig
import com.aether.data.model.HealthSummary
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * HealthViewModel 单元测试。
 *
 * 使用 ktor MockEngine 模拟 BFF `/health/summary/{date}` 与 `/health/summary` 响应，
 * 验证日期加载、上传、错误处理等行为。
 *
 * 关键点：
 * - ktor-client-mock 2.3.12 起 MockEngine 默认使用 `Dispatchers.IO` 执行请求，
 *   不再可通过 `MockEngineConfig.dispatcher` 配置。`runTest` + `advanceUntilIdle`
 *   无法等待真实 IO 线程完成，因此改用 `runBlocking` + `Dispatchers.Unconfined`。
 * - `Dispatchers.setMain(Dispatchers.Unconfined)` 使 `viewModelScope.launch` 启动的
 *   协程立即在调用线程开始执行，遇到 ktor 的 `withContext(Dispatchers.IO)` 时挂起并
 *   切换到 IO 线程；IO 完成后协程恢复（Unconfined 在恢复线程上继续执行）。
 * - 通过 [awaitLoading] 轮询 `isLoading`（协程开始时置 true，`finally` 中置 false）
 *   等待协程完成，避免依赖虚拟时间。
 */
class HealthViewModelTest {

    private val sampleSummary = HealthSummary(
        date = "2026-07-26",
        steps = 8523,
        sleepHours = 7.5,
        restingHeartRate = 62
    )

    @Before
    fun setMainDispatcher() {
        // Dispatchers.Unconfined 使 viewModelScope 协程立即启动；
        // ktor 内部 withContext(Dispatchers.IO) 会切换到真实 IO 线程，
        // 完成后协程在恢复线程上继续执行（Unconfined 语义）。
        Dispatchers.setMain(Dispatchers.Unconfined)
    }

    @After
    fun resetMainDispatcher() {
        Dispatchers.resetMain()
    }

    /**
     * 构造 AetherApi，注入 Mock 请求处理器。
     *
     * @param handler Mock 请求处理器（SAM 转换为 [MockRequestHandler]）
     */
    private fun makeApi(handler: MockRequestHandler): AetherApi {
        // ktor 2.3.12 起 MockEngine(handler) 直接注入请求处理器；
        // handler 在 Dispatchers.IO 上执行（ktor 框架默认）。
        val engine = MockEngine(handler)
        val client = HttpClient(engine) {
            install(ContentNegotiation) { json() }
        }
        return AetherApi(client, BffConfig(baseUrl = "http://test", userToken = "tok"))
    }

    private fun jsonSummary(s: HealthSummary): String =
        Json.encodeToString(HealthSummary.serializer(), s)

    /**
     * 等待 viewModelScope 中的异步操作完成。
     *
     * ViewModel 的异步方法（loadHealthSummary / uploadCurrentSummary）在协程开始时
     * 将 `isLoading` 置为 true，在 `finally` 中置为 false。通过轮询 `isLoading`
     * 等待协程完成，避免依赖虚拟时间（ktor IO 在真实线程上执行）。
     */
    private suspend fun awaitLoading(vm: HealthViewModel) {
        val deadline = System.currentTimeMillis() + 2000L
        while (vm.isLoading.value && System.currentTimeMillis() < deadline) {
            delay(10)
        }
    }

    @Test
    fun initialDateIsTodayFormatted() = runBlocking {
        val api = makeApi { _ ->
            respond("null", HttpStatusCode.NotFound)
        }
        val vm = HealthViewModel(api)
        // 默认日期格式 yyyy-MM-dd
        assertTrue("日期格式应为 yyyy-MM-dd: ${vm.selectedDate.value}",
            vm.selectedDate.value.matches(Regex("\\d{4}-\\d{2}-\\d{2}")))
        assertNull(vm.healthSummary.value)
        assertFalse(vm.isLoading.value)
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun loadHealthSummaryFetchesData() = runBlocking {
        val api = makeApi { requestData ->
            assertTrue(requestData.url.encodedPath.contains("/health/summary/2026-07-26"))
            respond(
                content = jsonSummary(sampleSummary),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val vm = HealthViewModel(api)
        vm.loadHealthSummary("2026-07-26")
        awaitLoading(vm)  // 等待 viewModelScope 中的协程完成
        assertEquals("2026-07-26", vm.selectedDate.value)
        val summary = vm.healthSummary.value
        assertNotNull(summary)
        assertEquals(8523, summary!!.steps)
        assertEquals(7.5, summary.sleepHours!!, 0.0001)
        assertEquals(62, summary.restingHeartRate)
        assertFalse(vm.isLoading.value)
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun loadHealthSummaryNullOnNotFound() = runBlocking {
        val api = makeApi { _ ->
            respond("null", HttpStatusCode.NotFound)
        }
        val vm = HealthViewModel(api)
        vm.loadHealthSummary("2026-07-26")
        awaitLoading(vm)  // 等待协程完成
        assertNull(vm.healthSummary.value)
        assertFalse(vm.isLoading.value)
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun loadHealthSummaryErrorSetsMessage() = runBlocking {
        // 200 但 body 非法 JSON → ktor 反序列化抛异常 → ViewModel 捕获并设置错误
        val api = makeApi { _ ->
            respond(
                content = "not-valid-json",
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val vm = HealthViewModel(api)
        vm.loadHealthSummary("2026-07-26")
        awaitLoading(vm)  // 等待协程完成
        assertNull(vm.healthSummary.value)
        assertFalse(vm.isLoading.value)
        val msg = vm.errorMessage.value
        assertTrue("errorMessage 应包含「加载健康数据失败」: $msg",
            msg != null && msg.contains("加载健康数据失败"))
    }

    @Test
    fun selectDateTriggersLoad() = runBlocking {
        val api = makeApi { requestData ->
            assertTrue(requestData.url.encodedPath.contains("/health/summary/2026-01-15"))
            respond(
                content = jsonSummary(sampleSummary.copy(date = "2026-01-15")),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val vm = HealthViewModel(api)
        vm.selectDate("2026-01-15")
        awaitLoading(vm)  // 等待 selectDate 内部触发的 loadHealthSummary 完成
        assertEquals("2026-01-15", vm.selectedDate.value)
        assertEquals("2026-01-15", vm.healthSummary.value?.date)
    }

    @Test
    fun uploadCurrentSummaryPostsSummary() = runBlocking {
        var capturedBody: String? = null
        val api = makeApi { requestData ->
            // loadHealthSummary 发起 GET，uploadCurrentSummary 发起 POST，
            // 需分别处理，避免对 GET 请求断言 POST 方法导致测试失败。
            when (requestData.method.value) {
                "GET" -> {
                    // loadHealthSummary 的 GET 请求：返回示例数据供上传使用
                    respond(
                        content = jsonSummary(sampleSummary),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
                "POST" -> {
                    // uploadCurrentSummary 的 POST 请求：验证并捕获 body
                    assertEquals("POST", requestData.method.value)
                    assertTrue(requestData.url.encodedPath.contains("/health/summary"))
                    capturedBody = (requestData.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString()
                    respond("", HttpStatusCode.OK)
                }
                else -> error("未预期的 HTTP 方法: ${requestData.method.value}")
            }
        }
        val vm = HealthViewModel(api)
        vm.loadHealthSummary("2026-07-26")
        awaitLoading(vm)  // 等待 GET 请求完成
        vm.uploadCurrentSummary()
        awaitLoading(vm)  // 等待 POST 请求完成
        assertFalse(vm.isLoading.value)
        assertNull(vm.errorMessage.value)
        assertNotNull(capturedBody)
        assertTrue("上传 body 应包含 date 字段: $capturedBody", capturedBody!!.contains("2026-07-26"))
        assertTrue("上传 body 应包含 steps 字段: $capturedBody", capturedBody!!.contains("8523"))
    }

    @Test
    fun uploadCurrentSummaryErrorSetsMessage() = runBlocking {
        // 模拟网络异常（MockEngine 抛出 → ktor 传播给调用方）
        val api = makeApi { _ ->
            throw RuntimeException("Network error")
        }
        val vm = HealthViewModel(api)
        vm.uploadCurrentSummary()
        awaitLoading(vm)  // 等待协程完成
        assertFalse(vm.isLoading.value)
        val msg = vm.errorMessage.value
        assertTrue("errorMessage 应包含「上传健康数据失败」: $msg",
            msg != null && msg.contains("上传健康数据失败"))
    }

    @Test
    fun clearErrorResetsErrorMessage() = runBlocking {
        // 200 + 非法 JSON → 反序列化异常 → ViewModel 设置错误
        val api = makeApi { _ ->
            respond(
                content = "not-valid-json",
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val vm = HealthViewModel(api)
        vm.loadHealthSummary("2026-07-26")
        awaitLoading(vm)  // 等待协程完成，错误信息已设置
        assertTrue(vm.errorMessage.value != null)
        vm.clearError()
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun updateCurrentSummaryMergesFields() = runBlocking {
        val api = makeApi { _ ->
            respond("null", HttpStatusCode.NotFound)
        }
        val vm = HealthViewModel(api)
        // updateCurrentSummary 是同步操作，无需 awaitLoading
        vm.updateCurrentSummary(steps = 1000)
        assertEquals(1000, vm.healthSummary.value?.steps)
        vm.updateCurrentSummary(sleepHours = 8.0)
        assertEquals(1000, vm.healthSummary.value?.steps)
        assertEquals(8.0, vm.healthSummary.value?.sleepHours!!, 0.0001)
    }
}
