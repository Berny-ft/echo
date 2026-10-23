package com.echo.whisper

import java.io.Closeable

/** A loaded whisper.cpp model. Not thread-safe: call [transcribe] from one thread at a time. */
class WhisperContext private constructor(private var ptr: Long) : Closeable {

    /** [samples] is 16 kHz mono float PCM. [language] is an ISO code or "auto". */
    fun transcribe(samples: FloatArray, language: String, prompt: String = "", threads: Int = defaultThreads()): String {
        check(ptr != 0L) { "WhisperContext is closed" }
        return nativeTranscribe(ptr, samples, language, prompt, threads).trim()
    }

    override fun close() {
        if (ptr != 0L) nativeFree(ptr)
        ptr = 0L
    }

    companion object {
        init { System.loadLibrary("echowhisper") }

        fun load(path: String): WhisperContext {
            val ptr = nativeInit(path)
            require(ptr != 0L) { "Couldn't load Whisper model at $path" }
            return WhisperContext(ptr)
        }

        /** Big cores only: on Tensor chips the little cores slow the whole batch down. */
        fun defaultThreads(): Int = Runtime.getRuntime().availableProcessors().coerceAtMost(8).let { if (it >= 8) 4 else it.coerceAtLeast(2) }

        @JvmStatic private external fun nativeInit(path: String): Long
        @JvmStatic private external fun nativeFree(ptr: Long)
        @JvmStatic private external fun nativeTranscribe(ptr: Long, samples: FloatArray, language: String, prompt: String, threads: Int): String
    }
}
