#!/usr/bin/env python3
import json, re
from pathlib import Path

EXCLUDED_DIRS = {'AetherTests', 'AetherUITests', 'AetherWatch'}
EXCLUDED_FILES = {'Localizable.xcstrings'}

def should_extract(s):
    if not s.strip(): return False
    if not re.search(r'[\u4e00-\u9fff]', s): return False
    # Skip strings with interpolation, placeholders, or pure symbols
    if re.search(r'\(.*?\\.*?\)|\\\(|\\\{[^}]+\\\}|\$\(|%[0-9]*[@df]', s): return False
    return True

def main():
    root = Path('.')
    xcstrings_path = root / 'Aether' / 'Resources' / 'Localizable.xcstrings'
    data = json.loads(xcstrings_path.read_text(encoding='utf-8')) if xcstrings_path.exists() else {'strings': {}}
    existing = set(data.get('strings', {}).keys())
    new = set()
    for p in (root / 'Aether').rglob('*.swift'):
        if any(ex in p.parts for ex in EXCLUDED_DIRS) or p.name in EXCLUDED_FILES:
            continue
        for line in p.read_text(encoding='utf-8').splitlines():
            if line.strip().startswith(('//', '/*', '*')):
                continue
            for m in re.finditer(r'"([^"\\]*(?:\\.[^"\\]*)*)"', line):
                s = m.group(1)
                if should_extract(s) and s not in existing:
                    new.add(s)
    out = []
    for k in sorted(new):
        out.append({'key': k, 'zh-Hans': k, 'zh-Hant': '', 'en': ''})
    out_path = root / 'scripts' / 'new_strings.json'
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Found {len(out)} candidates -> {out_path}')

if __name__ == '__main__':
    main()
