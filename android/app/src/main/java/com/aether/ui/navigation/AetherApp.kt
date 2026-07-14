package com.aether.ui.navigation

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.aether.data.api.AetherApi
import com.aether.data.api.BffConfig
import com.aether.data.api.BffConfigStore
import com.aether.data.api.ChatStreamClient
import com.aether.data.api.HttpClientFactory
import com.aether.data.repository.ConversationRepository
import com.aether.data.repository.MessageRepository
import com.aether.ui.chat.ChatScreen
import com.aether.ui.chat.ChatViewModel
import com.aether.ui.conversation.ConversationListScreen
import com.aether.ui.conversation.ConversationListViewModel
import com.aether.ui.settings.SettingsScreen
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * 简易服务定位器：持有 HttpClient 单例与可变 BFF 配置，
 * 在应用启动时由 MainActivity.init(context) 初始化并从 DataStore 同步配置。
 * ViewModel 通过此对象获取 API 客户端与 Repository。
 */
object ServiceLocator {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var store: BffConfigStore? = null

    // 当前 BFF 配置，由 DataStore 异步加载并实时更新
    @Volatile
    var bffConfig: BffConfig = BffConfig()
        private set

    private val httpClient by lazy { HttpClientFactory.create() }

    fun init(context: Context) {
        if (store != null) return
        val s = BffConfigStore(context.applicationContext)
        store = s
        scope.launch {
            s.config.collectLatest { config ->
                bffConfig = config
            }
        }
    }

    fun configStore(): BffConfigStore =
        store ?: error("ServiceLocator 尚未初始化，请先在 MainActivity 调用 ServiceLocator.init(context)")

    // 每次访问以最新配置构造，确保设置变更立即生效；HttpClient 复用单例
    val aetherApi: AetherApi get() = AetherApi(httpClient, bffConfig)
    val chatStreamClient: ChatStreamClient get() = ChatStreamClient(httpClient, bffConfig)
    val conversationRepository: ConversationRepository get() = ConversationRepository(aetherApi)
    val messageRepository: MessageRepository get() = MessageRepository(aetherApi)
}

/** ViewModel 工厂集合 */
object ViewModels {
    val conversationListFactory = viewModelFactory {
        initializer {
            ConversationListViewModel(ServiceLocator.conversationRepository)
        }
    }
    val chatFactory = viewModelFactory {
        initializer {
            ChatViewModel(ServiceLocator.chatStreamClient, ServiceLocator.messageRepository)
        }
    }
}

private object Routes {
    const val CONVERSATIONS = "conversations"
    const val CHAT = "chat/{conversationId}/{title}"
    const val SETTINGS = "settings"
    fun chat(conversationId: String, title: String): String =
        "chat/$conversationId/${URLEncoder.encode(title, "UTF-8")}"
}

/**
 * 应用根导航：会话列表 / 聊天 / 设置三页。
 */
@Composable
fun AetherApp() {
    val navController = rememberNavController()
    NavHost(navController, startDestination = Routes.CONVERSATIONS) {
        composable(Routes.CONVERSATIONS) {
            val vm: ConversationListViewModel = viewModel(factory = ViewModels.conversationListFactory)
            ConversationListScreen(
                viewModel = vm,
                onOpenConversation = { conv ->
                    navController.navigate(Routes.chat(conv.id, conv.title))
                },
                onOpenSettings = { navController.navigate(Routes.SETTINGS) }
            )
        }
        composable(
            route = Routes.CHAT,
            arguments = listOf(
                navArgument("conversationId") { type = NavType.StringType },
                navArgument("title") { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val conversationId = backStackEntry.arguments?.getString("conversationId") ?: return@composable
            val title = backStackEntry.arguments?.getString("title")?.let {
                URLDecoder.decode(it, "UTF-8")
            } ?: ""
            val vm: ChatViewModel = viewModel(factory = ViewModels.chatFactory)
            ChatScreen(
                conversationId = conversationId,
                conversationTitle = title,
                viewModel = vm,
                onBack = { navController.popBackStack() },
                onOpenSettings = { navController.navigate(Routes.SETTINGS) }
            )
        }
        composable(Routes.SETTINGS) {
            SettingsScreen(
                store = ServiceLocator.configStore(),
                onBack = { navController.popBackStack() }
            )
        }
    }
}
