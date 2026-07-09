import SwiftUI

/// Day 20: 隐私政策页面，展示 App 数据收集与使用说明。
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                Text("以太隐私政策")
                    .font(.title2)
                    .bold()
                Text("更新日期：2026年7月")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 数据收集范围
                policySection(
                    title: "一、数据收集范围",
                    content: """
                    1. 对话内容：包括用户输入的文本与 AI 生成的回复，用于上下文连续对话与缓存命中加速。
                    2. 健康数据：包括心率、睡眠时长、步数等，仅在用户明确授权 HealthKit 后读取，用于生成个性化健康洞察。
                    3. 使用统计：包括性能埋点（如请求延迟、token 数）与崩溃日志，用于持续优化 App 体验。
                    """
                )

                // 第三方 SDK
                policySection(
                    title: "二、第三方 SDK",
                    content: """
                    1. DeepSeek API：用于对话生成，用户输入文本会上传至 DeepSeek 服务端处理。
                    2. 阿里云百炼 Qwen API：用于对话生成，用户输入文本会上传至阿里云服务端处理。
                    3. Bugly：用于崩溃监控，仅上报崩溃堆栈与匿名设备信息，不包含用户对话内容与个人身份信息。
                    """
                )

                // 用户权利
                policySection(
                    title: "三、用户权利",
                    content: """
                    1. 查看已收集数据：可在「设置 - 调试面板」查看最近的请求与响应。
                    2. 删除对话记录：可在会话列表中删除任意对话，相关数据会从本地数据库移除。
                    3. 撤回 HealthKit 授权：可在「系统设置 - 隐私 - 健康」中撤回对以太的授权。
                    4. 关闭遥测上报：可在「设置 - 调试面板 - 立即上报」控制上报行为，本地缓冲不强制上报。
                    """
                )

                // 联系方式
                policySection(
                    title: "四、联系方式",
                    content: "如有任何隐私相关问题，请通过邮件联系：feedback@aether.app"
                )
            }
            .padding()
        }
        .navigationTitle("隐私政策")
        .accessibilityIdentifier("PrivacyPolicyView")
    }

    /// 单个政策段落
    /// - Parameters:
    ///   - title: 段落标题
    ///   - content: 段落正文
    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
        }
    }
}
