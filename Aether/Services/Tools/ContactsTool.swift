/// 通讯录联系人搜索工具（跨平台：iOS + macOS）
///
/// 通过 Contacts 框架（CNContactStore）按姓名或电话号码搜索通讯录联系人。
/// 调用方式：execute(arguments: ["query": "..."])，query 为必填参数。
/// 搜索流程：请求通讯录权限 -> 按姓名匹配 + 按电话号码匹配 -> 合并去重 -> 格式化返回。
import Foundation
import Contacts
import AetherFoundation

/// 通讯录搜索工具，通过 Contacts 框架按姓名或电话号码搜索联系人
final class ContactsTool: ToolProtocol, @unchecked Sendable {
    private let store = CNContactStore()

    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "search_contacts",
            description: "按姓名或电话号码搜索通讯录联系人",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "搜索关键词（姓名或号码）"]
                ],
                "required": ["query"]
            ]
        )
    }

    /// 执行联系人搜索。流程：1) 必须提供 query 参数；2) 请求通讯录权限；
    /// 3) 按姓名匹配 + 按电话号码匹配；4) 合并去重；5) 返回格式化结果字符串。
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return "错误：请提供搜索关键词"
        }
        let granted = try await requestContactAccess(within: Self.authorizationDeadline)
        guard granted else {
            return "通讯录权限未授权，请在设置中开启通讯录权限"
        }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey
        ] as [CNKeyDescriptor]
        // Search by name
        var results: [CNContact] = []
        let namePredicate = CNContact.predicateForContacts(matchingName: query)
        let nameMatches = try store.unifiedContacts(matching: namePredicate, keysToFetch: keys)
        results.append(contentsOf: nameMatches)
        // 按电话号码搜索：用 CNContactFetchRequest 逐条遍历，避免一次性拉取全部联系人
        let fetchRequest = CNContactFetchRequest(keysToFetch: keys)
        var allContacts: [CNContact] = []
        try store.enumerateContacts(with: fetchRequest) { contact, _ in
            allContacts.append(contact)
        }
        let phoneMatches = allContacts.filter { contact in
            contact.phoneNumbers.contains { $0.value.stringValue.contains(query) }
        }
        // Merge and dedupe by identifier
        var seen = Set<String>()
        let merged = (results + phoneMatches).filter { seen.insert($0.identifier).inserted }
        if merged.isEmpty {
            return "未找到匹配的联系人"
        }
        let lines = merged.map { contact -> String in
            // S3358: 用 if-else 替代嵌套三元，提升可读性
            let combined = "\(contact.givenName)\(contact.familyName)"
            let name: String
            if !combined.isEmpty {
                name = combined
            } else if !contact.familyName.isEmpty {
                name = contact.familyName
            } else {
                name = contact.givenName
            }
            let phones = contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: "、")
            return "姓名：\(name)，电话：\(phones.isEmpty ? "无" : phones)"
        }
        return lines.joined(separator: "\n")
    }

    /// 通讯录授权回调窗口。真机上用户点掉系统弹窗是亚秒到数十秒，
    /// 取 5 秒与端侧引擎的授权窗口同量级，越界即按未授权返回，不再挂住调用方。
    private static let authorizationDeadline: TimeInterval = 5

    /// 申请通讯录权限，回调在 `seconds` 内未触发时按未授权（false）收尾。
    /// `CNContactStore.requestAccess` 的回调在无法呈现/应答系统弹窗的运行环境
    /// （模拟器、无头 CI）里可能永不触发，无界 await 会把工具调用整条链挂死。
    private func requestContactAccess(within seconds: TimeInterval) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let once = ResumeOnceContinuation(continuation)
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    once.resume(throwing: error)
                } else {
                    once.resume(returning: granted)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                once.resume(returning: false)
            }
        }
    }
}
