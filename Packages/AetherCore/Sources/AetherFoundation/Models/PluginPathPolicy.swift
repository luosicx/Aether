import Foundation

/// 插件路径安全策略：校验插件 ID 与入口点路径，防止目录穿越、绝对路径与符号链接逃逸。
///
/// 插件 ID 会直接作为 `AppSupport/Plugins/{id}` 目录名，入口点会拼接到该目录下，
/// 两者都来自远程 manifest，必须视为不可信输入。
public enum PluginPathPolicy {
    /// 插件 ID 允许的字符规则：字母或数字开头，后续仅允许字母、数字、`.`、`_`、`-`，最长 128。
    public static func isValidPluginID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128, id != ".", id != "..",
              let first = id.first, first.isASCII, first.isLetter || first.isNumber else {
            return false
        }
        return id.allSatisfy { char in
            char.isASCII && (char.isLetter || char.isNumber || char == "." || char == "_" || char == "-")
        }
    }

    /// 将相对入口点解析到插件根目录内，返回可安全读写的文件 URL。
    ///
    /// 拒绝：绝对路径、`~` 开头、URL scheme、反斜杠、NUL、`..` 组件，
    /// 以及标准化或解析符号链接后落在根目录之外的路径。
    /// - Parameters:
    ///   - root: 插件根目录（`AppSupport/Plugins/{id}`）
    ///   - entryPoint: manifest 声明的相对入口点
    /// - Returns: 根目录内的入口文件 URL（文件不存在时返回其预期路径）
    public static func entryPointURL(root: URL, entryPoint: String) throws -> URL {
        guard !entryPoint.isEmpty else {
            throw PluginPathError.invalidEntryPoint("入口点为空")
        }
        guard !entryPoint.contains("\0") else {
            throw PluginPathError.invalidEntryPoint("入口点包含非法字符")
        }
        guard !entryPoint.contains("\\") else {
            throw PluginPathError.invalidEntryPoint("入口点不能包含反斜杠：\(entryPoint)")
        }
        guard !entryPoint.hasPrefix("/"), !entryPoint.hasPrefix("~"),
              !(entryPoint as NSString).isAbsolutePath else {
            throw PluginPathError.invalidEntryPoint("入口点必须是相对路径：\(entryPoint)")
        }
        if let scheme = URLComponents(string: entryPoint)?.scheme, !scheme.isEmpty {
            throw PluginPathError.invalidEntryPoint("入口点不能是 URL：\(entryPoint)")
        }
        let components = entryPoint.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else {
            throw PluginPathError.entryPointEscapesRoot(entryPoint)
        }

        let fileManager = FileManager.default
        let rootStandardized = root.standardizedFileURL
        let resolvedRoot = rootStandardized.resolvingSymlinksInPath().standardizedFileURL
        let candidate = rootStandardized.appendingPathComponent(entryPoint).standardizedFileURL
        guard isContained(candidate, in: rootStandardized) else {
            throw PluginPathError.entryPointEscapesRoot(entryPoint)
        }

        let resolvedParent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolvedCandidate = resolvedParent.appendingPathComponent(candidate.lastPathComponent)
        guard isContained(resolvedCandidate, in: resolvedRoot) else {
            throw PluginPathError.entryPointEscapesRoot(entryPoint)
        }

        // 目标已存在时继续解析其自身符号链接，避免通过链接读写根目录外的文件
        if fileManager.fileExists(atPath: candidate.path) {
            let fullyResolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isContained(fullyResolved, in: resolvedRoot) else {
                throw PluginPathError.entryPointEscapesRoot(entryPoint)
            }
            return fullyResolved
        }
        return resolvedCandidate
    }

    /// 目标路径是否位于指定根目录内（含根目录本身）。
    private static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.path
        if url.path == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.path.hasPrefix(prefix)
    }
}

/// 插件路径校验错误。
public enum PluginPathError: Error, LocalizedError, Equatable {
    /// 插件 ID 不合法
    case invalidPluginID(String)
    /// 入口点格式不合法
    case invalidEntryPoint(String)
    /// 入口点解析后逃逸出插件目录
    case entryPointEscapesRoot(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPluginID(let id):
            return "插件 ID 不合法：\(id)"
        case .invalidEntryPoint(let reason):
            return "插件入口点不合法：\(reason)"
        case .entryPointEscapesRoot(let entryPoint):
            return "插件入口点越界，拒绝访问插件目录外的文件：\(entryPoint)"
        }
    }
}
