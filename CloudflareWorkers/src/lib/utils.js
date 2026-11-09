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
