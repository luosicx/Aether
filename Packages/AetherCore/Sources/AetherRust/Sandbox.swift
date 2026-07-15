import Foundation
import AetherRustC

// wasmtime 不支持 iOS target，沙箱仅 macOS/Android 可用。
// iOS 上 AetherRustSandbox 不可用，PluginSandbox.useRust 在 iOS 上为 false。
#if !os(iOS)

/// Swift 友好的 Rust wasmtime 插件沙箱包装。
///
/// 将 `PluginSandbox.swift`（原声明式伪沙箱，maxExecutionTime/maxMemoryMB 未强制）
/// 迁移为 wasmtime 真隔离执行，强制 CPU（fuel）与内存（memory_limit）限额。
///
/// 三层句柄对应 Rust 侧：
/// - `AetherRustSandbox`：引擎（Pulley 解释器，无 JIT，iOS 友好）
/// - `AetherRustSandboxModule`：编译产物（可实例化多次）
/// - `AetherRustSandboxInstance`：运行时实例（持有 store + instance）
///
/// 插件 ABI 约定：导出 `execute(args_len: i32) -> i32` 函数，
/// 参数 JSON 由宿主写入线性内存偏移 0，长度由 args_len 传入，
/// 返回值 JSON 写入线性内存偏移 0，返回其长度（0 表示无返回值）。
public final class AetherRustSandbox: @unchecked Sendable {
    private let handle: OpaquePointer

    /// 创建沙箱引擎。
    /// - Parameters:
    ///   - maxFuel: CPU 指令限额（30 秒 ≈ 30_000_000_000）
    ///   - maxMemoryBytes: 线性内存上限（字节，50 MB = 52_428_800）
    public init?(maxFuel: UInt64 = 30_000_000_000, maxMemoryBytes: Int = 50 * 1024 * 1024) {
        guard let h = aether_sandbox_new(maxFuel, maxMemoryBytes) else { return nil }
        self.handle = h
    }

    deinit {
        aether_sandbox_free(handle)
    }

    /// 编译 WASM 模块（字节码）。失败返回 nil。
    /// - Parameter wasm: 已编译的 .wasm 字节码
    public func load(_ wasm: Data) -> AetherRustSandboxModule? {
        let count = wasm.count
        guard count > 0 else { return nil }
        let module = wasm.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> OpaquePointer? in
            guard let base = ptr.baseAddress else { return nil }
            return aether_sandbox_load(handle, base.assumingMemoryBound(to: UInt8.self), count)
        }
        guard let m = module else { return nil }
        return AetherRustSandboxModule(handle: m)
    }
}

/// 已编译的 WASM 模块（可实例化多次）。
public final class AetherRustSandboxModule: @unchecked Sendable {
    fileprivate let handle: OpaquePointer

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        aether_sandbox_module_free(handle)
    }

    /// 实例化模块，返回可调用实例。失败返回 nil。
    /// 初始 fuel = 创建引擎时的 maxFuel。
    public func instantiate() -> AetherRustSandboxInstance? {
        guard let h = aether_sandbox_instantiate(handle) else { return nil }
        return AetherRustSandboxInstance(handle: h)
    }
}

/// 沙箱运行时实例（持有 store + instance）。
public final class AetherRustSandboxInstance: @unchecked Sendable {
    fileprivate let handle: OpaquePointer

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        aether_sandbox_instance_free(handle)
    }

    /// 调用插件的 execute 函数，传入 JSON 参数，返回结果。
    /// 失败时（如 fuel 耗尽、缺少导出函数）返回对应的 error 类型。
    /// - Parameter argsJson: 传给插件的 JSON 参数字符串
    public func callJson(_ argsJson: String) -> AetherRustSandboxResult {
        let json = argsJson.withCString { cstr -> String in
            guard let cResult = aether_sandbox_call_json(handle, cstr) else {
                return #"{"ok":false,"error":"NullResult"}"#
            }
            defer { aether_free_string(cResult) }
            return String(cString: cResult)
        }
        return AetherRustSandboxResult(json: json)
    }

    /// 直接调用 execute（数值参数），返回结果。失败返回 0。
    /// 不经过 JSON 序列化，用于简单数值插件。
    public func callRaw(_ arg: Int32) -> Int32 {
        aether_sandbox_call_raw(handle, arg)
    }

    /// 剩余 fuel。
    public var fuelRemaining: UInt64 {
        aether_sandbox_fuel_remaining(handle)
    }

    /// 重置 fuel 到初始值。
    public func refillFuel() {
        aether_sandbox_refill_fuel(handle)
    }
}

#endif // !os(iOS)

/// 沙箱执行结果（解析自 Rust 侧返回的 JSON）。
public struct AetherRustSandboxResult: Equatable {
    /// 是否执行成功。
    public let ok: Bool
    /// 成功时的插件返回值（JSON 字符串），失败时为空串。
    public let output: String
    /// 剩余 fuel。
    public let fuelRemaining: UInt64
    /// 是否因 fuel 耗尽而 trap。
    public let outOfFuel: Bool
    /// 失败时的错误类型（如 "OutOfFuel"/"MissingExecute"/"Call"），成功时为 nil。
    public let error: String?

    /// 从 Rust 侧返回的 JSON 字符串解析。
    /// JSON 格式：
    /// - 成功：`{"ok":true,"output":"...","fuelRemaining":N,"outOfFuel":false}`
    /// - 失败：`{"ok":false,"error":"OutOfFuel|..."}`
    public init(json: String) {
        struct Payload: Decodable {
            let ok: Bool
            let output: String?
            let fuelRemaining: UInt64?
            let outOfFuel: Bool?
            let error: String?
        }
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            self.ok = false
            self.output = ""
            self.fuelRemaining = 0
            self.outOfFuel = false
            self.error = "InvalidJson"
            return
        }
        self.ok = payload.ok
        self.output = payload.output ?? ""
        self.fuelRemaining = payload.fuelRemaining ?? 0
        self.outOfFuel = payload.outOfFuel ?? false
        self.error = payload.error
    }
}
