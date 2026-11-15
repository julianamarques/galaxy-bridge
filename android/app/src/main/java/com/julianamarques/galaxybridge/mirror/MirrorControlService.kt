package com.julianamarques.galaxybridge.mirror

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.graphics.Path
import android.graphics.PointF
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.protocol.MirrorKey
import com.julianamarques.galaxybridge.protocol.MirrorScroll
import com.julianamarques.galaxybridge.protocol.MirrorTouch

class MirrorControlService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var stroke: GestureDescription.StrokeDescription? = null
    private var last: PointF? = null
    private val pending = mutableListOf<PointF>()
    private var pendingUp = false
    private var inFlight = false
    private var scrollDelta = PointF()
    private var scrollAt: PointF? = null
    private var scrolling = false

    private val strokeDone = object : GestureResultCallback() {
        override fun onCompleted(gestureDescription: GestureDescription?) {
            inFlight = false
            flush()
        }

        override fun onCancelled(gestureDescription: GestureDescription?) {
            inFlight = false
            stroke = null
            pending.clear()
            pendingUp = false
        }
    }

    private val scrollDone = object : GestureResultCallback() {
        override fun onCompleted(gestureDescription: GestureDescription?) = scrollFinished()
        override fun onCancelled(gestureDescription: GestureDescription?) = scrollFinished()
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    fun touch(touch: MirrorTouch) = handler.post {
        val point = point(touch.x, touch.y, touch.width, touch.height)
        when (touch.action) {
            MirrorTouch.DOWN -> down(point)
            MirrorTouch.MOVE -> if (stroke != null) {
                pending += point
                if (!inFlight) flush()
            }
            MirrorTouch.UP -> if (stroke != null) {
                pending += point
                pendingUp = true
                if (!inFlight) flush()
            }
        }
    }

    fun scroll(scroll: MirrorScroll) = handler.post {
        if (scrollAt == null) scrollAt = point(scroll.x, scroll.y, scroll.width, scroll.height)
        scrollDelta.offset((scroll.dx * SCROLL_PX).toFloat(), (scroll.dy * SCROLL_PX).toFloat())
        if (!scrolling) handler.postDelayed(::dispatchScroll, SCROLL_GATHER_MS)
        scrolling = true
    }

    fun key(key: String) = handler.post {
        when (key) {
            MirrorKey.BACK -> performGlobalAction(GLOBAL_ACTION_BACK)
            MirrorKey.HOME -> performGlobalAction(GLOBAL_ACTION_HOME)
            MirrorKey.RECENTS -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            MirrorKey.NOTIFICATIONS -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            MirrorKey.ENTER -> focused()?.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
            MirrorKey.COPY, MirrorKey.CUT -> copy(cut = key == MirrorKey.CUT)
            MirrorKey.DELETE -> edit { text, start, end -> if (start != end) Edit(text.removeRange(start, end), start) else if (start > 0) Edit(text.removeRange(start - 1, start), start - 1) else null }
        }
    }

    fun text(text: String) = handler.post {
        edit { current, start, end -> Edit(current.replaceRange(start, end, text), start + text.length) }
    }

    private fun copy(cut: Boolean) {
        val node = focused() ?: return
        val text = if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
        val start = minOf(node.textSelectionStart, node.textSelectionEnd)
        val end = maxOf(node.textSelectionStart, node.textSelectionEnd)
        if (start < 0 || end > text.length || start == end) return
        BridgeService.copyToMac(text.substring(start, end))
        node.performAction(if (cut) AccessibilityNodeInfo.ACTION_CUT else AccessibilityNodeInfo.ACTION_COPY)
    }

    private data class Edit(val text: String, val cursor: Int)

    private fun edit(change: (String, Int, Int) -> Edit?) {
        val node = focused()?.takeIf { it.isEditable } ?: return
        val current = if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
        val selection = listOf(node.textSelectionStart, node.textSelectionEnd)
        val (start, end) = if (selection.any { it < 0 || it > current.length }) current.length to current.length else selection.min() to selection.max()
        val edit = change(current, start, end) ?: return
        node.performAction(
            AccessibilityNodeInfo.ACTION_SET_TEXT,
            Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, edit.text) },
        )
        node.performAction(
            AccessibilityNodeInfo.ACTION_SET_SELECTION,
            Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, edit.cursor)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, edit.cursor)
            },
        )
    }

    private fun focused(): AccessibilityNodeInfo? =
        rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: findFocus(AccessibilityNodeInfo.FOCUS_INPUT)

    private fun down(point: PointF) {
        pending.clear()
        pendingUp = false
        val first = GestureDescription.StrokeDescription(Path().apply { moveTo(point.x, point.y) }, 0, SEGMENT_MS, true)
        stroke = first
        last = point
        dispatch(first, strokeDone)
    }

    private fun flush() {
        val previous = stroke ?: return
        val from = last ?: return
        if (inFlight || (pending.isEmpty() && !pendingUp)) return
        val path = Path().apply {
            moveTo(from.x, from.y)
            pending.forEach { lineTo(it.x, it.y) }
        }
        val finishing = pendingUp
        val next = previous.continueStroke(path, 0, SEGMENT_MS, !finishing)
        last = pending.lastOrNull() ?: from
        pending.clear()
        pendingUp = false
        stroke = if (finishing) null else next
        dispatch(next, strokeDone)
    }

    private fun dispatchScroll() {
        val start = scrollAt ?: return scrollFinished()
        val (width, height) = screenSize()
        val end = PointF(
            (start.x + scrollDelta.x).coerceIn(0f, width - 1f),
            (start.y + scrollDelta.y).coerceIn(0f, height - 1f),
        )
        scrollDelta = PointF()
        if (end == start) return scrollFinished()
        val path = Path().apply {
            moveTo(start.x, start.y)
            lineTo(end.x, end.y)
        }
        dispatch(GestureDescription.StrokeDescription(path, 0, SCROLL_MS), scrollDone)
    }

    private fun scrollFinished() {
        scrolling = false
        scrollAt = null
        if (scrollDelta.length() > 0) {
            scrolling = true
            handler.postDelayed(::dispatchScroll, SCROLL_GATHER_MS)
        }
    }

    private fun dispatch(stroke: GestureDescription.StrokeDescription, callback: GestureResultCallback) {
        if (callback === strokeDone) inFlight = true
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        if (!dispatchGesture(gesture, callback, handler)) callback.onCancelled(gesture)
    }

    private fun point(x: Int, y: Int, width: Int, height: Int): PointF {
        val (screenWidth, screenHeight) = screenSize()
        return PointF(x.toFloat() * screenWidth / width.coerceAtLeast(1), y.toFloat() * screenHeight / height.coerceAtLeast(1))
    }

    private fun screenSize(): Pair<Int, Int> {
        val display = getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val bounds = createDisplayContext(display).getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
        return bounds.width() to bounds.height()
    }

    companion object {
        private const val SEGMENT_MS = 8L
        private const val SCROLL_PX = 12.0
        private const val SCROLL_MS = 120L
        private const val SCROLL_GATHER_MS = 40L

        @Volatile var instance: MirrorControlService? = null
            private set

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
            val component = ComponentName(context, MirrorControlService::class.java)
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == component }
        }
    }
}
