package com.aether.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.aether.ui.navigation.ServiceLocator
import com.aether.ui.theme.AetherTheme
import com.aether.ui.navigation.AetherApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 初始化服务定位器（DataStore + BFF 配置同步）
        ServiceLocator.init(applicationContext)
        enableEdgeToEdge()
        setContent {
            AetherTheme {
                AetherApp()
            }
        }
    }
}
