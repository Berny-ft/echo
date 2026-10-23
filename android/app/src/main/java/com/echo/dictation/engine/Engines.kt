package com.echo.dictation.engine

import android.util.Log
import com.echo.llm.LlmSession
import com.echo.whisper.WhisperContext
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.Executors

/** Owns the Whisper model. All work runs on one dedicated thread, in submission order. */
class Transcriber {
    val dispatcher = Executors.newSingleThreadExecutor { Thread(it, "echo-whisper") }.asCoroutineDispatcher()
    private var ctx: WhisperContext? = null
    private var loadedPath: String? = null

    suspend fun ensureLoaded(path: String) = withContext(dispatcher) {
        if (loadedPath == path && ctx != null) return@withContext
        ctx?.close()
        ctx = null
        loadedPath = null
        val t0 = System.currentTimeMillis()
        ctx = WhisperContext.load(path)
        loadedPath = path
        Log.i(TAG, "Whisper model loaded in ${System.currentTimeMillis() - t0} ms")
    }

    suspend fun transcribe(samples: FloatArray, language: String, prompt: String): String = withContext(dispatcher) {
        val c = ctx ?: error("Speech model isn't loaded")
        if (samples.size < AudioRecorder.RATE / 4) "" else c.transcribe(samples, language, prompt)
    }

    suspend fun unload() = withContext(dispatcher) {
        ctx?.close()
        ctx = null
        loadedPath = null
    }

    private companion object { const val TAG = "EchoTranscriber" }
}

/** Owns the optional formatting model, on its own thread so it can prewarm while Whisper works. */
class Formatter {
    private val dispatcher = Executors.newSingleThreadExecutor { Thread(it, "echo-llm") }.asCoroutineDispatcher()
    private var session: LlmSession? = null
    private var loadedPath: String? = null

    val isLoaded: Boolean get() = session != null

    suspend fun ensureLoaded(path: String) = withContext(dispatcher) {
        if (loadedPath == path && session != null) return@withContext
        session?.close()
        session = null
        loadedPath = null
        val t0 = System.currentTimeMillis()
        session = LlmSession.load(path, threads = 4, contextSize = 4096)
        loadedPath = path
        Log.i(TAG, "Formatting model loaded in ${System.currentTimeMillis() - t0} ms")
    }

    suspend fun prewarm(system: String) = withContext(dispatcher) { session?.prewarm(system) }

    /** Returns the model's rewrite, or null on failure or after [timeoutMs]. */
    suspend fun rewrite(system: String, user: String, maxTokens: Int, timeoutMs: Long = 25_000): String? {
        val s = session ?: return null
        return coroutineScope {
            val timer = launch { delay(timeoutMs); s.cancel() }
            withContext(dispatcher) { s.generate(system, user, maxTokens) }.also { timer.cancel() }
        }
    }

    suspend fun unload() = withContext(dispatcher) {
        session?.close()
        session = null
        loadedPath = null
    }

    private companion object { const val TAG = "EchoFormatter" }
}
