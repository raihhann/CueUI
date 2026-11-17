package com.cueui.cueui_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.*
import android.view.*
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.*
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.io.File

/** Foreground camera with its own preview; no OEM camera UI automation. */
class CueCameraActivity : ComponentActivity() {
    private lateinit var preview: PreviewView
    private lateinit var status: TextView
    private var provider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var front = false
    private var busy = false
    var isForeground = false; private set
    private var generation = 0
    private var resultCallback: ((Map<String, Any?>) -> Unit)? = null
    private var videoFile: File? = null
    private var videoTitle = "Video"
    private var voice: VoiceBridge? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.BLACK) }
        status = TextView(this).apply { setTextColor(Color.WHITE); text = "Preparing camera…"; setPadding(20, 16, 20, 12) }
        preview = PreviewView(this)
        root.addView(status)
        root.addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
        val buttons = LinearLayout(this)
        fun button(label: String, action: () -> Unit) = Button(this).apply { text = label; setOnClickListener { action() } }
        fun local(action: String) = execute(action, emptyMap()) { result -> status.text = result["summary"].toString() }
        buttons.addView(button("Photo") { local("take_photo") }, LinearLayout.LayoutParams(0, -2, 1f))
        buttons.addView(button("Video / stop") { local(if (recording == null) "start_video" else "stop_video") }, LinearLayout.LayoutParams(0, -2, 1f))
        buttons.addView(button("Switch") { local("switch_camera") }, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(buttons)
        val command = EditText(this).apply { hint = "Type a command, e.g. stop video"; setTextColor(Color.WHITE); setHintTextColor(Color.LTGRAY); setSingleLine(true) }
        val commands = LinearLayout(this)
        commands.addView(command, LinearLayout.LayoutParams(0, -2, 1f))
        commands.addView(button("Run") {
            val text = command.text.toString().trim()
            if (text.isNotEmpty()) { command.setText(""); CueEventBridge.emit(mapOf("type" to "submitGoal", "text" to text)) }
        })
        commands.addView(button("Mic") {
            if (recording != null || AudioRecorderService.instance != null) status.text = "Use typed commands while recording audio."
            else voice?.startListening()
        })
        root.addView(commands)
        root.addView(button("Done") { if (recording != null) local("stop_video") else finish() })
        setContentView(root)
        voice = VoiceBridge(applicationContext)
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                provider = future.get()
                val pending = pendingCommand
                pendingCommand = null
                if (pending != null) execute(pending.first, pending.second, pending.third)
                else bind(false) { status.text = "Camera ready" }
            } catch (error: Exception) { completeFailure(error) }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun bind(video: Boolean, ready: () -> Unit) {
        val cameraProvider = provider ?: error("Camera is not ready.")
        val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        check(cameraProvider.hasCamera(selector)) { "This device does not have that camera." }
        cameraProvider.unbindAll()
        val cameraPreview = Preview.Builder().build().also { it.surfaceProvider = preview.surfaceProvider }
        if (video) {
            val recorder = Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.HD, FallbackStrategy.lowerQualityOrHigherThan(Quality.HD))).build()
            videoCapture = VideoCapture.withOutput(recorder)
            cameraProvider.bindToLifecycle(this, selector, cameraPreview, videoCapture)
        } else {
            imageCapture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
            cameraProvider.bindToLifecycle(this, selector, cameraPreview, imageCapture)
        }
        preview.postDelayed({
            if (isForeground && !isFinishing) ready()
            else { busy = false; complete(fail("Capture cancelled because the camera left the foreground.")) }
        }, 500L)
    }

    fun execute(action: String, args: Map<String, Any?>, callback: (Map<String, Any?>) -> Unit) {
        if (action == "cancel_capture" && busy && recording == null) {
            generation++; busy = false
            complete(fail("Photo countdown cancelled."))
            callback(ok("Photo countdown cancelled.")); return
        }
        if (busy && action != "cancel_capture") { callback(fail("Camera is busy. Wait for capture to finish.")); return }
        if (resultCallback != null) { callback(fail("A camera command is still finishing.")); return }
        resultCallback = callback
        try {
            when (action) {
                "preview" -> { front = args["lens"] == "front"; bind(false) { complete(ok("Camera ready.")) } }
                "switch_camera" -> {
                    check(recording == null) { "Stop video before switching cameras." }
                    front = when (args["lens"]) { "front" -> true; "back" -> false; else -> !front }
                    bind(false) { complete(ok("Switched to ${if (front) "front" else "back"} camera.")) }
                }
                "take_photo" -> {
                    check(recording == null) { "Stop video before taking a photo." }
                    if (args["lens"] != null) front = args["lens"] == "front"
                    busy = true
                    val token = ++generation
                    bind(false) {
                        val seconds = ((args["countdown"] as? Number)?.toInt() ?: 0).coerceIn(0, 30)
                        fun tick(remaining: Int) {
                            if (token != generation || isFinishing) return
                            if (remaining > 0) {
                                status.text = "Photo in $remaining…"
                                handler.postDelayed({ tick(remaining - 1) }, 1000L)
                            } else capturePhoto(args["title"]?.toString() ?: "Photo")
                        }
                        tick(seconds)
                    }
                }
                "start_video" -> {
                    check(recording == null) { "Video is already recording." }
                    check(AudioRecorderService.instance == null) { "Stop audio recording before starting video." }
                    check(ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) { "Microphone permission required for video." }
                    if (args["lens"] != null) front = args["lens"] == "front"
                    busy = true
                    bind(true) {
                        try {
                            videoFile = CueMediaStore(this).newFile("mp4")
                            videoTitle = args["title"]?.toString()?.ifBlank { "Video" } ?: "Video"
                            videoCapture?.targetRotation = preview.display.rotation
                            recording = videoCapture!!.output.prepareRecording(this, FileOutputOptions.Builder(videoFile!!).build())
                                .withAudioEnabled().start(ContextCompat.getMainExecutor(this)) { event ->
                                    when (event) {
                                        is VideoRecordEvent.Start -> { busy = false; status.text = "● Recording video"; complete(ok("Video recording started. Use Stop video to save.")) }
                                        is VideoRecordEvent.Finalize -> {
                                            recording = null; busy = false
                                            val result = if (event.hasError()) fail("Video failed (${event.error}).") else runCatching {
                                                ok("Saved video: $videoTitle", mapOf("media" to CueMediaStore(this).save(videoFile!!, "video", videoTitle)))
                                            }.getOrElse { fail(it.message ?: "Could not save video.") }
                                            status.text = result["summary"].toString()
                                            complete(result)
                                            CueEventBridge.emit(mapOf("type" to "mediaCaptureResult", "result" to result))
                                        }
                                    }
                                }
                        } catch (error: Exception) { completeFailure(error) }
                    }
                }
                "stop_video" -> {
                    check(recording != null) { "No active video recording." }
                    busy = true; status.text = "Saving video…"; recording?.stop()
                }
                "cancel_capture" -> { generation++; busy = false; complete(ok("Photo countdown cancelled.")) }
                else -> complete(fail("Unknown camera action."))
            }
        } catch (error: Exception) { completeFailure(error) }
    }

    private fun capturePhoto(title: String) {
        val file = CueMediaStore(this).newFile("jpg")
        imageCapture?.targetRotation = preview.display.rotation
        imageCapture!!.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    busy = false
                    val result = runCatching { ok("Saved photo: $title", mapOf("media" to CueMediaStore(this@CueCameraActivity).save(file, "photo", title))) }
                        .getOrElse { fail(it.message ?: "Could not save photo.") }
                    status.text = result["summary"].toString(); complete(result)
                    CueEventBridge.emit(mapOf("type" to "mediaCaptureResult", "result" to result))
                }
                override fun onError(exception: ImageCaptureException) { completeFailure(exception) }
            })
    }
    private fun complete(result: Map<String, Any?>) { val callback = resultCallback; resultCallback = null; callback?.invoke(result) }
    private fun completeFailure(error: Exception) {
        busy = false
        status.text = error.message ?: "Camera failed."
        complete(fail(status.text.toString()))
        pendingCommand?.third?.invoke(fail(status.text.toString())); pendingCommand = null
    }
    override fun onResume() {
        super.onResume()
        isForeground = true
        if (provider != null) {
            val pending = pendingCommand
            pendingCommand = null
            if (pending != null) execute(pending.first, pending.second, pending.third)
        }
    }
    override fun onPause() { isForeground = false; super.onPause() }
    override fun onStop() {
        generation++
        if (recording != null) recording?.stop()
        else if (busy) { busy = false; complete(fail("Capture cancelled because the camera left the screen.")) }
        super.onStop()
    }
    override fun onDestroy() {
        generation++; handler.removeCallbacksAndMessages(null)
        recording?.close(); voice?.shutdown()
        complete(fail("Camera closed."))
        if (instance === this) instance = null
        super.onDestroy()
    }
    companion object {
        var instance: CueCameraActivity? = null; private set
        val isRecording: Boolean get() = instance?.recording != null
        var pendingCommand: Triple<String, Map<String, Any?>, (Map<String, Any?>) -> Unit>? = null
        private fun ok(text: String, data: Map<String, Any?> = emptyMap()) = AudioRecorderService.ok(text, data)
        private fun fail(text: String) = AudioRecorderService.fail(text)
    }
}
