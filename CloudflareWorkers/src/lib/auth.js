/**
 * 鉴权中间件：校验 X-BFF-Token header
 *
 * 与现有 worker.js 行为对齐：从 KV `bff_tokens` 查询 token 合法性。
 * KV 值可为：
 *   - 纯字符串（视为 userId，向后兼容旧 token）
 *   - JSON 字符串 `{ userId, name, expiresAt, ... }`（新格式，携带用户元数据）
 *
 * P1-11 (H-S5): 增加 TTL 强制过期校验。如果 KV 记录中包含 `expiresAt`（ISO 8601 字符串），
 * 且当前时间已超过 expiresAt，则视为无效 token，返回 null。
 * 旧格式（纯字符串或无 expiresAt 字段）保持向后兼容，视为永久有效。
 *
 * 失败返回 null（不抛错），由调用方决定如何返回 401。
 */

/**
 * 校验请求中的 BFF Token
 * @param {Request} request
 * @param {Object} env - Cloudflare Workers 环境变量
 * @returns {Promise<{userId: string, user: Object|null}|null>} 鉴权失败返回 null
 */
export async function authenticate(request, env) {
  const bffToken = request.headers.get("X-BFF-Token");
  if (!bffToken) {
    return null;
  }

  const tokenRecord = await env.bff_tokens.get(bffToken);
  if (!tokenRecord) {
    return null;
  }

  // 尝试解析为 JSON（新格式：携带用户元数据）
  let user = null;
  let userId = null;
  try {
    const parsed = JSON.parse(tokenRecord);
    if (parsed && typeof parsed === "object") {
      user = parsed;
      userId = parsed.userId || parsed.user_id || parsed.id || null;

      // P1-11 (H-S5): 强制 TTL 校验——如果 expiresAt 存在且已过期，视为无效 token
      // 旧格式无 expiresAt 字段时跳过校验，保持向后兼容
      if (parsed.expiresAt) {
        const expiresAtMs = Date.parse(parsed.expiresAt);
        if (!Number.isNaN(expiresAtMs) && Date.now() >= expiresAtMs) {
          // Token 已过期：返回 null，由调用方返回 401
          return null;
        }
      }
    } else {
      // JSON 但非对象（如纯数字字符串被 parse 成 number），退化为字符串
      userId = String(parsed);
    }
  } catch (_) {
    // 非 JSON：纯字符串，直接作为 userId（向后兼容旧 token）
    userId = tokenRecord;
  }

  if (!userId) {
    return null;
  }

  return { userId, user };
}

/**
 * 要求鉴权的辅助函数：鉴权失败直接返回 401 Response
 * @param {Request} request
 * @param {Object} env
 * @returns {Promise<{ok: true, userId: string, user: Object|null}|{ok: false, response: Response}>}
 */
export async function requireAuth(request, env) {
  const auth = await authenticate(request, env);
  if (!auth) {
    return {
      ok: false,
      response: new Response(JSON.stringify({ error: "BFF Token 缺失或无效" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      }),
    };
  }
  return { ok: true, userId: auth.userId, user: auth.user };
}
