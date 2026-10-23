package com.echo.dictation.ui

import android.util.Log
import com.echo.dictation.EchoApp
import com.echo.dictation.engine.Audio
import com.echo.dictation.model.Catalog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Runs a WAV file (16 kHz mono 16-bit) through the real pipeline and logs timings under "EchoSelfTest". */
object SelfTest {
    private const val TAG = "EchoSelfTest"

    suspend fun run(app: EchoApp, path: String) = withContext(Dispatchers.Default) {
        runCatching {
            val samples = readWav(File(path))
            val s = app.prefs.current
            val speech = app.models.pathIfReady(s.speechModel) ?: error("speech model ${s.speechModel} not downloaded")
            var t = System.currentTimeMillis()
            app.transcriber.ensureLoaded(speech)
            Log.i(TAG, "whisper load ${System.currentTimeMillis() - t} ms")
            t = System.currentTimeMillis()
            val lang = if (Catalog.find(s.speechModel)?.englishOnly == true) "en" else s.language
            val raw = app.transcriber.transcribe(Audio.trimSilence(samples), lang, s.vocabulary.joinToString(", "))
            Log.i(TAG, "transcribe ${samples.size / 16000.0}s audio: ${System.currentTimeMillis() - t} ms\nRAW: $raw")
            t = System.currentTimeMillis()
            val (text, engine) = app.dictation.format(raw)
            Log.i(TAG, "format via $engine: ${System.currentTimeMillis() - t} ms\nOUT: $text")
            t = System.currentTimeMillis()
            val (text2, _) = app.dictation.format(raw)
            Log.i(TAG, "format again (warm): ${System.currentTimeMillis() - t} ms\nOUT2: $text2")
        }.onFailure { Log.e(TAG, "self-test failed", it) }
    }

    private fun readWav(f: File): FloatArray {
        val bytes = f.readBytes()
        // Find the "data" chunk rather than assuming a 44-byte header.
        var i = 12
        while (i + 8 <= bytes.size) {
            val id = String(bytes, i, 4)
            val len = ByteBuffer.wrap(bytes, i + 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
            if (id == "data") {
                val sb = ByteBuffer.wrap(bytes, i + 8, minOf(len, bytes.size - i - 8)).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                return FloatArray(sb.remaining()) { sb.get(it) / 32768f }
            }
            i += 8 + len
        }
        error("no data chunk in $f")
    }
}
