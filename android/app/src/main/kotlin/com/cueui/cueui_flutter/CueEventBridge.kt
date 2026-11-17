package com.cueui.cueui_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Bi-directional bridge state between Flutter/Dart UI + orchestrator and Android
 * native components (FloatingBubbleService, VoiceBridge, MainActivity permission callbacks).
 */
object CueEventBridge {
    @Volatile var whatsAppVoiceRecording = false
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    var bubbleActive: Boolean = false

    @Volatile
    var statusLine: String = "CueUI · Ready"

    @Volatile
    var isAwaitingReply: Boolean = false

    @Volatile
    var latestOutputText: String = "Ask CueUI to open an app, send a WhatsApp, check news, or search..."

    @Volatile
    var quickChoices: List<String> = emptyList()

    @Volatile
    var pendingPermissionKey: String? = null

    @Volatile
    var pendingConfirmationPrompt: String? = null

    private var overlayObserver: (() -> Unit)? = null

    fun attachSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun emit(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(event)
        } else {
            mainHandler.post { eventSink?.success(event) }
        }
    }

    fun setOverlayObserver(observer: (() -> Unit)?) {
        overlayObserver = observer
    }

    fun updateOverlayState(
        statusLine: String,
        latestOutput: String,
        quickChoices: List<String>,
        isAwaitingReply: Boolean,
        pendingPermissionKey: String?,
        pendingConfirmationPrompt: String?,
    ) {
        this.statusLine = statusLine
        this.latestOutputText = latestOutput
        this.quickChoices = quickChoices
        this.isAwaitingReply = isAwaitingReply
        this.pendingPermissionKey = pendingPermissionKey
        this.pendingConfirmationPrompt = pendingConfirmationPrompt
        mainHandler.post { overlayObserver?.invoke() }
    }

    fun notifyBubbleActive(active: Boolean) {
        bubbleActive = active
        emit(mapOf("type" to "bubbleState", "active" to active))
        mainHandler.post { overlayObserver?.invoke() }
    }
}
