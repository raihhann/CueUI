package com.cueui.cueui_flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import androidx.core.content.ContextCompat
import java.util.Locale

class VoiceBridge(private val context: Context) {

    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsEnabled = true
    private var isListening = false
    private var partialTranscript = ""
    private var rmsLevel = 0f
    private var statusNotice: String? = null

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            ttsReady = (status == TextToSpeech.SUCCESS)
            if (ttsReady) {
                tts?.language = Locale.getDefault()
            }
        }
    }

    fun hasRecordAudioPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    fun isSpeechSupported(): Boolean {
        val onDevice = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        return onDevice || SpeechRecognizer.isRecognitionAvailable(context)
    }

    fun currentStateMap(): Map<String, Any?> = mapOf(
        "isListening" to isListening,
        "partialTranscript" to partialTranscript,
        "rmsLevel" to rmsLevel.toDouble(),
        "ttsEnabled" to ttsEnabled,
        "speechAvailable" to isSpeechSupported(),
        "statusNotice" to statusNotice,
    )

    private fun pushState() {
        CueEventBridge.emit(mapOf("type" to "voiceState") + currentStateMap())
    }

    fun toggleTts(): Map<String, Any?> {
        ttsEnabled = !ttsEnabled
        if (!ttsEnabled) {
            tts?.stop()
        }
        pushState()
        return currentStateMap()
    }

    fun speakIfEnabled(text: String) {
        if (!ttsEnabled || !ttsReady || text.isBlank()) return
        tts?.speak(text.take(260), TextToSpeech.QUEUE_FLUSH, null, "cueui_${System.nanoTime()}")
    }

    fun clearNotice() {
        statusNotice = null
        pushState()
    }

    fun startListening() {
        if (!hasRecordAudioPermission()) {
            isListening = false
            statusNotice = "Grant Microphone permission to speak commands."
            pushState()
            CueEventBridge.emit(mapOf("type" to "missingPermission", "key" to AppPermissionKind.MICROPHONE.key))
            return
        }
        if (isListening) {
            stopListening()
            return
        }

        tts?.stop()
        destroyRecognizer()

        val useOnDevice = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        val available = useOnDevice || SpeechRecognizer.isRecognitionAvailable(context)
        if (!available) {
            isListening = false
            statusNotice = "No Speech Recognition service on this device. Tap the floating Bubble to type."
            pushState()
            return
        }

        val sr = if (useOnDevice && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            SpeechRecognizer.createSpeechRecognizer(context)
        }
        recognizer = sr

        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                isListening = true
                partialTranscript = ""
                statusNotice = null
                pushState()
            }

            override fun onBeginningOfSpeech() {}

            override fun onRmsChanged(rmsdB: Float) {
                rmsLevel = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
                pushState()
            }

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                isListening = false
                rmsLevel = 0f
                pushState()
            }

            override fun onError(error: Int) {
                statusNotice = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH -> "Didn't catch that. Tap Mic to try again."
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected."
                    SpeechRecognizer.ERROR_AUDIO -> "Audio recording error."
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission required."
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "Offline speech pack missing — type command or install voice data."
                    else -> "Voice recognition unavailable (code $error) — type command instead."
                }
                isListening = false
                partialTranscript = ""
                rmsLevel = 0f
                pushState()
                destroyRecognizer()
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val transcript = matches?.firstOrNull()?.trim().orEmpty()
                isListening = false
                partialTranscript = ""
                rmsLevel = 0f
                statusNotice = null
                pushState()
                destroyRecognizer()
                if (transcript.isNotEmpty()) {
                    CueEventBridge.emit(mapOf("type" to "voiceResult", "text" to transcript))
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val partial = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    ?.trim()
                    .orEmpty()
                if (partial.isNotEmpty()) {
                    partialTranscript = partial
                    pushState()
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toString())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }

        isListening = true
        partialTranscript = ""
        statusNotice = "Listening..."
        pushState()
        runCatching { sr.startListening(intent) }.onFailure { err ->
            isListening = false
            statusNotice = "Could not start mic: ${err.message}"
            pushState()
            destroyRecognizer()
        }
    }

    fun stopListening() {
        runCatching { recognizer?.stopListening() }
        destroyRecognizer()
        isListening = false
        rmsLevel = 0f
        statusNotice = null
        pushState()
    }

    private fun destroyRecognizer() {
        runCatching { recognizer?.destroy() }
        recognizer = null
    }

    fun shutdown() {
        destroyRecognizer()
        runCatching {
            tts?.stop()
            tts?.shutdown()
        }
        tts = null
    }
}
