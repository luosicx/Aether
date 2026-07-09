#!/usr/bin/env python3
import json
from pathlib import Path

ADDITIONAL = {
    "%@ 代码块": {"en": "%@ Code Block", "zh-Hant": "%@ 程式碼區塊"},
    "%d 级标题": {"en": "Heading %d", "zh-Hant": "%d 級標題"},
    "maxTokens：%d": {"en": "maxTokens: %d", "zh-Hant": "maxTokens：%d"},
    "temperature：%.1f": {"en": "temperature: %.1f", "zh-Hant": "temperature：%.1f"},
    "（UIT 测试模式）已收到：%@": {"en": "(UIT Test Mode) Received: %@", "zh-Hant": "（UIT 測試模式）已收到：%@"},
    "%d 个片段": {"en": "%d fragments", "zh-Hant": "%d 個片段"},
    "%d 维": {"en": "%d dimensions", "zh-Hant": "%d 維"},
    "%d%%": {"en": "%d%%", "zh-Hant": "%d%%"},
    "chat 限流（每分钟）：%d": {"en": "chat rate limit (per min): %d", "zh-Hant": "chat 限流（每分鐘）：%d"},
    "embed 限流（每分钟）：%d": {"en": "embed rate limit (per min): %d", "zh-Hant": "embed 限流（每分鐘）：%d"},
    "参数：%@": {"en": "arguments: %@", "zh-Hant": "參數：%@"},
    "引用 %d，来源 %@": {"en": "Citation %d, source %@", "zh-Hant": "引用 %d，來源 %@"},
    "工具步骤：%@": {"en": "Tool step: %@", "zh-Hant": "工具步驟：%@"},
    "工具执行超时（%ds）": {"en": "Tool execution timed out (%ds)", "zh-Hant": "工具執行逾時（%ds）"},
    "工具调用循环超过 %d 轮，已中止": {"en": "Tool calling loop exceeded %d rounds, aborted", "zh-Hant": "工具呼叫循環超過 %d 輪，已中止"},
    "感谢反馈": {"en": "Thanks for your feedback", "zh-Hant": "感謝回饋"},
    "授权失败：%@": {"en": "Authorization failed: %@", "zh-Hant": "授權失敗：%@"},
    "下载中…%d%%": {"en": "Downloading…%d%%", "zh-Hant": "下載中…%d%%"},
    "第 %d 轮": {"en": "Round %d", "zh-Hant": "第 %d 輪"},
    "确定删除 %@ 的 API Key？删除后无法恢复。": {"en": "Delete API Key for %@? This cannot be undone.", "zh-Hant": "確定刪除 %@ 的 API Key？刪除後無法恢復。"},
    "确定删除选中的 %d 个对话？删除后无法恢复。": {"en": "Delete selected %d conversations? This cannot be undone.", "zh-Hant": "確定刪除選中的 %d 個對話？刪除後無法恢復。"},
    "删除选中(%d)": {"en": "Delete Selected (%d)", "zh-Hant": "刪除選中(%d)"},
    "生成失败：%@": {"en": "Generation failed: %@", "zh-Hant": "生成失敗：%@"},
    "睡眠 %.1fh，心率均值 %.1fbpm，步数 %d": {"en": "Sleep %.1fh, avg heart rate %.1fbpm, steps %d", "zh-Hant": "睡眠 %.1fh，心率均值 %.1fbpm，步數 %d"},
    "语速：%d%%": {"en": "Rate: %d%%", "zh-Hant": "語速：%d%%"},
    "表格，%d 列 %d 行": {"en": "Table, %d columns by %d rows", "zh-Hant": "表格，%d 列 %d 行"},
    "返回：%@": {"en": "returned: %@", "zh-Hant": "返回：%@"},
    "未配置": {"en": "Not Configured", "zh-Hant": "未配置"},
    "无": {"en": "None", "zh-Hant": "無"},
    "片段 %d": {"en": "Fragment %d", "zh-Hant": "片段 %d"},
    "权重 %.1f": {"en": "Weight %.1f", "zh-Hant": "權重 %.1f"},
    "偏好工具：%@": {"en": "Preferred tools: %@", "zh-Hant": "偏好工具：%@"},
    "语气：%@": {"en": "Tone: %@", "zh-Hant": "語氣：%@"},
    "自定义事实：%@": {"en": "Custom fact: %@", "zh-Hant": "自訂事實：%@"},
    "用户最近 24h：%@": {"en": "User's last 24h: %@", "zh-Hant": "使用者最近 24h：%@"},
    "音调：%.1f": {"en": "Pitch: %.1f", "zh-Hant": "音調：%.1f"},
    "音量：%d%%": {"en": "Volume: %d%%", "zh-Hant": "音量：%d%%"},
    "%@，最后消息：%@": {"en": "%@, last message: %@", "zh-Hant": "%@，最後訊息：%@"},
}

def main():
    path = Path('AIBuilder/Resources/Localizable.xcstrings')
    data = json.loads(path.read_text(encoding='utf-8'))
    strings = data['strings']
    added = 0
    for key, trans in ADDITIONAL.items():
        if key in strings:
            continue
        entry = {'extractionState': 'manual', 'localizations': {}}
        for lang in ['zh-Hans', 'zh-Hant', 'en']:
            v = trans.get(lang, '') if lang != 'zh-Hans' else key
            if not v:
                v = trans.get('en', key)
            entry['localizations'][lang] = {'stringUnit': {'state': 'translated', 'value': v}}
        strings[key] = entry
        added += 1
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Added {added} entries')

if __name__ == '__main__':
    main()
