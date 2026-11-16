import { describe, it, expect } from "vitest";
import { clampInt } from "../src/lib/utils.js";

describe("clampInt", () => {
  it("解析合法整数并按上下界夹紧", () => {
    expect(clampInt("25", { min: 1, max: 200, fallback: 50 })).toBe(25);
    expect(clampInt("9999", { min: 1, max: 200, fallback: 50 })).toBe(200);
    expect(clampInt("-5", { min: 0, max: 200, fallback: 0 })).toBe(0);
    expect(clampInt(12.9, { min: 1, max: 200, fallback: 0 })).toBe(12);
  });

  it("非法值回退到 fallback，避免 NaN 绑定进 D1", () => {
    expect(clampInt("abc", { min: 1, max: 200, fallback: 50 })).toBe(50);
    expect(clampInt("", { min: 1, max: 200, fallback: 50 })).toBe(50);
    expect(clampInt(null, { min: 1, max: 200, fallback: 50 })).toBe(50);
    expect(clampInt(undefined, { min: 1, max: 200, fallback: 50 })).toBe(50);
    expect(clampInt(NaN, { min: 1, max: 200, fallback: 50 })).toBe(50);
  });
});
