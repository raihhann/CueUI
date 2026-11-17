package com.cueui.cueui_flutter

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.*
import android.speech.*
import java.io.File
import java.io.FileInputStream
import java.util.Locale
import java.util.concurrent.Executors

/** Offline file transcription via Android 13+ segmented audio-source recognition. */
class RecordingTranscriber(private val context: Context) {
    private var recognizer: SpeechRecognizer? = null
    private var pipe: Array<ParcelFileDescriptor>? = null
    private val handler = Handler(Looper.getMainLooper())
    private var completion: ((Map<String, Any?>) -> Unit)? = null
    private var watchdog: Runnable? = null
    private val segments = mutableListOf<String>()
    private var assetId = ""
    @Volatile private var writeFinished = false

    fun transcribe(id: String, callback: (Map<String, Any?>) -> Unit) {
        if (completion != null) { callback(AudioRecorderService.fail("A transcription is already running.")); return }
        if (Build.VERSION.SDK_INT < 33 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            callback(AudioRecorderService.fail("Saved-audio transcription needs Android 13+ and an installed on-device speech recognizer with audio-source support.")); return
        }
        if (AudioRecorderService.instance != null || CueCameraActivity.isRecording) {
            callback(AudioRecorderService.fail("Stop recording before transcribing.")); return
        }
        try {
            val store = CueMediaStore(context)
            val file = store.file(id)
            check(file.extension == "wav") { "Transcription currently supports CueUI audio recordings (WAV), not video." }
            check(store.get(id)?.get("durationMs").let { (it as? Number)?.toLong() ?: 0L } <= 30 * 60 * 1000) { "Split recordings longer than 30 minutes before transcribing." }
            completion = callback; assetId = id; segments.clear(); writeFinished = false
            pipe = ParcelFileDescriptor.createPipe()
            val engine = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            recognizer = engine
            engine.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) { finish(AudioRecorderService.fail("The on-device recognizer could not transcribe this file (code $error). Check offline language data and audio-source support.")) }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onSegmentResults(segmentResults: Bundle) { append(segmentResults) }
                override fun onEndOfSegmentedSession() { save() }
                override fun onResults(results: Bundle?) {
                    // An engine ignoring segmented sessions may return early. Never
                    // advertise a partial file transcript as a complete one.
                    if (writeFinished) { append(results); save() }
                    else finish(AudioRecorderService.fail("This speech engine ended before consuming the recording. Segmented file transcription is not supported by this engine."))
                }
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe!![0])
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, AudioRecorderService.RATE)
                putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            }
            engine.startListening(intent)
            val writingEnd = pipe!![1]
            val executor = Executors.newSingleThreadExecutor()
            executor.execute {
                try {
                    FileInputStream(file).use { input ->
                        check(input.skip(44) == 44L) { "Invalid WAV file." }
                        ParcelFileDescriptor.AutoCloseOutputStream(writingEnd).use { output ->
                            input.copyTo(output)
                            writeFinished = true
                        }
                    }
                } catch (error: Exception) {
                    handler.post { if (completion != null) finish(AudioRecorderService.fail("Could not stream saved audio: ${error.message}")) }
                } finally { executor.shutdown() }
            }
            watchdog = Runnable { finish(AudioRecorderService.fail("Transcription timed out. This device may not support saved-audio recognition.")) }
            handler.postDelayed(watchdog!!, 31 * 60 * 1000L)
        } catch (error: Exception) { if (completion != null) finish(AudioRecorderService.fail(error.message ?: "Transcription failed.")) else callback(AudioRecorderService.fail(error.message ?: "Transcription failed.")) }
    }
    private fun append(bundle: Bundle?) { bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()?.takeIf { it.isNotBlank() }?.let(segments::add) }
    private fun save() {
        if (segments.isEmpty()) { finish(AudioRecorderService.fail("No speech was recognized in the recording.")); return }
        val transcript = segments.joinToString(" ")
        val result = runCatching { AudioRecorderService.ok("Transcript saved and searchable.", mapOf("media" to CueMediaStore(context).update(assetId, transcript = transcript))) }
            .getOrElse { AudioRecorderService.fail(it.message ?: "Could not save transcript.") }
        finish(result)
    }
    private fun finish(result: Map<String, Any?>) {
        val callback = completion ?: return
        completion = null; watchdog?.let(handler::removeCallbacks); watchdog = null
        recognizer?.destroy(); recognizer = null
        pipe?.forEach { runCatching { it.close() } }; pipe = null
        callback(result)
    }
    fun shutdown() { if (completion != null) finish(AudioRecorderService.fail("Transcription cancelled because the app closed.")) }
    fun cancel() { if (completion != null) finish(AudioRecorderService.fail("Transcription cancelled.")) }
}
