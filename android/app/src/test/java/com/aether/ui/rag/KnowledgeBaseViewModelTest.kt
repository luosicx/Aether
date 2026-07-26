package com.aether.ui.rag

import com.aether.data.api.AetherApi
import com.aether.data.api.BffConfig
import com.aether.data.model.DocumentChunk
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * KnowledgeBaseViewModel 单元测试。
 *
 * 使用 ktor MockEngine 模拟 BFF `/rag/search` 响应，
 * 验证搜索加载、错误处理、清空状态等行为。
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
class KnowledgeBaseViewModelTest {

    private val sampleChunks = listOf(
        DocumentChunk(
            id = "chunk-1",
            content = "Aether 是一个跨端 AI 助手框架",
            source = "docs/intro.md",
            chunkIndex = 0,
            weight = 0.95f,
            createdAt = 0L
        ),
        DocumentChunk(
            id = "chunk-2",
            content = "RAG 模块支持向量检索与重排",
            source = "docs/rag.md",
            chunkIndex = 1,
            weight = 0.82f,
            createdAt = 0L
        )
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

    private fun jsonChunks(chunks: List<DocumentChunk>): String =
        Json.encodeToString(ListSerializer(DocumentChunk.serializer()), chunks)

    /**
     * 等待 viewModelScope 中的异步操作完成。
     *
     * ViewModel 的 `search` 方法在协程开始时将 `isLoading` 置为 true，在 `finally`
     * 中置为 false。通过轮询 `isLoading` 等待协程完成，避免依赖虚拟时间
     * （ktor IO 在真实线程上执行）。
     */
    private suspend fun awaitLoading(vm: KnowledgeBaseViewModel) {
        val deadline = System.currentTimeMillis() + 2000L
        while (vm.isLoading.value && System.currentTimeMillis() < deadline) {
            delay(10)
        }
    }

    @Test
    fun initialStateIsEmpty() = runBlocking {
        val api = makeApi { _ ->
            respond("", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val vm = KnowledgeBaseViewModel(api)
        assertEquals("", vm.searchQuery.value)
        assertTrue(vm.searchResults.value.isEmpty())
        assertFalse(vm.isLoading.value)
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun searchLoadsResultsSuccessfully() = runBlocking {
        val api = makeApi { requestData ->
            assertEquals("POST", requestData.method.value)
            assertTrue(requestData.url.encodedPath.contains("/rag/search"))
            respond(
                content = jsonChunks(sampleChunks),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val vm = KnowledgeBaseViewModel(api)
        vm.search("Aether")
        awaitLoading(vm)  // 等待 viewModelScope 中的协程完成
        assertEquals("Aether", vm.searchQuery.value)
        assertEquals(2, vm.searchResults.value.size)
        assertEquals("chunk-1", vm.searchResults.value.first().id)
        assertFalse(vm.isLoading.value)
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun searchEmptyQueryClearsResults() = runBlocking {
        val api = makeApi { _ ->
            respond("[]", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val vm = KnowledgeBaseViewModel(api)
        vm.updateQuery("dummy")
        vm.search("   ")
        // 空字符串不应触发请求，且清空错误与结果
        assertEquals("   ", vm.searchQuery.value)
        assertTrue(vm.searchResults.value.isEmpty())
        assertNull(vm.errorMessage.value)
        assertFalse(vm.isLoading.value)
    }

    @Test
    fun searchErrorSetsErrorMessage() = runBlocking {
        val api = makeApi { _ ->
            respond(
                content = "Internal Server Error",
                status = HttpStatusCode.InternalServerError,
                headers = headersOf(HttpHeaders.ContentType, "text/plain")
            )
        }
        val vm = KnowledgeBaseViewModel(api)
        vm.search("fail")
        awaitLoading(vm)  // 等待协程完成
        assertFalse(vm.isLoading.value)
        assertTrue(vm.searchResults.value.isEmpty())
        val msg = vm.errorMessage.value
        assertTrue("errorMessage 应包含「搜索失败」: $msg", msg != null && msg.contains("搜索失败"))
    }

    @Test
    fun clearErrorResetsErrorMessage() = runBlocking {
        val api = makeApi { _ ->
            respond("Internal Server Error", HttpStatusCode.InternalServerError)
        }
        val vm = KnowledgeBaseViewModel(api)
        vm.search("fail")
        awaitLoading(vm)  // 等待协程完成，错误信息已设置
        assertTrue(vm.errorMessage.value != null)
        vm.clearError()
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun updateQueryDoesNotTriggerSearch() = runBlocking {
        var requestCount = 0
        val api = makeApi { _ ->
            requestCount++
            respond("[]", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val vm = KnowledgeBaseViewModel(api)
        vm.updateQuery("aether")
        vm.updateQuery("rag")
        // updateQuery 不触发网络请求，无需 awaitLoading
        assertEquals("rag", vm.searchQuery.value)
        assertEquals(0, requestCount)
        assertTrue(vm.searchResults.value.isEmpty())
    }

    @Test
    fun resetClearsAllState() = runBlocking {
        val api = makeApi { _ ->
            respond("[]", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val vm = KnowledgeBaseViewModel(api)
        vm.updateQuery("aether")
        vm.reset()
        // reset 是同步操作，无需 awaitLoading
        assertEquals("", vm.searchQuery.value)
        assertTrue(vm.searchResults.value.isEmpty())
        assertNull(vm.errorMessage.value)
        assertFalse(vm.isLoading.value)
    }
}
