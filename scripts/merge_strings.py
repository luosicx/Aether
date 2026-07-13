#!/usr/bin/env python3
import json
from pathlib import Path

xcstrings_path = Path('Aether/Resources/Localizable.xcstrings')
new_path = Path('scripts/new_strings.json')
data = json.loads(xcstrings_path.read_text(encoding='utf-8'))
strings = data.setdefault('strings', {})
for item in json.loads(new_path.read_text(encoding='utf-8')):
    key = item['key']
    if key in strings:
        continue
    entry = {'extractionState': 'manual', 'localizations': {}}
    for lang in ['zh-Hans', 'zh-Hant', 'en']:
        v = item.get(lang, '')
        if v:
            entry['localizations'][lang] = {'stringUnit': {'state': 'translated', 'value': v}}
    strings[key] = entry
xcstrings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Merged, total keys: {len(strings)}')
