package com.echo.dictation.overlay

import android.Manifest
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.Toast
import com.echo.dictation.EchoApp
import com.echo.dictation.R
import com.echo.dictation.engine.DictationState
import com.echo.dictation.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * Keeps the floating bubble on screen and holds the microphone. It runs as a foreground
 * service started while Echo is open, which is what lets it record later from any app.
 */
class OverlayService : Service() {
    private val app get() = application as EchoApp
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var wm: WindowManager
    private lateinit var bubble: BubbleView
    private lateinit var params: WindowManager.LayoutParams
    private var attached = false
    private var lastError: String? = null

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        running = true
        wm = getSystemService(WindowManager::class.java)
        startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        bubble = BubbleView(this)
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            // Never take focus: the text field in the app underneath must keep it.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val screen = wm.currentWindowMetrics.bounds
            x = app.prefs.bubbleX.takeIf { it >= 0 } ?: (screen.width() - bubble.sizePx - 16)
            y = app.prefs.bubbleY.takeIf { it >= 0 } ?: (screen.height() * 0.32f).toInt()
        }
        setupTouch()

        scope.launch {
            combine(app.dictation.state, EchoAccessibilityService.editing, app.prefs.state) { state, editing, settings ->
                bubble.state = state
                if (state is DictationState.Error && state.message != lastError) {
                    Toast.makeText(this@OverlayService, state.message, Toast.LENGTH_SHORT).show()
                }
                lastError = (state as? DictationState.Error)?.message
                val serviceOn = EchoAccessibilityService.instance != null
                val active = state !is DictationState.Idle
                settings.bubbleEnabled && (active || !settings.onlyWhenTyping || !serviceOn || editing)
            }.collect { visible -> setVisible(visible) }
        }
        scope.launch { app.dictation.level.collect { bubble.level = it } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE) {
            app.prefs.update { copy(bubbleEnabled = false) }
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        app.dictation.cancel()
        scope.cancel()
        if (attached) wm.removeView(bubble)
        super.onDestroy()
    }

    private fun setVisible(visible: Boolean) {
        if (visible && !attached) {
            bubble.alpha = 0f
            wm.addView(bubble, params)
            bubble.animate().alpha(1f).setDuration(150).start()
            attached = true
        } else if (!visible && attached) {
            attached = false
            bubble.animate().alpha(0f).setDuration(120).withEndAction { runCatching { wm.removeView(bubble) } }.start()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupTouch() {
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        val longPress = Runnable {
            if (!dragging) {
                bubble.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                dragging = true // swallow the release
            }
        }
        bubble.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = params.x; startY = params.y; dragging = false
                    v.postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong() + 200)
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!dragging && (abs(dx) > slop || abs(dy) > slop)) { dragging = true; v.removeCallbacks(longPress) }
                    if (dragging) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        if (attached) wm.updateViewLayout(bubble, params)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    v.removeCallbacks(longPress)
                    if (dragging) snapToEdge() else onTap()
                }
                MotionEvent.ACTION_CANCEL -> v.removeCallbacks(longPress)
            }
            true
        }
    }

    private fun onTap() {
        val haptics = app.prefs.current.haptics
        if (haptics) bubble.performHapticFeedback(
            if (app.dictation.state.value is DictationState.Recording) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        )
        app.dictation.toggle(EchoAccessibilityService.instance)
    }

    private fun snapToEdge() {
        val screen = wm.currentWindowMetrics.bounds
        val w = bubble.width
        val targetX = if (params.x + w / 2 < screen.width() / 2) 0 else screen.width() - w
        params.y = params.y.coerceIn(0, screen.height() - bubble.height)
        ValueAnimator.ofInt(params.x, targetX).apply {
            duration = 180
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                params.x = it.animatedValue as Int
                if (attached) wm.updateViewLayout(bubble, params)
            }
            start()
        }
        app.prefs.bubbleX = targetX
        app.prefs.bubbleY = params.y
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Echo bubble", NotificationManager.IMPORTANCE_MIN).apply {
            description = "Shown while the dictation bubble is available"
            setShowBadge(false)
        })
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val hide = PendingIntent.getService(this, 1, Intent(this, OverlayService::class.java).setAction(ACTION_HIDE), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("Echo is ready")
            .setContentText("Tap the bubble in any app to dictate")
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Hide bubble", hide).build())
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL = "bubble"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_HIDE = "com.echo.dictation.HIDE"
        @Volatile var running = false
            private set

        fun canRun(context: Context) =
            Settings.canDrawOverlays(context) &&
                context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

        /** Starts the bubble if the user turned it on. Safe to call from anywhere; failures are logged. */
        fun startIfEnabled(context: Context) {
            val app = context.applicationContext as EchoApp
            if (running || !app.prefs.current.bubbleEnabled || !canRun(context)) return
            runCatching { context.startForegroundService(Intent(context, OverlayService::class.java)) }
                .onFailure { Log.w("EchoOverlay", "couldn't start bubble service", it) }
        }

        fun stop(context: Context) = context.stopService(Intent(context, OverlayService::class.java))
    }
}
