//! Android JNI 绑定（仅 Android target 编译）。
//!
//! jni 0.21 生命周期模型：JNIEnv<'local> 的 'local 代表 local reference frame，
//! new_string 返回 JString<'local>。JNI 导出函数返回 Java 对象时用 into_raw()
//! 转为原始 jstring 指针（所有权转移给 JVM），规避 'static 约束。

use jni::objects::{JClass, JString};
use jni::JNIEnv;

use aether_core::{parse_chunk, redact};

/// 创建 JString 并转为原始 jstring 指针（所有权转移给 JVM）。
/// 分配失败返回 null。
fn new_jstring(env: &mut JNIEnv, s: &str) -> jni::sys::jstring {
    match env.new_string(s) {
        Ok(js) => js.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 解析单行 SSE（无状态），返回 `{"content": <Option>}` 的 JSON 串；
/// 非 data 行 / 解析失败返回空串。
///
/// 早期实现用 thread_local 累积器跨 chunk 累积 tool_calls：协程在挂起点后可能
/// 恢复到另一个线程，累积状态会串流（上一轮 tool_calls 残留到下一轮）且永不释放；
/// Android 侧只消费 content，故改为与 C ABI `aether_sse_parse_chunk` 一致的无状态解析。
#[no_mangle]
pub extern "system" fn Java_com_aether_rust_SseBridge_parseChunk(
    mut env: JNIEnv,
    _class: JClass,
    line: JString,
) -> jni::sys::jstring {
    let line: String = match env.get_string(&line) {
        Ok(s) => s.into(),
        Err(_) => return new_jstring(&mut env, ""),
    };
    match parse_chunk(&line) {
        Some(content) => serde_json::to_string(&serde_json::json!({ "content": content }))
            .map(|j| new_jstring(&mut env, &j))
            .unwrap_or_else(|_| new_jstring(&mut env, "")),
        None => new_jstring(&mut env, ""),
    }
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

/// 对输入字符串脱敏（UUID/邮箱/URL/Token/凭证字段/路径）。
///
/// 对应 Kotlin `com.aether.rust.Redact.redact`，调用 `aether_core::redact`。
/// 入参 `input` 为 Java String，返回脱敏后的 Java String。
/// 解析失败时返回空串（不抛 Java 异常）。
#[no_mangle]
pub extern "system" fn Java_com_aether_rust_Redact_redact(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jni::sys::jstring {
    let s: String = match env.get_string(&input) {
        Ok(s) => s.into(),
        Err(_) => return new_jstring(&mut env, ""),
    };
    let redacted = redact(&s);
    new_jstring(&mut env, &redacted)
}
