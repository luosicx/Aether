//! Android JNI 绑定（仅 Android target 编译）。
//!
//! jni 0.21 生命周期模型：JNIEnv<'local> 的 'local 代表 local reference frame，
//! new_string 返回 JString<'local>。JNI 导出函数返回 Java 对象时用 into_raw()
//! 转为原始 jstring 指针（所有权转移给 JVM），规避 'static 约束。

use jni::objects::{JClass, JString};
use jni::JNIEnv;
use std::collections::BTreeMap;

use aether_core::{parse_with_tool_accumulation, AccumulatedToolCall};

// 全局累积器（thread-local）。生产应改为 per-Instance 字段，
// 此处用 thread-local 兜底，符合"首个落地单元"的最小可行原则。
thread_local! {
    static ACC: std::cell::RefCell<BTreeMap<i64, AccumulatedToolCall>> =
        std::cell::RefCell::new(BTreeMap::new());
}

/// 创建 JString 并转为原始 jstring 指针（所有权转移给 JVM）。
/// 分配失败返回 null。
fn new_jstring(env: &mut JNIEnv, s: &str) -> jni::sys::jstring {
    match env.new_string(s) {
        Ok(js) => js.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_aether_rust_SseBridge_parseWithTools(
    mut env: JNIEnv,
    _class: JClass,
    line: JString,
) -> jni::sys::jstring {
    let line: String = match env.get_string(&line) {
        Ok(s) => s.into(),
        Err(_) => return new_jstring(&mut env, ""),
    };
    let json = ACC.with(|acc| {
        let mut acc = acc.borrow_mut();
        parse_with_tool_accumulation(&line, &mut acc).and_then(|p| {
            serde_json::to_string(&serde_json::json!({
                "content": p.content,
                "toolCalls": p.tool_calls,
            }))
            .ok()
        })
    });
    match json {
        Some(j) => new_jstring(&mut env, &j),
        None => new_jstring(&mut env, ""),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_aether_rust_SseBridge_reset(_env: JNIEnv, _class: JClass) {
    ACC.with(|acc| acc.borrow_mut().clear());
}

/// f64 余弦相似度（Android RAG/Memory 用）。入参两个 double[]，返回 double。
#[no_mangle]
pub extern "system" fn Java_com_aether_rust_VectorMath_cosineF64(
    mut env: JNIEnv,
    _class: JClass,
    a: jni::sys::jdoubleArray,
    b: jni::sys::jdoubleArray,
) -> jni::sys::jdouble {
    // jni 0.21 API：
    // - JPrimitiveArray::<T>::from_raw 从原始 jarray 指针构造类型化数组包装
    // - JNIEnv::get_array_elements 为 unsafe，需传入 ReleaseMode，
    //   返回 AutoElements<T>（实现 Deref<Target=[T]>，可直接当 &[T] 用）
    // - 只读访问用 NoCopyBack（JNI_ABORT），避免回写开销
    use jni::objects::{JPrimitiveArray, ReleaseMode};
    use jni::sys::jdouble;
    let result = (|| {
        let a_arr = unsafe { JPrimitiveArray::<jdouble>::from_raw(a) };
        let b_arr = unsafe { JPrimitiveArray::<jdouble>::from_raw(b) };
        let a_elems = unsafe { env.get_array_elements(&a_arr, ReleaseMode::NoCopyBack) }.ok()?;
        let b_elems = unsafe { env.get_array_elements(&b_arr, ReleaseMode::NoCopyBack) }.ok()?;
        Some(aether_core::cosine_similarity_f64(&a_elems, &b_elems))
    })();
    result.unwrap_or(0.0)
}
