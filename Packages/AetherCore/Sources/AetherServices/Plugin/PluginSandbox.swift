import Foundation
import AetherFoundation
import AetherRust

/// 插件沙箱：基于插件清单的权限声明 + Rust wasmtime 真隔离执行。
///
/// 两层防护：
/// 1. **权限校验**（声明式，保留）：基于 `manifest.permissions` 校验插件可执行的操作
///    （工具调用、网络/文件/剪贴板访问）。
/// 2. **执行隔离**（wasmtime 真隔离，迁移自原声明式伪沙箱）：
///    原 `maxExecutionTime`/`maxMemoryMB` 仅为固定常量，未真正强制；
///    现迁移为 Rust `aether-core` wasmtime 嵌入，真正强制 CPU（fuel）与内存限额。
///    通过 `executeWasm` 执行 WASM 字节码插件，Pulley 解释器（无 JIT）iOS 友好。
///
/// 如需回退到原声明式伪沙箱（不执行 WASM），将 `useRust` 置为 false。
public final class PluginSandbox {
    /// 切换开关：true 走 Rust wasmtime 真隔离，false 走原声明式伪沙箱（不执行 WASM）。
    /// wasmtime 不支持 iOS target，iOS 上强制 false（声明式伪沙箱兜底）。
    #if os(iOS)
    private static let useRust = false
    #else
    private static let useRust = true
    #endif

    /// 关联的插件清单
    private let manifest: PluginManifest

    /// 构造沙箱
    /// - Parameter manifest: 插件清单
    public init(manifest: PluginManifest) {
        self.manifest = manifest
    }

    /// 检查插件是否有权限执行指定工具
    /// - Parameter toolName: 工具名
    /// - Returns: 工具在 manifest.tools 中声明时返回 true
    public func canExecute(toolName: String) -> Bool {
        manifest.tools.contains { $0.name == toolName }
    }

    /// 检查插件是否有网络访问权限
    public func canAccessNetwork() -> Bool {
        hasPermission(.network)
    }

    /// 检查插件是否有文件系统访问权限
    public func canAccessFileSystem() -> Bool {
        hasPermission(.fileSystem)
    }

    /// 检查插件是否有剪贴板访问权限
    public func canAccessClipboard() -> Bool {
        hasPermission(.clipboard)
    }

    /// 最大执行时间（秒），固定 30 秒。对应 wasmtime fuel 限额（每秒约 10^9 指令）。
    public var maxExecutionTime: TimeInterval { 30 }

    /// 最大内存使用（MB），固定 50MB。对应 wasmtime 线性内存上限。
    public var maxMemoryMB: Int { 50 }

    /// 执行 WASM 字节码插件，强制 fuel 与内存限额。
    ///
    /// - Parameters:
    ///   - wasm: 已编译的 .wasm 字节码
    ///   - argsJson: 传给插件 `execute` 函数的 JSON 参数
    /// - Returns: 沙箱执行结果（检查 `ok` 字段判断成功与否）
    public func executeWasm(_ wasm: Data, argsJson: String) -> AetherRustSandboxResult {
        guard Self.useRust else {
            return AetherRustSandboxResult(json: #"{"ok":false,"error":"RustDisabled"}"#)
        }
        #if !os(iOS)
        let maxFuel = UInt64(maxExecutionTime * 1_000_000_000)
        let maxMemoryBytes = maxMemoryMB * 1024 * 1024
        guard let sandbox = AetherRustSandbox(maxFuel: maxFuel, maxMemoryBytes: maxMemoryBytes) else {
            return AetherRustSandboxResult(json: #"{"ok":false,"error":"EngineInitFailed"}"#)
        }
        guard let module = sandbox.load(wasm) else {
            return AetherRustSandboxResult(json: #"{"ok":false,"error":"CompileFailed"}"#)
        }
        guard let instance = module.instantiate() else {
            return AetherRustSandboxResult(json: #"{"ok":false,"error":"InstantiateFailed"}"#)
        }
        return instance.callJson(argsJson)
        #else
        // iOS 上 wasmtime 不支持，useRust 已为 false，guard 已返回。
        // 此分支不可达，仅为满足编译器返回类型要求。
        return AetherRustSandboxResult(json: #"{"ok":false,"error":"RustDisabled"}"#)
        #endif
    }

    // MARK: - Private

    /// 检查 manifest 中是否声明了指定权限类型
    private func hasPermission(_ type: PluginPermission.PermissionType) -> Bool {
        manifest.permissions.contains { $0.type == type }
    }
}
