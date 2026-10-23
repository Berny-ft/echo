package com.echo.dictation.engine

import android.util.Log
import com.echo.dictation.EchoApp
import com.echo.dictation.model.Catalog
import com.echo.dictation.model.HistoryItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

sealed interface DictationState {
    data object Idle : DictationState
    data object Preparing : DictationState
    data class Recording(val startedAt: Long) : DictationState
    data object Processing : DictationState
    data class Done(val text: String) : DictationState
    data class Error(val message: String) : DictationState
}

/** Where the dictated text should go; implemented by the accessibility service. */
interface TextTarget {
    val targetPackage: String?
    val targetApp: String?
    /** Inserts at the cursor of the focused field. Returns false if nothing could take the text. */
    fun insert(text: String): Boolean
}

/**
 * Runs one dictation: record → transcribe (in ~25 s chunks while still recording, so long
 * dictations finish fast) → clean up → optionally rewrite with the local model → insert.
 */
class DictationController(private val app: EchoApp) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val _state = MutableStateFlow<DictationState>(DictationState.Idle)
    val state: StateFlow<DictationState> = _state
    private val _level = MutableStateFlow(0f)
    val level: StateFlow<Float> = _level

    private val recorder = AudioRecorder { _level.value = it }
    private var chunker: Job? = null
    private var chunkJobs = mutableListOf<Deferred<String>>()
    private var cutAt = 0
    private var target: TextTarget? = null
    private var packageName: String? = null
    private var appName: String? = null
    private var preload: Job? = null

    val isBusy: Boolean get() = _state.value !is DictationState.Idle && _state.value !is DictationState.Done && _state.value !is DictationState.Error

    fun toggle(target: TextTarget?) {
        when (_state.value) {
            is DictationState.Recording -> stop()
            DictationState.Preparing, DictationState.Processing -> Unit
            else -> start(target)
        }
    }

    fun start(target: TextTarget?) {
        if (isBusy) return
        val settings = app.prefs.current
        val speechPath = app.models.pathIfReady(settings.speechModel)
        if (speechPath == null) {
            fail("Download a speech model in Echo first")
            return
        }
        this.target = target
        packageName = target?.targetPackage
        appName = target?.targetApp
        try {
            recorder.start()
        } catch (e: Exception) {
            fail(e.message ?: "Microphone unavailable")
            return
        }
        _state.value = DictationState.Recording(System.currentTimeMillis())
        cutAt = 0
        chunkJobs = mutableListOf()

        // Load models and process the formatting instructions while the user is still speaking.
        preload = scope.launch {
            runCatching { app.transcriber.ensureLoaded(speechPath) }.onFailure { Log.e(TAG, "whisper load", it) }
            val llmPath = app.models.pathIfReady(settings.formatterModel)
            if (llmPath != null) runCatching {
                app.formatter.ensureLoaded(llmPath)
                app.formatter.prewarm(TextFormatter.systemPrompt(TextFormatter.resolvedStyle(context()), context()))
            }.onFailure { Log.e(TAG, "llm load", it) }
        }
        chunker = scope.launch { chunkWhileRecording() }
    }

    fun stop() {
        if (_state.value !is DictationState.Recording) return
        chunker?.cancel()
        val audio = recorder.stop()
        _level.value = 0f
        _state.value = DictationState.Processing
        scope.launch { finish(audio) }
    }

    fun cancel() {
        chunker?.cancel()
        if (_state.value is DictationState.Recording) recorder.stop()
        _level.value = 0f
        _state.value = DictationState.Idle
    }

    private suspend fun chunkWhileRecording() {
        val chunk = AudioRecorder.RATE * 25
        while (scope.isActive) {
            delay(1000)
            if (recorder.sampleCount - cutAt < chunk + AudioRecorder.RATE * 5) continue
            val tail = recorder.snapshot(cutAt)
            val cut = Audio.quietestPoint(tail, chunk, chunk + AudioRecorder.RATE * 5)
            val piece = tail.copyOf(cut)
            cutAt += cut
            chunkJobs.add(scope.async { transcribePiece(piece) })
        }
    }

    private suspend fun transcribePiece(samples: FloatArray): String {
        preload?.join()
        if (!Audio.hasSpeech(samples)) return ""
        val s = app.prefs.current
        val lang = if (Catalog.find(s.speechModel)?.englishOnly == true) "en" else s.language
        return app.transcriber.transcribe(Audio.trimSilence(samples), lang, s.vocabulary.joinToString(", "))
    }

    private suspend fun finish(audio: FloatArray) {
        val t0 = System.currentTimeMillis()
        try {
            val rest = audio.copyOfRange(cutAt.coerceAtMost(audio.size), audio.size)
            val pieces = chunkJobs.awaitAll() + transcribePiece(rest)
            val raw = pieces.filter { it.isNotBlank() }.joinToString(" ").trim()
            if (raw.isEmpty()) {
                fail("Didn't catch that")
                return
            }
            val (text, engine) = format(raw)
            if (text.isEmpty()) {
                fail("Didn't catch that")
                return
            }
            val inserted = target?.insert(text) ?: false
            if (!inserted) app.copyToClipboard(text)
            val ms = System.currentTimeMillis() - t0
            Log.i(TAG, "dictation: ${audio.size / 16000.0}s audio, processed in $ms ms via $engine")
            app.history.add(HistoryItem(System.currentTimeMillis(), text, raw, engine, appName, audio.size / 16000.0, ms))
            _state.value = DictationState.Done(if (inserted) text else "Copied: $text")
        } catch (e: Exception) {
            Log.e(TAG, "dictation failed", e)
            fail(e.message ?: "Something went wrong")
        }
        scope.launch { delay(1200); if (_state.value is DictationState.Done) _state.value = DictationState.Idle }
    }

    /** Public for the self-test: formats an already-transcribed string the same way a dictation would. */
    suspend fun format(raw: String): Pair<String, String> {
        val c = context()
        val style = TextFormatter.resolvedStyle(c)
        val cleaned = TextFormatter.applyReplacements(TextFormatter.basicCleanup(raw), c.replacements)
        if (cleaned.isEmpty()) return "" to "none"

        val llmPath = app.models.pathIfReady(app.prefs.current.formatterModel)
        if (llmPath == null || !TextFormatter.wantsModel(cleaned, style)) {
            return TextFormatter.finalize(cleaned, style) to "Basic cleanup"
        }
        runCatching { app.formatter.ensureLoaded(llmPath) }.onFailure {
            return TextFormatter.finalize(cleaned, style) to "Basic cleanup (model failed to load)"
        }
        val maxTokens = (cleaned.length / 2 + 64).coerceAtMost(1024)
        val out = app.formatter.rewrite(TextFormatter.systemPrompt(style, c), TextFormatter.userPrompt(cleaned), maxTokens)
            ?.let { TextFormatter.sanitize(it) }
        val label = Catalog.find(app.prefs.current.formatterModel)?.title ?: "Local model"
        return when {
            out == null -> TextFormatter.finalize(cleaned, style) to "Basic cleanup (model timed out)"
            TextFormatter.isPlausible(out, cleaned, style) -> TextFormatter.applyReplacements(out, c.replacements) to label
            else -> TextFormatter.finalize(cleaned, style) to "Basic cleanup (model output rejected)"
        }
    }

    private fun context(): TextFormatter.Context {
        val s = app.prefs.current
        return TextFormatter.Context(s.style, packageName, appName, s.vocabulary, s.replacements)
    }

    private fun fail(message: String) {
        _state.value = DictationState.Error(message)
        scope.launch { delay(2500); if (_state.value is DictationState.Error) _state.value = DictationState.Idle }
    }

    private companion object { const val TAG = "EchoDictation" }
}
