import Foundation
import JavaScriptCore
import AetherFoundation

/// 插件工具适配器：将插件清单中声明的工具适配为本地 ToolProtocol。
///
/// 与 MCPToolAdapter 类似的适配器模式，把 PluginToolDef 的元信息映射为 ToolDefinition，
/// execute 时通过 JavaScriptCore 执行插件入口点 JS 代码。
///
/// JS 插件约定：入口 JS 文件需定义全局函数 `execute(args)`，接收参数对象，返回字符串。
/// 示例：
/// ```js
/// function execute(args) {
///     return "Hello, " + (args.name || "world");
/// }
/// ```
///
/// 执行配额：
/// - 源码 / 参数 / 结果分别限制 1 MB / 256 KB / 1 MB
/// - 每次执行使用独立的 JSVirtualMachine，避免跨调用的全局状态污染
/// - 超过 `executionTimeout` 后调用方立即失败。JavaScriptCore 未公开强制终止 API，
///   因此被中止的脚本可能在本线程内继续运行到自然结束，但不会影响其他调用。
public final class PluginToolAdapter: ToolProtocol, @unchecked Sendable {
    /// 暴露给 LLM 的工具元信息（由 PluginToolDef 转换而来）
    public let definition: ToolDefinition
    /// 关联的插件清单
    private let manifest: PluginManifest
    /// 适配的工具定义
    private let toolDef: PluginManifest.PluginToolDef
    /// 单次执行的最长等待时间（秒）
    private let executionTimeout: TimeInterval

    /// JS 源码体积上限（1 MB）
    static let maxSourceBytes = 1024 * 1024
    /// 参数体积上限（256 KB）
    static let maxArgumentBytes = 256 * 1024
    /// 结果体积上限（1 MB）
    static let maxResultBytes = 1024 * 1024

    /// 构造适配器
    /// - Parameters:
    ///   - manifest: 插件清单
    ///   - toolDef: 工具定义
    ///   - executionTimeout: 单次执行超时（秒），默认 30
    public init(manifest: PluginManifest, toolDef: PluginManifest.PluginToolDef,
                executionTimeout: TimeInterval = 30) {
        self.manifest = manifest
        self.toolDef = toolDef
        self.executionTimeout = max(executionTimeout, 0.05)
        self.definition = ToolDefinition(
            name: toolDef.name,
            description: toolDef.description,
            parameters: toolDef.parameters
        )
    }

    /// 执行插件工具：通过 JavaScriptCore 执行插件入口点 JS 代码。
    ///
    /// JS 代码加载顺序：
    /// 1. 从插件目录 `AppSupport/Plugins/{pluginID}/{entryPoint}` 加载 JS 文件（入口点经路径校验）
    /// 2. 入口点明确为内联 JS 代码时直接执行（便于测试与无文件场景）
    ///
    /// JS 代码需定义全局函数 `execute(args)`，返回字符串结果。
    /// - Parameter arguments: 工具参数
    /// - Returns: 插件工具执行结果字符串
    /// - Throws: JS 执行异常、路径越界、超时或体积超限时抛出错误
    public func execute(arguments: [String: Any]) async throws -> String {
        let jsCode = try loadJSCode()
        guard jsCode.utf8.count <= Self.maxSourceBytes else {
            throw NSError(
                domain: "PluginToolAdapter", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "插件 JS 源码超过 \(Self.maxSourceBytes / 1024) KB 上限"]
            )
        }
        if JSONSerialization.isValidJSONObject(arguments),
           let size = try? JSONSerialization.data(withJSONObject: arguments).count,
           size > Self.maxArgumentBytes {
            throw NSError(
                domain: "PluginToolAdapter", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "插件工具参数超过 \(Self.maxArgumentBytes / 1024) KB 上限"]
            )
        }
        let box = ArgumentsBox(arguments)
        return try await Self.runWithTimeout(seconds: executionTimeout) {
            try Self.evaluate(jsCode, arguments: box.value)
        }
    }

    // MARK: - Private

    /// 加载 JS 代码：入口点像文件路径时从插件目录读取，否则视为内联代码。
    ///
    /// 入口点来自远程 manifest，路径必须经 `PluginPathPolicy` 校验，
    /// 禁止绝对路径、`..` 穿越与符号链接逃逸。
    private func loadJSCode() throws -> String {
        let entryPoint = manifest.entryPoint
        // 内联代码特征（测试或无文件场景）；纯路径形式不会包含这些字符组合
        if entryPoint.contains("\n") || entryPoint.contains("function") || entryPoint.contains("{") {
            return entryPoint
        }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginRoot = appSupport
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(manifest.id, isDirectory: true)
        let entryURL = try PluginPathPolicy.entryPointURL(root: pluginRoot, entryPoint: entryPoint)

        guard let data = try? Data(contentsOf: entryURL),
              let code = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "PluginToolAdapter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "插件入口文件不存在或无法读取：\(entryPoint)"]
            )
        }
        return code
    }

    /// 在独立线程中执行 JS，并限制调用方等待时间。
    ///
    /// 使用非结构化 Task 竞速：执行块与超时块只有一方能恢复 continuation，
    /// 因此超时后调用方立即返回，不会等待仍在运行的 JS。
    private static func runWithTimeout(seconds: TimeInterval,
                                       _ work: @escaping @Sendable () throws -> String) async throws -> String {
        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let result = try work()
                    guard gate.tryResume() else { return }
                    continuation.resume(returning: result)
                } catch {
                    guard gate.tryResume() else { return }
                    continuation.resume(throwing: error)
                }
            }
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard gate.tryResume() else { return }
                continuation.resume(throwing: NSError(
                    domain: "PluginToolAdapter", code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "插件 JS 执行超时（\(Int(seconds)) 秒）"]
                ))
            }
        }
    }

    /// 使用 JavaScriptCore 执行 JS 代码并调用 execute 函数。
    private static func evaluate(_ jsCode: String, arguments: [String: Any]) throws -> String {
        guard let vm = JSVirtualMachine(), let context = JSContext(virtualMachine: vm) else {
            throw NSError(
                domain: "PluginToolAdapter", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法创建 JavaScriptContext"]
            )
        }

        // 捕获 JS 异常
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }

        // 移除动态代码执行入口，降低插件自行构造代码的能力（函数声明不受影响）
        context.evaluateScript("""
        (function () {
            try { globalThis.eval = undefined; } catch (e) {}
            try { globalThis.Function = undefined; } catch (e) {}
        })();
        """)

        // 注入参数为全局对象 args（同时支持 execute(args) 调用）
        context.setObject(arguments.jsValue(in: context), forKeyedSubscript: "args" as NSCopying & NSObjectProtocol)

        // 执行插件 JS 代码（定义 execute 函数）
        context.evaluateScript(jsCode)

        if let error = jsError {
            throw NSError(
                domain: "PluginToolAdapter", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "JS 执行错误：\(error)"]
            )
        }

        // 调用 execute(args) 获取结果
        guard let executeFn = context.objectForKeyedSubscript("execute"),
              !executeFn.isUndefined else {
            throw NSError(
                domain: "PluginToolAdapter", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "插件 JS 未定义 execute 函数"]
            )
        }

        let argsValue: JSValue = context.objectForKeyedSubscript("args") ?? JSValue()
        let result = executeFn.call(withArguments: [argsValue])

        if let error = jsError {
            throw NSError(
                domain: "PluginToolAdapter", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "JS execute 调用错误：\(error)"]
            )
        }

        guard let resultValue = result, !resultValue.isUndefined, !resultValue.isNull else {
            throw NSError(
                domain: "PluginToolAdapter", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "JS execute 返回空值"]
            )
        }

        // 结果转字符串
        if let str = resultValue.toString(), !resultValue.isUndefined {
            guard str.utf8.count <= maxResultBytes else {
                throw NSError(
                    domain: "PluginToolAdapter", code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "插件 JS 返回值超过 \(maxResultBytes / 1024) KB 上限"]
                )
            }
            return str
        }

        throw NSError(
            domain: "PluginToolAdapter", code: 11,
            userInfo: [NSLocalizedDescriptionKey: "JS execute 返回值无法转为字符串"]
        )
    }
}

/// 参数容器：跨线程传递不可变参数字典。
private final class ArgumentsBox: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}

/// 保证超时与执行两条路径只有一方能恢复 continuation。
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

// MARK: - [String: Any] → JSValue 辅助

private extension Dictionary where Key == String, Value == Any {
    /// 将 [String: Any] 转换为 JSValue（递归处理嵌套字典与数组）。
    func jsValue(in context: JSContext) -> JSValue {
        var jsDict: [String: Any] = [:]
        for (key, value) in self {
            jsDict[key] = convertValue(value, in: context)
        }
        return JSValue(object: jsDict, in: context) ?? JSValue(undefinedIn: context)
    }

    /// 递归转换 Swift 值为 JSValue 兼容类型。
    private func convertValue(_ value: Any, in context: JSContext) -> Any {
        if let dict = value as? [String: Any] {
            var jsDict: [String: Any] = [:]
            for (k, v) in dict {
                jsDict[k] = convertValue(v, in: context)
            }
            return jsDict
        } else if let arr = value as? [Any] {
            return arr.map { convertValue($0, in: context) }
        }
        // 基本类型（String/Int/Double/Bool）直接返回，JSValue 可接受
        return value
    }
}
