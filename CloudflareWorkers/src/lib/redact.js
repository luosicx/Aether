/**
 * 脱敏工具：移除日志/错误信息中的用户敏感上下文（UUID/邮箱/URL/Token/密码字段/路径）。
 *
 * 正则匹配已迁移至 Rust（aether-core，regex crate 线性时间 NFA + SIMD），
 * 统一 Apple/Workers/Android 三端脱敏算法。
 */

// Redactor WASM 懒加载单例
let _redactor = null;
async function getRedactor() {
  if (_redactor) return _redactor;
  const mod = await import("../../wasm/aether_sse.js");
  await mod.default();
  _redactor = mod.Redactor;
  return _redactor;
}

/**
 * 对输入字符串脱敏（UUID/邮箱/URL/Token/密码字段/路径）。
 * 返回脱敏后的新字符串，原字符串不变。普通信息（如 "Network timeout"）不会被修改。
 * @param {string} input
 * @returns {Promise<string>} 脱敏后的字符串
 */
export async function redact(input) {
  if (!input || typeof input !== "string") return "";
  const Redactor = await getRedactor();
  return Redactor.redact(input);
}
