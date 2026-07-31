/**
 * Aether Web Companion 配置 (v2.0)
 *
 * 静态站点无构建步骤，环境变量通过部署时注入 window.__AETHER_ENV__ 对象覆盖默认值。
 * 例如在 index.html 加载本脚本前注入：
 *   <script>window.__AETHER_ENV__ = { BFF_BASE_URL: 'https://your-bff.workers.dev' };</script>
 * 或由部署脚本生成同级 env.js（后续接入）。
 *
 * 默认值与 iOS BFFConfig.swift 对齐：endpoint 占位 https://aether-bff.example.com，
 * 部署后必须替换为真实 BFF 网关域名。BFF 路由本身无版本前缀（/chat/stream、/conversations），
 * apiVersion 仅作为客户端逻辑版本标签保留。
 */
(function (global) {
  "use strict";

  // 从注入的环境对象读取，缺省回退到默认值
  const ENV = (global && global.__AETHER_ENV__) || {};

  const CONFIG = {
    // BFF 网关配置
    bff: {
      // BFF 网关默认地址（占位，部署后替换）
      baseUrl: ENV.BFF_BASE_URL || "https://aether-bff.example.com",
      // API 逻辑版本（客户端标签，不参与 URL 拼接）
      apiVersion: ENV.BFF_API_VERSION || "v2",
      // 普通请求超时（毫秒）
      timeoutMs: Number(ENV.BFF_TIMEOUT_MS || 30000),
      // 流式请求超时（毫秒，SSE 长连接）
      streamTimeoutMs: Number(ENV.BFF_STREAM_TIMEOUT_MS || 120000),
      // 默认上游供应商与模型（与 BFF chat.js 默认值一致）
      provider: ENV.BFF_PROVIDER || "deepseek",
      model: ENV.BFF_MODEL || "deepseek-chat",
    },
    // 安全存储配置（Web Crypto API + IndexedDB）
    storage: {
      dbName: "aether-web",
      dbVersion: 1,
      storeName: "secrets",
      keyName: "master-key", // 非提取的 AES-GCM 主密钥（CryptoKey 对象）
      tokenKey: "bff-token", // 加密后的 BFF Token 密文记录
    },
    // 客户端限流（与 iOS BFFConfig.chatRateLimitPerMin / embedRateLimitPerMin 对齐）
    rateLimit: {
      chatPerMin: 20,
      embedPerMin: 10,
    },
    // BFF Token 客户端 TTL（90 天，与 BFFConfig.tokenTTLSeconds 对齐）
    tokenTTLSeconds: 90 * 24 * 60 * 60,
  };

  global.AetherConfig = CONFIG;
})(typeof window !== "undefined" ? window : this);
