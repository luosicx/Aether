/**
 * Durable Object 全局限流器测试（第二批整改）
 *
 * 覆盖：
 * 1. RateLimiterDO.fetch：满桶放行 → 连续扣减 → 拒绝 + retryAfter
 * 2. limit 配置变更时容量重整（令牌截断到新容量）
 * 3. storage 状态恢复（模拟 DO 实例被驱逐重启后配额不重置）
 * 4. checkRateLimit 经 DO 路由（mock namespace 透传结果）
 * 5. 降级链：DO 抛异常 / 返回非 2xx / 未绑定 → 内存令牌桶兜底
 */

import { describe, it, expect, vi } from "vitest";
import { RateLimiterDO } from "../src/do/rate-limiter.js";
import { checkRateLimit } from "../src/lib/ratelimit.js";

// ============ 测试基础设施 ============

/** DO state mock：内存 Map 实现 storage.get/put */
function makeDOState(seed = new Map()) {
  const store = seed;
  return {
    storage: {
      get: async (k) => (store.has(k) ? store.get(k) : undefined),
      put: async (k, v) => {
        store.set(k, v);
      },
      delete: async (k) => {
        store.delete(k);
      },
    },
    _store: store,
  };
}

/** 构造 DO 限流请求 */
function doRequest(limit) {
  return new Request("https://rate-limiter-do/check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ limit }),
  });
}

/** mock DurableObjectNamespace：转发到真实 RateLimiterDO 实例（每 key 独立实例 + 独立 storage） */
function makeDONamespace() {
  // 真实 CF 语义：idFromName(name) 同名返回同一 DO 实例（配额全局汇聚），
  // 不同 name 是不同实例且 storage 完全隔离
  const instances = new Map();
  const stores = new Map();
  return {
    idFromName: (name) => ({ name }),
    get: (id) => {
      if (!instances.has(id.name)) {
        const store = new Map();
        stores.set(id.name, store);
        instances.set(id.name, new RateLimiterDO(makeDOState(store), {}));
      }
      const doInstance = instances.get(id.name);
      return {
        // 与真实 DO stub 签名对齐：支持 fetch(input, init) 两参形式
        fetch: (input, init) => doInstance.fetch(new Request(input, init)),
      };
    },
    _stores: stores,
  };
}

// ============ RateLimiterDO 直测 ============

describe("RateLimiterDO", () => {
  it("首次请求从满桶放行，remaining 正确", async () => {
    const state = makeDOState();
    const doInstance = new RateLimiterDO(state, {});

    const resp = await doInstance.fetch(doRequest(3));
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.allowed).toBe(true);
    expect(data.remaining).toBe(2);
  });

  it("连续请求扣满后拒绝，retryAfter ≥ 1 秒", async () => {
    const state = makeDOState();
    const doInstance = new RateLimiterDO(state, {});

    // capacity=2：前 2 次放行，第 3 次拒绝
    const r1 = await (await doInstance.fetch(doRequest(2))).json();
    const r2 = await (await doInstance.fetch(doRequest(2))).json();
    const r3 = await (await doInstance.fetch(doRequest(2))).json();
    expect(r1.allowed).toBe(true);
    expect(r2.allowed).toBe(true);
    expect(r3.allowed).toBe(false);
    expect(r3.retryAfter).toBeGreaterThanOrEqual(1);
  });

  it("跨实例共享 storage：配额全局扣减（模拟跨边缘节点汇聚同一 DO）", async () => {
    // 两个 "节点"（不同 RateLimiterDO 实例）共享同一 storage
    const sharedStore = new Map();
    const node1 = new RateLimiterDO(makeDOState(sharedStore), {});
    const node2 = new RateLimiterDO(makeDOState(sharedStore), {});

    // capacity=2：node1 消耗 2 次后，node2 应立即被拒（全局配额耗尽）
    await node1.fetch(doRequest(2));
    await node1.fetch(doRequest(2));
    const r = await (await node2.fetch(doRequest(2))).json();
    expect(r.allowed).toBe(false);
  });

  it("DO 重启后从 storage 恢复状态（配额不重置）", async () => {
    const sharedStore = new Map();
    // 第一代实例扣减 1 次
    const gen1 = new RateLimiterDO(makeDOState(sharedStore), {});
    await gen1.fetch(doRequest(2));

    // 第二代实例（新 isolate，同 storage）：剩余 1 次
    const gen2 = new RateLimiterDO(makeDOState(sharedStore), {});
    const r1 = await (await gen2.fetch(doRequest(2))).json();
    const r2 = await (await gen2.fetch(doRequest(2))).json();
    expect(r1.allowed).toBe(true);
    expect(r1.remaining).toBe(0);
    expect(r2.allowed).toBe(false);
  });

  it("limit 变更时重整容量：已积累令牌截断到新容量", async () => {
    const state = makeDOState();
    const doInstance = new RateLimiterDO(state, {});

    // 预置一个旧配置（capacity=10）下已扣 0 的满桶
    state.storage.put("bucket", { capacity: 10, refillRate: 10 / 60, tokens: 10, last: Date.now() });

    // 新配置 limit=3：令牌应截断为 3，remaining=2
    const r = await (await doInstance.fetch(doRequest(3))).json();
    expect(r.allowed).toBe(true);
    expect(r.remaining).toBe(2);
  });

  it("非法 body 返回 400", async () => {
    const doInstance = new RateLimiterDO(makeDOState(), {});
    const resp = await doInstance.fetch(
      new Request("https://rate-limiter-do/check", { method: "POST", body: "not-json" })
    );
    expect(resp.status).toBe(400);
  });

  it("limit 缺省/非法时按 60 处理", async () => {
    const doInstance = new RateLimiterDO(makeDOState(), {});
    const resp = await doInstance.fetch(
      new Request("https://rate-limiter-do/check", {
        method: "POST",
        body: JSON.stringify({}),
      })
    );
    const data = await resp.json();
    expect(data.allowed).toBe(true);
    expect(data.remaining).toBe(59);
  });
});

// ============ checkRateLimit 的 DO 路由与降级 ============

describe("checkRateLimit: DO 路由与降级", () => {
  it("绑定 RATE_LIMITER 时走 DO 路径并透传结果", async () => {
    const ns = makeDONamespace();
    const env = { RATE_LIMITER: ns };

    const r1 = await checkRateLimit("user-do-1", env, 2);
    const r2 = await checkRateLimit("user-do-1", env, 2);
    const r3 = await checkRateLimit("user-do-1", env, 2);
    expect(r1.allowed).toBe(true);
    expect(r2.allowed).toBe(true);
    expect(r3.allowed).toBe(false);
    expect(r3.retryAfter).toBeGreaterThanOrEqual(1);

    // 同一 key 复用同一 DO 实例（storage 只有一份桶状态）
    expect(ns._stores.get("user-do-1").has("bucket")).toBe(true);
  });

  it("不同 key 使用独立配额（DO 实例隔离）", async () => {
    const ns = makeDONamespace();
    const env = { RATE_LIMITER: ns };

    await checkRateLimit("user-a", env, 1);
    const aSecond = await checkRateLimit("user-a", env, 1);
    const bFirst = await checkRateLimit("user-b", env, 1);
    expect(aSecond.allowed).toBe(false);
    expect(bFirst.allowed).toBe(true);
  });

  it("DO 抛异常时降级内存令牌桶（请求不失败）", async () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      const ns = {
        idFromName: () => {
          throw new Error("DO namespace unavailable");
        },
      };
      const env = { RATE_LIMITER: ns };

      const r = await checkRateLimit("user-fallback-1", env, 60);
      expect(r.allowed).toBe(true);
      expect(r.remaining).toBeGreaterThanOrEqual(0);
      expect(errSpy).toHaveBeenCalled();
    } finally {
      errSpy.mockRestore();
    }
  });

  it("DO 返回非 2xx 时降级内存令牌桶", async () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      const ns = {
        idFromName: () => ({ name: "x" }),
        get: () => ({
          fetch: async () => new Response("internal", { status: 500 }),
        }),
      };
      const env = { RATE_LIMITER: ns };

      const r = await checkRateLimit("user-fallback-2", env, 60);
      expect(r.allowed).toBe(true);
    } finally {
      errSpy.mockRestore();
    }
  });

  it("未绑定 RATE_LIMITER 时直接走内存令牌桶", async () => {
    const r = await checkRateLimit("user-nodo", {}, 600);
    expect(r.allowed).toBe(true);
  });
});
