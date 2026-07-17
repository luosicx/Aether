package com.aether.rust

/**
 * Rust 向量数学桥接：通过 JNI 调用 `aether-core-ffi` 的余弦相似度计算。
 *
 * 对应 Rust 导出函数：`Java_com_aether_rust_VectorMath_cosineF64`。
 *
 * 库加载失败（纯 JVM 测试环境）时 [nativeLoaded] 为 false，[cosineF64Safe] 返回 0.0。
 */
object VectorMath {
    // 不用 init { System.loadLibrary }：init 抛 UnsatisfiedLinkError 会导致对象
    // 永久初始化失败（后续访问抛 NoClassDefFoundError），safe 包装无法生效。
    private val nativeLoaded: Boolean = try {
        System.loadLibrary("aether_core_ffi")
        true
    } catch (e: UnsatisfiedLinkError) {
        false
    }

    /**
     * 计算两个向量的余弦相似度。长度不等或空数组返回 0.0。
     */
    external fun cosineF64(a: DoubleArray, b: DoubleArray): Double

    /**
     * 安全版本：JNI 不可用或异常时返回 0.0。供无 .so 产物的回退场景使用。
     */
    fun cosineF64Safe(a: DoubleArray, b: DoubleArray): Double {
        if (!nativeLoaded) return 0.0
        return try {
            cosineF64(a, b)
        } catch (e: UnsatisfiedLinkError) {
            0.0
        }
    }
}
