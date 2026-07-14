#!/usr/bin/env python3
"""
gen_swift_tokens.py — 读取 DesignTokens/tokens.json，生成 Swift 设计令牌代码（输出到 stdout）。

用法：
    python3 scripts/gen_swift_tokens.py [path/to/tokens.json]

不依赖任何第三方库，仅使用 Python 标准库。
"""
import json
import sys
import os


# ---------------------------------------------------------------------------
# 十六进制色值解析
# ---------------------------------------------------------------------------

def parse_hex_color(hex_str):
    """解析十六进制色值字符串，返回 (r, g, b, a) 浮点元组（0.0–1.0）。

    支持两种格式：
      - #RRGGBB     （alpha 默认 1.0）
      - #RRGGBBAA   （alpha = AA / 255）
    """
    s = hex_str.strip().lstrip("#")
    if len(s) == 6:
        r = int(s[0:2], 16)
        g = int(s[2:4], 16)
        b = int(s[4:6], 16)
        a = 255
    elif len(s) == 8:
        r = int(s[0:2], 16)
        g = int(s[2:4], 16)
        b = int(s[4:6], 16)
        a = int(s[6:8], 16)
    else:
        raise ValueError(f"不支持的色值格式: {hex_str!r}（仅支持 #RRGGBB / #RRGGBBAA）")
    return (r / 255.0, g / 255.0, b / 255.0, a / 255.0)


def fmt_float(v):
    """将浮点数格式化为 Swift 字面量：最多 6 位小数，去除尾随 0。"""
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    if s in ("", "-", "-0"):
        s = "0"
    # 保证至少有一位小数（Swift 接受整数，但保持一致风格）
    if "." not in s:
        s += ".0"
    return s


# ---------------------------------------------------------------------------
# Swift weight 映射
# ---------------------------------------------------------------------------

SWIFT_FONT_WEIGHT = {
    "regular": ".regular",
    "medium": ".medium",
    "semibold": ".semibold",
    "bold": ".bold",
    "heavy": ".heavy",
    "black": ".black",
    "light": ".light",
    "ultraLight": ".ultraLight",
}


# ---------------------------------------------------------------------------
# 命名工具
# ---------------------------------------------------------------------------

def swift_color_name(key):
    """颜色静态属性名加 gen 前缀，避免与 ColorTokens.swift 冲突。"""
    return "gen" + key[0].upper() + key[1:]


def swift_font_name(key):
    """字体静态属性名加 gen 前缀，避免与 TypographyTokens.swift 中的
    aetherTitle / aetherDisplay / aetherBody 等同名声明冲突。"""
    return "gen" + key[0].upper() + key[1:]


# ---------------------------------------------------------------------------
# 生成器
# ---------------------------------------------------------------------------

def gen_colors(color_tokens):
    lines = []
    lines.append("public extension Color {")
    for key, tok in color_tokens.items():
        hex_val = tok["value"]
        r, g, b, a = parse_hex_color(hex_val)
        name = swift_color_name(key)
        desc = tok.get("description", "")
        if desc:
            lines.append(f"    /// {desc}")
        lines.append(
            f"    static let {name} = Color("
            f"red: {fmt_float(r)}, green: {fmt_float(g)}, "
            f"blue: {fmt_float(b)}, opacity: {fmt_float(a)})"
        )
    lines.append("}")
    return "\n".join(lines)


def gen_typography(typo_tokens):
    lines = []
    lines.append("public extension Font {")
    for key, tok in typo_tokens.items():
        size = tok["value"]["size"]
        weight_str = tok["value"]["weight"]
        weight_swift = SWIFT_FONT_WEIGHT.get(weight_str, ".regular")
        name = swift_font_name(key)
        desc = tok.get("description", "")
        if desc:
            lines.append(f"    /// {desc}")
        lines.append(
            f"    static let {name} = .system(size: {int(size)}, weight: {weight_swift})"
        )
    lines.append("}")
    return "\n".join(lines)


def gen_spacing(spacing_tokens):
    lines = []
    lines.append("public enum GeneratedSpacing {")
    for key, tok in spacing_tokens.items():
        val = tok["value"]
        desc = tok.get("description", "")
        if desc:
            lines.append(f"    /// {desc}")
        lines.append(f"    public static let {key}: CGFloat = {fmt_float(float(val))}")
    lines.append("}")
    return "\n".join(lines)


def gen_corner_radius(cr_tokens):
    lines = []
    lines.append("public enum GeneratedCornerRadius {")
    for key, tok in cr_tokens.items():
        val = tok["value"]
        desc = tok.get("description", "")
        if desc:
            lines.append(f"    /// {desc}")
        lines.append(f"    public static let {key}: CGFloat = {fmt_float(float(val))}")
    lines.append("}")
    return "\n".join(lines)


def gen_animation(anim_tokens):
    lines = []
    lines.append("public enum GeneratedAnimation {")
    for key, tok in anim_tokens.items():
        val = tok["value"]
        desc = tok.get("description", "")
        if desc:
            lines.append(f"    /// {desc}")
        # 使用 easeInOut 作为默认曲线，与原 AnimationTokens 风格一致
        lines.append(
            f"    public static let {key}: Animation = "
            f".easeInOut(duration: {fmt_float(float(val))})"
        )
    lines.append("}")
    return "\n".join(lines)


def generate_swift(tokens):
    parts = []
    parts.append("import SwiftUI")
    parts.append("")
    parts.append("// Auto-generated from tokens.json. Do not edit manually.")
    parts.append("// 单一真相源：DesignTokens/tokens.json")
    parts.append("// 生成脚本：scripts/gen_swift_tokens.py")
    parts.append("")

    if "color" in tokens:
        parts.append(gen_colors(tokens["color"]))
        parts.append("")

    if "typography" in tokens:
        parts.append(gen_typography(tokens["typography"]))
        parts.append("")

    if "spacing" in tokens:
        parts.append(gen_spacing(tokens["spacing"]))
        parts.append("")

    if "cornerRadius" in tokens:
        parts.append(gen_corner_radius(tokens["cornerRadius"]))
        parts.append("")

    if "animation" in tokens:
        parts.append(gen_animation(tokens["animation"]))
        parts.append("")

    # 末尾换行
    return "\n".join(parts).rstrip() + "\n"


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main():
    # 默认路径：相对脚本位置推导项目根目录下的 DesignTokens/tokens.json
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    default_tokens_path = os.path.join(repo_root, "DesignTokens", "tokens.json")

    tokens_path = sys.argv[1] if len(sys.argv) > 1 else default_tokens_path

    with open(tokens_path, "r", encoding="utf-8") as f:
        tokens = json.load(f)

    swift_code = generate_swift(tokens)
    sys.stdout.write(swift_code)


if __name__ == "__main__":
    main()
