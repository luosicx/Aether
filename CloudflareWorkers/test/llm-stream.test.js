/**
 * callLLMStream 取消传播单元测试
 *
 * mock 全局 fetch 与 WASM 模块（Node 无法 fetch 本地 wasm 文件），
 * 验证：opts.signal 透传、abort 中止上游、消费端提前退出取消上游流。
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// WASM SSE 解析 mock 为纯 JS（仅 OpenAI envelope，与生产 extractContent 语义一致）
vi.mock("../wasm/aether_sse.js", () => ({
  default: async () => {},
  SseState: class {
    extractContent(line) {
      const data = line.replace(/^data:\s*/, "");
      if (data === "[DONE]") return null;
      try {
        return JSON.parse(data).choices?.[0]?.delta?.content || null;
      } catch (_) {
        return null;
      }
    }
  },
}));

import { callLLMStream } from "../src/lib/llm.js";

const env = {
  DEEPSEEK_API_KEY: "mock-key",
  DEEPSEEK_BASE_URL: "https://deepseek.test",
};
const messages = [{ role: "user", content: "hi" }];
const encoder = new TextEncoder();

function deltaEvent(content) {
  return `data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`;
}

/** 构造上游 SSE Response；cancelSpy 记录流是否被消费端取消 */
function upstreamResponse(chunks, { close = true, cancelSpy } = {}) {
  const stream = new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
      if (close) controller.close();
    },
    cancel() {
      if (cancelSpy) cancelSpy();
    },
  });
  return new Response(stream, { status: 200 });
}

let fetchMock;

beforeEach(() => {
  fetchMock = vi.fn(async () => upstreamResponse([deltaEvent("你"), deltaEvent("好"), "data: [DONE]\n\n"]));
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("callLLMStream 取消传播", () => {
  it("opts.signal 透传给上游 fetch", async () => {
    const controller = new AbortController();
    const deltas = [];
    for await (const delta of callLLMStream(env, "deepseek-chat", messages, { signal: controller.signal })) {
      deltas.push(delta);
    }
    expect(deltas).toEqual(["你", "好"]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][1].signal).toBe(controller.signal);
  });

  it("未传 signal 时正常流式产出（向后兼容）", async () => {
    const deltas = [];
    for await (const delta of callLLMStream(env, "deepseek-chat", messages)) {
      deltas.push(delta);
    }
    expect(deltas).toEqual(["你", "好"]);
    expect(fetchMock.mock.calls[0][1].signal).toBeUndefined();
  });

  it("signal abort 时中止上游 fetch 并抛错", async () => {
    // 模拟上游悬挂：仅 signal abort 才 reject（与真实 fetch 行为一致）
    fetchMock = vi.fn((url, init) =>
      new Promise((_, reject) => {
        init.signal.addEventListener("abort", () =>
          reject(new DOMException("The operation was aborted.", "AbortError"))
        );
      })
    );
    vi.stubGlobal("fetch", fetchMock);

    const controller = new AbortController();
    const gen = callLLMStream(env, "deepseek-chat", messages, { signal: controller.signal });
    const pending = gen.next();
    controller.abort();
    await expect(pending).rejects.toThrow("aborted");
  });

  it("消费端提前 break 时取消上游流（关闭连接）", async () => {
    const cancelSpy = vi.fn();
    // 不 close 的流：只有消费端取消才会触发 cancel 算法
    fetchMock = vi.fn(async () => upstreamResponse([deltaEvent("部分")], { close: false, cancelSpy }));
    vi.stubGlobal("fetch", fetchMock);

    for await (const delta of callLLMStream(env, "deepseek-chat", messages)) {
      expect(delta).toBe("部分");
      break;
    }
    expect(cancelSpy).toHaveBeenCalledTimes(1);
  });

  it("正常读完不触发上游 cancel（流自然结束）", async () => {
    const cancelSpy = vi.fn();
    fetchMock = vi.fn(async () =>
      upstreamResponse([deltaEvent("完"), "data: [DONE]\n\n"], { cancelSpy })
    );
    vi.stubGlobal("fetch", fetchMock);

    const deltas = [];
    for await (const delta of callLLMStream(env, "deepseek-chat", messages)) {
      deltas.push(delta);
    }
    expect(deltas).toEqual(["完"]);
    expect(cancelSpy).not.toHaveBeenCalled();
  });
});