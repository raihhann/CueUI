package com.cueui.cueui_flutter

import android.Manifest
import android.content.*
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.util.concurrent.Executors

class CueMediaController(private val activity: MainActivity) {
    private val store = CueMediaStore(activity)
    private val transcriber = RecordingTranscriber(activity)
    private var player: MediaPlayer? = null
    private val worker = Executors.newSingleThreadExecutor()

    fun execute(action: String, args: Map<String, Any?>, callback: (Map<String, Any?>) -> Unit) {
        fun denied(permission: String, key: String, label: String): Boolean {
            if (ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) return false
            callback(mapOf("ok" to false, "summary" to "CueUI needs $label permission.", "data" to mapOf("missingPermissionKey" to key, "missingPermissionLabel" to label)))
            return true
        }
        try {
            when (action) {
                "list" -> worker.execute {
                    val result = runCatching { ok("Media library", mapOf("items" to store.list(args["query"]?.toString().orEmpty()), "recording" to (AudioRecorderService.instance?.state() ?: mapOf("active" to false)))) }.getOrElse { fail(it.message ?: "Could not load media.") }
                    activity.runOnUiThread { callback(result) }
                }
                "state" -> callback(ok("Recording state", mapOf("recording" to (AudioRecorderService.instance?.state() ?: mapOf("active" to false)), "videoActive" to CueCameraActivity.isRecording, "whatsAppVoiceActive" to CueEventBridge.whatsAppVoiceRecording)))
                "external_voice_state" -> { CueEventBridge.whatsAppVoiceRecording = args["active"] == true; callback(ok("Voice message state updated.")) }
                "start_audio" -> {
                    if (denied(Manifest.permission.RECORD_AUDIO, "MICROPHONE", "Microphone")) return
                    check(AudioRecorderService.instance == null && AudioRecorderService.pendingStart == null) { "Audio is already recording or starting." }
                    check(!CueCameraActivity.isRecording) { "Stop video recording first." }
                    player?.release(); player = null
                    AudioRecorderService.pendingStart = callback
                    val intent = Intent(activity, AudioRecorderService::class.java).putExtra("title", args["title"]?.toString())
                    try { ContextCompat.startForegroundService(activity, intent) }
                    catch (error: Exception) { AudioRecorderService.pendingStart = null; throw error }
                }
                "pause_audio" -> callback(AudioRecorderService.instance?.pause() ?: fail("No active audio recording."))
                "resume_audio" -> callback(AudioRecorderService.instance?.resume() ?: fail("No active audio recording."))
                "stop_audio" -> AudioRecorderService.instance?.stop(args["title"]?.toString(), callback) ?: callback(fail("No active audio recording."))
                "preview", "take_photo", "switch_camera", "start_video", "stop_video", "cancel_capture" -> {
                    if (denied(Manifest.permission.CAMERA, "CAMERA", "Camera")) return
                    if (action == "start_video" && denied(Manifest.permission.RECORD_AUDIO, "MICROPHONE", "Microphone")) return
                    if (action == "stop_video" || action == "cancel_capture") {
                        val camera = CueCameraActivity.instance
                        if (camera == null) callback(fail("No active camera session.")) else camera.execute(action, args, callback)
                    } else if (CueCameraActivity.instance?.isForeground == true) CueCameraActivity.instance!!.execute(action, args, callback)
                    else {
                        check(CueCameraActivity.pendingCommand == null) { "Camera is already opening." }
                        CueCameraActivity.pendingCommand = Triple(action, args, callback)
                        activity.startActivity(Intent(activity, CueCameraActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                    }
                }
                "play" -> {
                    val id = args["id"].toString()
                    val item = store.get(id) ?: error("Media not found.")
                    if (item["kind"] == "audio") {
                        check(AudioRecorderService.instance == null && !CueCameraActivity.isRecording) { "Stop recording before playback." }
                        player?.release()
                        player = MediaPlayer().apply {
                            setDataSource(store.file(id).absolutePath)
                            setOnCompletionListener { it.release(); if (player === it) player = null; CueEventBridge.emit(mapOf("type" to "playbackStopped")) }
                            setOnPreparedListener { it.start(); callback(ok("Playing ${item["title"]}.")) }
                            setOnErrorListener { _, _, _ -> callback(fail("Playback failed.")); true }
                            prepareAsync()
                        }
                    } else {
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.media", store.file(id))
                        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, item["mimeType"].toString()).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        callback(ok("Opened ${item["title"]}."))
                    }
                }
                "stop_playback" -> { player?.release(); player = null; callback(ok("Playback stopped.")) }
                "rename" -> callback(ok("Renamed media.", mapOf("media" to store.update(args["id"].toString(), title = args["title"].toString()))))
                "delete" -> { store.delete(args["id"].toString()); callback(ok("Deleted media.")) }
                "save_transcript" -> callback(ok("Transcript saved.", mapOf("media" to store.update(args["id"].toString(), transcript = args["transcript"].toString()))))
                "transcribe" -> transcriber.transcribe(args["id"].toString(), callback)
                "cancel_transcription" -> { transcriber.cancel(); callback(ok("Transcription cancelled.")) }
                "share" -> {
                    val id = args["id"].toString()
                    val item = store.get(id) ?: error("Media not found.")
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.media", store.file(id))
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = item["mimeType"].toString()
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_TEXT, args["caption"]?.toString().orEmpty())
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = ClipData.newRawUri("CueUI media", uri)
                    }
                    if (args["package"] != null) intent.setPackage(args["package"].toString())
                    activity.startActivity(if (args["package"] != null) intent else Intent.createChooser(intent, "Share ${item["title"]}"))
                    callback(ok("Opened media sharing."))
                }
                "load_preferences" -> callback(ok("Preferences", mapOf("theme" to activity.getPreferences(0).getString("theme", "system"))))
                "save_preferences" -> { activity.getPreferences(0).edit().putString("theme", args["theme"].toString()).apply(); callback(ok("Appearance saved.")) }
                else -> callback(fail("Unknown media action: $action"))
            }
        } catch (error: Exception) { callback(fail(error.message ?: "Media action failed.")) }
    }
    fun shutdown() { player?.release(); player = null; transcriber.shutdown(); worker.shutdown() }
    private fun ok(text: String, data: Map<String, Any?> = emptyMap()) = AudioRecorderService.ok(text, data)
    private fun fail(text: String) = AudioRecorderService.fail(text)
}
