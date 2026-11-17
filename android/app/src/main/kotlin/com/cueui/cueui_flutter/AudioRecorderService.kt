package com.cueui.cueui_flutter

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.*
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Executors

/** PCM WAV capture makes saved recordings portable and directly transcribable. */
class AudioRecorderService : Service() {
    private var recorder: AudioRecord? = null
    private var file: File? = null
    private var title = "Voice recording"
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    @Volatile private var paused = false
    @Volatile private var commandListening = false
    private var pausedBeforeCommand = false
    private var startedAt = 0L
    private var pausedAt = 0L
    private var pausedMs = 0L
    private var writeFailure: String? = null
    private var stopCallback: ((Map<String, Any?>) -> Unit)? = null

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() { super.onCreate(); instance = this }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "pause" -> pause()
            "resume" -> resume()
            "stop" -> stop(null) { }
            else -> if (!running) start(intent?.getStringExtra("title").orEmpty())
        }
        return START_NOT_STICKY
    }

    private fun foreground() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Audio recording", NotificationManager.IMPORTANCE_LOW))
        fun action(name: String, code: Int) = PendingIntent.getService(this, code,
            Intent(this, AudioRecorderService::class.java).setAction(name), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_stat_pilot)
            .setContentTitle(if (paused) "Recording paused" else "Recording audio")
            .setContentText(title).setOngoing(true)
            .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
            .addAction(0, if (paused) "Resume" else "Pause", action(if (paused) "resume" else "pause", 1))
            .addAction(0, "Stop & save", action("stop", 2)).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(2001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(2001, notification)
    }

    private fun start(requestedTitle: String) {
        try {
            check(ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) { "Microphone permission required." }
            check(!CueCameraActivity.isRecording) { "Stop video recording first." }
            title = requestedTitle.ifBlank { "Voice recording" }
            foreground()
            val bufferSize = maxOf(AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT), 8192)
            val audio = AudioRecord(MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferSize)
            recorder = audio
            check(audio.state == AudioRecord.STATE_INITIALIZED) { "Microphone could not initialize." }
            file = CueMediaStore(this).newFile("wav")
            audio.startRecording()
            running = true; paused = false; startedAt = SystemClock.elapsedRealtime(); pausedMs = 0
            pushState()
            pendingStart?.invoke(ok("Audio recording started. Use Pause or Stop & save.", mapOf("recording" to state())))
            pendingStart = null
            worker.execute {
                try {
                    RandomAccessFile(file!!, "rw").use { output ->
                        output.write(ByteArray(44))
                        val buffer = ByteArray(bufferSize)
                        while (running) {
                            if (commandListening) { Thread.sleep(30); continue }
                            val count = audio.read(buffer, 0, buffer.size)
                            if (count > 0 && !paused) output.write(buffer, 0, count)
                            else if (count < 0 && running && !commandListening) error("Microphone read failed ($count).")
                        }
                        val length = output.length() - 44
                        check(length > 0) { "Recording is empty." }
                        output.seek(0); output.write(wavHeader(length.toInt()))
                    }
                } catch (error: Exception) { writeFailure = error.message }
                main.post { finishRecording() }
            }
        } catch (error: Exception) {
            running = false
            recorder?.release(); recorder = null
            pendingStart?.invoke(fail(error.message ?: "Recording failed.")); pendingStart = null
            stopSelf()
        }
    }

    fun state(): Map<String, Any?> = mapOf("active" to running, "paused" to paused, "title" to title,
        "elapsedMs" to if (startedAt == 0L) 0L else ((if (paused) pausedAt else SystemClock.elapsedRealtime()) - startedAt - pausedMs))
    fun pause(): Map<String, Any?> {
        if (!running) return fail("No active audio recording.")
        if (!paused) { pausedAt = SystemClock.elapsedRealtime(); paused = true }
        foreground(); pushState(); return ok("Audio recording paused.", mapOf("recording" to state()))
    }
    fun resume(): Map<String, Any?> {
        if (!running) return fail("No active audio recording.")
        if (paused) { pausedMs += SystemClock.elapsedRealtime() - pausedAt; paused = false }
        foreground(); pushState(); return ok("Audio recording resumed.", mapOf("recording" to state()))
    }
    fun pauseForCommand() {
        if (!running || commandListening) return
        pausedBeforeCommand = paused
        if (!paused) { pausedAt = SystemClock.elapsedRealtime(); paused = true }
        commandListening = true
        recorder?.stop()
        pushState()
    }
    fun resumeAfterCommand() {
        if (!running || !commandListening) return
        recorder?.startRecording()
        commandListening = false
        if (!pausedBeforeCommand) { pausedMs += SystemClock.elapsedRealtime() - pausedAt; paused = false }
        pushState()
    }
    fun stop(newTitle: String?, callback: (Map<String, Any?>) -> Unit) {
        if (!running || stopCallback != null) { callback(fail("No active audio recording to stop.")); return }
        if (!newTitle.isNullOrBlank()) title = newTitle.trim()
        stopCallback = callback
        running = false
        runCatching { recorder?.stop() }
    }
    private fun finishRecording() {
        running = false
        recorder?.release(); recorder = null
        val saved = runCatching {
            check(writeFailure == null) { writeFailure ?: "Recording failed." }
            CueMediaStore(this).save(file!!, "audio", title)
        }
        val result = saved.fold({ ok("Saved audio: $title", mapOf("media" to it)) }, { fail(it.message ?: "Could not save recording.") })
        stopCallback?.invoke(result); stopCallback = null
        CueEventBridge.emit(mapOf("type" to "mediaCaptureResult", "result" to result))
        pushState(); stopSelf()
    }
    private fun pushState() = CueEventBridge.emit(mapOf("type" to "recordingState", "recording" to state()))
    override fun onDestroy() {
        running = false
        runCatching { recorder?.stop() }
        worker.shutdown()
        if (instance === this) instance = null
        super.onDestroy()
    }
    companion object {
        const val RATE = 16000
        private const val CHANNEL = "cue_audio_recording"
        var instance: AudioRecorderService? = null; private set
        val activeFilePath: String? get() = instance?.file?.absolutePath
        var pendingStart: ((Map<String, Any?>) -> Unit)? = null
        fun ok(summary: String, data: Map<String, Any?> = emptyMap()) = mapOf("ok" to true, "summary" to summary, "data" to data)
        fun fail(summary: String) = mapOf("ok" to false, "summary" to summary)
        fun wavHeader(size: Int): ByteArray = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            .put("RIFF".toByteArray()).putInt(size + 36).put("WAVEfmt ".toByteArray()).putInt(16)
            .putShort(1.toShort()).putShort(1.toShort()).putInt(RATE).putInt(RATE * 2)
            .putShort(2.toShort()).putShort(16.toShort()).put("data".toByteArray()).putInt(size).array()
    }
}
