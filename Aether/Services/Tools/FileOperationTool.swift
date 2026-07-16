/// 文件操作工具（macOS only）
///
/// 通过 FileManager 管理文件和目录，支持列出目录内容、搜索文件、复制、移动、重命名、
/// 删除（移到废纸篓）以及获取文件信息。
/// 调用方式：execute(arguments: ["action": "...", "path": "...", ...])，action 为必填参数。
/// 主要 action：list/search/copy/move/rename/delete/info。
import Foundation
import AppKit
import AetherFoundation

/// macOS 文件操作工具
final class FileOperationTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `manage_file`
    /// - parameters: `action`（必填，String）— 操作类型；`path`/`src`/`dst`/`name` 按需传入
    var definition: ToolDefinition {
        ToolDefinition(
            name: "manage_file",
            description: "管理文件：列出目录/搜索文件/复制/移动/重命名/删除/获取文件信息",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作：list/search/copy/move/rename/delete/info"],
                    "path": ["type": "string", "description": "文件或目录路径"],
                    "src": ["type": "string", "description": "源路径（copy/move）"],
                    "dst": ["type": "string", "description": "目标路径（copy/move）"],
                    "name": ["type": "string", "description": "搜索文件名模式或新文件名"]
                ],
                "required": ["action"]
            ]
        )
    }

    private let fm = FileManager.default

    /// 敏感目录黑名单：禁止访问这些目录下的任何文件，防止泄露密钥、凭证等。
    private let sensitivePathPrefixes: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/.config",
            "\(home)/.aws",
            "\(home)/.docker",
            "\(home)/Library/Keychains",
            "\(home)/Library/Cookies",
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Firefox",
            "\(home)/Library/Application Support/1Password"
        ]
    }()

    /// 校验路径是否安全：不在敏感目录黑名单内。
    /// 对路径做标准化（解析 `..`、符号链接、冗余分隔符）后检查前缀。
    /// 大小写不敏感比较，防止在大小写不敏感文件系统（APFS 默认）上绕过。
    /// - Parameter path: 用户提供的原始路径
    /// - Returns: 通过校验的标准化路径，或 nil 表示路径被拒绝
    private func validatePath(_ path: String) -> String? {
        // 标准化路径：解析 .. 和 . 等
        let standardized = (path as NSString).standardizingPath
        // 大小写不敏感比较，防止 /Users/Alice/.ssh 绕过 /Users/alice/.ssh
        let lowercased = standardized.lowercased()
        for prefix in sensitivePathPrefixes {
            let prefixLower = prefix.lowercased()
            if lowercased == prefixLower || lowercased.hasPrefix(prefixLower + "/") {
                return nil
            }
        }
        return standardized
    }

    /// 执行文件操作
    ///
    /// - Parameter arguments: 含 `action` 及其所需路径参数的字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "list": return listDir(arguments)
        case "search": return searchFiles(arguments)
        case "copy": return copyFile(arguments)
        case "move": return moveFile(arguments)
        case "rename": return renameFile(arguments)
        case "delete": return deleteFile(arguments)
        case "info": return fileInfo(arguments)
        default: return "错误：不支持的操作，支持 list/search/copy/move/rename/delete/info"
        }
    }

    /// 列出指定目录下的所有条目名称
    private func listDir(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：请提供 path 参数"
        }
        guard let safePath = validatePath(path) else {
            return "错误：拒绝访问敏感路径"
        }
        guard let items = try? fm.contentsOfDirectory(atPath: safePath) else {
            return "错误：无法读取目录：\(path)"
        }
        if items.isEmpty { return "目录为空" }
        return items.joined(separator: "\n")
    }

    /// 递归搜索目录下匹配通配符模式的文件
    private func searchFiles(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String,
              let namePattern = arguments["name"] as? String else {
            return "错误：请提供 path 和 name 参数"
        }
        guard let safePath = validatePath(path) else {
            return "错误：拒绝访问敏感路径"
        }
        let url = URL(fileURLWithPath: safePath)
        var results: [String] = []
        // 用 FileManager enumerator 递归遍历目录树
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent
            if fileName.matchesGlobPattern(namePattern) {
                results.append(fileURL.path)
            }
        }
        return results.isEmpty ? "未找到匹配文件" : results.joined(separator: "\n")
    }

    /// 复制文件或目录到目标路径
    private func copyFile(_ arguments: [String: Any]) -> String {
        guard let src = arguments["src"] as? String, let dst = arguments["dst"] as? String else {
            return "错误：请提供 src 和 dst 参数"
        }
        guard let safeSrc = validatePath(src) else {
            return "错误：拒绝访问敏感路径（src）"
        }
        guard let safeDst = validatePath(dst) else {
            return "错误：拒绝访问敏感路径（dst）"
        }
        do {
            try fm.copyItem(atPath: safeSrc, toPath: safeDst)
            return "已复制"
        } catch {
            return "错误：复制失败：\(error.localizedDescription)"
        }
    }

    /// 移动文件或目录到目标路径
    private func moveFile(_ arguments: [String: Any]) -> String {
        guard let src = arguments["src"] as? String, let dst = arguments["dst"] as? String else {
            return "错误：请提供 src 和 dst 参数"
        }
        guard let safeSrc = validatePath(src) else {
            return "错误：拒绝访问敏感路径（src）"
        }
        guard let safeDst = validatePath(dst) else {
            return "错误：拒绝访问敏感路径（dst）"
        }
        do {
            try fm.moveItem(atPath: safeSrc, toPath: safeDst)
            return "已移动"
        } catch {
            return "错误：移动失败：\(error.localizedDescription)"
        }
    }

    /// 重命名文件：保留所在目录，仅替换文件名部分
    private func renameFile(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String, let newName = arguments["name"] as? String else {
            return "错误：请提供 path 和 name 参数"
        }
        guard let safePath = validatePath(path) else {
            return "错误：拒绝访问敏感路径"
        }
        let srcURL = URL(fileURLWithPath: safePath)
        // 在原路径所在目录下拼接新文件名
        let dstURL = srcURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try fm.moveItem(at: srcURL, to: dstURL)
            return "已重命名"
        } catch {
            return "错误：重命名失败：\(error.localizedDescription)"
        }
    }

    /// 删除文件：移到废纸篓而非永久删除，便于恢复
    private func deleteFile(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：请提供 path 参数"
        }
        guard let safePath = validatePath(path) else {
            return "错误：拒绝访问敏感路径"
        }
        let url = URL(fileURLWithPath: safePath)
        do {
            // 移到废纸篓
            var resultURL: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resultURL)
            return "已删除（移到废纸篓）"
        } catch {
            return "错误：删除失败：\(error.localizedDescription)"
        }
    }

    /// 获取文件信息：大小、修改时间、类型（文件/目录）
    private func fileInfo(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：请提供 path 参数"
        }
        guard let safePath = validatePath(path) else {
            return "错误：拒绝访问敏感路径"
        }
        guard let attrs = try? fm.attributesOfItem(atPath: safePath) else {
            return "错误：无法获取文件信息"
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modDate = attrs[.modificationDate] as? Date ?? Date()
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return """
        路径：\(path)
        大小：\(size) 字节
        修改时间：\(dateFormatter.string(from: modDate))
        类型：\(isDir ? "目录" : "文件")
        """
    }
}

/// 文件名通配符匹配的私有扩展
private extension String {
    /// 简单通配符匹配：`*` 匹配任意字符，`*.swift` 匹配扩展名
    func matchesGlobPattern(_ pattern: String) -> Bool {
        // 简单通配符匹配：* 匹配任意字符
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") {
            // *.swift 等
            let ext = String(pattern.dropFirst().dropLast())
            return self.hasSuffix(ext)
        }
        return self == pattern
    }
}
