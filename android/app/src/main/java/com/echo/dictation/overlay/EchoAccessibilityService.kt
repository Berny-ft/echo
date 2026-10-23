package com.echo.dictation.overlay

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.echo.dictation.engine.TextTarget
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Knows which app and text field have focus, and types dictated text into it.
 * Only reacts to focus events; it never reads or stores what's on screen.
 */
class EchoAccessibilityService : AccessibilityService(), TextTarget {

    override var targetPackage: String? = null
        private set
    override val targetApp: String?
        get() = targetPackage?.let { pkg ->
            runCatching { packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))).toString() }.getOrNull()
        }

    override fun onServiceConnected() {
        instance = this
        OverlayService.startIfEnabled(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == "com.echo.dictation" || pkg == "com.android.systemui") return
        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_FOCUSED, AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED -> {
                targetPackage = pkg
                _editing.value = event.source?.isEditable == true || focusedEditable() != null
            }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // Keyboards and our own bubble fire window events too; only real apps change the target.
                if (event.className?.toString()?.contains("InputMethod") == true) return
                targetPackage = pkg
                _editing.value = focusedEditable() != null
            }
        }
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (instance === this) instance = null
        _editing.value = false
        super.onDestroy()
    }

    private fun focusedEditable(): AccessibilityNodeInfo? =
        runCatching { findFocus(AccessibilityNodeInfo.FOCUS_INPUT) }.getOrNull()?.takeIf { it.isEditable }

    override fun insert(text: String): Boolean {
        val node = focusedEditable() ?: return false
        if (!node.isPassword && setTextAtCursor(node, text)) return true
        return paste(node, text)
    }

    /** Splices [text] in at the cursor (replacing any selection) and moves the cursor after it. */
    private fun setTextAtCursor(node: AccessibilityNodeInfo, text: String): Boolean {
        val current = if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
        var start = node.textSelectionStart
        var end = node.textSelectionEnd
        if (start < 0 || end < 0 || start > current.length || end > current.length) { start = current.length; end = current.length }
        if (start > end) start = end.also { end = start }

        val before = current.substring(0, start)
        val after = current.substring(end)
        val lead = if (before.isNotEmpty() && !before.last().isWhitespace() && !text.first().isWhitespace()) " " else ""
        val trail = if (after.isNotEmpty() && !after.first().isWhitespace() && after.first() !in ".,!?;:") " " else ""
        val insert = lead + text + trail
        val updated = before + insert + after

        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, updated) }
        if (!node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) return false

        val cursor = before.length + insert.length - trail.length
        node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, cursor)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, cursor)
        })
        // Some apps accept the action but ignore it; check the text really changed.
        node.refresh()
        return node.text?.toString()?.contains(text.take(40)) == true
    }

    private fun paste(node: AccessibilityNodeInfo, text: String): Boolean {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Echo", text))
        return node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
    }

    companion object {
        @Volatile var instance: EchoAccessibilityService? = null
            private set
        private val _editing = MutableStateFlow(false)
        /** True while a text field in another app has input focus. */
        val editing: StateFlow<Boolean> = _editing
    }
}
