package com.echo.dictation.engine

import kotlin.math.sqrt

/** Small signal-processing helpers on 16 kHz mono float audio. */
object Audio {
    private const val FRAME = AudioRecorder.RATE / 50 // 20 ms

    private fun rms(s: FloatArray, from: Int, to: Int): Float {
        var sum = 0f
        for (i in from until to) sum += s[i] * s[i]
        return sqrt(sum / maxOf(1, to - from))
    }

    /** Speech threshold relative to the clip's own noise floor, so it adapts to quiet rooms and loud streets. */
    private fun threshold(s: FloatArray): Float {
        val frames = (0 until s.size / FRAME).map { rms(s, it * FRAME, (it + 1) * FRAME) }.sorted()
        if (frames.isEmpty()) return 0.01f
        val floor = frames[frames.size / 10]
        return maxOf(floor * 3f, 0.006f)
    }

    fun hasSpeech(s: FloatArray): Boolean {
        val t = threshold(s)
        var loud = 0
        for (f in 0 until s.size / FRAME) if (rms(s, f * FRAME, (f + 1) * FRAME) > t) loud++
        return loud >= 8 // ~160 ms of voice
    }

    /**
     * Shortens every pause longer than [maxPauseSec] to that length. Whisper is faster on less
     * audio and hallucinates less on long stretches of silence.
     */
    fun trimSilence(s: FloatArray, maxPauseSec: Float = 1.0f): FloatArray {
        if (s.size < FRAME * 10) return s
        val t = threshold(s)
        val maxPause = (maxPauseSec * 50).toInt()
        val out = FloatArray(s.size)
        var n = 0
        var quietRun = 0
        for (f in 0 until s.size / FRAME) {
            val from = f * FRAME
            if (rms(s, from, from + FRAME) > t) quietRun = 0 else quietRun++
            if (quietRun <= maxPause) {
                System.arraycopy(s, from, out, n, FRAME)
                n += FRAME
            }
        }
        return out.copyOf(n)
    }

    /** Index of the quietest 300 ms window in [from, to), for cutting long recordings between words. */
    fun quietestPoint(s: FloatArray, from: Int, to: Int): Int {
        val win = AudioRecorder.RATE * 3 / 10
        var best = to
        var bestRms = Float.MAX_VALUE
        var i = from
        while (i + win <= to) {
            val r = rms(s, i, i + win)
            if (r < bestRms) { bestRms = r; best = i + win / 2 }
            i += FRAME
        }
        return best
    }
}
