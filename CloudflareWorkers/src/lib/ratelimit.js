/**
 * 限流中间件：令牌桶限流器（Durable Objects 全局 + 内存降级）
 *
 * 优先级：
 *   1. Durable Object（env.RATE_LIMITER，src/do/rate-limiter.js）：
 *      跨边缘节点全局精确限流，每个 limit key 一个 DO 实例
 *   2. isolate 内存令牌桶（WASM Rust token-bucket → 纯 JS 降级）：
 *      DO 未绑定/异常时兜底，仅对单个 isolate 生效
 *
 * 默认每 userId 每分钟 60 次（capacity=60, refillRate=1/sec）。
 */

// RateLimiter WASM 懒加载单例；WASM 产物不可用时降级纯 JS 令牌桶（算法等价）
let _RateLimiterCtor = null;
let _wasmLoadFailed = false;
async function getRateLimiterCtor() {
  if (_RateLimiterCtor) return _RateLimiterCtor;
  if (_wasmLoadFailed) return null;
  try {
    const mod = await import("../../wasm/aether_sse.js");
    await mod.default();
    _RateLimiterCtor = mod.RateLimiter;
  } catch (err) {
    console.error("ratelimit: WASM 不可用，降级纯 JS 令牌桶:", err && err.message);
    _wasmLoadFailed = true;
  }
  return _RateLimiterCtor;
}

/**
 * 纯 JS 令牌桶（WASM 不可用时的等价降级实现）
 * 接口与 WASM RateLimiter 对齐：new (capacity, refillRate, nowMs) / acquire(n, nowMs) / availableTokens(nowMs)
 */
class JSRateLimiter {
  constructor(capacity, refillRate, now) {
    this.capacity = capacity;
    this.tokens = capacity;
    this.refillRate = refillRate; // tokens/sec
    this.last = now;
  }

  refill(now) {
    const dt = Math.max(0, now - this.last) / 1000;
    this.tokens = Math.min(this.capacity, this.tokens + dt * this.refillRate);
    this.last = now;
  }

  acquire(n, now) {
    this.refill(now);
    if (this.tokens >= n) {
      this.tokens -= n;
      return 0;
    }
    return (n - this.tokens) / this.refillRate; // 需等待的秒数
  }

  availableTokens(now) {
    this.refill(now);
    return this.tokens;
  }
}

// 内存计数器：userId -> RateLimiter 实例
const rateLimitMap = new Map();

/**
 * 检查限流（令牌桶算法）
 *
 * 优先级：
 *   1. Durable Object（env.RATE_LIMITER 绑定）：跨边缘节点全局精确限流，
 *      每个 limit key 一个 DO 实例，storage 持久化桶状态
 *   2. isolate 内存令牌桶（WASM → 纯 JS 降级）：DO 未绑定或调用异常时兜底，
 *      仅对当前 isolate 生效（额度按节点数放大，可接受但非精确）
 *
 * @param {string} userId - 限流维度 key（userId / authfail:IP / chat:userId）
 * @param {Object} env - Workers 环境变量（RATE_LIMITER DO binding）
 * @param {number} limit - 每分钟允许的请求数，默认 60
 * @returns {Promise<{allowed: boolean, retryAfter?: number, remaining?: number}>}
 */
export async function checkRateLimit(userId, env, limit = 60) {
  // 1. Durable Object 全局限流
  if (env && env.RATE_LIMITER && typeof env.RATE_LIMITER.idFromName === "function") {
    try {
      const viaDO = await checkViaDurableObject(env.RATE_LIMITER, userId, limit);
      if (viaDO) return viaDO;
    } catch (err) {
      // DO 异常不阻断请求：降级内存桶，保持可用性优先
      console.error("ratelimit: DO 调用失败，降级内存令牌桶:", err && err.message);
    }
  }

  // 2. 内存令牌桶（WASM 优先，不可用降级纯 JS）
  return checkInMemory(userId, limit);
}

/**
 * 经 Durable Object 检查限流
 * @param {DurableObjectNamespace} namespace - env.RATE_LIMITER
 * @param {string} key - 限流维度 key（DO 实例名，同一 key 全局唯一实例）
 * @param {number} limit - 每分钟配额
 * @returns {Promise<{allowed:boolean, retryAfter:number, remaining:number}|null>}
 *   DO 返回非 2xx 或响应异常时返回 null（触发降级）
 */
async function checkViaDurableObject(namespace, key, limit) {
  const id = namespace.idFromName(key);
  const stub = namespace.get(id);
  const resp = await stub.fetch("https://rate-limiter-do/check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ limit }),
  });
  if (!resp.ok) {
    console.error("ratelimit: DO 返回异常状态:", resp.status);
    return null;
  }
  const result = await resp.json();
  if (!result || typeof result.allowed !== "boolean") return null;
  return result;
}

/**
 * isolate 内存令牌桶检查（原实现，降级路径）
 */
async function checkInMemory(userId, limit) {
  const now = Date.now();
  const RateLimiter = await getRateLimiterCtor();

  let bucket = rateLimitMap.get(userId);
  if (!bucket) {
    // capacity = limit, refillRate = limit / 60 tokens/sec
    bucket = new (RateLimiter || JSRateLimiter)(limit, limit / 60.0, now);
    rateLimitMap.set(userId, bucket);
  }

  const retryAfter = bucket.acquire(1.0, now);
  if (retryAfter > 0) {
    return { allowed: false, retryAfter: Math.ceil(retryAfter) };
  }

  return { allowed: true, remaining: Math.floor(bucket.availableTokens(now)) };
}

/**
 * 限流失败响应构造（与现有 worker.js 429 格式对齐）
 * @param {number} retryAfter
 * @returns {Response}
 */
export function rateLimitResponse(retryAfter) {
  return new Response(JSON.stringify({ error: "rate limited" }), {
    status: 429,
    headers: {
      "Content-Type": "application/json",
      "Retry-After": String(retryAfter),
    },
  });
}
