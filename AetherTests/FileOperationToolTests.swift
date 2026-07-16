#if os(macOS)
import XCTest
@testable import Aether

final class FileOperationToolTests: XCTestCase {
    private let tool = FileOperationTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "manage_file")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteListDir() async throws {
        let result = try await tool.execute(arguments: ["action": "list", "path": "/tmp"])
        XCTAssertFalse(result.isEmpty)
    }

    func testExecuteFileInfo() async throws {
        let result = try await tool.execute(arguments: ["action": "info", "path": "/tmp"])
        XCTAssertTrue(result.contains("路径") || result.contains("错误"), "实际：\(result)")
    }

    // MARK: - definition 详细验证

    /// definition 的 properties 应包含 action/path/src/dst/name
    func testDefinitionProperties() {
        let properties = tool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties, "properties 应为字典")
        XCTAssertNotNil(properties?["action"], "应包含 action 属性")
        XCTAssertNotNil(properties?["path"], "应包含 path 属性")
        XCTAssertNotNil(properties?["src"], "应包含 src 属性")
        XCTAssertNotNil(properties?["dst"], "应包含 dst 属性")
        XCTAssertNotNil(properties?["name"], "应包含 name 属性")
    }

    /// definition 的 type 应为 object，required 应包含 action
    func testDefinitionTypeAndRequired() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["action"])
    }

    // MARK: - list 错误处理

    /// list 缺少 path 参数应返回错误
    func testExecuteListMissingPath() async throws {
        let result = try await tool.execute(arguments: ["action": "list"])
        XCTAssertEqual(result, "错误：请提供 path 参数")
    }

    /// list 不存在的目录应返回错误
    func testExecuteListNonExistentPath() async throws {
        let result = try await tool.execute(arguments: ["action": "list", "path": "/nonexistent/path/12345"])
        XCTAssertTrue(result.contains("错误"), "不存在的目录应返回错误：\(result)")
    }

    // MARK: - search 错误处理

    /// search 缺少 path 和 name 参数应返回错误
    func testExecuteSearchMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "search"])
        XCTAssertEqual(result, "错误：请提供 path 和 name 参数")
    }

    /// search 只提供 path 缺少 name 应返回错误
    func testExecuteSearchMissingName() async throws {
        let result = try await tool.execute(arguments: ["action": "search", "path": "/tmp"])
        XCTAssertEqual(result, "错误：请提供 path 和 name 参数")
    }

    /// search 在 /tmp 下搜索应返回非空结果或未找到提示
    func testExecuteSearchWithValidPath() async throws {
        let result = try await tool.execute(arguments: ["action": "search", "path": "/tmp", "name": "*"])
        XCTAssertFalse(result.isEmpty, "搜索结果不应为空")
    }

    // MARK: - copy 错误处理

    /// copy 缺少 src 和 dst 参数应返回错误
    func testExecuteCopyMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "copy"])
        XCTAssertEqual(result, "错误：请提供 src 和 dst 参数")
    }

    /// copy 只提供 src 缺少 dst 应返回错误
    func testExecuteCopyMissingDst() async throws {
        let result = try await tool.execute(arguments: ["action": "copy", "src": "/tmp"])
        XCTAssertEqual(result, "错误：请提供 src 和 dst 参数")
    }

    /// copy 不存在的源文件应返回错误
    func testExecuteCopyNonExistentSrc() async throws {
        let result = try await tool.execute(arguments: ["action": "copy", "src": "/nonexistent/src", "dst": "/tmp/dst"])
        XCTAssertTrue(result.contains("错误"), "不存在的源文件应返回错误：\(result)")
    }

    /// copy 有效文件应返回"已复制"并实际复制
    func testExecuteCopyValidFile() async throws {
        let tempDir = NSTemporaryDirectory()
        let srcFile = (tempDir as NSString).appendingPathComponent("aether_test_src.txt")
        let dstFile = (tempDir as NSString).appendingPathComponent("aether_test_dst.txt")
        try "test content".write(toFile: srcFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: srcFile)
            try? FileManager.default.removeItem(atPath: dstFile)
        }
        let result = try await tool.execute(arguments: ["action": "copy", "src": srcFile, "dst": dstFile])
        XCTAssertEqual(result, "已复制")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstFile), "目标文件应存在")
    }

    // MARK: - move 错误处理

    /// move 缺少 src 和 dst 参数应返回错误
    func testExecuteMoveMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "move"])
        XCTAssertEqual(result, "错误：请提供 src 和 dst 参数")
    }

    /// move 不存在的源文件应返回错误
    func testExecuteMoveNonExistentSrc() async throws {
        let result = try await tool.execute(arguments: ["action": "move", "src": "/nonexistent/src", "dst": "/tmp/dst"])
        XCTAssertTrue(result.contains("错误"), "不存在的源文件应返回错误：\(result)")
    }

    /// move 有效文件应返回"已移动"并实际移动
    func testExecuteMoveValidFile() async throws {
        let tempDir = NSTemporaryDirectory()
        let srcFile = (tempDir as NSString).appendingPathComponent("aether_move_src.txt")
        let dstFile = (tempDir as NSString).appendingPathComponent("aether_move_dst.txt")
        try "move content".write(toFile: srcFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: srcFile)
            try? FileManager.default.removeItem(atPath: dstFile)
        }
        let result = try await tool.execute(arguments: ["action": "move", "src": srcFile, "dst": dstFile])
        XCTAssertEqual(result, "已移动")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstFile), "目标文件应存在")
        XCTAssertFalse(FileManager.default.fileExists(atPath: srcFile), "源文件应不存在")
    }

    // MARK: - rename 错误处理

    /// rename 缺少 path 和 name 参数应返回错误
    func testExecuteRenameMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "rename"])
        XCTAssertEqual(result, "错误：请提供 path 和 name 参数")
    }

    /// rename 只提供 path 缺少 name 应返回错误
    func testExecuteRenameMissingName() async throws {
        let result = try await tool.execute(arguments: ["action": "rename", "path": "/tmp"])
        XCTAssertEqual(result, "错误：请提供 path 和 name 参数")
    }

    /// rename 不存在的文件应返回错误
    func testExecuteRenameNonExistentFile() async throws {
        let result = try await tool.execute(arguments: ["action": "rename", "path": "/nonexistent/file.txt", "name": "newname.txt"])
        XCTAssertTrue(result.contains("错误"), "不存在的文件应返回错误：\(result)")
    }

    // MARK: - delete 错误处理

    /// delete 缺少 path 参数应返回错误
    func testExecuteDeleteMissingPath() async throws {
        let result = try await tool.execute(arguments: ["action": "delete"])
        XCTAssertEqual(result, "错误：请提供 path 参数")
    }

    /// delete 不存在的文件应返回错误
    func testExecuteDeleteNonExistentFile() async throws {
        let result = try await tool.execute(arguments: ["action": "delete", "path": "/nonexistent/file.txt"])
        XCTAssertTrue(result.contains("错误"), "不存在的文件应返回错误：\(result)")
    }

    // MARK: - info 错误处理

    /// info 缺少 path 参数应返回错误
    func testExecuteInfoMissingPath() async throws {
        let result = try await tool.execute(arguments: ["action": "info"])
        XCTAssertEqual(result, "错误：请提供 path 参数")
    }

    /// info 不存在的文件应返回错误
    func testExecuteInfoNonExistentFile() async throws {
        let result = try await tool.execute(arguments: ["action": "info", "path": "/nonexistent/file.txt"])
        XCTAssertEqual(result, "错误：无法获取文件信息")
    }

    // MARK: - 不支持的 action

    /// 不支持的 action 应返回错误
    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertEqual(result, "错误：不支持的操作，支持 list/search/copy/move/rename/delete/info")
    }

    /// action 不是 String 类型应返回错误
    func testExecuteActionNotString() async throws {
        let result = try await tool.execute(arguments: ["action": 123])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    // MARK: - 敏感路径保护测试

    /// list 敏感目录（~/.ssh）应被拒绝
    func testListSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "list",
            "path": "\(home)/.ssh"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    /// list 敏感目录（~/Library/Keychains）应被拒绝
    func testListKeychainPathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "list",
            "path": "\(home)/Library/Keychains"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    /// info 敏感文件应被拒绝
    func testInfoSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "info",
            "path": "\(home)/.ssh/id_rsa"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    /// delete 敏感文件应被拒绝
    func testDeleteSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "delete",
            "path": "\(home)/.ssh/id_rsa"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    /// copy 从敏感路径应被拒绝
    func testCopyFromSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "copy",
            "src": "\(home)/.ssh/id_rsa",
            "dst": "/tmp/leaked"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径（src）")
    }

    /// copy 到敏感路径应被拒绝
    func testCopyToSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "copy",
            "src": "/tmp/test.txt",
            "dst": "\(home)/.ssh/leaked"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径（dst）")
    }

    /// move 从敏感路径应被拒绝
    func testMoveFromSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "move",
            "src": "\(home)/.aws/credentials",
            "dst": "/tmp/leaked"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径（src）")
    }

    /// rename 敏感文件应被拒绝
    func testRenameSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "rename",
            "path": "\(home)/.ssh/id_rsa",
            "name": "leaked"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    /// search 敏感目录应被拒绝
    func testSearchSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "search",
            "path": "\(home)/.ssh",
            "name": "*"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    /// 路径遍历（..）标准化后命中敏感目录应被拒绝
    func testPathTraversalToSensitivePathRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // 假设当前目录在 home 下，使用 ../../.ssh 尝试访问
        let result = try await tool.execute(arguments: [
            "action": "list",
            "path": "\(home)/Documents/../../.ssh"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径")
    }

    // MARK: - 大小写绕过防护测试

    /// 敏感路径大小写变体应被拒绝（APFS 大小写不敏感）
    func testSensitivePathCaseInsensitiveBypassRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // 将 home 路径中某段改为大写，模拟大小写绕过
        // 例如 /Users/alice/.ssh → /Users/Alice/.ssh
        let capitalizedHome = home.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.lastPathComponent,
            with: FileManager.default.homeDirectoryForCurrentUser.lastPathComponent.uppercased()
        )
        let result = try await tool.execute(arguments: [
            "action": "list",
            "path": "\(capitalizedHome)/.ssh"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径", "大小写变体应被拒绝")
    }

    /// 敏感路径大小写变体（.SSH 大写）应被拒绝
    func testSensitivePathCaseInsensitiveDotSSHRejected() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = try await tool.execute(arguments: [
            "action": "info",
            "path": "\(home)/.SSH/id_rsa"
        ])
        XCTAssertEqual(result, "错误：拒绝访问敏感路径", ".SSH 大写应被拒绝")
    }
}
#endif
