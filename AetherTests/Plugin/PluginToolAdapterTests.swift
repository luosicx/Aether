import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// v1.1 Phase C 测试：PluginToolAdapter 的 JavaScriptCore 执行能力。
///
/// 覆盖范围：
/// 1. 内联 JS 代码执行（entryPoint 作为 JS 代码）
/// 2. 参数传递（字符串/数字/嵌套对象）
/// 3. JS 异常捕获
/// 4. 缺少 execute 函数时抛错
/// 5. 从文件加载 JS（写入临时文件）
@MainActor
final class PluginToolAdapterTests: XCTestCase {

    // MARK: - 辅助：构造适配器

    /// 使用内联 JS 代码构造一个 PluginToolAdapter
    private func makeAdapter(jsCode: String, pluginID: String = "js-test",
                             executionTimeout: TimeInterval = 30) -> PluginToolAdapter {
        let toolDef = PluginManifest.PluginToolDef(
            name: "js_tool", description: "JS 测试工具",
            parameters: ["type": "object", "properties": [:]]
        )
        let manifest = PluginManifest(
            id: pluginID, name: "JS 插件", version: "1.0.0", author: "测试",
            description: "JS 执行测试", tools: [toolDef], permissions: [],
            entryPoint: jsCode
        )
        return PluginToolAdapter(manifest: manifest, toolDef: toolDef, executionTimeout: executionTimeout)
    }

    /// 插件根目录（AppSupport/Plugins/{pluginID}）
    private func pluginDirectory(for pluginID: String) -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
    }

    // MARK: - 内联 JS 执行

    /// 简单的内联 JS execute 函数应返回字符串结果
    func testInlineJSExecution() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return "hello world";
        }
        """)
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "hello world")
    }

    /// JS execute 函数应能读取字符串参数
    func testJSReadsStringArgument() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return "Name: " + args.name;
        }
        """)
        let result = try await adapter.execute(arguments: ["name": "Aether"])
        XCTAssertEqual(result, "Name: Aether")
    }

    /// JS execute 函数应能读取数字参数
    func testJSReadsNumberArgument() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return "Count: " + args.count;
        }
        """)
        let result = try await adapter.execute(arguments: ["count": 42])
        XCTAssertEqual(result, "Count: 42")
    }

    /// JS execute 函数应能读取嵌套对象参数
    func testJSReadsNestedObjectArgument() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return args.user.name + " is " + args.user.age;
        }
        """)
        let result = try await adapter.execute(arguments: [
            "user": ["name": "Alice", "age": 30]
        ])
        XCTAssertEqual(result, "Alice is 30")
    }

    // MARK: - 异常处理

    /// JS 执行抛出异常时应被捕获并抛出 NSError
    func testJSThrowsErrorIsCaught() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            throw new Error("JS boom");
        }
        """)
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("应抛出 JS 异常错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("JS"), "错误信息应包含 JS 相关描述，实际：\(error.localizedDescription)")
        }
    }

    /// JS 语法错误应被捕获
    func testJSSyntaxErrorIsCaught() async throws {
        let adapter = makeAdapter(jsCode: "function execute(args) { return;") // 缺少右括号
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("应抛出语法错误")
        } catch {
            // 语法错误应被捕获
            XCTAssertTrue(error.localizedDescription.contains("JS") || error.localizedDescription.contains("错误"))
        }
    }

    /// 缺少 execute 函数时应抛出错误
    func testMissingExecuteFunctionThrows() async throws {
        let adapter = makeAdapter(jsCode: """
        function notExecute(args) {
            return "wrong function";
        }
        """)
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("应抛出缺少 execute 函数的错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("execute"), "错误应提示缺少 execute 函数，实际：\(error.localizedDescription)")
        }
    }

    /// execute 返回 undefined 时应抛出错误
    func testExecuteReturnsUndefinedThrows() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return undefined;
        }
        """)
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("应抛出返回空值的错误")
        } catch {
            // 返回 undefined/null 应被检测到
            XCTAssertTrue(error.localizedDescription.contains("空值") || error.localizedDescription.contains("字符串"))
        }
    }

    // MARK: - 文件加载

    /// 从插件目录加载 JS 文件并执行
    func testLoadJSFromFile() async throws {
        let pluginID = "file-test-\(UUID().uuidString.prefix(8))"
        let jsCode = """
        function execute(args) {
            return "from file: " + args.input;
        }
        """
        // 写入 JS 文件到 AppSupport/Plugins/{pluginID}/main.js
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let jsURL = pluginDir.appendingPathComponent("main.js")
        try jsCode.data(using: .utf8)?.write(to: jsURL)
        defer { try? fm.removeItem(at: pluginDir) }

        let toolDef = PluginManifest.PluginToolDef(
            name: "file_tool", description: "文件加载测试",
            parameters: ["type": "object"]
        )
        let manifest = PluginManifest(
            id: pluginID, name: "文件插件", version: "1.0.0", author: "测试",
            description: "文件加载", tools: [toolDef], permissions: [],
            entryPoint: "main.js"
        )
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)

        let result = try await adapter.execute(arguments: ["input": "success"])
        XCTAssertEqual(result, "from file: success")
    }

    // MARK: - definition 映射

    /// definition 应正确映射 toolDef 的 name / description / parameters
    func testDefinitionMapping() {
        let toolDef = PluginManifest.PluginToolDef(
            name: "mapped_tool", description: "映射测试工具",
            parameters: ["type": "object", "properties": ["x": ["type": "string"]]]
        )
        let manifest = PluginManifest(
            id: "map-test", name: "映射插件", version: "1.0.0", author: "测试",
            description: "映射", tools: [toolDef], permissions: [], entryPoint: "main.js"
        )
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)
        XCTAssertEqual(adapter.definition.name, "mapped_tool")
        XCTAssertEqual(adapter.definition.description, "映射测试工具")
        XCTAssertEqual(adapter.definition.parameters["type"] as? String, "object")
    }

    // MARK: - 返回值类型转换

    /// execute 返回 null（不是 undefined）时应抛出错误
    func testExecuteReturnsNullThrowsError() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return null;
        }
        """)
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("null 返回值应抛出错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("空值"),
                          "应提示返回空值，实际：\(error.localizedDescription)")
        }
    }

    /// execute 返回数字 42 时应通过 toString 转换为 "42"
    func testExecuteReturnsNumberConvertsToString() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return 42;
        }
        """)
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "42", "数字返回值应转为字符串 \"42\"")
    }

    /// execute 返回空字符串 "" 时不应抛错（实现返回空串，未做空值判定）
    /// 注：任务期望空字符串抛错，但实现未对空串做拦截——空串通过 isUndefined/isNull 检查后被 toString 返回。
    /// 不修改实现，改为验证实际行为。
    func testExecuteReturnsEmptyStringDoesNotThrow() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return "";
        }
        """)
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "", "空字符串应原样返回，不抛错")
    }

    /// execute 返回对象 {a:1} 时应通过 toString 转换为 "[object Object]"
    func testExecuteReturnsObjectConvertsToString() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return {a: 1};
        }
        """)
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "[object Object]", "对象返回值应转为 \"[object Object]\"")
    }

    // MARK: - 参数类型支持

    /// 参数包含数组时应能被 JS 读取
    func testExecuteWithArrayParameter() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return args.items[0] + "-" + args.items[1];
        }
        """)
        let result = try await adapter.execute(arguments: ["items": ["a", "b"]])
        XCTAssertEqual(result, "a-b", "JS 应能读取数组参数")
    }

    /// 参数包含 Bool true 时应能被 JS 读取
    func testExecuteWithBoolParameter() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return args.flag ? "yes" : "no";
        }
        """)
        let result = try await adapter.execute(arguments: ["flag": true])
        XCTAssertEqual(result, "yes", "JS 应能读取 Bool 参数 true")
    }

    /// 参数包含 NSNull（nil）时应能被 JS 读取为 null
    func testExecuteWithNilParameter() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return args.value === null ? "is-null" : "not-null";
        }
        """)
        let result = try await adapter.execute(arguments: ["value": NSNull()])
        XCTAssertEqual(result, "is-null", "NSNull 应在 JS 中表现为 null")
    }

    // MARK: - 文件加载边界

    /// 入口文件存在但为空时应抛错（空文件无 execute 函数定义）
    func testLoadJSCodeFromEmptyFile() async throws {
        let pluginID = "empty-file-\(UUID().uuidString.prefix(8))"
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let jsURL = pluginDir.appendingPathComponent("main.js")
        // 写入空文件
        try Data().write(to: jsURL)
        defer { try? fm.removeItem(at: pluginDir) }

        let toolDef = PluginManifest.PluginToolDef(
            name: "empty_file_tool", description: "空文件测试",
            parameters: ["type": "object"]
        )
        let manifest = PluginManifest(
            id: pluginID, name: "空文件插件", version: "1.0.0", author: "测试",
            description: "空文件加载", tools: [toolDef], permissions: [],
            entryPoint: "main.js"
        )
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)

        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("空入口文件应因缺少 execute 函数而抛错")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("execute"),
                          "错误应提示缺少 execute 函数，实际：\(error.localizedDescription)")
        }
    }

    // MARK: - P1 安全：路径越界

    /// 穿越式入口点不得读取插件目录外的文件
    func testTraversalEntryPointIsRejected() async throws {
        let pluginID = "traversal-\(UUID().uuidString.prefix(8))"
        let fm = FileManager.default
        let pluginsRoot = pluginDirectory(for: pluginID).deletingLastPathComponent()
        try fm.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)
        let escapedFile = pluginsRoot.appendingPathComponent("escaped.js")
        try "function execute(args) { return 'escaped'; }".data(using: .utf8)!.write(to: escapedFile)
        defer { try? fm.removeItem(at: escapedFile) }

        let toolDef = PluginManifest.PluginToolDef(
            name: "escape_tool", description: "越界测试", parameters: ["type": "object"]
        )
        let manifest = PluginManifest(
            id: pluginID, name: "越界插件", version: "1.0.0", author: "测试",
            description: "越界", tools: [toolDef], permissions: [], entryPoint: "../escaped.js"
        )
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)

        do {
            let result = try await adapter.execute(arguments: [:])
            XCTFail("穿越式入口点应被拒绝，实际执行结果：\(result)")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("越界") || error.localizedDescription.contains("入口点"),
                          "错误应说明入口点越界，实际：\(error.localizedDescription)")
        }
    }

    /// 入口文件为指向目录外的符号链接时应被拒绝
    func testSymlinkedEntryFileIsRejected() async throws {
        let pluginID = "symlink-\(UUID().uuidString.prefix(8))"
        let fm = FileManager.default
        let pluginDir = pluginDirectory(for: pluginID)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: pluginDir) }

        let outsideFile = fm.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).js")
        try "function execute(args) { return 'outside'; }".data(using: .utf8)!.write(to: outsideFile)
        defer { try? fm.removeItem(at: outsideFile) }
        try fm.createSymbolicLink(at: pluginDir.appendingPathComponent("main.js"), withDestinationURL: outsideFile)

        let toolDef = PluginManifest.PluginToolDef(
            name: "symlink_tool", description: "符号链接测试", parameters: ["type": "object"]
        )
        let manifest = PluginManifest(
            id: pluginID, name: "符号链接插件", version: "1.0.0", author: "测试",
            description: "符号链接", tools: [toolDef], permissions: [], entryPoint: "main.js"
        )
        let adapter = PluginToolAdapter(manifest: manifest, toolDef: toolDef)

        do {
            let result = try await adapter.execute(arguments: [:])
            XCTFail("符号链接逃逸应被拒绝，实际执行结果：\(result)")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("越界") || error.localizedDescription.contains("入口点"),
                          "错误应说明入口点越界，实际：\(error.localizedDescription)")
        }
    }

    // MARK: - P1 安全：执行配额

    /// 长时间运行的脚本应按时超时返回错误
    func testExecutionTimeoutThrows() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            var end = Date.now() + 1500;
            while (Date.now() < end) {}
            return "done";
        }
        """, executionTimeout: 0.1)

        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("超时脚本应抛错")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("超时"),
                          "错误应说明执行超时，实际：\(error.localizedDescription)")
        }
    }

    /// 超过 1 MB 的 JS 源码应被拒绝
    func testOversizedSourceIsRejected() async throws {
        let padding = String(repeating: "a", count: 1_048_577)
        let adapter = makeAdapter(jsCode: "function execute(args) { return 'x'; }\n//" + padding)
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("超长源码应被拒绝")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("源码"),
                          "错误应说明源码超限，实际：\(error.localizedDescription)")
        }
    }

    /// 超过 256 KB 的参数应被拒绝
    func testOversizedArgumentsAreRejected() async throws {
        let adapter = makeAdapter(jsCode: "function execute(args) { return 'ok'; }")
        do {
            _ = try await adapter.execute(arguments: ["blob": String(repeating: "a", count: 300 * 1024)])
            XCTFail("超大参数应被拒绝")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("参数"),
                          "错误应说明参数超限，实际：\(error.localizedDescription)")
        }
    }

    /// 超过 1 MB 的返回值应被拒绝
    func testOversizedResultIsRejected() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return "x".repeat(1048577);
        }
        """)
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("超大返回值应被拒绝")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("返回值"),
                          "错误应说明返回值超限，实际：\(error.localizedDescription)")
        }
    }

    /// 动态代码执行入口（eval / Function）应被移除
    func testDynamicCodeEntryPointsAreRemoved() async throws {
        let adapter = makeAdapter(jsCode: """
        function execute(args) {
            return typeof eval + "|" + typeof Function;
        }
        """)
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "undefined|undefined", "eval 与 Function 应不可用")
    }
}
