package com.cueui.cueui_flutter

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.io.File
import java.io.FileOutputStream

/**
 * Native AccessibilityService exposing on-screen UI tree capture, gesture/node taps,
 * text entry, scrolling, global keys, and OS screenshots cleanly to Flutter via MethodChannel.
 */
class CueAccessibilityService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var lastSnapshot: List<Map<String, Any?>> = emptyList()

    @Volatile
    var currentPackageName: String = ""
        private set

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "CueAccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        if (!pkg.isNullOrBlank() && pkg != packageName) {
            currentPackageName = pkg
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "CueAccessibilityService interrupted")
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun activeAppRoot(): AccessibilityNodeInfo? {
        val primary = rootInActiveWindow
        if (primary != null && primary.packageName?.toString() != packageName) {
            return primary
        }
        val appWindow = windows?.firstOrNull { win ->
            win.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                win.root != null &&
                win.root?.packageName?.toString() != packageName
        }
        return appWindow?.root
    }

    fun captureUiNodes(): List<Map<String, Any?>> {
        val root = activeAppRoot() ?: return emptyList()
        val nodes = mutableListOf<Map<String, Any?>>()
        collectNodes(root, nodes)
        lastSnapshot = nodes
        return nodes
    }

    private fun collectNodes(node: AccessibilityNodeInfo?, out: MutableList<Map<String, Any?>>) {
        if (node == null || !node.isVisibleToUser) return
        val rect = Rect()
        node.getBoundsInScreen(rect)

        val text = node.text?.toString()?.trim().orEmpty()
        val desc = node.contentDescription?.toString()?.trim().orEmpty()
        val viewId = node.viewIdResourceName?.trim().orEmpty()
        val important = node.isClickable || node.isEditable || node.isScrollable ||
            text.isNotEmpty() || desc.isNotEmpty()

        if (important && !rect.isEmpty) {
            out += mapOf(
                "index" to out.size,
                "className" to node.className?.toString().orEmpty(),
                "text" to text,
                "contentDesc" to desc,
                "viewId" to viewId,
                "clickable" to node.isClickable,
                "editable" to node.isEditable,
                "scrollable" to node.isScrollable,
                "focused" to node.isFocused,
                "left" to rect.left,
                "top" to rect.top,
                "right" to rect.right,
                "bottom" to rect.bottom,
            )
        }

        for (i in 0 until node.childCount) {
            collectNodes(node.getChild(i), out)
        }
    }

    fun tapElementByIndex(index: Int, callback: (Map<String, Any?>) -> Unit) {
        val nodes = if (index in lastSnapshot.indices) lastSnapshot else captureUiNodes()
        val target = nodes.getOrNull(index)
        if (target == null) {
            callback(mapOf("ok" to false, "summary" to "Element index $index out of range (0..${nodes.lastIndex})."))
            return
        }
        val left = (target["left"] as Number).toInt()
        val top = (target["top"] as Number).toInt()
        val right = (target["right"] as Number).toInt()
        val bottom = (target["bottom"] as Number).toInt()
        val cx = (left + right) / 2
        val cy = (top + bottom) / 2
        val text = target["text"] as? String ?: ""
        val desc = target["contentDesc"] as? String ?: ""
        val label = text.ifBlank { desc.ifBlank { "element" } }

        if (clickNodeMatchingBounds(left, top, right, bottom, text, desc)) {
            callback(mapOf("ok" to true, "summary" to "Tapped [$index] $label @($cx,$cy)"))
            return
        }
        dispatchTap(cx.toFloat(), cy.toFloat()) { ok ->
            if (ok) {
                callback(mapOf("ok" to true, "summary" to "Tapped [$index] $label @($cx,$cy)"))
            } else {
                callback(mapOf("ok" to false, "summary" to "Failed to tap element [$index]."))
            }
        }
    }

    fun tapByQuery(query: String, callback: (Map<String, Any?>) -> Unit) {
        val nodes = captureUiNodes()
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) {
            callback(mapOf("ok" to false, "summary" to "Empty query."))
            return
        }
        var bestIdx = -1
        var bestScore = Int.MIN_VALUE
        for (node in nodes) {
            val textLower = (node["text"] as? String ?: "").trim().lowercase()
            val descLower = (node["contentDesc"] as? String ?: "").trim().lowercase()
            val idShort = (node["viewId"] as? String ?: "").substringAfterLast('/').trim().lowercase()
            var score = when {
                textLower == needle || descLower == needle -> 100
                idShort == needle -> 90
                textLower.startsWith(needle) || descLower.startsWith(needle) -> 70
                needle in textLower || needle in descLower -> 50
                needle in idShort -> 35
                else -> Int.MIN_VALUE
            }
            if (score == Int.MIN_VALUE) continue
            if (node["clickable"] == true) score += 12
            if (node["editable"] == true) score += 6
            if (score > bestScore) {
                bestScore = score
                bestIdx = (node["index"] as Number).toInt()
            }
        }
        if (bestIdx < 0) {
            callback(mapOf("ok" to false, "summary" to "No visible UI element matching '$query' found."))
        } else {
            tapElementByIndex(bestIdx, callback)
        }
    }

    private fun clickNodeMatchingBounds(
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        text: String,
        desc: String,
    ): Boolean {
        val root = activeAppRoot() ?: return false
        val node = findLiveNode(root, left, top, right, bottom, text, desc) ?: return false
        var current: AccessibilityNodeInfo? = node
        while (current != null) {
            if (current.isClickable && current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true
            }
            current = current.parent
        }
        return false
    }

    private fun findLiveNode(
        root: AccessibilityNodeInfo?,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        text: String,
        desc: String,
    ): AccessibilityNodeInfo? {
        if (root == null) return null
        val rect = Rect()
        root.getBoundsInScreen(rect)
        if (rect.left == left && rect.top == top && rect.right == right && rect.bottom == bottom) {
            val txt = root.text?.toString()?.trim().orEmpty()
            val dsc = root.contentDescription?.toString()?.trim().orEmpty()
            if (txt == text && dsc == desc) return root
        }
        for (i in 0 until root.childCount) {
            findLiveNode(root.getChild(i), left, top, right, bottom, text, desc)?.let { return it }
        }
        return null
    }

    private fun dispatchTap(x: Float, y: Float, callback: (Boolean) -> Unit) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 60L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        val dispatched = dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    mainHandler.post { callback(true) }
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    mainHandler.post { callback(false) }
                }
            },
            null,
        )
        if (!dispatched) callback(false)
    }

    fun typeIntoFocusedOrEditable(text: String): Map<String, Any?> {
        val root = activeAppRoot()
            ?: return mapOf("ok" to false, "summary" to "No active window found to type text.")

        val targetNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: findFirstEditable(root)
            ?: return mapOf("ok" to false, "summary" to "No focused or editable text field found on screen.")

        targetNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        if (targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
            return mapOf("ok" to true, "summary" to "Typed '${text.take(40)}' into active field.")
        }

        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("CueUI", text))
        val pasted = targetNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        return if (pasted) {
            mapOf("ok" to true, "summary" to "Pasted '${text.take(40)}' into active field.")
        } else {
            mapOf("ok" to false, "summary" to "Target field rejected text input.")
        }
    }

    private fun findFirstEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null || !node.isVisibleToUser) return null
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            findFirstEditable(node.getChild(i))?.let { return it }
        }
        return null
    }

    fun scrollScreen(direction: String, callback: (Map<String, Any?>) -> Unit) {
        val metrics = resources.displayMetrics
        val w = metrics.widthPixels.toFloat()
        val h = metrics.heightPixels.toFloat()
        val coords = when (direction.lowercase()) {
            "down" -> listOf(w * 0.5f, h * 0.72f, w * 0.5f, h * 0.25f)
            "up" -> listOf(w * 0.5f, h * 0.28f, w * 0.5f, h * 0.75f)
            "left" -> listOf(w * 0.80f, h * 0.5f, w * 0.20f, h * 0.5f)
            "right" -> listOf(w * 0.20f, h * 0.5f, w * 0.80f, h * 0.5f)
            else -> null
        } ?: run {
            callback(mapOf("ok" to false, "summary" to "Unknown scroll direction '$direction'. Use up/down/left/right."))
            return
        }

        val path = Path().apply {
            moveTo(coords[0], coords[1])
            lineTo(coords[2], coords[3])
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, 280L))
            .build()
        val started = dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    mainHandler.post { callback(mapOf("ok" to true, "summary" to "Scrolled $direction.")) }
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    mainHandler.post { callback(mapOf("ok" to false, "summary" to "Scroll gesture was cancelled.")) }
                }
            },
            null,
        )
        if (!started) callback(mapOf("ok" to false, "summary" to "Scroll gesture failed to start."))
    }

    fun performGlobalKey(key: String): Map<String, Any?> {
        val action = when (key.uppercase()) {
            "BACK" -> GLOBAL_ACTION_BACK
            "HOME" -> GLOBAL_ACTION_HOME
            "RECENTS" -> GLOBAL_ACTION_RECENTS
            "NOTIFICATIONS" -> GLOBAL_ACTION_NOTIFICATIONS
            "QUICK_SETTINGS" -> GLOBAL_ACTION_QUICK_SETTINGS
            "POWER_DIALOG" -> GLOBAL_ACTION_POWER_DIALOG
            "LOCK_SCREEN" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) GLOBAL_ACTION_LOCK_SCREEN else -1
            else -> -1
        }
        if (action == -1) return mapOf("ok" to false, "summary" to "Unsupported key '$key'.")
        val ok = performGlobalAction(action)
        return mapOf("ok" to ok, "summary" to if (ok) "Performed $key." else "Failed to perform $key.")
    }

    fun captureScreenshotToFile(outputFile: File, callback: (Map<String, Any?>) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            callback(mapOf("ok" to false, "summary" to "Accessibility screenshots require Android 11 (API 30+)."))
            return
        }
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    val bitmap = Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                    try {
                        outputFile.parentFile?.mkdirs()
                        if (bitmap != null) {
                            FileOutputStream(outputFile).use { out ->
                                bitmap.compress(Bitmap.CompressFormat.PNG, 95, out)
                            }
                            bitmap.recycle()
                        }
                        screenshot.hardwareBuffer.close()
                        callback(
                            mapOf(
                                "ok" to true,
                                "summary" to "Saved screenshot to ${outputFile.name}",
                                "data" to mapOf("path" to outputFile.absolutePath),
                            ),
                        )
                    } catch (t: Throwable) {
                        callback(mapOf("ok" to false, "summary" to "Screenshot save failed: ${t.message}"))
                    }
                }

                override fun onFailure(errorCode: Int) {
                    callback(mapOf("ok" to false, "summary" to "Screenshot failed (code $errorCode)."))
                }
            },
        )
    }

    companion object {
        private const val TAG = "CueAccessibility"

        @Volatile
        var instance: CueAccessibilityService? = null
            private set

        fun isConnected(): Boolean = instance != null
    }
}
