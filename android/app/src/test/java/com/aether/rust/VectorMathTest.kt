package com.aether.rust

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * VectorMath 单元测试。
 *
 * 纯 JVM 测试环境中 JNI 不可用，nativeLoaded = false，cosineF64Safe 回退返回 0.0。
 */
class VectorMathTest {

    @Test
    fun cosineF64SafeReturnsZeroWhenJniUnavailable() {
        val a = doubleArrayOf(1.0, 2.0, 3.0)
        val b = doubleArrayOf(4.0, 5.0, 6.0)
        val result = VectorMath.cosineF64Safe(a, b)
        assertEquals(0.0, result, 0.0001)
    }

    @Test
    fun cosineF64SafeReturnsZeroForEmptyArrays() {
        val result = VectorMath.cosineF64Safe(doubleArrayOf(), doubleArrayOf())
        assertEquals(0.0, result, 0.0001)
    }

    @Test
    fun cosineF64SafeReturnsZeroForDifferentLengths() {
        val a = doubleArrayOf(1.0, 2.0)
        val b = doubleArrayOf(1.0, 2.0, 3.0)
        val result = VectorMath.cosineF64Safe(a, b)
        // JNI 不可用返回 0.0；JNI 可用时长度不等也返回 0.0
        assertEquals(0.0, result, 0.0001)
    }
}
