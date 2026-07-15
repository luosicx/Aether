#!/usr/bin/env python3
"""
gen_csharp_tokens.py — 读取 DesignTokens/tokens.json，生成 C# 设计令牌代码（输出到 stdout）。

用法：
    python3 scripts/gen_csharp_tokens.py [path/to/tokens.json]

生成 `static class DesignTokens { ... }`，包含 Color 属性、字号常量、间距、圆角、动画时长。
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


def to_csharp_color(hex_str):
    """返回 C# Color.FromArgb(...) 调用字符串（ARGB 顺序）。"""
    r, g, b, a = parse_hex_color(hex_str)
    return f"Color.FromArgb({a}, {r}, {g}, {b})"


# ---------------------------------------------------------------------------
# C# weight 映射（FontWeights）
# ---------------------------------------------------------------------------

CSHARP_FONT_WEIGHT = {
    "regular": "FontWeights.Normal",
    "medium": "FontWeights.Medium",
    "semibold": "FontWeights.SemiBold",
    "bold": "FontWeights.Bold",
    "heavy": "FontWeights.ExtraBold",
    "black": "FontWeights.Black",
    "light": "FontWeights.Light",
    "ultraLight": "FontWeights.Thin",
}


# ---------------------------------------------------------------------------
# 命名工具
# ---------------------------------------------------------------------------

def pascal_case(key):
    """将 key 转为 PascalCase（C# 属性命名惯例）。"""
    if not key:
        return key
    return key[0].upper() + key[1:]


def fmt_num(v):
    """格式化数字：整数则无小数点（加 f 后缀保持 double），否则保留合适精度。"""
    f = float(v)
    if f.is_integer():
        return f"{int(f)}"
    return f"{f:g}"


# ---------------------------------------------------------------------------
# 生成器
# ---------------------------------------------------------------------------

def gen_csharp(tokens):
    lines = []
    lines.append("using Windows.UI;")
    lines.append("using Windows.UI.Text;")
    lines.append("using Windows.UI.Xaml.Media;")
    lines.append("")
    lines.append("namespace Aether.Windows.Design")
    lines.append("{")
    lines.append("    /// <summary>")
    lines.append("    /// Auto-generated from tokens.json. Do not edit manually.")
    lines.append("    /// 单一真相源：DesignTokens/tokens.json")
    lines.append("    /// 生成脚本：scripts/gen_csharp_tokens.py")
    lines.append("    /// </summary>")
    lines.append("    public static class DesignTokens")
    lines.append("    {")

    # Color
    if "color" in tokens:
        lines.append("        #region Color")
        for key, tok in tokens["color"].items():
            hex_val = tok["value"]
            desc = tok.get("description", "")
            prop = pascal_case(key)
            if desc:
                lines.append(f"        /// <summary>{desc}</summary>")
            lines.append(
                f"        public static Color {prop}Color => {to_csharp_color(hex_val)};"
            )
        lines.append("        #endregion")
        lines.append("")

    # Typography
    if "typography" in tokens:
        lines.append("        #region Typography")
        for key, tok in tokens["typography"].items():
            size = tok["value"]["size"]
            weight_str = tok["value"]["weight"]
            weight_cs = CSHARP_FONT_WEIGHT.get(weight_str, "FontWeights.Normal")
            desc = tok.get("description", "")
            prop = pascal_case(key)
            if desc:
                lines.append(f"        /// <summary>{desc}</summary>")
            lines.append(f"        public static double {prop}FontSize => {fmt_num(size)};")
            lines.append(f"        public static FontWeight {prop}FontWeight => {weight_cs};")
        lines.append("        #endregion")
        lines.append("")

    # Spacing
    if "spacing" in tokens:
        lines.append("        #region Spacing")
        for key, tok in tokens["spacing"].items():
            val = tok["value"]
            desc = tok.get("description", "")
            prop = "Spacing" + pascal_case(key)
            if desc:
                lines.append(f"        /// <summary>{desc}</summary>")
            lines.append(f"        public static double {prop} => {fmt_num(val)};")
        lines.append("        #endregion")
        lines.append("")

    # CornerRadius
    if "cornerRadius" in tokens:
        lines.append("        #region CornerRadius")
        for key, tok in tokens["cornerRadius"].items():
            val = tok["value"]
            desc = tok.get("description", "")
            prop = "Corner" + pascal_case(key)
            if desc:
                lines.append(f"        /// <summary>{desc}</summary>")
            lines.append(f"        public static double {prop} => {fmt_num(val)};")
        lines.append("        #endregion")
        lines.append("")

    # Animation
    if "animation" in tokens:
        lines.append("        #region Animation (duration in ms)")
        for key, tok in tokens["animation"].items():
            val = tok["value"]
            desc = tok.get("description", "")
            prop = "Anim" + pascal_case(key) + "Ms"
            if desc:
                lines.append(f"        /// <summary>{desc}</summary>")
            # tokens.json 中单位是秒，C# 输出为毫秒整数
            ms = int(round(float(val) * 1000))
            lines.append(f"        public static int {prop} => {ms};")
        lines.append("        #endregion")
        lines.append("")

    lines.append("    }")
    lines.append("}")
    return "\n".join(lines).rstrip() + "\n"


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

    sys.stdout.write(gen_csharp(tokens))


if __name__ == "__main__":
    main()
