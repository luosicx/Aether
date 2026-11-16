/**
 * 共享工具函数
 */

/**
 * 生成 UUID（Workers runtime 支持 crypto.randomUUID）
 * @returns {string}
 */
export function genId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "id-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
}

/**
 * 构造 JSON 成功响应
 * @param {any} data
 * @param {number} status
 * @returns {Response}
 */
export function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * 解析并夹紧整数参数。
 *
 * 直接 `Math.min(parseInt(x), 200)` 在 `x` 非数字时得到 NaN：NaN 绑定进 D1 会
 * 变成 NULL/报错，负 offset 或超大 limit 也会放大查询开销。统一在此兜底：
 * 非法值回退 fallback，越界值夹到 [min, max]，合法值截断为整数。
 *
 * @param {string|number|null|undefined} value
 * @param {{min?:number, max?:number, fallback?:number}} [opts]
 * @returns {number}
 */
export function clampInt(value, { min = 0, max = 200, fallback = 0 } = {}) {
  const n = typeof value === "number" ? value : parseInt(value, 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(Math.trunc(n), min), max);
}
