package com.echo.llm

import java.io.Closeable

/**
 * A loaded llama.cpp chat model. Keeps the KV cache between calls, so a system prompt that
 * doesn't change is only processed once. Not thread-safe: use from one thread at a time.
 */
class LlmSession private constructor(private var ptr: Long) : Closeable {

    /** Pre-processes [system] so the next [generate] with the same instructions starts faster. */
    fun prewarm(system: String) {
        if (ptr != 0L) nativePrewarm(ptr, system)
    }

    /** Returns the model's reply, or null if it failed or was cancelled. */
    fun generate(system: String, user: String, maxTokens: Int): String? {
        check(ptr != 0L) { "LlmSession is closed" }
        return nativeGenerate(ptr, system, user, maxTokens)
    }

    /** Safe to call from any thread; stops a running [generate]. */
    fun cancel() {
        if (ptr != 0L) nativeCancel(ptr)
    }

    override fun close() {
        if (ptr != 0L) nativeFree(ptr)
        ptr = 0L
    }

    companion object {
        init { System.loadLibrary("echollm") }

        fun load(path: String, threads: Int = 4, contextSize: Int = 4096): LlmSession {
            val ptr = nativeLoad(path, threads, contextSize)
            require(ptr != 0L) { "Couldn't load model at $path" }
            return LlmSession(ptr)
        }

        @JvmStatic private external fun nativeLoad(path: String, threads: Int, contextSize: Int): Long
        @JvmStatic private external fun nativeFree(ptr: Long)
        @JvmStatic private external fun nativeCancel(ptr: Long)
        @JvmStatic private external fun nativePrewarm(ptr: Long, system: String)
        @JvmStatic private external fun nativeGenerate(ptr: Long, system: String, user: String, maxTokens: Int): String?
    }
}
