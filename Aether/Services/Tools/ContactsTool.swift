/// 通讯录联系人搜索工具（跨平台：iOS + macOS）
///
/// 通过 Contacts 框架（CNContactStore）按姓名或电话号码搜索通讯录联系人。
/// 调用方式：execute(arguments: ["query": "..."])，query 为必填参数。
/// 搜索流程：请求通讯录权限 -> 按姓名匹配 + 按电话号码匹配 -> 合并去重 -> 格式化返回。
import Foundation
import Contacts

/// 通讯录搜索工具，通过 Contacts 框架按姓名或电话号码搜索联系人
final class ContactsTool: ToolProtocol {
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
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
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
        // Search by phone number - fetch all contacts with phone numbers and filter
        // (CNContact doesn't have a direct phone predicate; fetch all and filter)
        let allContactsPredicate = CNContact.predicateForContactsInContainer(withIdentifier: store.defaultContainerIdentifier())
        let allContacts = try store.unifiedContacts(matching: allContactsPredicate, keysToFetch: keys)
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
            let name = "\(contact.givenName)\(contact.familyName)".isEmpty ?
                (contact.familyName.isEmpty ? contact.givenName : contact.familyName) :
                "\(contact.givenName)\(contact.familyName)"
            let phones = contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: "、")
            return "姓名：\(name)，电话：\(phones.isEmpty ? "无" : phones)"
        }
        return lines.joined(separator: "\n")
    }
}
