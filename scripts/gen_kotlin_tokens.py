#!/usr/bin/env python3
"""
gen_kotlin_tokens.py — 读取 DesignTokens/tokens.json，生成 Kotlin 设计令牌代码（输出到 stdout）。

用法：
    python3 scripts/gen_kotlin_tokens.py [path/to/tokens.json]

生成 `object DesignTokens { ... }`，包含 Color val、字号常量、间距、圆角、动画时长。
不依赖任何第三方库，仅使用 Python 标准库。
"""
import json
import sys
import os


# ---------------------------------------------------------------------------
# 十六进制色值解析
# ---------------------------------------------------------------------------

def parse_hex_color(hex_str):
    """解析十六进制色值，返回 (r, g, b, a) 整数元组（0–255）。"""
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
        raise ValueError(f"不支持的色值格式: {hex_str!r}")
    return (r, g, b, a)


def to_android_color(hex_str):
    """返回 Android Color.argb(...) 调用字符串。"""
    r, g, b, a = parse_hex_color(hex_str)
    return f"Color.argb({a}, {r}, {g}, {b})"


def to_hex_literal(hex_str):
    """返回 0xAARRGGBB 整数字面量。"""
    s = hex_str.strip().lstrip("#")
    if len(s) == 6:
        s = "FF" + s
    return f"0x{s.upper()}L"


# ---------------------------------------------------------------------------
# Kotlin weight 映射（FontWeight）
# ---------------------------------------------------------------------------

KOTLIN_FONT_WEIGHT = {
    "regular": "FontWeight.Normal",
    "medium": "FontWeight.Medium",
    "semibold": "FontWeight.SemiBold",
    "bold": "FontWeight.Bold",
    "heavy": "FontWeight.ExtraBold",
    "black": "FontWeight.Black",
    "light": "FontWeight.Light",
    "ultraLight": "FontWeight.Thin",
}


# ---------------------------------------------------------------------------
# 生成器
# ---------------------------------------------------------------------------

def gen_kotlin(tokens):
    lines = []
    lines.append("package com.aether.design")
    lines.append("")
    lines.append("import androidx.compose.ui.graphics.Color")
    lines.append("import androidx.compose.ui.text.font.FontWeight")
    lines.append("import androidx.compose.ui.unit.dp")
    lines.append("import androidx.compose.ui.unit.sp")
    lines.append("")
    lines.append("/**")
    lines.append(" * Auto-generated from tokens.json. Do not edit manually.")
    lines.append(" * 单一真相源：DesignTokens/tokens.json")
    lines.append(" * 生成脚本：scripts/gen_kotlin_tokens.py")
    lines.append(" */")
    lines.append("object DesignTokens {")
    lines.append("")

    # Color
    if "color" in tokens:
        lines.append("    // MARK: - Color")
        for key, tok in tokens["color"].items():
            hex_val = tok["value"]
            desc = tok.get("description", "")
            comment = f" // {desc}" if desc else ""
            # Kotlin 属性名采用 camelCase，首字母小写
            prop = key[0].lower() + key[1:] if key else key
            lines.append(f"    val {prop}: Color = {to_android_color(hex_val)}{comment}")
        lines.append("")

    # Typography
    if "typography" in tokens:
        lines.append("    // MARK: - Typography")
        for key, tok in tokens["typography"].items():
            size = tok["value"]["size"]
            weight_str = tok["value"]["weight"]
            weight_kt = KOTLIN_FONT_WEIGHT.get(weight_str, "FontWeight.Normal")
            desc = tok.get("description", "")
            comment = f" // {desc}" if desc else ""
            prop = key[0].lower() + key[1:] if key else key
            lines.append(
                f"    val {prop}Size: androidx.compose.ui.unit.TextUnit = {int(size)}.sp{comment}"
            )
            lines.append(f"    val {prop}Weight: FontWeight = {weight_kt}")
        lines.append("")

    # Spacing
    if "spacing" in tokens:
        lines.append("    // MARK: - Spacing")
        for key, tok in tokens["spacing"].items():
            val = tok["value"]
            desc = tok.get("description", "")
            comment = f" // {desc}" if desc else ""
            lines.append(f"    val spacing{key.upper()}: androidx.compose.ui.unit.Dp = {fmt_num(val)}.dp{comment}")
        lines.append("")

    # CornerRadius
    if "cornerRadius" in tokens:
        lines.append("    // MARK: - CornerRadius")
        for key, tok in tokens["cornerRadius"].items():
            val = tok["value"]
            desc = tok.get("description", "")
            comment = f" // {desc}" if desc else ""
            lines.append(f"    val corner{key[0].upper() + key[1:]}: androidx.compose.ui.unit.Dp = {fmt_num(val)}.dp{comment}")
        lines.append("")

    # Animation
    if "animation" in tokens:
        lines.append("    // MARK: - Animation (duration in ms)")
        for key, tok in tokens["animation"].items():
            val = tok["value"]
            desc = tok.get("description", "")
            comment = f" // {desc}" if desc else ""
            # tokens.json 中单位是秒，Kotlin 输出为毫秒整数
            ms = int(round(float(val) * 1000))
            lines.append(f"    val anim{key[0].upper() + key[1:]}Ms: Int = {ms}{comment}")
        lines.append("")

    lines.append("}")
    return "\n".join(lines).rstrip() + "\n"


def fmt_num(v):
    """格式化数字：整数则无小数点，否则保留合适精度。"""
    f = float(v)
    if f.is_integer():
        return str(int(f))
    return f"{f:g}"


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    default_tokens_path = os.path.join(repo_root, "DesignTokens", "tokens.json")

    tokens_path = sys.argv[1] if len(sys.argv) > 1 else default_tokens_path

    with open(tokens_path, "r", encoding="utf-8") as f:
        tokens = json.load(f)

    sys.stdout.write(gen_kotlin(tokens))


if __name__ == "__main__":
    main()
