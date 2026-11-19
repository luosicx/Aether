package com.aether.ui.chat

/**
 * 流式文本节流器：把 token 级增量合并为最多每 [intervalNanos] 一次的快照。
 *
 * 没有它时每个 token 都要把整段文本 toString 一次并刷新一次 UI，
 * 长回复会持续重组整屏。窗口内的增量只累积，到期后的下一次追加才返回快照。
 */
class StreamingTextThrottler(
    private val intervalNanos: Long = DEFAULT_INTERVAL_NANOS,
    private val nowNanos: () -> Long = { System.nanoTime() }
) {
    companion object {
        /** 与 Apple 端 / Windows 端一致的 100ms */
        const val DEFAULT_INTERVAL_NANOS = 100_000_000L
    }

    private val buffer = StringBuilder()
    private var lastEmitNanos = Long.MIN_VALUE / 2

    /** 追加一段增量；到达节流窗口时返回完整快照，否则返回 null。 */
    fun append(chunk: String): String? {
        buffer.append(chunk)
        val now = nowNanos()
        if (now - lastEmitNanos >= intervalNanos) {
            lastEmitNanos = now
            return buffer.toString()
        }
        return null
    }

    /** 返回累积的完整文本（包含尚未到节流窗口的尾部）。 */
    fun flush(): String = buffer.toString()
}
