/**
 * Durable Object：全局限流器（跨边缘节点精确限流）
 *
 * 背景：isolate 内存令牌桶仅对单个 Worker isolate 生效，同一 userId 的请求
 * 落到不同边缘节点时会各自独立计数，限流额度被放大 N 倍（N = 节点数）。
 * Durable Object 提供单点强一致语义：每个 limit key 对应一个 DO 实例，
 * 全部边缘节点的请求汇聚到同一实例扣减令牌，实现真正的全局配额。
 *
 * 用法（wrangler.toml）：
 *   [[durable_objects.bindings]]
 *   name = "RATE_LIMITER"
 *   class_name = "RateLimiterDO"
 *   [[migrations]]
 *   tag = "v1"
 *   new_sqlite_classes = ["RateLimiterDO"]
 *
 * 接口：POST /  body: { limit }  →  { allowed, retryAfter, remaining }
 *   - limit：每分钟允许的请求数（capacity），变更时自动重整桶容量
 *
 * 状态：storage.key = "bucket" 持久化 { capacity, refillRate, tokens, last }，
 *   DO 实例被驱逐重启后从 storage 恢复，不丢配额。
 *
 * 注意：DO 内不依赖 WASM（避免 DO 环境重复加载产物），用与 JSRateLimiter
 * 等价的纯 JS 令牌桶算法（ratelimit.js 的内存降级实现），两侧口径一致。
 */

const BUCKET_KEY = "bucket";

export class RateLimiterDO {
  /**
   * @param {DurableObjectState} state - DO 状态（storage）
   * @param {Object} env
   */
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  /**
   * 处理限流请求
   * @param {Request} request - POST，body: { limit }
   * @returns {Promise<Response>} { allowed, retryAfter, remaining }
   */
  async fetch(request) {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return new Response(JSON.stringify({ error: "bad request" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const limitNum = Number(body && body.limit);
    const limit = Number.isFinite(limitNum) && limitNum > 0 ? limitNum : 60;
    const now = Date.now();

    // 从 storage 恢复桶状态（DO 可能被驱逐重启；首次调用时初始化满桶）
    /** @type {{capacity:number, refillRate:number, tokens:number, last:number}|null} */
    let bucket = await this.state.storage.get(BUCKET_KEY);
    if (
      !bucket ||
      typeof bucket.tokens !== "number" ||
      typeof bucket.last !== "number"
    ) {
      bucket = {
        capacity: limit,
        refillRate: limit / 60.0,
        tokens: limit,
        last: now,
      };
    }

    // limit 配置变更时重整容量（保持已积累令牌但不超过新容量）
    if (bucket.capacity !== limit) {
      bucket.capacity = limit;
      bucket.refillRate = limit / 60.0;
      bucket.tokens = Math.min(bucket.tokens, limit);
    }

    // 补充令牌（与 JSRateLimiter.refill 同算法）
    const dt = Math.max(0, now - bucket.last) / 1000;
    bucket.tokens = Math.min(bucket.capacity, bucket.tokens + dt * bucket.refillRate);
    bucket.last = now;

    // 扣减
    let allowed;
    let retryAfter = 0;
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      allowed = true;
    } else {
      allowed = false;
      retryAfter = Math.max(1, Math.ceil((1 - bucket.tokens) / bucket.refillRate));
    }

    await this.state.storage.put(BUCKET_KEY, bucket);

    return new Response(
      JSON.stringify({ allowed, retryAfter, remaining: Math.floor(bucket.tokens) }),
      { headers: { "Content-Type": "application/json" } }
    );
  }
}
