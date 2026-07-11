#if os(macOS)
import XCTest
@testable import Aether

final class FileOperationToolTests: XCTestCase {
    private let tool = FileOperationTool()
    private var tempDir: String { NSTemporaryDirectory() }

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "manage_file")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteListDir() async throws {
        let result = try await tool.execute(arguments: ["action": "list", "path": tempDir])
        XCTAssertFalse(result.isEmpty)
    }

    func testExecuteFileInfo() async throws {
        let result = try await tool.execute(arguments: ["action": "info", "path": tempDir])
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
        let result = try await tool.execute(arguments: ["action": "list", "path": tempDir + "/nonexistent/path/12345"])
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
        let result = try await tool.execute(arguments: ["action": "search", "path": tempDir])
        XCTAssertEqual(result, "错误：请提供 path 和 name 参数")
    }

    /// search 在临时目录下搜索应返回非空结果或未找到提示
    func testExecuteSearchWithValidPath() async throws {
        let result = try await tool.execute(arguments: ["action": "search", "path": tempDir, "name": "*"])
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
        let result = try await tool.execute(arguments: ["action": "copy", "src": tempDir])
        XCTAssertEqual(result, "错误：请提供 src 和 dst 参数")
    }

    /// copy 不存在的源文件应返回错误
    func testExecuteCopyNonExistentSrc() async throws {
        let result = try await tool.execute(arguments: ["action": "copy", "src": tempDir + "/nonexistent_src", "dst": tempDir + "/nonexistent_dst"])
        XCTAssertTrue(result.contains("错误"), "不存在的源文件应返回错误：\(result)")
    }

    /// copy 有效文件应返回"已复制"并实际复制
    func testExecuteCopyValidFile() async throws {
        let srcFile = (tempDir as NSString).appendingPathComponent("aether_test_src.txt")
        let dstFile = (tempDir as NSString).appendingPathComponent("aether_test_dst.txt")
        try "test content".write(toFile: srcFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: srcFile)
            try? FileManager.default.removeItem(atPath: dstFile)
        }
        let tool = FileOperationTool()
        tool.requiresDestructiveConfirmation = false
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
        let result = try await tool.execute(arguments: ["action": "move", "src": tempDir + "/nonexistent_src", "dst": tempDir + "/nonexistent_dst"])
        XCTAssertTrue(result.contains("错误"), "不存在的源文件应返回错误：\(result)")
    }

    /// move 有效文件应返回"已移动"并实际移动
    func testExecuteMoveValidFile() async throws {
        let srcFile = (tempDir as NSString).appendingPathComponent("aether_move_src.txt")
        let dstFile = (tempDir as NSString).appendingPathComponent("aether_move_dst.txt")
        try "move content".write(toFile: srcFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: srcFile)
            try? FileManager.default.removeItem(atPath: dstFile)
        }
        let tool = FileOperationTool()
        tool.requiresDestructiveConfirmation = false
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
        let result = try await tool.execute(arguments: ["action": "rename", "path": tempDir])
        XCTAssertEqual(result, "错误：请提供 path 和 name 参数")
    }

    /// rename 不存在的文件应返回错误
    func testExecuteRenameNonExistentFile() async throws {
        let result = try await tool.execute(arguments: ["action": "rename", "path": tempDir + "/nonexistent_file.txt", "name": "newname.txt"])
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
        let result = try await tool.execute(arguments: ["action": "delete", "path": tempDir + "/nonexistent_file.txt"])
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
        let result = try await tool.execute(arguments: ["action": "info", "path": tempDir + "/nonexistent_file.txt"])
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

    // MARK: - 沙盒安全

    /// 路径遍历应被阻止
    func testPathTraversalBlocked() async throws {
        let result = try await tool.execute(arguments: ["action": "list", "path": "../../../etc/passwd"])
        XCTAssertTrue(result.contains("路径超出允许范围"), "路径遍历应被阻止：\(result)")
    }

    /// 沙盒内的 list 操作应正常工作
    func testSandboxedListWorks() async throws {
        let result = try await tool.execute(arguments: ["action": "list", "path": tempDir])
        XCTAssertFalse(result.contains("路径超出允许范围"), "临时目录应在沙盒内：\(result)")
    }

    // MARK: - 二次确认

    /// 删除操作在 requiresDestructiveConfirmation 为 true 时应要求二次确认
    func testDeleteRequiresSecondaryConfirmation() async throws {
        let file = (tempDir as NSString).appendingPathComponent("aether_delete_confirm.txt")
        try "delete me".write(toFile: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: file) }
        let result = try await tool.execute(arguments: ["action": "delete", "path": file])
        XCTAssertEqual(result, "错误：删除/覆盖操作需要二次确认（待实现 UI）")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file), "未确认前不应删除文件")
    }

    /// 移动操作在 requiresDestructiveConfirmation 为 true 时应要求二次确认
    func testMoveRequiresSecondaryConfirmation() async throws {
        let srcFile = (tempDir as NSString).appendingPathComponent("aether_move_confirm_src.txt")
        let dstFile = (tempDir as NSString).appendingPathComponent("aether_move_confirm_dst.txt")
        try "move me".write(toFile: srcFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: srcFile)
            try? FileManager.default.removeItem(atPath: dstFile)
        }
        let result = try await tool.execute(arguments: ["action": "move", "src": srcFile, "dst": dstFile])
        XCTAssertEqual(result, "错误：删除/覆盖操作需要二次确认（待实现 UI）")
        XCTAssertTrue(FileManager.default.fileExists(atPath: srcFile), "未确认前不应移动源文件")
    }

    /// 复制覆盖操作在 requiresDestructiveConfirmation 为 true 时应要求二次确认
    func testCopyOverwriteRequiresSecondaryConfirmation() async throws {
        let srcFile = (tempDir as NSString).appendingPathComponent("aether_copy_confirm_src.txt")
        let dstFile = (tempDir as NSString).appendingPathComponent("aether_copy_confirm_dst.txt")
        try "source".write(toFile: srcFile, atomically: true, encoding: .utf8)
        try "destination".write(toFile: dstFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: srcFile)
            try? FileManager.default.removeItem(atPath: dstFile)
        }
        let result = try await tool.execute(arguments: ["action": "copy", "src": srcFile, "dst": dstFile])
        XCTAssertEqual(result, "错误：删除/覆盖操作需要二次确认（待实现 UI）")
    }
}
#endif
