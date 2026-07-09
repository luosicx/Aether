#!/usr/bin/env python3
import json, re
from pathlib import Path

PRIORITY_PATHS = [
    'AIBuilder/Views/Settings/SettingsView.swift',
    'AIBuilder/Views/Settings/HealthSettingsView.swift',
    'AIBuilder/Views/Settings/TTSVoicePickerView.swift',
    'AIBuilder/Views/Settings/PresetPrompts.swift',
    'AIBuilder/Views/Settings/PrivacyPolicyView.swift',
    'AIBuilder/Views/Chat/ChatView.swift',
    'AIBuilder/Views/Chat/ChatInputBar.swift',
    'AIBuilder/Views/Chat/MessageListView.swift',
    'AIBuilder/Views/Chat/StepCardView.swift',
    'AIBuilder/Views/Chat/FeedbackBar.swift',
    'AIBuilder/Views/Conversation/ConversationList.swift',
    'AIBuilder/Views/Conversation/ConversationRow.swift',
    'AIBuilder/Views/RAG/KnowledgeBaseView.swift',
    'AIBuilder/Views/OnDevice/OnDeviceModelView.swift',
    'AIBuilder/Core/Constants/ModelProvider.swift',
    'AIBuilder/Core/Models/OnDeviceError.swift',
    'AIBuilder/ViewModels/SettingsViewModel.swift',
    'AIBuilder/ViewModels/ConversationListVM.swift',
    'AIBuilder/ViewModels/KnowledgeBaseVM.swift',
    'AIBuilder/ViewModels/ChatViewModel.swift',
]

def should_extract(s):
    if not s.strip(): return False
    if not re.search(r'[\u4e00-\u9fff]', s): return False
    # Skip strings with interpolation, placeholders, or pure symbols
    if re.search(r'\(.*?\\.*?\)|\\\(|\\\{[^}]+\\\}|\$\(|%[0-9]*[@df]', s): return False
    return True

def main():
    root = Path('.')
    xcstrings_path = root / 'AIBuilder' / 'Resources' / 'Localizable.xcstrings'
    data = json.loads(xcstrings_path.read_text(encoding='utf-8')) if xcstrings_path.exists() else {'strings': {}}
    existing = set(data.get('strings', {}).keys())
    new = set()
    for rel in PRIORITY_PATHS:
        p = root / rel
        if not p.exists():
            print(f'Skip missing: {rel}')
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
    out_path = root / 'scripts' / 'priority_strings.json'
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Found {len(out)} candidates -> {out_path}')

if __name__ == '__main__':
    main()
