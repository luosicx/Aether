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
public final class PluginToolAdapter: ToolProtocol, @unchecked Sendable {
    /// 暴露给 LLM 的工具元信息（由 PluginToolDef 转换而来）
    public let definition: ToolDefinition
    /// 关联的插件清单
    private let manifest: PluginManifest
    /// 适配的工具定义
    private let toolDef: PluginManifest.PluginToolDef

    /// 构造适配器
    /// - Parameters:
    ///   - manifest: 插件清单
    ///   - toolDef: 工具定义
    public init(manifest: PluginManifest, toolDef: PluginManifest.PluginToolDef) {
        self.manifest = manifest
        self.toolDef = toolDef
        self.definition = ToolDefinition(
            name: toolDef.name,
            description: toolDef.description,
            parameters: toolDef.parameters
        )
    }

    /// 执行插件工具：通过 JavaScriptCore 执行插件入口点 JS 代码。
    ///
    /// JS 代码加载顺序：
    /// 1. 尝试从插件目录 `AppSupport/Plugins/{pluginID}/{entryPoint}` 加载 JS 文件
    /// 2. 文件不存在时，将 `entryPoint` 视为内联 JS 代码（便于测试与无文件场景）
    ///
    /// JS 代码需定义全局函数 `execute(args)`，返回字符串结果。
    /// - Parameter arguments: 工具参数
    /// - Returns: 插件工具执行结果字符串
    /// - Throws: JS 执行异常或结果非字符串时抛出错误
    public func execute(arguments: [String: Any]) async throws -> String {
        let jsCode = try loadJSCode()
        return try evaluateJS(jsCode, arguments: arguments)
    }

    // MARK: - Private

    /// 加载 JS 代码：优先从插件目录读取入口文件，失败时回退到内联代码。
    private func loadJSCode() throws -> String {
        // 构造入口文件 URL：AppSupport/Plugins/{pluginID}/{entryPoint}
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let entryURL = appSupport
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(manifest.id, isDirectory: true)
            .appendingPathComponent(manifest.entryPoint)

        if fm.fileExists(atPath: entryURL.path),
           let data = try? Data(contentsOf: entryURL),
           let code = String(data: data, encoding: .utf8) {
            return code
        }
        // 回退：entryPoint 视为内联 JS 代码（测试或无文件场景）
        return manifest.entryPoint
    }

    /// 使用 JavaScriptCore 执行 JS 代码并调用 execute 函数。
    private func evaluateJS(_ jsCode: String, arguments: [String: Any]) throws -> String {
        guard let context = JSContext() else {
            throw NSError(
                domain: "PluginToolAdapter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建 JavaScriptContext"]
            )
        }

        // 捕获 JS 异常
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }

        // 注入参数为全局对象 args（同时支持 execute(args) 调用）
        context.setObject(arguments.jsValue(in: context), forKeyedSubscript: "args" as NSCopying & NSObjectProtocol)

        // 执行插件 JS 代码（定义 execute 函数）
        context.evaluateScript(jsCode)

        if let error = jsError {
            throw NSError(
                domain: "PluginToolAdapter", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "JS 执行错误：\(error)"]
            )
        }

        // 调用 execute(args) 获取结果
        guard let executeFn = context.objectForKeyedSubscript("execute"),
              !executeFn.isUndefined else {
            throw NSError(
                domain: "PluginToolAdapter", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "插件 JS 未定义 execute 函数"]
            )
        }

        let argsValue = context.objectForKeyedSubscript("args") ?? JSValue(undefinedIn: context)
        let result = executeFn.call(withArguments: [argsValue])

        if let error = jsError {
            throw NSError(
                domain: "PluginToolAdapter", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "JS execute 调用错误：\(error)"]
            )
        }

        guard let resultValue = result, !resultValue.isUndefined, !resultValue.isNull else {
            throw NSError(
                domain: "PluginToolAdapter", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "JS execute 返回空值"]
            )
        }

        // 结果转字符串
        if let str = resultValue.toString(), !resultValue.isUndefined {
            return str
        }

        throw NSError(
            domain: "PluginToolAdapter", code: 6,
            userInfo: [NSLocalizedDescriptionKey: "JS execute 返回值无法转为字符串"]
        )
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
