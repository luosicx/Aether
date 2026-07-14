package com.aether.data.api

import com.aether.app.BuildConfig

data class BffConfig(
    val baseUrl: String = BuildConfig.BFF_BASE_URL,
    val userToken: String = ""  // 从 DataStore 读取
)
