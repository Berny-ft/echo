package com.echo.dictation.engine

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.math.sqrt

/**
 * Captures 16 kHz mono audio (Whisper's native rate) on its own thread.
 * Samples accumulate in [buffer]; [onLevel] gets a 0–1 loudness value ~30 times a second.
 */
class AudioRecorder(private val onLevel: (Float) -> Unit) {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false
    private val buffer = FloatBuffer()

    val sampleCount: Int get() = buffer.size

    @SuppressLint("MissingPermission") // Checked by the caller before starting.
    fun start() {
        buffer.clear()
        val minSize = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, maxOf(minSize, RATE / 2 * 4),
        )
        check(rec.state == AudioRecord.STATE_INITIALIZED) { "Microphone unavailable" }
        rec.startRecording()
        record = rec
        running = true
        thread = Thread({
            val chunk = FloatArray(RATE / 30)
            while (running) {
                val n = rec.read(chunk, 0, chunk.size, AudioRecord.READ_BLOCKING)
                if (n <= 0) continue
                buffer.append(chunk, n)
                var sum = 0f
                for (i in 0 until n) sum += chunk[i] * chunk[i]
                onLevel((sqrt(sum / n) * 12f).coerceIn(0f, 1f))
            }
        }, "echo-audio").apply { priority = Thread.MAX_PRIORITY; start() }
    }

    /** Stops capture and returns the whole recording. */
    fun stop(): FloatArray {
        running = false
        thread?.join(500)
        thread = null
        record?.run { runCatching { stop() }; release() }
        record = null
        return buffer.takeFrom(0)
    }

    /** Copies samples from [from] to now, without stopping. */
    fun snapshot(from: Int): FloatArray = buffer.copyRange(from, buffer.size)

    companion object { const val RATE = 16_000 }
}

/** Growable float array shared between the audio thread and readers. */
private class FloatBuffer {
    private var data = FloatArray(AudioRecorder.RATE * 30)
    @Volatile var size = 0
        private set

    @Synchronized fun append(src: FloatArray, n: Int) {
        if (size + n > data.size) data = data.copyOf(maxOf(data.size * 2, size + n))
        System.arraycopy(src, 0, data, size, n)
        size += n
    }

    @Synchronized fun copyRange(from: Int, to: Int): FloatArray = data.copyOfRange(from.coerceIn(0, size), to.coerceIn(0, size))
    @Synchronized fun takeFrom(from: Int): FloatArray = copyRange(from, size)
    @Synchronized fun clear() { size = 0 }
}
