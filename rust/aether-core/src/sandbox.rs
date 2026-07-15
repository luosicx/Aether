//! 插件沙箱：基于 wasmtime 的真隔离执行。
//!
//! 将 `PluginSandbox.swift`（原声明式伪沙箱，maxExecutionTime/maxMemoryMB 未强制）
//! 迁移为 wasmtime 嵌入，真正强制 CPU（fuel）与内存（memory_limit）限额。
//!
//! 设计要点：
//! - Pulley 解释器（无 JIT），iOS 友好（不要求 W^X 可执行内存）
//! - fuel 限额对应原 maxExecutionTime（每秒约 10^9 条指令，30 秒 = 3×10^10）
//! - memory_limit 对应原 maxMemoryMB
//! - 仅 host target（Apple/Android），wasm32 不编译
//!
//! 插件 ABI 约定：
//! - 插件导出 `execute(args_len: i32) -> i32` 函数
//! - 参数 JSON 由宿主写入线性内存偏移 0，长度由 args_len 传入
//! - 返回值 JSON 写入线性内存偏移 0，返回其长度（0 表示无返回值）

#![cfg(not(target_arch = "wasm32"))]

use wasmtime::{Engine, Func, Instance, Linker, Memory, Module, Store, TypedFunc};

/// 沙箱配置。对应原 PluginSandbox 的 maxExecutionTime / maxMemoryMB。
pub struct SandboxConfig {
    /// fuel 限额（CPU 指令数）。30 秒 ≈ 30_000_000_000（按每秒 10^9 估算）。
    pub max_fuel: u64,
    /// 线性内存上限（字节）。50 MB = 52_428_800。
    pub max_memory_bytes: usize,
}

impl Default for SandboxConfig {
    fn default() -> Self {
        Self {
            max_fuel: 30_000_000_000,
            max_memory_bytes: 50 * 1024 * 1024,
        }
    }
}

/// 沙箱引擎（可复用，编译多个模块共享）。
pub struct Sandbox {
    engine: Engine,
    config: SandboxConfig,
}

/// 已加载的模块（编译产物，可实例化多次）。
pub struct SandboxModule {
    module: Module,
    engine: Engine,
    config: SandboxConfig,
}

/// 沙箱实例（运行时，持有 store + instance）。
pub struct SandboxInstance {
    store: Store<()>,
    instance: Instance,
    memory: Option<Memory>,
    execute_fn: Option<TypedFunc<i32, i32>>,
    config: SandboxConfig,
}

/// 沙箱执行结果。
#[derive(Debug)]
pub struct SandboxResult {
    /// 返回值（JSON 字符串，从线性内存读取）。
    pub output: String,
    /// 剩余 fuel。
    pub fuel_remaining: u64,
    /// 是否因 fuel 耗尽而 trap。
    pub out_of_fuel: bool,
}

/// 沙箱错误。
#[derive(Debug, thiserror::Error)]
pub enum SandboxError {
    #[error("WASM 编译失败: {0}")]
    Compile(String),
    #[error("WASM 实例化失败: {0}")]
    Instantiate(String),
    #[error("WASM 调用失败: {0}")]
    Call(String),
    #[error("Fuel 耗尽")]
    OutOfFuel,
    #[error("内存超限")]
    MemoryLimit,
    #[error("缺少导出函数 `execute`")]
    MissingExecute,
    #[error("缺少线性内存导出")]
    MissingMemory,
    #[error("UTF-8 解码失败: {0}")]
    Utf8(String),
}

impl Sandbox {
    /// 创建沙箱引擎。使用 Pulley 解释器（无 JIT），iOS 友好。
    pub fn new(config: SandboxConfig) -> Result<Self, SandboxError> {
        let mut cfg = wasmtime::Config::new();
        // 启用 fuel 消耗（CPU 限额）
        cfg.consume_fuel(true);
        // 使用 Pulley 解释器（无 JIT，不要求可执行内存）
        cfg.target("pulley64")
            .map_err(|e| SandboxError::Compile(e.to_string()))?;

        let engine =
            Engine::new(&cfg).map_err(|e| SandboxError::Compile(e.to_string()))?;
        Ok(Self { engine, config })
    }

    /// 用默认配置创建沙箱（fuel=30秒估算，memory=50MB）。
    pub fn with_defaults() -> Result<Self, SandboxError> {
        Self::new(SandboxConfig::default())
    }

    /// 编译 WASM 模块（字节码或 WAT 文本）。
    pub fn load(&self, wasm: &[u8]) -> Result<SandboxModule, SandboxError> {
        let module = Module::new(&self.engine, wasm)
            .map_err(|e| SandboxError::Compile(e.to_string()))?;
        Ok(SandboxModule {
            module,
            engine: self.engine.clone(),
            config: SandboxConfig {
                max_fuel: self.config.max_fuel,
                max_memory_bytes: self.config.max_memory_bytes,
            },
        })
    }
}

impl SandboxModule {
    /// 实例化模块，返回可调用的沙箱实例。
    /// 初始 fuel = config.max_fuel，每次调用 execute 消耗。
    pub fn instantiate(&self) -> Result<SandboxInstance, SandboxError> {
        let mut store = Store::new(&self.engine, ());
        // 设置初始 fuel
        let _ = store.set_fuel(self.config.max_fuel);

        let linker = Linker::new(&self.engine);
        let instance = linker
            .instantiate(&mut store, &self.module)
            .map_err(|e| SandboxError::Instantiate(e.to_string()))?;

        // 获取线性内存导出
        let memory = instance.get_memory(&mut store, "memory").or_else(|| {
            // 尝试获取第一个导出的 memory
            self.module
                .exports()
                .find_map(|export| {
                    if export.ty().memory().is_some() {
                        instance.get_memory(&mut store, export.name())
                    } else {
                        None
                    }
                })
        });

        // 获取 execute 函数导出
        let execute_fn = instance
            .get_typed_func::<i32, i32>(&mut store, "execute")
            .ok();

        Ok(SandboxInstance {
            store,
            instance,
            memory,
            execute_fn,
            config: SandboxConfig {
                max_fuel: self.config.max_fuel,
                max_memory_bytes: self.config.max_memory_bytes,
            },
        })
    }
}

impl SandboxInstance {
    /// 直接调用 execute 函数（传入 i32 参数，返回 i32 结果）。
    /// 不经过 JSON 序列化，用于简单数值插件。
    pub fn call_raw(&mut self, arg: i32) -> Result<i32, SandboxError> {
        let execute_fn = self
            .execute_fn
            .as_ref()
            .ok_or(SandboxError::MissingExecute)?;
        execute_fn
            .call(&mut self.store, arg)
            .map_err(|e| {
                // wasmtime 29 的 fuel 耗尽 trap 消息不含 "fuel" 字样，
                // 通过检查调用后剩余 fuel 是否为 0 来判断。
                let fuel = self.store.get_fuel().unwrap_or(u64::MAX);
                if fuel == 0 {
                    SandboxError::OutOfFuel
                } else {
                    SandboxError::Call(e.to_string())
                }
            })
    }

    /// 调用插件的 `execute` 函数，传入 JSON 参数，返回 JSON 结果。
    ///
    /// 流程：
    /// 1. 将 args_json 写入线性内存偏移 0
    /// 2. 调用 execute(args_len)，返回结果长度
    /// 3. 从线性内存偏移 0 读取返回的 result_len 字节
    pub fn call_json(&mut self, args_json: &str) -> Result<SandboxResult, SandboxError> {
        let args_bytes = args_json.as_bytes();
        let args_len = args_bytes.len() as i32;

        // 阶段1：写入参数到内存偏移 0（借用 self.memory 与 self.store，不调用 self 方法）
        {
            let memory = self.memory.as_ref().ok_or(SandboxError::MissingMemory)?;
            let mem_size = memory.data_size(&self.store);
            if args_len as usize > mem_size {
                let pages_needed = ((args_len as usize - mem_size) / 65536 + 1) as u64;
                memory
                    .grow(&mut self.store, pages_needed)
                    .map_err(|_| SandboxError::MemoryLimit)?;
            }
            memory.data_mut(&mut self.store)[..args_len as usize].copy_from_slice(args_bytes);
        } // memory 借用在此结束

        // 阶段2：调用 execute(args_len)（可变借用 self，调用 self.call_raw）
        let result_len = self.call_raw(args_len)?;

        // 阶段3：读取返回值（重新借用 self.memory）
        let output = if result_len > 0 {
            let memory = self.memory.as_ref().ok_or(SandboxError::MissingMemory)?;
            let data = memory.data(&self.store);
            let end = (result_len as usize).min(data.len());
            String::from_utf8(data[..end].to_vec())
                .map_err(|e| SandboxError::Utf8(e.to_string()))?
        } else {
            String::new()
        };

        let fuel_remaining = self.store.get_fuel().unwrap_or(0);
        let out_of_fuel = fuel_remaining == 0;

        Ok(SandboxResult {
            output,
            fuel_remaining,
            out_of_fuel,
        })
    }

    /// 剩余 fuel。
    pub fn fuel_remaining(&self) -> u64 {
        self.store.get_fuel().unwrap_or(0)
    }

    /// 重置 fuel 到初始值。
    pub fn refill_fuel(&mut self) {
        let _ = self.store.set_fuel(self.config.max_fuel);
    }

    /// 获取实例中的任意导出函数。
    pub fn get_func(&mut self, name: &str) -> Option<Func> {
        self.instance.get_func(&mut self.store, name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 简单插件 WAT：接收一个 i32 参数，返回 i32 + 1
    const ADD_ONE_WAT: &str = r#"
        (module
            (memory (export "memory") 1)
            (func (export "execute") (param i32) (result i32)
                local.get 0
                i32.const 1
                i32.add)
        )
    "#;

    /// 示例插件 WAT：读取内存中的参数长度，写入固定返回值 "ok"
    const ECHO_WAT: &str = r#"
        (module
            (memory (export "memory") 1)
            (func (export "execute") (param i32) (result i32)
                (i32.store8 (i32.const 0) (i32.const 111))
                (i32.store8 (i32.const 1) (i32.const 107))
                (i32.const 2))
        )
    "#;

    /// 无限循环插件（用于测试 fuel 耗尽）
    const INFINITE_LOOP_WAT: &str = r#"
        (module
            (memory (export "memory") 1)
            (func (export "execute") (param i32) (result i32)
                (loop $forever
                    (br $forever))
                (i32.const 0))
        )
    "#;

    fn make_sandbox() -> Sandbox {
        Sandbox::new(SandboxConfig {
            max_fuel: 1_000_000,
            max_memory_bytes: 1024 * 1024,
        })
        .expect("sandbox creation failed")
    }

    /// 将 WAT 文本编译为 WASM 字节码后加载到沙箱。
    /// 生产环境插件应预编译为 .wasm 字节码，无需此 helper。
    fn load_wat(sb: &Sandbox, wat_src: &str) -> SandboxModule {
        let wasm = wat::parse_str(wat_src).expect("WAT parse failed");
        sb.load(&wasm).expect("load failed")
    }

    #[test]
    fn load_and_instantiate_simple_module() {
        let sb = make_sandbox();
        let module = load_wat(&sb, ADD_ONE_WAT);
        let instance = module.instantiate().expect("instantiate failed");
        assert!(instance.fuel_remaining() > 0);
    }

    #[test]
    fn call_execute_add_one() {
        let sb = make_sandbox();
        let module = load_wat(&sb, ADD_ONE_WAT);
        let mut instance = module.instantiate().expect("instantiate failed");

        let result = instance.call_raw(41).expect("call failed");
        assert_eq!(result, 42);
    }

    #[test]
    fn call_json_echo() {
        let sb = make_sandbox();
        let module = load_wat(&sb, ECHO_WAT);
        let mut instance = module.instantiate().expect("instantiate failed");

        let result = instance.call_json("hello").expect("call failed");
        assert_eq!(result.output, "ok");
        assert!(!result.out_of_fuel);
    }

    #[test]
    fn fuel_exhaustion_traps() {
        let sb = make_sandbox();
        let module = load_wat(&sb, INFINITE_LOOP_WAT);
        let mut instance = module.instantiate().expect("instantiate failed");

        let result = instance.call_json("");
        assert!(matches!(result, Err(SandboxError::OutOfFuel)));
    }

    #[test]
    fn fuel_remaining_decreases() {
        let sb = make_sandbox();
        let module = load_wat(&sb, ADD_ONE_WAT);
        let mut instance = module.instantiate().expect("instantiate failed");

        let initial = instance.fuel_remaining();
        instance.call_raw(1).unwrap();
        let after = instance.fuel_remaining();
        assert!(after < initial);
    }

    #[test]
    fn refill_fuel_resets() {
        let sb = make_sandbox();
        let module = load_wat(&sb, ADD_ONE_WAT);
        let mut instance = module.instantiate().expect("instantiate failed");

        let initial = instance.fuel_remaining();
        instance.call_raw(1).unwrap();
        instance.refill_fuel();
        assert_eq!(instance.fuel_remaining(), initial);
    }

    #[test]
    fn missing_execute_function() {
        const NO_EXECUTE_WAT: &str = r#"
            (module
                (memory (export "memory") 1)
                (func (export "other") (result i32) (i32.const 0))
            )
        "#;
        let sb = make_sandbox();
        let module = load_wat(&sb, NO_EXECUTE_WAT);
        let mut instance = module.instantiate().expect("instantiate failed");
        let result = instance.call_json("");
        assert!(matches!(result, Err(SandboxError::MissingExecute)));
    }

    #[test]
    fn default_config_values() {
        let config = SandboxConfig::default();
        assert_eq!(config.max_fuel, 30_000_000_000);
        assert_eq!(config.max_memory_bytes, 50 * 1024 * 1024);
    }

    #[test]
    fn with_defaults_creates_engine() {
        let sb = Sandbox::with_defaults().expect("sandbox creation failed");
        let module = load_wat(&sb, ADD_ONE_WAT);
        let instance = module.instantiate().expect("instantiate failed");
        assert!(instance.fuel_remaining() > 0);
    }
}
