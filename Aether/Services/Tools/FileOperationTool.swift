/// 文件操作工具（macOS only）
///
/// 通过 FileManager 管理文件和目录，支持列出目录内容、搜索文件、复制、移动、重命名、
/// 删除（移到废纸篓）以及获取文件信息。
/// 调用方式：execute(arguments: ["action": "...", "path": "...", ...])，action 为必填参数。
/// 主要 action：list/search/copy/move/rename/delete/info。
#if os(macOS)
import Foundation
import AppKit

/// 文件操作沙盒：限制工具只能访问允许的根目录
struct FileOperationSandbox {
    let allowedRootDirectories: [URL]

    /// 创建沙盒
    /// - Parameter allowedRootDirectories: 允许的根目录；传 nil 时使用默认的文档目录和临时目录
    init(allowedRootDirectories: [URL]? = nil) {
        if let allowedRootDirectories = allowedRootDirectories {
            self.allowedRootDirectories = allowedRootDirectories
        } else {
            var roots: [URL] = []
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                roots.append(documents)
            }
            roots.append(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            self.allowedRootDirectories = roots
        }
    }

    /// 检查路径是否在允许范围内
    /// - Parameter path: 待检查路径
    /// - Returns: 是否允许访问
    func isPathAllowed(_ path: String) -> Bool {
        // 拒绝包含 .. 段的路径，防止路径遍历
        let components = path.split(separator: "/")
        if components.contains("..") {
            return false
        }

        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath()
        let resolvedPath = resolved.path

        return allowedRootDirectories.contains { root in
            let resolvedRoot = root.resolvingSymlinksInPath()
            let rootPath = resolvedRoot.path
            return resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/")
        }
    }
}

/// macOS 文件操作工具
final class FileOperationTool: ToolProtocol {
    var riskLevel: ToolRiskLevel { .dangerous }

    /// 文件操作沙盒
    var sandbox: FileOperationSandbox = FileOperationSandbox()
    /// 删除/覆盖操作是否需要二次确认
    var requiresDestructiveConfirmation: Bool = true

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

    /// 验证单一路径是否在沙盒允许范围内
    private func validatePath(_ path: String) -> String? {
        guard sandbox.isPathAllowed(path) else {
            return "错误：路径超出允许范围: \(path)"
        }
        return nil
    }

    /// 列出指定目录下的所有条目名称
    private func listDir(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：请提供 path 参数"
        }
        if let error = validatePath(path) { return error }
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
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
        if let error = validatePath(path) { return error }
        let url = URL(fileURLWithPath: path)
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
        if let error = validatePath(src) { return error }
        if let error = validatePath(dst) { return error }
        if requiresDestructiveConfirmation && fm.fileExists(atPath: dst) {
            return "错误：删除/覆盖操作需要二次确认（待实现 UI）"
        }
        do {
            try fm.copyItem(atPath: src, toPath: dst)
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
        if let error = validatePath(src) { return error }
        if let error = validatePath(dst) { return error }
        if requiresDestructiveConfirmation {
            return "错误：删除/覆盖操作需要二次确认（待实现 UI）"
        }
        do {
            try fm.moveItem(atPath: src, toPath: dst)
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
        if let error = validatePath(path) { return error }
        let srcURL = URL(fileURLWithPath: path)
        // 在原路径所在目录下拼接新文件名
        let dstURL = srcURL.deletingLastPathComponent().appendingPathComponent(newName)
        if let error = validatePath(dstURL.path) { return error }
        if requiresDestructiveConfirmation && fm.fileExists(atPath: dstURL.path) {
            return "错误：删除/覆盖操作需要二次确认（待实现 UI）"
        }
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
        if let error = validatePath(path) { return error }
        if requiresDestructiveConfirmation {
            return "错误：删除/覆盖操作需要二次确认（待实现 UI）"
        }
        let url = URL(fileURLWithPath: path)
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
        if let error = validatePath(path) { return error }
        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
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
#endif
