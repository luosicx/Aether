#!/usr/bin/env python3
import json, re
from pathlib import Path

# Exclude strings that are clearly tool descriptions, prompts, code fragments, or internal logs.
EXCLUDE_PATTERNS = [
    r'\\',                          # escaped characters (e.g. \n)
    r'\$\(',                        # Swift interpolation fragment
    r'%[@df]|%\d+\$?[@df]',        # format placeholders
    r'^\s*[-·]',                    # starts with bullet
    r'^\[',                         # starts with [
    r'^\\n',                        # starts with escaped newline
    r'\brun_\w+|\bopen_url|\bnew_tab|\bnavigate|\bscript|\bjs\b|\bmove\b|\bset_\w+|\bget_\w+|\bshow_\w+|\bcopy_to\w*|\bshow_text',
    r'command/shift/option/control|command|shift|option|control|alt|modifier',
    r'时需要|参数名|字段|示例值|枚举值|可选值',
    r'^(?:你(?:是|将|应该|可以|需要)|请(?:按|遵|用|务)|如果|涉及|回答|给出|给(?:出|用户)|用(?:户|于)|先(?:理|询)|从(?:图|文|设)|创建|列出|获取|打开|关闭|运行|执行|识别|截取|设置|读取|写入|删除|移动|查询|搜索|发送|播放|暂停|增加|减少|调整|显示|隐藏|最小化|最大化|前台|后台|截屏|截图)\b',
    r'^(?:URL|HTTP|JSON|SDK|API|App|iOS|macOS|HealthKit|LLM|ReAct|MVP|PRD|OKR|PDCA|SWOT|LaTeX|SDK|BFF|MLX|OCR|Finder|Geocoding|Forecast|SHA256|JavaScript|Shell|X|Y)\b',
]

EXCLUDE_EXACT = {
    '代码块', '分析', '关键词',
}

def should_keep(s):
    if len(s) > 180:
        return False
    if s in EXCLUDE_EXACT:
        return False
    if any(re.search(p, s, re.IGNORECASE) for p in EXCLUDE_PATTERNS):
        return False
    return True

def main():
    path = Path('scripts/new_strings.json')
    data = json.loads(path.read_text(encoding='utf-8'))
    kept = [item for item in data if should_keep(item['key'])]
    out_path = Path('scripts/filtered_strings.json')
    out_path.write_text(json.dumps(kept, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Kept {len(kept)} / {len(data)}')

if __name__ == '__main__':
    main()
