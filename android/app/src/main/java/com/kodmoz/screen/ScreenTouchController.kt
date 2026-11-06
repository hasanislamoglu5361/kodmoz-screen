package com.kodmoz.screen

import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.abs

/**
 * SurfaceView üzerindeki dokunuşları Mac fare olaylarına çevirir.
 * Compose yerine gerçek View dokunuşunu kullanmak, SurfaceView ile
 * Compose katmanı arasındaki olay önceliği belirsizliğini ortadan kaldırır.
 */
class ScreenTouchController(
    private val onMove: (Float, Float) -> Unit,
    private val onButton: (Float, Float, Boolean, Int) -> Unit,
    private val onScroll: (Float, Float) -> Unit,
) : View.OnTouchListener {

    private enum class Mode { Undecided, Move, Drag, Scroll }

    private val handler = Handler(Looper.getMainLooper())
    private var view: View? = null
    private var mode = Mode.Undecided
    private var downTime = 0L
    private var lastX = 0f
    private var lastY = 0f
    private var totalMove = 0f
    private var pressed = false
    private var dragging = false
    private var scrolling = false
    private var lastCentroidX = 0f
    private var lastCentroidY = 0f
    private var lastTapTime = 0L
    private var lastTapX = 0f
    private var lastTapY = 0f
    private var touchSlop = 20f

    private val longPress = Runnable {
        if (!pressed || mode != Mode.Undecided) return@Runnable
        mode = Mode.Drag
        dragging = true
        onButton(normalizedX(lastX), normalizedY(lastY), true, 1)
    }

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        view = v
        if (touchSlop <= 0f) {
            touchSlop = ViewConfiguration.get(v.context).scaledTouchSlop.toFloat()
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> handleDown(event)
            MotionEvent.ACTION_POINTER_DOWN -> handlePointerDown(event)
            MotionEvent.ACTION_MOVE -> handleMove(event)
            MotionEvent.ACTION_POINTER_UP -> handlePointerUp(event)
            MotionEvent.ACTION_UP -> handleUp(event)
            MotionEvent.ACTION_CANCEL -> handleCancel()
        }
        return true
    }

    private fun handleDown(event: MotionEvent) {
        pressed = true
        mode = Mode.Undecided
        dragging = false
        scrolling = false
        totalMove = 0f
        downTime = System.currentTimeMillis()
        lastX = event.x
        lastY = event.y
        onMove(normalizedX(lastX), normalizedY(lastY))
        handler.postDelayed(longPress, 330)
    }

    private fun handlePointerDown(event: MotionEvent) {
        if (scrolling) return
        handler.removeCallbacks(longPress)
        if (dragging) {
            onButton(normalizedX(lastX), normalizedY(lastY), false, 1)
            dragging = false
        }
        scrolling = true
        mode = Mode.Scroll
        lastCentroidX = centroidX(event)
        lastCentroidY = centroidY(event)
    }

    private fun handleMove(event: MotionEvent) {
        if (scrolling) {
            if (event.pointerCount >= 2) {
                val cx = centroidX(event)
                val cy = centroidY(event)
                val dx = cx - lastCentroidX
                val dy = cy - lastCentroidY
                if (abs(dx) > 0.6f || abs(dy) > 0.6f) {
                    onScroll(dx * 1.2f, dy * 1.2f)
                }
                lastCentroidX = cx
                lastCentroidY = cy
            }
            return
        }

        val x = event.x
        val y = event.y
        val dx = x - lastX
        val dy = y - lastY
        val distance = kotlin.math.hypot(dx.toDouble(), dy.toDouble())
        totalMove += distance.toFloat()
        lastX = x
        lastY = y

        if (mode == Mode.Undecided && distance > touchSlop) {
            mode = Mode.Move
            handler.removeCallbacks(longPress)
        }

        if (mode == Mode.Move || mode == Mode.Drag) {
            onMove(normalizedX(x), normalizedY(y))
        }
    }

    private fun handlePointerUp(event: MotionEvent) {
        if (!scrolling) return
        lastCentroidX = centroidX(event)
        lastCentroidY = centroidY(event)
    }

    private fun handleUp(event: MotionEvent) {
        pressed = false
        handler.removeCallbacks(longPress)

        if (scrolling) {
            scrolling = false
            mode = Mode.Undecided
            return
        }

        lastX = event.x
        lastY = event.y

        when (mode) {
            Mode.Drag -> {
                if (dragging) {
                    onButton(normalizedX(lastX), normalizedY(lastY), false, 1)
                }
            }

            Mode.Undecided -> {
                val elapsed = System.currentTimeMillis() - downTime
                if (elapsed < 380 && totalMove < touchSlop * 1.2f) {
                    val now = System.currentTimeMillis()
                    val isDouble = now - lastTapTime < 300 &&
                        kotlin.math.hypot(
                            (lastX - lastTapX).toDouble(),
                            (lastY - lastTapY).toDouble()
                        ) < 48.0
                    val clicks = if (isDouble) 2 else 1
                    lastTapTime = now
                    lastTapX = lastX
                    lastTapY = lastY
                    onButton(normalizedX(lastX), normalizedY(lastY), true, clicks)
                    onButton(normalizedX(lastX), normalizedY(lastY), false, clicks)
                }
            }

            else -> Unit
        }
        dragging = false
        mode = Mode.Undecided
    }

    private fun handleCancel() {
        pressed = false
        handler.removeCallbacks(longPress)
        if (dragging) {
            onButton(normalizedX(lastX), normalizedY(lastY), false, 1)
        }
        dragging = false
        scrolling = false
        mode = Mode.Undecided
    }

    private fun normalizedX(x: Float): Float {
        val width = view?.width?.toFloat() ?: return 0f
        return if (width <= 0f) 0f else (x / width).coerceIn(0f, 1f)
    }

    private fun normalizedY(y: Float): Float {
        val height = view?.height?.toFloat() ?: return 0f
        return if (height <= 0f) 0f else (y / height).coerceIn(0f, 1f)
    }

    private fun centroidX(event: MotionEvent): Float {
        var sum = 0f
        for (index in 0 until event.pointerCount) sum += event.getX(index)
        return if (event.pointerCount > 0) sum / event.pointerCount else event.x
    }

    private fun centroidY(event: MotionEvent): Float {
        var sum = 0f
        for (index in 0 until event.pointerCount) sum += event.getY(index)
        return if (event.pointerCount > 0) sum / event.pointerCount else event.y
    }
}
