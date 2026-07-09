import Foundation
import SwiftUI
#if os(iOS)
import MessageUI
import UIKit
#endif

/// Day 20: 投诉反馈服务，调用系统邮件 composer 预填反馈邮件。
final class FeedbackService {
    /// 单例
    static let shared = FeedbackService()
    private init() {}

    /// 收件邮箱
    private let recipient = "feedback@aether.app"

    /// 邮件主题
    private var subject: String { NSLocalizedString("以太用户反馈", comment: "") }

    /// 收集设备信息用于反馈邮件正文
    /// - Returns: 包含设备型号、系统版本、App 版本与构建号的字符串
    func collectDeviceInfo() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        #if os(iOS)
        let device = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let systemName = "iOS"
        #else
        let device = "Mac"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        let systemName = "macOS"
        #endif
        return """
        设备：\(device)
        系统：\(systemName) \(systemVersion)
        App 版本：\(version) (\(build))
        """
    }

    /// 构造邮件内容字典（收件人 / 主题 / 正文）
    /// - Returns: 包含 to / subject / body 三个键的字典
    func mailContent() -> [String: String] {
        [
            "to": recipient,
            "subject": subject,
            "body": "\n\n---\n\(collectDeviceInfo())"
        ]
    }

    /// 构造 mailto: URL，用于在没有 MFMailComposeViewController 的设备上打开邮件 App。
    /// - Returns: mailto: URL，nil 表示构造失败
    func mailtoURL() -> URL? {
        let body = mailContent()["body"] ?? ""
        let subject = mailContent()["subject"] ?? ""
        // URL 编码 subject 与 body
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let urlString = "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"
        return URL(string: urlString)
    }
}

// MARK: - Day 20: MailComposerView
#if os(iOS)
/// 桥接 MFMailComposeViewController 到 SwiftUI 的 UIViewControllerRepresentable。
/// 注意：MFMailComposeViewController 仅在真实设备可用，模拟器无法呈现邮件 composer。
struct MailComposerView: UIViewControllerRepresentable {
    /// 完成回调（ dismissed / sent / failed / cancelled ）
    var onFinish: ((MFMailComposeResult) -> Void)?

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        let content = FeedbackService.shared.mailContent()
        if let to = content["to"] {
            composer.setToRecipients([to])
        }
        composer.setSubject(content["subject"] ?? "")
        composer.setMessageBody(content["body"] ?? "", isHTML: false)
        composer.mailComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // 无需更新
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// MailCompose delegate
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: ((MFMailComposeResult) -> Void)?

        init(onFinish: ((MFMailComposeResult) -> Void)?) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
            onFinish?(result)
        }
    }
}
#endif
