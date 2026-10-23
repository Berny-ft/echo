package com.echo.dictation.overlay

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.View
import android.view.animation.LinearInterpolator
import com.echo.dictation.engine.DictationState
import kotlin.math.min

/** The floating record button. Drawn by hand: cheaper than a Compose tree in an overlay window. */
class BubbleView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    val sizePx = (56 * density).toInt()
    private val margin = 8 * density

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glyph = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt(); strokeCap = Paint.Cap.ROUND }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val arc = RectF()

    var state: DictationState = DictationState.Idle
        set(value) {
            field = value
            if (value is DictationState.Processing || value is DictationState.Preparing) spinner.start() else spinner.cancel()
            invalidate()
        }

    var level = 0f
        set(value) {
            // Rise fast, fall slowly, so the bars look like speech rather than noise.
            field = if (value > field) value else field * 0.85f + value * 0.15f
            if (state is DictationState.Recording) invalidate()
        }

    private var spin = 0f
    private val spinner = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 900
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { spin = it.animatedValue as Float; invalidate() }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val s = sizePx + (2 * margin).toInt()
        setMeasuredDimension(s, s)
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val r = sizePx / 2f

        fill.color = when (state) {
            is DictationState.Recording -> 0xFFE5484D.toInt()
            is DictationState.Done -> 0xFF30A46C.toInt()
            is DictationState.Error -> 0xFFF5A524.toInt()
            else -> 0xF01E1F2B.toInt()
        }
        fill.setShadowLayer(4 * density, 0f, 1.5f * density, 0x55000000)
        canvas.drawCircle(cx, cy, r, fill)

        when (val s = state) {
            is DictationState.Recording -> {
                ring.color = 0x66E5484D
                ring.strokeWidth = 3 * density
                canvas.drawCircle(cx, cy, r + (1 + level * 6) * density, ring)
                drawBars(canvas, cx, cy, r, level)
            }
            DictationState.Processing, DictationState.Preparing -> {
                drawBars(canvas, cx, cy, r, 0f, alpha = 110)
                ring.color = 0xFFFFFFFF.toInt()
                ring.strokeWidth = 2.5f * density
                val ar = r - 5 * density
                arc.set(cx - ar, cy - ar, cx + ar, cy + ar)
                canvas.drawArc(arc, spin, 90f, false, ring)
            }
            is DictationState.Done -> {
                glyph.strokeWidth = 3.5f * density
                glyph.style = Paint.Style.STROKE
                val u = r * 0.32f
                canvas.drawLine(cx - u, cy, cx - u * 0.25f, cy + u * 0.75f, glyph)
                canvas.drawLine(cx - u * 0.25f, cy + u * 0.75f, cx + u * 1.1f, cy - u * 0.7f, glyph)
            }
            is DictationState.Error -> {
                glyph.strokeWidth = 4 * density
                glyph.style = Paint.Style.FILL
                canvas.drawLine(cx, cy - r * 0.35f, cx, cy + r * 0.08f, glyph)
                canvas.drawCircle(cx, cy + r * 0.32f, 2.3f * density, glyph)
            }
            DictationState.Idle -> drawBars(canvas, cx, cy, r, 0f)
        }
        if (state !is DictationState.Recording) return
        // Keep animating the level meter while recording.
        postInvalidateOnAnimation()
    }

    /** Five-bar waveform, the same glyph as the app icon; [amp] stretches the bars with the voice. */
    private fun drawBars(canvas: Canvas, cx: Float, cy: Float, r: Float, amp: Float, alpha: Int = 255) {
        glyph.style = Paint.Style.STROKE
        glyph.strokeWidth = 3.2f * density
        glyph.alpha = alpha
        val base = floatArrayOf(0.22f, 0.4f, 0.56f, 0.4f, 0.22f)
        val gap = r * 0.21f
        for (i in base.indices) {
            val wobble = if (amp > 0) (0.6f + 0.4f * ((i * 37 + (System.nanoTime() / 60_000_000).toInt()) % 5) / 4f) else 1f
            val h = min(r * 0.62f, r * (base[i] + amp * 0.5f * wobble))
            val x = cx + (i - 2) * gap
            canvas.drawLine(x, cy - h / 2, x, cy + h / 2, glyph)
        }
        glyph.alpha = 255
    }

    override fun onDetachedFromWindow() {
        spinner.cancel()
        super.onDetachedFromWindow()
    }
}
