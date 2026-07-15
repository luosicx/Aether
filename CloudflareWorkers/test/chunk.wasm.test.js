import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { initSync, Chunker } from "../wasm/aether_sse.js";

describe("WASM Chunker", () => {
  beforeAll(() => {
    const wasmPath = fileURLToPath(new URL("../wasm/aether_sse_bg.wasm", import.meta.url));
    const wasmBuffer = readFileSync(wasmPath);
    initSync({ module: wasmBuffer });
  });

  it("returns empty array for empty text", () => {
    const json = Chunker.chunkDocument("", 2048, 256);
    expect(JSON.parse(json)).toEqual([]);
  });

  it("returns empty array for maxChars=0", () => {
    const json = Chunker.chunkDocument("hello world", 0, 0);
    expect(JSON.parse(json)).toEqual([]);
  });

  it("short text returns single chunk", () => {
    const text = "Hello world. This is a test.";
    const json = Chunker.chunkDocument(text, 2048, 256);
    const chunks = JSON.parse(json);
    expect(chunks).toHaveLength(1);
    expect(chunks[0]).toBe("Hello world. This is a test.");
  });

  it("splits on sentence boundary", () => {
    const text = "First sentence. Second one.";
    const json = Chunker.chunkDocument(text, 20, 0);
    const chunks = JSON.parse(json);
    expect(chunks).toHaveLength(2);
    expect(chunks[0]).toBe("First sentence.");
    expect(chunks[1]).toBe("Second one.");
  });

  it("overlap carries suffix to next chunk", () => {
    // "AAAA. " (6 chars), maxChars=5 triggers split, overlap=3
    // overlap = "A. " (last 3 of "AAAA. ")
    const json = Chunker.chunkDocument("AAAA. BBBB.", 5, 3);
    const chunks = JSON.parse(json);
    expect(chunks).toHaveLength(2);
    expect(chunks[0]).toBe("AAAA.");
    expect(chunks[1].startsWith("A. ")).toBe(true);
  });

  it("chinese sentence boundary works", () => {
    const text = "这是第一句话。这是第二句话。这是第三句话。";
    const json = Chunker.chunkDocument(text, 20, 0);
    const chunks = JSON.parse(json);
    expect(chunks.length).toBeGreaterThanOrEqual(2);
  });

  it("single long sentence not split", () => {
    const text = "thisisaverylongsentencewithoutspacesorpunctuation";
    const json = Chunker.chunkDocument(text, 10, 0);
    const chunks = JSON.parse(json);
    expect(chunks).toHaveLength(1);
    expect(chunks[0]).toBe(text);
  });

  it("chunks are trimmed", () => {
    const json = Chunker.chunkDocument("Hello. World.", 2048, 256);
    const chunks = JSON.parse(json);
    expect(chunks).toHaveLength(1);
    expect(chunks[0].startsWith(" ")).toBe(false);
    expect(chunks[0].endsWith(" ")).toBe(false);
  });

  it("returns valid JSON string array", () => {
    const json = Chunker.chunkDocument("A. B. C.", 2048, 0);
    expect(() => JSON.parse(json)).not.toThrow();
    expect(Array.isArray(JSON.parse(json))).toBe(true);
  });
});
