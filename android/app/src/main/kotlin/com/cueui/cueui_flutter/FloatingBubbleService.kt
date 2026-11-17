package com.cueui.cueui_flutter

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import kotlin.math.abs

class FloatingBubbleService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var rootContainer: FrameLayout
    private lateinit var layoutParams: WindowManager.LayoutParams
    private lateinit var bubbleBadge: ImageView
    private lateinit var panelCard: LinearLayout
    private lateinit var statusView: TextView
    private lateinit var outputView: TextView
    private lateinit var confirmContainer: LinearLayout
    private lateinit var confirmPromptView: TextView
    private lateinit var dynamicChoicesScroll: HorizontalScrollView
    private lateinit var dynamicChoicesRow: LinearLayout
    private lateinit var commandInput: EditText

    private var expanded = false
    private var pendingShowKeyboard = false
    private var collapsedX = 0
    private var collapsedY = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startOverlayForeground()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        buildOverlayViews()
        CueEventBridge.setOverlayObserver { renderOverlayState() }
        CueEventBridge.notifyBubbleActive(true)
        renderOverlayState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_COLLAPSE -> setExpanded(false)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        CueEventBridge.setOverlayObserver(null)
        CueEventBridge.notifyBubbleActive(false)
        if (::rootContainer.isInitialized && rootContainer.isAttachedToWindow) {
            windowManager.removeView(rootContainer)
        }
        super.onDestroy()
    }

    private fun startOverlayForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "CueUI Floating Bubble", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(channel)
        }
        val openAppIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, FloatingBubbleService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_pilot)
            .setContentTitle("CueUI Assistant")
            .setContentText("Floating assistant ready (Flutter + Nano AI)")
            .setContentIntent(openAppIntent)
            .addAction(0, "Stop", stopIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildOverlayViews() {
        rootContainer = FrameLayout(this)
        layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(310)
        }

        bubbleBadge = ImageView(this).apply {
            setImageResource(R.drawable.ic_bubble_pilot)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "CueUI Assistant"
            setPadding(dp(12), dp(12), dp(12), dp(12))
            elevation = dp(10).toFloat()
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF18181C"))
                setStroke(dp(1) + 1, Color.parseColor("#FFDDEB3B"))
            }
            layoutParams = FrameLayout.LayoutParams(dp(52), dp(52))
        }

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        bubbleBadge.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = layoutParams.x
                    startY = layoutParams.y
                    moved = false
                    v.animate().scaleX(0.92f).scaleY(0.92f).setDuration(90).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (abs(dx) > 12 || abs(dy) > 12) moved = true
                    layoutParams.x = (startX + dx).toInt()
                    layoutParams.y = (startY + dy).toInt()
                    windowManager.updateViewLayout(rootContainer, layoutParams)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(90).start()
                    if (event.action == MotionEvent.ACTION_UP && !moved) setExpanded(true)
                    true
                }
                else -> false
            }
        }

        panelCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            elevation = dp(16).toFloat()
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(Color.parseColor("#FF16161A"))
                setStroke(dp(1), Color.parseColor("#FF2A2A32"))
            }
            layoutParams = FrameLayout.LayoutParams(dp(336), WindowManager.LayoutParams.WRAP_CONTENT)
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(6))
        }
        val headerIcon = ImageView(this).apply {
            setImageResource(R.drawable.ic_bubble_pilot)
            setPadding(dp(5), dp(5), dp(5), dp(5))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF202026"))
                setStroke(dp(1), Color.parseColor("#FFDDEB3B"))
            }
            layoutParams = LinearLayout.LayoutParams(dp(26), dp(26)).apply { marginEnd = dp(8) }
        }
        statusView = TextView(this).apply {
            text = "CueUI · Ready"
            setTextColor(Color.parseColor("#FFDDEB3B"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        headerRow.addView(headerIcon)
        headerRow.addView(statusView)
        headerRow.addView(smallHeaderBtn("—") { setExpanded(false) })
        headerRow.addView(smallHeaderBtn("✕") { stopSelf() })

        outputView = TextView(this).apply {
            text = CueEventBridge.latestOutputText
            setTextColor(Color.parseColor("#FFE4E4E7"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dp(2), dp(6), dp(2), dp(6))
        }
        val outputScroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(104))
            addView(outputView)
        }

        dynamicChoicesRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(4), 0, dp(6))
        }
        dynamicChoicesScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            visibility = View.GONE
            addView(dynamicChoicesRow)
        }

        confirmPromptView = TextView(this).apply {
            setTextColor(Color.parseColor("#FFDDEB3B"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }
        val confirmActions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(6), 0, 0)
            addView(Button(this@FloatingBubbleService).apply {
                text = "Confirm"
                setOnClickListener { CueEventBridge.emit(mapOf("type" to "resolveConfirm", "approved" to true)) }
            })
            addView(Button(this@FloatingBubbleService).apply {
                text = "Cancel"
                setOnClickListener { CueEventBridge.emit(mapOf("type" to "resolveConfirm", "approved" to false)) }
            })
        }
        confirmContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(10), dp(8), dp(10), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(Color.parseColor("#FF1F1F24"))
                setStroke(1, Color.parseColor("#66DDEB3B"))
            }
            addView(confirmPromptView)
            addView(confirmActions)
        }

        val chipsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(4), 0, dp(8))
            addView(quickChip("YouTube Lofi") { CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to "play lofi music on youtube")) })
            addView(quickChip("Hot News") { CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to "what is the current hot news")) })
            addView(quickChip("Notifs") { CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to "read notifications")) })
            addView(quickChip("Flash") { CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to "turn on flashlight")) })
        }
        val chipsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(chipsRow)
        }

        commandInput = EditText(this).apply {
            hint = "Ask CueUI or reply..."
            setHintTextColor(Color.parseColor("#FF7C7C85"))
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setSingleLine(true)
            setPadding(dp(14), dp(9), dp(14), dp(9))
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.parseColor("#FF222228"))
                setStroke(dp(1), Color.parseColor("#FF34343D"))
            }
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_SEND) {
                    dispatchInput()
                    true
                } else {
                    false
                }
            }
            setOnClickListener { showKeyboardNow() }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginEnd = dp(8)
            }
        }
        val sendBtn = TextView(this).apply {
            text = "Run"
            setTextColor(Color.parseColor("#FF111113"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(9), dp(16), dp(9))
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.parseColor("#FFDDEB3B"))
            }
            setOnClickListener { dispatchInput() }
        }
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(commandInput)
            addView(sendBtn)
        }

        panelCard.addView(headerRow)
        panelCard.addView(outputScroll)
        panelCard.addView(dynamicChoicesScroll)
        panelCard.addView(confirmContainer)
        panelCard.addView(chipsScroll)
        panelCard.addView(inputRow)

        rootContainer.addView(bubbleBadge)
        rootContainer.addView(panelCard)
        rootContainer.viewTreeObserver.addOnWindowFocusChangeListener { hasFocus ->
            if (hasFocus && expanded && pendingShowKeyboard) {
                pendingShowKeyboard = false
                showKeyboardNow()
            }
        }
        windowManager.addView(rootContainer, layoutParams)
    }

    private fun renderOverlayState() {
        if (!::statusView.isInitialized) return
        statusView.text = if (CueEventBridge.isAwaitingReply) "CueUI · Waiting for reply" else CueEventBridge.statusLine
        outputView.text = CueEventBridge.latestOutputText

        dynamicChoicesRow.removeAllViews()
        val choices = CueEventBridge.quickChoices
        if (choices.isNotEmpty()) {
            dynamicChoicesScroll.visibility = View.VISIBLE
            if (CueEventBridge.isAwaitingReply && !expanded) setExpanded(true)
            choices.forEach { choice ->
                val isAccent = choice.startsWith("Yes", ignoreCase = true) || choice.startsWith("Grant", ignoreCase = true)
                dynamicChoicesRow.addView(
                    quickChip(choice, accent = isAccent) {
                        val permKey = CueEventBridge.pendingPermissionKey
                        if (permKey != null && choice.startsWith("Grant", ignoreCase = true)) {
                            setExpanded(false)
                            val launch = Intent(this, MainActivity::class.java).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                putExtra(MainActivity.EXTRA_PERMISSION_KEY, permKey)
                            }
                            startActivity(launch)
                        } else {
                            CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to choice))
                        }
                    },
                )
            }
        } else {
            dynamicChoicesScroll.visibility = View.GONE
        }

        val confirmPrompt = CueEventBridge.pendingConfirmationPrompt
        if (!confirmPrompt.isNullOrBlank()) {
            confirmContainer.visibility = View.VISIBLE
            confirmPromptView.text = confirmPrompt
            if (!expanded) setExpanded(true)
        } else {
            confirmContainer.visibility = View.GONE
        }
    }

    private fun dispatchInput() {
        val text = commandInput.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        commandInput.setText("")
        CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to text))
    }

    private fun setExpanded(expand: Boolean) {
        if (expanded == expand) return
        expanded = expand
        bubbleBadge.visibility = if (expand) View.GONE else View.VISIBLE
        panelCard.visibility = if (expand) View.VISIBLE else View.GONE
        if (expand) {
            collapsedX = layoutParams.x
            collapsedY = layoutParams.y
            val screenWidth = resources.displayMetrics.widthPixels
            layoutParams.x = ((screenWidth - dp(332)) / 2).coerceAtLeast(dp(12))
            layoutParams.y = collapsedY.coerceIn(dp(64), dp(220))
        } else {
            layoutParams.x = collapsedX
            layoutParams.y = collapsedY
        }
        layoutParams.flags = if (expand) {
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        } else {
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        }
        layoutParams.softInputMode = if (expand) WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE else WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN
        if (rootContainer.isAttachedToWindow) windowManager.updateViewLayout(rootContainer, layoutParams)

        if (expand) {
            pendingShowKeyboard = true
            commandInput.requestFocus()
            commandInput.postDelayed(
                {
                    if (expanded && pendingShowKeyboard) {
                        pendingShowKeyboard = false
                        showKeyboardNow()
                    }
                },
                140L,
            )
        } else {
            pendingShowKeyboard = false
            commandInput.clearFocus()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                commandInput.windowInsetsController?.hide(WindowInsets.Type.ime())
            }
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(commandInput.windowToken, 0)
        }
    }

    private fun showKeyboardNow() {
        commandInput.requestFocus()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            commandInput.windowInsetsController?.show(WindowInsets.Type.ime())
        }
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.showSoftInput(commandInput, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun smallHeaderBtn(label: String, onClick: () -> Unit): TextView = TextView(this).apply {
        text = label
        setTextColor(Color.parseColor("#FFB4B4BC"))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        gravity = Gravity.CENTER
        setPadding(dp(10), dp(4), dp(10), dp(4))
        background = GradientDrawable().apply {
            cornerRadius = dp(12).toFloat()
            setColor(Color.parseColor("#FF222228"))
            setStroke(1, Color.parseColor("#FF32323B"))
        }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { marginStart = dp(6) }
        setOnClickListener { onClick() }
    }

    private fun quickChip(label: String, accent: Boolean = false, onClick: () -> Unit): TextView = TextView(this).apply {
        text = label
        setTextColor(Color.parseColor(if (accent) "#FFDDEB3B" else "#FFE4E4E7"))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        setPadding(dp(11), dp(5), dp(11), dp(5))
        background = GradientDrawable().apply {
            cornerRadius = dp(16).toFloat()
            setColor(Color.parseColor(if (accent) "#FF252814" else "#FF222228"))
            setStroke(1, Color.parseColor(if (accent) "#FFDDEB3B" else "#FF32323B"))
        }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { marginEnd = dp(6) }
        setOnClickListener { onClick() }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val CHANNEL_ID = "cueui_overlay"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_STOP = "com.cueui.cueui_flutter.STOP_BUBBLE"
        private const val ACTION_COLLAPSE = "com.cueui.cueui_flutter.COLLAPSE_BUBBLE"

        fun start(context: Context) {
            val intent = Intent(context, FloatingBubbleService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FloatingBubbleService::class.java))
        }

        fun collapseIfRunning(context: Context) {
            if (!CueEventBridge.bubbleActive) return
            runCatching {
                context.startService(Intent(context, FloatingBubbleService::class.java).setAction(ACTION_COLLAPSE))
            }
        }
    }
}
