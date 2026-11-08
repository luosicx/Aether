/**
 * BFF 契约测试：openapi.yaml 是线协议唯一契约源
 *
 * 校验四类漂移：
 * 1. 路由漂移：每个 operation 的 operationId 必须与 worker.js dispatch 的 handler 完全一致，
 *    且 openapi 里的 path/method 能被 matchRoute 正确解析；
 * 2. 响应漂移：真实执行路由（内存 KV/D1）后，状态码必须在契约中声明，
 *    响应 body 的字段集合必须落在对应 schema 的 properties 内，必填字段必须存在；
 * 3. 鉴权漂移：所有受保护端点未携带 token 时都返回契约声明的 401；
 * 4. 客户端漂移：Android / Windows 的 BFF DTO 反序列化字段必须声明在对应 schema 中，
 *    envelope 字段必须出现在某个成功响应里。
 *
 * 新增路由/DTO 时本测试会失败，除非同步更新 openapi.yaml —— 这正是单一契约源的目的。
 */

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import worker, { matchRoute } from "../worker.js";

const ROOT = new URL("../", import.meta.url);
const spec = parse(readFileSync(new URL("openapi.yaml", ROOT), "utf8"));
const workerSource = readFileSync(new URL("worker.js", ROOT), "utf8");

const HTTP_METHODS = ["get", "post", "patch", "put", "delete"];
const TOKEN = "contract-token";
const USER_ID = "contract-user";

/** spec 展开为 operation 列表 */
const operations = [];
for (const [path, item] of Object.entries(spec.paths)) {
  for (const method of Object.keys(item)) {
    if (HTTP_METHODS.includes(method)) {
      operations.push({ path, method: method.toUpperCase(), ...item[method] });
    }
  }
}

/** 解析 #/components/{schemas,responses}/X 引用 */
function resolveRef(node) {
  if (!node || !node.$ref) return node;
  const match = /^#\/components\/(schemas|responses)\/(.+)$/.exec(node.$ref);
  if (!match) throw new Error(`不支持的 $ref: ${node.$ref}`);
  return spec.components[match[1]][match[2]];
}

/** 取某状态码对应的 JSON 响应 schema（无 JSON body 时返回 null） */
function resolveResponseSchema(op, status) {
  const response = resolveRef(op.responses[String(status)]);
  const media = response && response.content && response.content["application/json"];
  return media ? resolveRef(media.schema) : null;
}

/** 按 schema 校验实际响应（字段集合 + 类型 + 枚举），不做隐式补全 */
function assertSchema(value, schemaNode, where) {
  const schema = resolveRef(schemaNode);
  if (!schema) return;
  if (schema.nullable && value === null) return;

  if (schema.type === "object" || schema.properties) {
    expect(
      value !== null && typeof value === "object" && !Array.isArray(value),
      `${where}: 应为对象`
    ).toBe(true);
    const declared = new Set(Object.keys(schema.properties || {}));
    for (const key of Object.keys(value)) {
      expect(declared.has(key), `${where}: 出现契约外字段 "${key}"`).toBe(true);
    }
    for (const key of schema.required || []) {
      expect(value, `${where}: 缺少必填字段 "${key}"`).toHaveProperty(key);
    }
    for (const [key, prop] of Object.entries(schema.properties || {})) {
      if (key in value) assertSchema(value[key], prop, `${where}.${key}`);
    }
    return;
  }

  if (schema.type === "array") {
    expect(Array.isArray(value), `${where}: 应为数组`).toBe(true);
    value.forEach((item, index) => assertSchema(item, schema.items, `${where}[${index}]`));
    return;
  }

  if (schema.enum) {
    expect(schema.enum, `${where}: 取值 ${JSON.stringify(value)} 超出枚举`).toContain(value);
  }
  switch (schema.type) {
    case "string":
      expect(typeof value, `${where}: 应为 string`).toBe("string");
      break;
    case "integer":
      expect(Number.isInteger(value), `${where}: 应为 integer`).toBe(true);
      break;
    case "number":
      expect(typeof value, `${where}: 应为 number`).toBe("number");
      break;
    case "boolean":
      expect(typeof value, `${where}: 应为 boolean`).toBe("boolean");
      break;
    default:
      break;
  }
}

// ============ 内存 KV / D1 ============

function makeKV() {
  const store = new Map([[TOKEN, JSON.stringify({ userId: USER_ID })]]);
  return {
    get: async (key) => (store.has(key) ? store.get(key) : null),
    put: async (key, value) => void store.set(key, value),
    delete: async (key) => void store.delete(key),
  };
}

/** D1 mock：按 SQL 子字符串匹配注册返回值，未注册的写操作默认 changes=1 */
function makeDB(pairs = []) {
  const handlers = pairs.map(([match, fns]) => ({ match, ...fns }));
  return {
    prepare(sql) {
      const matched = handlers.find((h) => sql.includes(h.match));
      let binds = [];
      const stmt = {
        bind(...args) {
          binds = args;
          return stmt;
        },
        async first() {
          return matched && matched.first ? await matched.first(binds) : null;
        },
        async all() {
          return matched && matched.all ? await matched.all(binds) : { results: [] };
        },
        async run() {
          return matched && matched.run
            ? await matched.run(binds)
            : { success: true, meta: { changes: 1 } };
        },
      };
      return stmt;
    },
    async batch(stmts) {
      return Promise.all(stmts.map((stmt) => stmt.run()));
    },
  };
}

const ok = () => ({ success: true, meta: { changes: 1 } });

function buildRequest({ path, method = "GET", body, token = TOKEN }) {
  const headers = new Headers();
  if (token) headers.set("X-BFF-Token", token);
  const init = { method, headers };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
    headers.set("Content-Type", "application/json");
  }
  return new Request("https://bff.test" + path, init);
}

// ============ 成功响应探针 ============

const CONVERSATION_ROW = {
  id: "conv-1",
  user_id: USER_ID,
  title: "契约会话",
  parent_id: null,
  created_at: 1700000000000,
  updated_at: 1700000000000,
  last_message_preview: null,
  is_pinned: 0,
  system_prompt: "你是一个有帮助的AI助手。",
  unread_count: 0,
  order_field: 1700000000000,
};

const MESSAGE_ROW = {
  id: "msg-1",
  conversation_id: "conv-1",
  role: "user",
  content: "你好",
  tool_calls: null,
  tool_call_id: null,
  tool_name: null,
  feedback: null,
  created_at: 1700000000000,
};

const MEMORY_ROW = {
  id: "mem-1",
  user_id: USER_ID,
  content: "用户偏好咖啡",
  category: "context",
  importance: 0.5,
  embedding: null,
  source_conversation_id: null,
  created_at: 1700000000000,
};

// 关键词检索不 SELECT user_id / embedding
const MEMORY_SEARCH_ROW = {
  id: "mem-1",
  content: "用户偏好咖啡",
  category: "context",
  importance: 0.5,
  source_conversation_id: null,
  created_at: 1700000000000,
};

// 关键词检索不 SELECT created_at
const CHUNK_ROW = {
  id: "chunk-1",
  document_id: "doc-1",
  content: "文档内容",
  metadata: null,
  chunk_index: 0,
  weight: 1,
  document_title: "契约文档",
};

const HEALTH_ROW = {
  user_id: USER_ID,
  date: "2026-01-01",
  steps: 1000,
  sleep_hours: 7.5,
  resting_heart_rate: 60,
};

const probes = {
  "conversations.list": {
    request: { path: "/conversations" },
    handlers: [["FROM conversations WHERE user_id", { all: () => ({ results: [CONVERSATION_ROW] }) }]],
  },
  "conversations.create": {
    request: { path: "/conversations", method: "POST", body: { title: "契约会话" } },
    status: 201,
    handlers: [["INSERT INTO conversations", { run: ok }]],
  },
  "conversations.get": {
    request: { path: "/conversations/conv-1" },
    handlers: [["FROM conversations WHERE id = ?1 AND user_id", { first: () => CONVERSATION_ROW }]],
  },
  "conversations.update": {
    request: { path: "/conversations/conv-1", method: "PATCH", body: { title: "改名" } },
    handlers: [
      ["UPDATE conversations SET", { run: ok }],
      [
        "FROM conversations WHERE id = ?1 AND user_id",
        { first: () => ({ ...CONVERSATION_ROW, title: "改名" }) },
      ],
    ],
  },
  "conversations.delete": {
    request: { path: "/conversations/conv-1", method: "DELETE" },
    handlers: [
      ["DELETE FROM messages WHERE conversation_id IN", { run: ok }],
      ["DELETE FROM conversations WHERE id = ?1 AND user_id", { run: ok }],
    ],
  },
  "messages.list": {
    request: { path: "/conversations/conv-1/messages" },
    handlers: [
      ["SELECT id FROM conversations", { first: () => ({ id: "conv-1" }) }],
      ["FROM messages WHERE conversation_id", { all: () => ({ results: [MESSAGE_ROW] }) }],
    ],
  },
  "messages.delete": {
    request: { path: "/messages/msg-1", method: "DELETE" },
    handlers: [["DELETE FROM messages", { run: ok }]],
  },
  "messages.feedback": {
    request: { path: "/messages/msg-1/feedback", method: "POST", body: { feedback: 1 } },
    handlers: [["UPDATE messages SET feedback", { run: ok }]],
  },
  "memory.list": {
    request: { path: "/memory" },
    handlers: [["FROM memories WHERE user_id", { all: () => ({ results: [MEMORY_ROW] }) }]],
  },
  "memory.create": {
    request: { path: "/memory", method: "POST", body: { content: "用户偏好咖啡" } },
    status: 201,
    handlers: [["INSERT INTO memories", { run: ok }]],
  },
  "memory.search": {
    request: { path: "/memory/search", method: "POST", body: { query: "咖啡" } },
    handlers: [["FROM memories", { all: () => ({ results: [MEMORY_SEARCH_ROW] }) }]],
  },
  "memory.delete": {
    request: { path: "/memory/mem-1", method: "DELETE" },
    handlers: [["DELETE FROM memories", { run: ok }]],
  },
  "rag.search": {
    request: { path: "/rag/search", method: "POST", body: { query: "契约" } },
    handlers: [["FROM document_chunks dc", { all: () => ({ results: [CHUNK_ROW] }) }]],
  },
  "rag.upload": {
    request: {
      path: "/rag/documents",
      method: "POST",
      body: { title: "契约文档", content: "hello world" },
    },
    status: 201,
    handlers: [["INSERT INTO documents", { run: ok }]],
  },
  "health.upload": {
    request: { path: "/health/summary", method: "POST", body: { date: "2026-01-01", steps: 1000 } },
    handlers: [["INSERT OR REPLACE INTO health_summaries", { run: ok }]],
  },
  "health.get": {
    request: { path: "/health/summary/2026-01-01" },
    handlers: [["FROM health_summaries", { first: () => HEALTH_ROW }]],
  },
};

// ============ 客户端 DTO 解析 ============

/** Kotlin：data class X(...) 构造参数，优先取 @SerialName，否则取属性名 */
function parseKotlinDtos(source) {
  const classes = new Map();
  let current = null;
  for (const line of source.split("\n")) {
    const head = line.match(/data class (\w+)\(/);
    if (head) {
      current = head[1];
      classes.set(current, []);
      continue;
    }
    if (current && /^\)/.test(line)) {
      current = null;
      continue;
    }
    if (!current) continue;
    const serialized = line.match(/@SerialName\("([^"]+)"\)/);
    if (serialized) {
      classes.get(current).push(serialized[1]);
      continue;
    }
    const property = line.match(/\bval (\w+)\s*:/);
    if (property) classes.get(current).push(property[1]);
  }
  return classes;
}

/** C#：sealed class X { [JsonPropertyName("k")] ... } */
function parseCSharpDtos(source) {
  const classes = new Map();
  const blockRe = /public sealed class (\w+)\s*\{([\s\S]*?)\n\}/g;
  for (const match of source.matchAll(blockRe)) {
    const keys = [...match[2].matchAll(/\[JsonPropertyName\("([^"]+)"\)\]/g)].map((m) => m[1]);
    classes.set(match[1], keys);
  }
  return classes;
}

const ANDROID_DTOS_URL = new URL(
  "../../android/app/src/main/java/com/aether/data/api/BffDtos.kt",
  import.meta.url
);
const WINDOWS_DTOS_URL = new URL("../../windows/Aether.Windows/Models/BffDtos.cs", import.meta.url);
const ANDROID_API_URL = new URL(
  "../../android/app/src/main/java/com/aether/data/api/AetherApi.kt",
  import.meta.url
);
const WINDOWS_API_URL = new URL(
  "../../windows/Aether.Windows/Services/AetherApiClient.cs",
  import.meta.url
);

const clientDtos = [
  { client: "Android", classes: parseKotlinDtos(readFileSync(ANDROID_DTOS_URL, "utf8")) },
  { client: "Windows", classes: parseCSharpDtos(readFileSync(WINDOWS_DTOS_URL, "utf8")) },
];

// ============ 测试 ============

describe("BFF 契约：openapi.yaml ↔ Worker 路由", () => {
  it("每个 operation 都有唯一 operationId", () => {
    const ids = operations.map((op) => op.operationId);
    for (const [index, id] of ids.entries()) {
      expect(id, `${operations[index].method} ${operations[index].path} 缺少 operationId`).toBeTruthy();
    }
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("operationId 与 dispatch 的 handler 一一对应", () => {
    const handlers = [...workerSource.matchAll(/case "([a-z]+\.[a-z]+)":/g)].map((m) => m[1]);
    expect(new Set(handlers).size).toBe(handlers.length);
    expect(operations.map((op) => op.operationId).sort()).toEqual(handlers.sort());
  });

  it("openapi 路径能被 matchRoute 正确解析", () => {
    for (const op of operations) {
      const concretePath = op.path.replace(/\{[^}]+\}/g, "probe-id");
      const route = matchRoute(op.method, concretePath);
      expect(route, `${op.method} ${op.path} 未匹配到路由`).not.toBeNull();
      expect(route.handler, `${op.method} ${op.path} 命中了错误 handler`).toBe(op.operationId);
    }
  });

  it("未携带 token 的请求都返回契约声明的 401", async () => {
    for (const op of operations) {
      const probe = probes[op.operationId];
      const request = buildRequest({
        ...(probe ? probe.request : {}),
        path: op.path.replace(/\{[^}]+\}/g, "probe-id"),
        method: op.method,
        token: null,
      });
      // 鉴权先于业务校验，无 body 也能命中 401
      const resp = await worker.fetch(request, { bff_tokens: makeKV(), DB: makeDB() }, {});
      expect(resp.status, `${op.operationId} 未鉴权状态码`).toBe(401);
      expect(op.responses["401"], `${op.operationId} 未在契约中声明 401`).toBeTruthy();
    }
  });

  it("每个 operation 都有成功响应探针", () => {
    const probed = Object.keys(probes).sort();
    const expected = operations
      .filter((op) => op.operationId !== "chat.stream")
      .map((op) => op.operationId)
      .sort();
    expect(probed).toEqual(expected);
  });

  it("成功响应符合契约 schema", async () => {
    for (const [operationId, probe] of Object.entries(probes)) {
      const op = operations.find((item) => item.operationId === operationId);
      const status = probe.status || 200;
      const env = { bff_tokens: makeKV(), DB: makeDB(probe.handlers) };
      const resp = await worker.fetch(buildRequest(probe.request), env, {});
      expect(resp.status, `${operationId} 实际状态码`).toBe(status);

      const schema = resolveResponseSchema(op, status);
      expect(schema, `${operationId} 未在契约中声明 ${status} 的 JSON schema`).toBeTruthy();
      assertSchema(await resp.json(), schema, operationId);
    }
  });
});

describe("BFF 契约：客户端 DTO", () => {
  it("DTO 字段都声明在对应 schema 中", () => {
    for (const { client, classes } of clientDtos) {
      for (const [name, keys] of classes) {
        if (name.endsWith("Envelope")) continue;
        if (!name.endsWith("Dto")) continue;

        const schemaName = name.slice(0, -"Dto".length);
        const schema = spec.components.schemas[schemaName];
        expect(schema, `${client} ${name} 找不到对应 schema "${schemaName}"`).toBeTruthy();
        expect(keys.length, `${client} ${name} 未解析到任何字段`).toBeGreaterThan(0);

        const declared = new Set(Object.keys(schema.properties || {}));
        for (const key of keys) {
          expect(
            declared.has(key),
            `${client} ${name}.${key} 未在契约 schema "${schemaName}" 中声明`
          ).toBe(true);
        }
      }
    }
  });

  it("客户端调用的路径都存在于契约中", () => {
    /** 路径参数统一归一化为 *，便于与 openapi path 模板比较 */
    const normalize = (path) =>
      path
        .split("?")[0]
        .replace(/\$\{[^}]+\}/g, "*")
        .replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, "*")
        .replace(/\{[^}]+\}/g, "*")
        .replace(/\/+$/, "");
    const contractPaths = new Set(operations.map((op) => normalize(op.path)));

    const androidSource = readFileSync(ANDROID_API_URL, "utf8");
    const windowsSource = readFileSync(WINDOWS_API_URL, "utf8");
    const clientPaths = [
      ...[...androidSource.matchAll(/\$\{config\.baseUrl\}([^"]*)/g)].map((m) => m[1]),
      ...[...windowsSource.matchAll(/\{_baseUrl\}([^"]*)/g)].map((m) => m[1]),
    ];

    expect(clientPaths.length).toBeGreaterThan(0);
    for (const path of clientPaths) {
      expect(
        contractPaths.has(normalize(path)),
        `客户端调用了契约中不存在的路径 "${path}"`
      ).toBe(true);
    }
  });

  it("envelope 字段都是契约成功响应字段", () => {
    const responseKeys = new Set();
    for (const op of operations) {
      for (const status of Object.keys(op.responses)) {
        const schema = resolveResponseSchema(op, status);
        if (schema && schema.properties) {
          for (const key of Object.keys(schema.properties)) responseKeys.add(key);
        }
      }
    }

    let checked = 0;
    for (const { client, classes } of clientDtos) {
      for (const [name, keys] of classes) {
        if (!name.endsWith("Envelope")) continue;
        checked += 1;
        for (const key of keys) {
          expect(
            responseKeys.has(key),
            `${client} ${name}.${key} 不是任何契约响应的字段`
          ).toBe(true);
        }
      }
    }
    expect(checked).toBeGreaterThan(0);
  });
});
