//! Android JNI 绑定（仅 Android target 编译）。

use jni::objects::{JClass, JObject, JString};
use jni::JNIEnv;
use std::collections::BTreeMap;

use aether_core::{parse_with_tool_accumulation, AccumulatedToolCall};

// 全局累积器（thread-local）。生产应改为 per-Instance 字段，
// 此处用 thread-local 兜底，符合"首个落地单元"的最小可行原则。
thread_local! {
    static ACC: std::cell::RefCell<BTreeMap<i64, AccumulatedToolCall>> =
        std::cell::RefCell::new(BTreeMap::new());
}

#[no_mangle]
pub extern "system" fn Java_com_aether_rust_SseBridge_parseWithTools(
    mut env: JNIEnv,
    _class: JClass,
    line: JString,
) -> JString<'static> {
    let line: String = match env.get_string(&line) {
        Ok(s) => s.into(),
        Err(_) => return env.new_string("").unwrap_or(JObject::null().into()),
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
        Some(j) => env.new_string(j).unwrap_or(JObject::null().into()),
        None => env.new_string("").unwrap_or(JObject::null().into()),
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
    // get_double_array_elements 返回 AutoElements，Deref 到 &[jdouble]，
    // drop 时自动 release，无需手动 unsafe。
    let result = (|| {
        let a_arr = env
            .get_double_array_elements(a, jni::objects::JObject::null())
            .ok()?;
        let b_arr = env
            .get_double_array_elements(b, jni::objects::JObject::null())
            .ok()?;
        Some(aether_core::cosine_similarity_f64(&a_arr, &b_arr))
    })();
    result.unwrap_or(0.0)
}
