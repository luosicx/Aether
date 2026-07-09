#!/usr/bin/env python3
import json
from pathlib import Path

xcstrings_path = Path('AIBuilder/Resources/Localizable.xcstrings')
data = json.loads(xcstrings_path.read_text(encoding='utf-8'))
strings = data.setdefault('strings', {})

ADDITIONAL = {
    # LLMError
    "网络连接失败，请检查网络": {"en": "Network connection failed; please check your network", "zh-Hant": "網路連線失敗，請檢查網路"},
    "API Key 无效，请检查设置": {"en": "API Key invalid; please check Settings", "zh-Hant": "API Key 無效，請檢查設定"},
    "请求格式错误，请重试": {"en": "Request format error; please retry", "zh-Hant": "請求格式錯誤，請重試"},
    "账户余额不足": {"en": "Insufficient account balance", "zh-Hant": "帳戶餘額不足"},
    "请求过于频繁，请稍后再试": {"en": "Too many requests; please try again later", "zh-Hant": "請求過於頻繁，請稍後再試"},
    "服务暂时不可用，请稍后再试": {"en": "Service temporarily unavailable; please try again later", "zh-Hant": "服務暫時不可用，請稍後再試"},
    "服务异常（%d），请稍后再试": {"en": "Service error (%d); please try again later", "zh-Hant": "服務異常（%d），請稍後再試"},
    "请求超时，请重试": {"en": "Request timed out; please retry", "zh-Hant": "請求超時，請重試"},
    "未知错误，请重试": {"en": "Unknown error; please retry", "zh-Hant": "未知錯誤，請重試"},
    # AppIntents
    "向 AI Builder 提问": {"en": "Ask AI Builder", "zh-Hant": "向 AI Builder 提問"},
    "向 AI Builder 发送问题并获取回复": {"en": "Send a question to AI Builder and get a reply", "zh-Hant": "向 AI Builder 傳送問題並取得回覆"},
    "切换会话": {"en": "Switch Conversation", "zh-Hant": "切換對話"},
    "在 AI Builder 中创建新对话": {"en": "Create a new conversation in AI Builder", "zh-Hant": "在 AI Builder 中建立新對話"},
    "按关键词切换到最近匹配的会话": {"en": "Switch to the most recent matching conversation by keyword", "zh-Hant": "按關鍵詞切換到最近匹配的對話"},
    "关键词": {"en": "Keyword", "zh-Hant": "關鍵詞"},
    "问题": {"en": "Question", "zh-Hant": "問題"},
    "未找到匹配会话": {"en": "No matching conversation found", "zh-Hant": "未找到匹配對話"},
    "AI Builder 暂时无法回复：%@": {"en": "AI Builder is temporarily unable to reply: %@", "zh-Hant": "AI Builder 暫時無法回覆：%@"},
    "AI Builder 未返回内容，请重试。": {"en": "AI Builder returned no content; please retry.", "zh-Hant": "AI Builder 未返回內容，請重試。"},
    # Services
    "BFF Token 无效": {"en": "BFF Token invalid", "zh-Hant": "BFF Token 無效"},
    "BFF 服务异常": {"en": "BFF service error", "zh-Hant": "BFF 服務異常"},
    "无效的 BFF embedding 请求": {"en": "Invalid BFF embedding request", "zh-Hant": "無效的 BFF embedding 請求"},
    "无效的 embedding 请求": {"en": "Invalid embedding request", "zh-Hant": "無效的 embedding 請求"},
    "端侧模型不支持工具调用，已自动切换到云端": {"en": "On-device model does not support tool calls; automatically switched to cloud", "zh-Hant": "端側模型不支援工具呼叫，已自動切換到雲端"},
    "mlx-swift 未集成，端侧推理不可用": {"en": "mlx-swift is not integrated; on-device inference unavailable", "zh-Hant": "mlx-swift 未整合，端側推理不可用"},
    "[端侧模型未加载，请先下载并加载模型]": {"en": "[On-device model not loaded; please download and load the model first]", "zh-Hant": "[端側模型未載入，請先下載並載入模型]"},
    "[生成失败：%@]": {"en": "[Generation failed: %@]", "zh-Hant": "[生成失敗：%@]"},
    "[端侧推理不可用：mlx-swift 未集成]": {"en": "[On-device inference unavailable: mlx-swift not integrated]", "zh-Hant": "[端側推理不可用：mlx-swift 未整合]"},
    "删除模型文件失败：%@": {"en": "Failed to delete model file: %@", "zh-Hant": "刪除模型檔案失敗：%@"},
    "下载失败：%@": {"en": "Download failed: %@", "zh-Hant": "下載失敗：%@"},
    "钥匙串错误: %@": {"en": "Keychain error: %@", "zh-Hant": "鑰匙串錯誤：%@"},
    "API Key 未设置": {"en": "API Key not set", "zh-Hant": "API Key 未設定"},
    "网络错误: %@": {"en": "Network error: %@", "zh-Hant": "網路錯誤：%@"},
    "保存失败: %@": {"en": "Save failed: %@", "zh-Hant": "儲存失敗：%@"},
    "AI Builder 用户反馈": {"en": "AI Builder User Feedback", "zh-Hant": "AI Builder 用戶反饋"},
    "(未知音色)": {"en": "(Unknown Voice)", "zh-Hant": "（未知音色）"},
    "语音识别器不可用": {"en": "Speech recognizer unavailable", "zh-Hant": "語音識別器不可用"},
    "未找到中文语音，使用默认语音": {"en": "Chinese voice not found; using default voice", "zh-Hant": "未找到中文語音，使用預設語音"},
    "当前设备不支持 HealthKit": {"en": "This device does not support HealthKit", "zh-Hant": "目前裝置不支援 HealthKit"},
    "未获得 HealthKit 授权": {"en": "HealthKit authorization not obtained", "zh-Hant": "未獲得 HealthKit 授權"},
    "健康洞察已生成": {"en": "Health insight generated", "zh-Hant": "健康洞察已生成"},
    "⚠️ 以上内容由 AI 生成，仅供参考，非医疗建议。如有健康问题请咨询医生。": {
        "en": "⚠️ The above content is AI-generated for reference only and is not medical advice. Please consult a doctor for health concerns.",
        "zh-Hant": "⚠️ 以上內容由 AI 生成，僅供參考，非醫療建議。如有健康問題請諮詢醫生。"
    },
    "以下是最近 %d 天的健康数据：": {"en": "Health data for the last %d days:", "zh-Hant": "以下是最近 %d 天的健康資料："},
    "- 心率：无数据": {"en": "- Heart rate: no data", "zh-Hant": "- 心率：無資料"},
    "- 心率：平均 %.1f bpm，最高 %.1f bpm，最低 %.1f bpm": {"en": "- Heart rate: avg %.1f bpm, max %.1f bpm, min %.1f bpm", "zh-Hant": "- 心率：平均 %.1f bpm，最高 %.1f bpm，最低 %.1f bpm"},
    "- 睡眠：无数据": {"en": "- Sleep: no data", "zh-Hant": "- 睡眠：無資料"},
    "- 睡眠：平均 %.1f 小时/天": {"en": "- Sleep: avg %.1f hours/day", "zh-Hant": "- 睡眠：平均 %.1f 小時/天"},
    "- 步数：无数据": {"en": "- Steps: no data", "zh-Hant": "- 步數：無資料"},
    "- 步数：平均 %.0f 步/天": {"en": "- Steps: avg %.0f steps/day", "zh-Hant": "- 步數：平均 %.0f 步/天"},
    "请基于以上健康数据给出 3 条具体建议，关注改善睡眠质量、合理运动强度与日常活动量。": {
        "en": "Please provide 3 specific suggestions based on the above health data, focusing on improving sleep quality, reasonable exercise intensity, and daily activity.",
        "zh-Hant": "請基於以上健康資料給出 3 條具體建議，關注改善睡眠品質、合理運動強度與日常活動量。"
    },
    # Views
    "关闭": {"en": "Close", "zh-Hant": "關閉"},
    "加载中": {"en": "Loading", "zh-Hant": "載入中"},
    "AI 正在输入": {"en": "AI is typing", "zh-Hant": "AI 正在輸入"},
    "错误提示": {"en": "Error alert", "zh-Hant": "錯誤提示"},
    "点击关闭错误提示": {"en": "Tap to dismiss error alert", "zh-Hant": "點擊關閉錯誤提示"},
    "用户发送的图片，点击查看全屏": {"en": "Image sent by user; tap to view full screen", "zh-Hant": "用戶傳送的圖片，點擊查看全螢幕"},
    "关闭全屏图片": {"en": "Close full-screen image", "zh-Hant": "關閉全螢幕圖片"},
    "%d 级标题": {"en": "Heading level %d", "zh-Hant": "第 %d 級標題"},
    "%@ 代码块": {"en": "%@ code block", "zh-Hant": "%@ 程式碼區塊"},
    "代码块": {"en": "Code block", "zh-Hant": "程式碼區塊"},
    "引用 %d，来源 %@": {"en": "Citation %d, source %@", "zh-Hant": "引用 %d，來源 %@"},
    "查看引用的文档片段": {"en": "View cited document snippet", "zh-Hant": "查看引用的文件片段"},
    "工具步骤：%@": {"en": "Tool step: %@", "zh-Hant": "工具步驟：%@"},
    "表格，%d 列 %d 行": {"en": "Table, %d columns by %d rows", "zh-Hant": "表格，%d 列 %d 行"},
    "%@，最后消息：%@": {"en": "%@, last message: %@", "zh-Hant": "%@，最後訊息：%@"},
    "音调：%.1f": {"en": "Pitch: %.1f", "zh-Hant": "音調：%.1f"},
    "确定删除 %@ 的 API Key？删除后无法恢复。": {"en": "Delete the API Key for %@? This action cannot be undone.", "zh-Hant": "確定刪除 %@ 的 API Key？刪除後無法恢復。"},
    "参数：%@": {"en": "Parameters: %@", "zh-Hant": "參數：%@"},
    "返回：%@": {"en": "Result: %@", "zh-Hant": "返回：%@"},
    # ChatViewModel
    "知识库检索失败: %@": {"en": "Knowledge base retrieval failed: %@", "zh-Hant": "知識庫檢索失敗：%@"},
    "工具调用循环超过 %d 轮，已中止": {"en": "Tool call loop exceeded %d rounds and was stopped", "zh-Hant": "工具呼叫循環超過 %d 輪，已中止"},
    "%@ 已完成：%@": {"en": "%@ completed: %@", "zh-Hant": "%@ 已完成：%@"},
    "工具执行失败: %@": {"en": "Tool execution failed: %@", "zh-Hant": "工具執行失敗：%@"},
}

added = 0
for key, trans in ADDITIONAL.items():
    if key in strings:
        continue
    entry = {'extractionState': 'manual', 'localizations': {}}
    entry['localizations']['zh-Hans'] = {'stringUnit': {'state': 'translated', 'value': key}}
    for lang in ['en', 'zh-Hant']:
        v = trans.get(lang, '')
        if v:
            entry['localizations'][lang] = {'stringUnit': {'state': 'translated', 'value': v}}
    strings[key] = entry
    added += 1

xcstrings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Added {added} keys, total: {len(strings)}')
