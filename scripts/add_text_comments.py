#!/usr/bin/env python3
"""Add comment parameter to Text("中文") calls for SwiftUI auto-extraction.

Converts Text("中文内容") → Text("中文内容", comment: "")
Only matches literal strings containing Chinese characters.
Skips Text() calls that already have a comment or use NSLocalizedString/String(format:).
"""
import re
from pathlib import Path

# 15 view files with hardcoded Chinese
FILES = [
    "Aether/Views/Settings/SettingsView.swift",
    "Aether/Views/Settings/MCPSettingsView.swift",
    "Aether/Views/OnDevice/OnDeviceModelView.swift",
    "Aether/Views/Settings/PluginSettingsView.swift",
    "Aether/Views/Settings/HealthSettingsView.swift",
    "Aether/Views/Chat/MessageListView.swift",
    "Aether/Views/Chat/InlineChartView.swift",
    "Aether/Views/MenuBarExtra/MenuBarPanel.swift",
    "Aether/Views/Components/LaunchScreen.swift",
    "Aether/Views/Settings/PrivacyPolicyView.swift",
    "Aether/Views/Settings/TTSVoicePickerView.swift",
    "Aether/Views/Conversation/ConversationList.swift",
    "Aether/Views/Chat/MessageBubble.swift",
    "Aether/Views/Chat/StepCardView.swift",
    "Aether/Views/Chat/ChatInputBar.swift",
]

# Match Text("...中文...") without existing comment, NSLocalizedString, String(format:, or verbatim:
# Pattern: Text("chinese") where the string contains Chinese chars and is a simple literal
# Negative lookbehind to avoid matching inside other contexts
TEXT_PATTERN = re.compile(
    r'Text\("([^"\\]*(?:\\.[^"\\]*)*)"\)'  # Text("...") with escaped char support
)

def has_chinese(s):
    return bool(re.search(r'[\u4e00-\u9fff]', s))

def should_skip_line(line):
    stripped = line.strip()
    # Skip comment lines
    if stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
        return True
    return False

def process_text_match(m):
    content = m.group(1)
    if not has_chinese(content):
        return m.group(0)  # no Chinese, skip
    # Check if this is part of a larger expression by looking at what follows
    # We need to check the full line context, but for now just add comment
    return f'Text("{content}", comment: "")'

def process_file(filepath):
    path = Path(filepath)
    if not path.exists():
        print(f"  SKIP (not found): {filepath}")
        return 0
    content = path.read_text(encoding='utf-8')
    original = content
    count = 0
    new_lines = []
    for line in content.splitlines(keepends=True):
        if should_skip_line(line):
            new_lines.append(line)
            continue
        # Skip lines that already have Text with comment or NSLocalizedString
        if 'NSLocalizedString' in line or "comment:" in line or 'String(format:' in line or 'String(localized:' in line:
            # Still process Text() calls on this line that are simple literals
            # But be careful - only process if the Text() is not already inside NSLocalizedString
            new_line = TEXT_PATTERN.sub(process_text_match, line)
            new_lines.append(new_line)
            if new_line != line:
                count += 1
            continue
        new_line = TEXT_PATTERN.sub(process_text_match, line)
        new_lines.append(new_line)
        if new_line != line:
            count += 1
    new_content = ''.join(new_lines)
    if new_content != original:
        path.write_text(new_content, encoding='utf-8')
    return count

def main():
    total = 0
    for f in FILES:
        count = process_file(f)
        total += count
        if count > 0:
            print(f"  {f}: {count} Text() calls updated")
    print(f"\nTotal: {total} Text() calls updated with comments")

if __name__ == '__main__':
    main()
