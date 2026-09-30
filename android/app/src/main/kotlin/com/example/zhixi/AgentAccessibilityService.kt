package com.example.zhixi

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Point
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Display
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

class AgentAccessibilityService : AccessibilityService() {
    private var screenWidth = 0
    private var screenHeight = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        current = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        if (current === this) current = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    fun observe(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error("screenshot_unavailable", "当前 Android 版本不支持无障碍截图", null)
            return
        }
        takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
            override fun onSuccess(screenshot: ScreenshotResult) {
                val buffer = screenshot.hardwareBuffer
                screenWidth = buffer.width
                screenHeight = buffer.height
                val nodes = collectNodes(screenWidth, screenHeight)
                Thread {
                    try {
                        val source = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
                            ?: throw IllegalStateException("无法读取屏幕画面")
                        val width = minOf(source.width, 720)
                        val height = (source.height * width.toFloat() / source.width).roundToInt()
                        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
                        val bytes = ByteArrayOutputStream()
                        scaled.compress(Bitmap.CompressFormat.JPEG, 68, bytes)
                        if (scaled !== source) scaled.recycle()
                        source.recycle()
                        val encoded = Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
                        mainExecutor.execute {
                            result.success(
                                mapOf(
                                    "screenshotBase64" to encoded,
                                    "width" to width,
                                    "height" to height,
                                    "nodes" to nodes,
                                ),
                            )
                        }
                    } catch (error: Exception) {
                        mainExecutor.execute {
                            result.error("screenshot_failed", error.message ?: "无法读取屏幕画面", null)
                        }
                    } finally {
                        buffer.close()
                    }
                }.start()
            }

            override fun onFailure(errorCode: Int) {
                val reason = when (errorCode) {
                    ERROR_TAKE_SCREENSHOT_SECURE_WINDOW -> "当前页面禁止截图，无法继续观察"
                    ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT -> "截图间隔过短，请稍后重试"
                    ERROR_TAKE_SCREENSHOT_NO_ACCESSIBILITY_ACCESS -> "无障碍服务未获得截图权限"
                    else -> "无法截取屏幕（错误码 $errorCode）"
                }
                result.error("screenshot_failed", reason, null)
            }
        })
    }

    private fun collectNodes(width: Int, height: Int): List<Map<String, Any>> {
        val output = ArrayList<Map<String, Any>>()
        val root = rootInActiveWindow ?: return output
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty() && output.size < 100) {
            val node = queue.removeFirst()
            if (node.isVisibleToUser) {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                val text = if (node.isPassword) "" else node.text?.toString().orEmpty().take(160)
                val description = if (node.isPassword) "" else node.contentDescription?.toString().orEmpty().take(160)
                if (!rect.isEmpty && (text.isNotEmpty() || description.isNotEmpty() || node.isClickable || node.isEditable)) {
                    output.add(
                        mapOf(
                            "text" to text,
                            "description" to description,
                            "class" to node.className?.toString().orEmpty(),
                            "clickable" to node.isClickable,
                            "editable" to node.isEditable,
                            "bounds" to mapOf(
                                "left" to normalized(rect.left, width),
                                "top" to normalized(rect.top, height),
                                "right" to normalized(rect.right, width),
                                "bottom" to normalized(rect.bottom, height),
                            ),
                        ),
                    )
                }
            }
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let(queue::addLast)
            }
        }
        return output
    }

    private fun normalized(value: Int, length: Int): Int =
        (value * 1000f / length).roundToInt().coerceIn(0, 1000)

    @Suppress("DEPRECATION")
    private fun screenSize(): Point {
        if (screenWidth > 0 && screenHeight > 0) return Point(screenWidth, screenHeight)
        val size = Point()
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealSize(size)
        return size
    }

    private fun gesture(
        x1: Float,
        y1: Float,
        x2: Float,
        y2: Float,
        durationMs: Long,
        result: MethodChannel.Result,
    ) {
        val size = screenSize()
        val path = Path().apply {
            moveTo(x1 / 1000f * (size.x - 1), y1 / 1000f * (size.y - 1))
            if (x1 != x2 || y1 != y2) lineTo(x2 / 1000f * (size.x - 1), y2 / 1000f * (size.y - 1))
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                result.success(true)
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                result.error("gesture_cancelled", "手势被系统取消", null)
            }
        }, null)
        if (!accepted) result.error("gesture_failed", "系统未接受手势，请检查无障碍权限", null)
    }

    fun tap(x: Float, y: Float, result: MethodChannel.Result) =
        gesture(x, y, x, y, 60, result)

    fun swipe(
        x1: Float,
        y1: Float,
        x2: Float,
        y2: Float,
        durationMs: Long,
        result: MethodChannel.Result,
    ) = gesture(x1, y1, x2, y2, durationMs, result)

    fun typeText(text: String, result: MethodChannel.Result) {
        val target = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (target == null || !target.isEditable) {
            result.error("input_unavailable", "请先点按可输入的文本框", null)
            return
        }
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        if (target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
            result.success(true)
        } else {
            result.error("input_failed", "当前文本框不接受文字输入", null)
        }
    }

    fun globalAction(action: String?, result: MethodChannel.Result) {
        val androidAction = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            else -> {
                result.error("invalid_argument", "仅支持返回或主页操作", null)
                return
            }
        }
        if (performGlobalAction(androidAction)) {
            result.success(true)
        } else {
            result.error("action_failed", "系统未执行该操作", null)
        }
    }

    companion object {
        @Volatile
        var current: AgentAccessibilityService? = null
            private set
    }
}
