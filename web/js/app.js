/**
 * Aether Web Companion 应用逻辑骨架 (v2.0)
 *
 * 模块组成：
 *   1. BFFError          - 统一错误类型（区分鉴权 / 限流 / 超时 / 流式错误）
 *   2. SecureStorage     - 基于 Web Crypto API + IndexedDB 的令牌安全存储
 *   3. BFFClient         - BFF 网关 API 客户端（登录 / 会话列表 / 消息列表 / 流式发送）
 *   4. UIManager         - UI 渲染与交互管理（对话列表 / 消息 / 流式追加 / 加载状态）
 *   5. bootstrap         - 启动流程（自动登录恢复 / 事件绑定）
 *
 * 对齐 CloudflareWorkers BFF：
 *   - 鉴权 Header：X-BFF-Token
 *   - POST /chat/stream  SSE: {"type":"delta","content":"..."} / {"type":"done",...} / [DONE]
 *   - GET  /conversations            -> { conversations: [...] }
 *   - GET  /conversations/:id/messages -> 消息列表
 *
 * 错误约定（与 iOS BFFProxyClient 对齐）：
 *   - 401：BFF Token 缺失/无效
 *   - 429：服务端限流（携带 Retry-After）
 *   - 5xx：BFF 服务异常
 */
(function (global) {
  "use strict";

  // ===================================================================
  // 1. 统一错误类型
  // ===================================================================

  /**
   * BFF 客户端统一错误
   * @param {string} message 错误信息
   * @param {string} code    错误码：unauthorized / rate_limited / timeout / network / stream_error / error
   * @param {number} [status] HTTP 状态码
   */
  class BFFError extends Error {
    constructor(message, code, status) {
      super(message);
      this.name = "BFFError";
      this.code = code;
      this.status = status;
    }
  }

  // ===================================================================
  // 2. 安全存储：Web Crypto API (AES-GCM) + IndexedDB
  // ===================================================================

  /**
   * SecureStorage
   *
   * 安全模型：
   *   - BFF Token 明文永不写入 localStorage / sessionStorage。
   *   - 使用非提取（non-extractable）的 AES-GCM 主密钥加密 Token 密文。
   *   - 主密钥以 CryptoKey 对象形式存于 IndexedDB（结构化克隆，不可导出）。
   *   - 密文记录 { iv, ciphertext } 单独存储。
   *
   * 注意：浏览器环境无法做到与 iOS Keychain 同等强度的硬件级保护，
   * 此方案为 Web 端在可用性范围内的最优实践，仍受同源策略与 XSS 防护约束。
   */
  class SecureStorage {
    constructor(cfg) {
      this.cfg = cfg || (global.AetherConfig && global.AetherConfig.storage);
      this._dbPromise = null;
    }

    /** 打开并缓存 IndexedDB 连接 */
    _openDB() {
      if (this._dbPromise) return this._dbPromise;
      const { dbName, dbVersion, storeName } = this.cfg;
      this._dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open(dbName, dbVersion);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains(storeName)) {
            db.createObjectStore(storeName);
          }
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
      return this._dbPromise;
    }

    /** 读取/生成非提取的 AES-GCM 主密钥 */
    async _getMasterKey() {
      const db = await this._openDB();
      const { storeName, keyName } = this.cfg;
      const existing = await this._get(db, storeName, keyName);
      if (existing instanceof CryptoKey) return existing;
      // 首次使用：生成新主密钥并持久化（extractable=false，不可导出）
      const key = await crypto.subtle.generateKey(
        { name: "AES-GCM", length: 256 },
        false,
        ["encrypt", "decrypt"]
      );
      await this._put(db, storeName, keyName, key);
      return key;
    }

    /** 持久化加密后的 BFF Token */
    async saveToken(token) {
      const key = await this._getMasterKey();
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const enc = new TextEncoder();
      const ciphertext = await crypto.subtle.encrypt(
        { name: "AES-GCM", iv },
        key,
        enc.encode(token)
      );
      const db = await this._openDB();
      await this._put(db, this.cfg.storeName, this.cfg.tokenKey, {
        iv: Array.from(iv),
        ciphertext: Array.from(new Uint8Array(ciphertext)),
        savedAt: Date.now(),
      });
    }

    /** 读取并解密 BFF Token，失败返回 null */
    async loadToken() {
      try {
        const db = await this._openDB();
        const record = await this._get(db, this.cfg.storeName, this.cfg.tokenKey);
        if (!record) return null;
        const key = await this._getMasterKey();
        const iv = new Uint8Array(record.iv);
        const ciphertext = new Uint8Array(record.ciphertext);
        const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext);
        return new TextDecoder().decode(plain);
      } catch (_) {
        return null;
      }
    }

    /** 清除 Token 与主密钥 */
    async clearToken() {
      const db = await this._openDB();
      await this._delete(db, this.cfg.storeName, this.cfg.tokenKey);
      await this._delete(db, this.cfg.storeName, this.cfg.keyName);
    }

    // ---- IndexedDB 原语 ----
    _get(db, store, k) {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(store, "readonly");
        const req = tx.objectStore(store).get(k);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    _put(db, store, k, v) {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(store, "readwrite");
        tx.objectStore(store).put(v, k);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
    }
    _delete(db, store, k) {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(store, "readwrite");
        tx.objectStore(store).delete(k);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
    }
  }

  // ===================================================================
  // 3. BFF 网关 API 客户端
  // ===================================================================

  /**
   * BFFClient
   * @param {string} baseUrl BFF 网关地址（不含末尾斜杠）
   * @param {string} apiKey  BFF Token（X-BFF-Token）
   */
  class BFFClient {
    constructor(baseUrl, apiKey) {
      this.baseUrl = String(baseUrl || "").replace(/\/+$/, "");
      this.apiKey = apiKey || "";
      this._cfg = (global.AetherConfig && global.AetherConfig.bff) || {};
    }

    /** 构造请求头 */
    _headers(extra) {
      const h = {
        "Content-Type": "application/json",
        "X-BFF-Token": this.apiKey,
      };
      return Object.assign(h, extra || {});
    }

    /** 统一非流式请求 + 错误处理 */
    async _request(path, options) {
      options = options || {};
      const timeout = options.timeoutMs || this._cfg.timeoutMs || 30000;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeout);
      try {
        const resp = await fetch(this.baseUrl + path, {
          method: options.method || "GET",
          headers: this._headers(options.headers),
          body: options.body ? JSON.stringify(options.body) : undefined,
          signal: controller.signal,
        });
        return await this._handleResponse(resp);
      } catch (err) {
        if (err instanceof BFFError) throw err;
        if (err && err.name === "AbortError") {
          throw new BFFError("请求超时", "timeout");
        }
        throw new BFFError(err && err.message ? err.message : "网络错误", "network");
      } finally {
        clearTimeout(timer);
      }
    }

    /** 解析响应并归一化错误 */
    async _handleResponse(resp) {
      if (resp.ok) {
        const ct = resp.headers.get("content-type") || "";
        return ct.includes("application/json") ? resp.json() : resp.text();
      }
      let message = "请求失败";
      try {
        const e = await resp.json();
        message = (e && (e.error || e.message)) || message;
      } catch (_) {
        /* 非 JSON 错误体，忽略 */
      }
      if (resp.status === 401) {
        throw new BFFError("BFF Token 缺失或无效", "unauthorized", 401);
      }
      if (resp.status === 429) {
        const retryAfter = resp.headers.get("Retry-After");
        throw new BFFError(
          "请求过于频繁，请" + (retryAfter ? retryAfter + " 秒后" : "稍后") + "重试",
          "rate_limited",
          429
        );
      }
      throw new BFFError(message, "error", resp.status);
    }

    /**
     * 登录：校验 BFF Token 有效性
     * 通过一次轻量鉴权请求（拉取 1 条会话）验证 Token，成功即视为登录通过。
     * @param {string} apiKey BFF Token
     * @returns {Promise<{ok: true}>}
     */
    async login(apiKey) {
      this.apiKey = apiKey || "";
      await this.fetchConversations({ limit: 1 });
      return { ok: true };
    }

    /**
     * 获取对话列表
     * @param {{limit?:number, offset?:number, pinned?:boolean}} [params]
     * @returns {Promise<Array>}
     */
    async fetchConversations(params) {
      params = params || {};
      const qs = new URLSearchParams();
      if (params.limit != null) qs.set("limit", params.limit);
      if (params.offset != null) qs.set("offset", params.offset);
      if (params.pinned) qs.set("pinned", "1");
      const query = qs.toString();
      const data = await this._request("/conversations" + (query ? "?" + query : ""));
      return (data && data.conversations) || [];
    }

    /**
     * 获取指定会话的历史消息
     * @param {string} conversationId
     * @returns {Promise<Array>}
     */
    async fetchMessages(conversationId) {
      const data = await this._request(
        "/conversations/" + encodeURIComponent(conversationId) + "/messages"
      );
      return Array.isArray(data) ? data : (data && data.messages) || [];
    }

    /**
     * 发送消息（SSE 流式）
     * @param {string} conversationId 会话 ID（首次可为空，BFF 自动创建）
     * @param {string} content        消息内容
     * @param {{onDelta?:Function, onDone?:Function, onError?:Function}} [handlers]
     * @returns {Promise<void>}
     *
     * SSE 事件：
     *   data: {"type":"delta","content":"xxx"}   -> onDelta(content)
     *   data: {"type":"done","conversationId":...,"messageId":...} -> onDone(evt)
     *   data: [DONE]                              -> 流结束
     *   data: {"type":"error","message":"xxx"}    -> 抛出 / onError
     */
    async sendMessage(conversationId, content, handlers) {
      handlers = handlers || {};
      const body = {
        message: content,
        conversationId: conversationId || undefined,
        provider: this._cfg.provider,
        model: this._cfg.model,
        memoryEnabled: true,
      };
      const timeout = this._cfg.streamTimeoutMs || 120000;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeout);
      try {
        const resp = await fetch(this.baseUrl + "/chat/stream", {
          method: "POST",
          headers: this._headers(),
          body: JSON.stringify(body),
          signal: controller.signal,
        });
        if (!resp.ok || !resp.body) {
          let message = "流式请求失败";
          try {
            const e = await resp.json();
            message = (e && (e.error || e.message)) || message;
          } catch (_) {
            /* 忽略 */
          }
          if (resp.status === 401) throw new BFFError("BFF Token 缺失或无效", "unauthorized", 401);
          if (resp.status === 429) throw new BFFError("请求过于频繁，请稍后重试", "rate_limited", 429);
          throw new BFFError(message, "error", resp.status);
        }

        // 解析 SSE 流：帧以 \n\n 分隔，取 data: 行拼接
        const reader = resp.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          let sep;
          while ((sep = buffer.indexOf("\n\n")) !== -1) {
            const frame = buffer.slice(0, sep);
            buffer = buffer.slice(sep + 2);
            const payload = parseSSEFrame(frame);
            if (payload === "[DONE]") return;
            let evt;
            try {
              evt = JSON.parse(payload);
            } catch (_) {
              continue; // 非 JSON 帧忽略
            }
            if (evt.type === "delta") {
              if (handlers.onDelta) handlers.onDelta(evt.content || "");
            } else if (evt.type === "done") {
              if (handlers.onDone) handlers.onDone(evt);
            } else if (evt.type === "error") {
              throw new BFFError(evt.message || "流式错误", "stream_error");
            }
          }
        }
      } catch (err) {
        if (err && err.name === "AbortError") {
          err = new BFFError("流式请求超时", "timeout");
        }
        if (handlers.onError) {
          handlers.onError(err);
          return;
        }
        throw err;
      } finally {
        clearTimeout(timer);
      }
    }
  }

  /** 解析单个 SSE 帧，返回 data: 负载字符串 */
  function parseSSEFrame(frame) {
    return frame
      .split("\n")
      .filter((l) => l.startsWith("data:"))
      .map((l) => l.slice(5).replace(/^ /, ""))
      .join("\n");
  }

  // ===================================================================
  // 4. UI 管理器
  // ===================================================================

  /**
   * UIManager：负责 DOM 渲染与交互状态管理
   */
  class UIManager {
    constructor() {
      // 缓存常用 DOM 节点
      this.loginView = document.getElementById("login-view");
      this.appView = document.getElementById("app-view");
      this.loginForm = document.getElementById("login-form");
      this.loginError = document.getElementById("login-error");
      this.loginButton = document.getElementById("login-button");
      this.conversationList = document.getElementById("conversation-list");
      this.messageList = document.getElementById("message-list");
      this.messageForm = document.getElementById("message-form");
      this.messageInput = document.getElementById("message-input");
      this.sendButton = document.getElementById("send-button");
      this.loadingOverlay = document.getElementById("loading-overlay");
      this.loadingText = document.getElementById("loading-text");

      // 运行时状态
      this.currentConversationId = null;
      this.conversations = [];
      this.streamingBody = null; // 当前流式追加的目标气泡 body
      this.sending = false;
    }

    // ---- 视图切换 ----
    showLogin() {
      this.loginView.hidden = false;
      this.appView.hidden = true;
    }

    showApp() {
      this.loginView.hidden = true;
      this.appView.hidden = false;
    }

    // ---- 加载状态 ----
    showLoading(text) {
      this.loadingText.textContent = text || "加载中...";
      this.loadingOverlay.hidden = false;
    }

    hideLoading() {
      this.loadingOverlay.hidden = true;
    }

    // ---- 登录错误 ----
    showLoginError(message) {
      this.loginError.textContent = message || "登录失败";
      this.loginError.hidden = false;
    }

    clearLoginError() {
      this.loginError.hidden = true;
      this.loginError.textContent = "";
    }

    // ---- 发送按钮状态 ----
    setSending(flag) {
      this.sending = !!flag;
      this.sendButton.disabled = this.sending;
      this.messageInput.disabled = this.sending;
      if (!this.sending) this.messageInput.focus();
    }

    /**
     * 渲染对话列表
     * @param {Array} list 对话数组（来自 GET /conversations）
     */
    renderConversations(list) {
      this.conversations = list || [];
      this.conversationList.innerHTML = "";
      if (!this.conversations.length) {
        const hint = document.createElement("p");
        hint.className = "empty-hint";
        hint.textContent = "暂无对话";
        this.conversationList.appendChild(hint);
        return;
      }
      this.conversations.forEach((conv) => {
        const item = document.createElement("button");
        item.type = "button";
        item.className = "conversation-item";
        item.dataset.id = conv.id;
        if (conv.id === this.currentConversationId) item.classList.add("active");

        const title = document.createElement("span");
        title.className = "conversation-title";
        title.textContent = conv.title || "新会话";

        const preview = document.createElement("span");
        preview.className = "conversation-preview";
        preview.textContent = conv.last_message_preview || "";

        item.appendChild(title);
        item.appendChild(preview);

        if (typeof this.onSelectConversation === "function") {
          item.addEventListener("click", () => this.onSelectConversation(conv));
        }
        this.conversationList.appendChild(item);
      });
    }

    /** 刷新当前选中态（不重建整列） */
    refreshActive() {
      this.conversationList
        .querySelectorAll(".conversation-item")
        .forEach((el) => {
          el.classList.toggle("active", el.dataset.id === this.currentConversationId);
        });
    }

    /**
     * 渲染单条消息
     * @param {{role:string, content:string}} message
     * @returns {HTMLElement} 消息 body 节点（供流式追加复用）
     */
    renderMessage(message) {
      const bubble = document.createElement("article");
      bubble.className = "message message-" + (message.role || "assistant");

      const avatar = document.createElement("span");
      avatar.className = "message-avatar";
      avatar.textContent = message.role === "user" ? "我" : "A";

      const body = document.createElement("div");
      body.className = "message-body";
      body.textContent = message.content || "";

      bubble.appendChild(avatar);
      bubble.appendChild(body);
      this.messageList.appendChild(bubble);
      this._scrollToBottom();
      return body;
    }

    /** 清空消息区 */
    clearMessages() {
      this.messageList.innerHTML = "";
      this.streamingBody = null;
    }

    /**
     * 追加流式增量内容到当前助手气泡
     * @param {string} chunk 增量文本
     */
    appendToStream(chunk) {
      if (!this.streamingBody) {
        this.streamingBody = this.renderMessage({ role: "assistant", content: "" });
      }
      this.streamingBody.textContent += chunk;
      this._scrollToBottom();
    }

    /** 开始一条新的流式助手消息 */
    beginStream() {
      this.streamingBody = null;
    }

    /** 结束流式（释放引用） */
    endStream() {
      this.streamingBody = null;
    }

    /** 在流式过程中渲染错误为助手消息 */
    renderStreamError(message) {
      this.endStream();
      this.renderMessage({ role: "assistant", content: "[错误] " + (message || "生成失败") });
    }

    _scrollToBottom() {
      this.messageList.scrollTop = this.messageList.scrollHeight;
    }
  }

  // ===================================================================
  // 5. 启动流程
  // ===================================================================

  function bootstrap() {
    const config = global.AetherConfig;
    const storage = new SecureStorage();
    const ui = new UIManager();
    let client = null;

    // ---- 对话选择：加载历史消息 ----
    ui.onSelectConversation = async (conv) => {
      ui.currentConversationId = conv.id;
      ui.refreshActive();
      ui.clearMessages();
      try {
        ui.showLoading("加载消息...");
        const messages = await client.fetchMessages(conv.id);
        messages.forEach((m) => {
          ui.renderMessage({ role: m.role, content: m.content });
        });
      } catch (err) {
        ui.renderMessage({
          role: "assistant",
          content: "[加载历史失败] " + (err.message || "未知错误"),
        });
      } finally {
        ui.hideLoading();
      }
    };

    // ---- 登录表单提交 ----
    ui.loginForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      ui.clearLoginError();
      const endpoint = document.getElementById("bff-endpoint").value.trim();
      const token = document.getElementById("bff-token").value.trim();
      if (!endpoint || !token) {
        ui.showLoginError("请填写网关地址与 BFF Token");
        return;
      }
      ui.showLoading("登录中...");
      try {
        client = new BFFClient(endpoint, token);
        await client.login(token);
        // 登录成功：安全持久化 Token，网关地址非敏感可存 localStorage
        await storage.saveToken(token);
        localStorage.setItem("bff_endpoint", endpoint);
        await enterApp();
      } catch (err) {
        ui.showLoginError(err.message || "登录失败");
      } finally {
        ui.hideLoading();
      }
    });

    // ---- 进入主应用：拉取对话列表 ----
    async function enterApp() {
      ui.showApp();
      try {
        ui.showLoading("加载对话...");
        const list = await client.fetchConversations();
        ui.renderConversations(list);
      } catch (err) {
        ui.showLoginError(err.message || "加载对话失败");
        ui.showLogin();
      } finally {
        ui.hideLoading();
      }
    }

    // ---- 发送消息（流式） ----
    ui.messageForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (ui.sending) return;
      const content = ui.messageInput.value.trim();
      if (!content) return;

      ui.renderMessage({ role: "user", content });
      ui.messageInput.value = "";
      ui.beginStream();
      ui.setSending(true);

      try {
        await client.sendMessage(ui.currentConversationId, content, {
          onDelta: (chunk) => ui.appendToStream(chunk),
          onDone: (evt) => {
            // 首条消息：BFF 自动创建会话，回填 currentConversationId
            if (evt && evt.conversationId && !ui.currentConversationId) {
              ui.currentConversationId = evt.conversationId;
            }
            ui.endStream();
          },
          onError: (err) => ui.renderStreamError(err.message),
        });
      } catch (err) {
        ui.renderStreamError(err.message);
      } finally {
        ui.setSending(false);
      }
    });

    // ---- 输入框自适应高度 + 回车发送 ----
    ui.messageInput.addEventListener("input", () => {
      ui.messageInput.style.height = "auto";
      ui.messageInput.style.height = Math.min(ui.messageInput.scrollHeight, 160) + "px";
    });
    ui.messageInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        ui.messageForm.requestSubmit();
      }
    });

    // ---- 新建对话 ----
    document.getElementById("new-conversation").addEventListener("click", () => {
      ui.currentConversationId = null;
      ui.refreshActive();
      ui.clearMessages();
    });

    // ---- 退出登录 ----
    document.getElementById("logout-button").addEventListener("click", async () => {
      await storage.clearToken();
      localStorage.removeItem("bff_endpoint");
      location.reload();
    });

    // ---- 自动登录：从安全存储恢复 Token ----
    (async function autoLogin() {
      try {
        const token = await storage.loadToken();
        if (!token) {
          ui.showLogin();
          // 预填默认网关地址
          document.getElementById("bff-endpoint").value =
            localStorage.getItem("bff_endpoint") || (config.bff.baseUrl);
          return;
        }
        const endpoint =
          localStorage.getItem("bff_endpoint") || config.bff.baseUrl;
        client = new BFFClient(endpoint, token);
        await enterApp();
      } catch (err) {
        ui.showLogin();
        ui.showLoginError("自动登录失败，请重新输入 Token");
      }
    })();
  }

  // 暴露到全局以便调试（骨架阶段便于在控制台排查）
  global.AetherWeb = { BFFError, SecureStorage, BFFClient, UIManager, bootstrap };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
  } else {
    bootstrap();
  }
})(typeof window !== "undefined" ? window : this);
