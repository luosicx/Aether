import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { initSync, VectorMath } from "../wasm/aether_sse.js";

describe("WASM VectorMath", () => {
  beforeAll(() => {
    const wasmPath = fileURLToPath(new URL("../wasm/aether_sse_bg.wasm", import.meta.url));
    const wasmBuffer = readFileSync(wasmPath);
    initSync({ module: wasmBuffer });
  });

  it("identical vectors have cosine 1.0 (f32)", () => {
    const a = new Float32Array([1.0, 2.0, 3.0]);
    expect(VectorMath.cosineF32(a, a)).toBeCloseTo(1.0, 5);
  });

  it("orthogonal vectors have cosine 0.0 (f32)", () => {
    const a = new Float32Array([1.0, 0.0]);
    const b = new Float32Array([0.0, 1.0]);
    expect(VectorMath.cosineF32(a, b)).toBeCloseTo(0.0, 5);
  });

  it("mismatched length returns 0 (f32)", () => {
    const a = new Float32Array([1.0, 2.0, 3.0]);
    const b = new Float32Array([1.0, 2.0]);
    expect(VectorMath.cosineF32(a, b)).toBe(0.0);
  });

  it("identical vectors have cosine 1.0 (f64)", () => {
    const a = new Float64Array([1.0, 0.0, 0.0]);
    expect(VectorMath.cosineF64(a, a)).toBeCloseTo(1.0, 10);
  });

  it("known value: [1,0,0] vs [1,1,0] = 1/√2 (f64)", () => {
    const a = new Float64Array([1.0, 0.0, 0.0]);
    const b = new Float64Array([1.0, 1.0, 0.0]);
    expect(VectorMath.cosineF64(a, b)).toBeCloseTo(1 / Math.sqrt(2), 10);
  });

  it("topKF32 returns descending results as JSON", () => {
    const query = new Float32Array([1.0, 0.0]);
    // corpus 作为 JSON 字符串传入（number[][]）
    const corpusJson = JSON.stringify([[0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]);
    const result = JSON.parse(VectorMath.topKF32(query, corpusJson, 2));
    // [1,0] 完全匹配 → score 1.0；[1,1] → 1/√2
    expect(result).toHaveLength(2);
    expect(result[0][0]).toBe(1); // index 1
    expect(result[0][1]).toBeCloseTo(1.0, 5);
    expect(result[1][0]).toBe(2); // index 2
  });

  it("topKF32 with k=0 returns empty array", () => {
    const query = new Float32Array([1.0]);
    const corpusJson = JSON.stringify([[1.0]]);
    const result = JSON.parse(VectorMath.topKF32(query, corpusJson, 0));
    expect(result).toHaveLength(0);
  });
});
