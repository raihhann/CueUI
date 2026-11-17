package com.cueui.cueui_flutter

import android.content.Context
import android.media.MediaMetadataRetriever
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Private media and metadata. Only this directory is exposed by FileProvider. */
class CueMediaStore(private val context: Context) {
    val directory: File get() = File(context.filesDir, "cue_media").apply { mkdirs() }

    fun newFile(extension: String): File = File(directory, "${System.currentTimeMillis()}_${UUID.randomUUID()}.$extension")

    @Synchronized fun save(file: File, kind: String, title: String): Map<String, Any?> {
        require(owns(file) && file.exists() && file.length() > 0) { "Media was not saved." }
        val duration = if (kind == "photo") 0L else runCatching {
            MediaMetadataRetriever().let { reader ->
                try {
                    reader.setDataSource(file.absolutePath)
                    reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                } finally { reader.release() }
            }
        }.getOrDefault(0L)
        val json = JSONObject().put("id", file.name).put("path", file.absolutePath)
            .put("kind", kind).put("title", title.trim().ifBlank { kind.replaceFirstChar(Char::uppercase) })
            .put("createdAt", System.currentTimeMillis()).put("durationMs", duration)
            .put("mimeType", when (kind) { "photo" -> "image/jpeg"; "video" -> "video/mp4"; else -> "audio/wav" })
            .put("transcript", "")
        write(file, json)
        changed()
        return asMap(json)
    }

    @Synchronized fun list(query: String = ""): List<Map<String, Any?>> {
        // Recover PCM written before an unexpected process death. An active
        // recording is never indexed, played, deleted or repaired mid-write.
        directory.listFiles().orEmpty().filter {
            it.extension == "wav" && it.length() > 44 && !sidecar(it).exists() && it.absolutePath != AudioRecorderService.activeFilePath
        }.forEach { file -> runCatching {
            java.io.RandomAccessFile(file, "rw").use { output ->
                output.seek(0); output.write(AudioRecorderService.wavHeader((output.length() - 44).toInt()))
            }
            save(file, "audio", "Recovered recording")
        } }
        return directory.listFiles().orEmpty()
        .filter { it.extension == "json" }
        .mapNotNull { runCatching { JSONObject(it.readText()) }.getOrNull() }
        .filter { File(it.optString("path")).let { file -> owns(file) && file.exists() } }
        .filter { query.isBlank() || "${it.optString("title")} ${it.optString("transcript")}".contains(query, true) }
        .sortedByDescending { it.optLong("createdAt") }.map(::asMap)
    }

    fun get(id: String): Map<String, Any?>? = list().firstOrNull { it["id"] == id }
    fun file(id: String): File {
        val asset = get(id) ?: error("Media item not found.")
        return File(asset["path"].toString()).also { require(owns(it)) }
    }

    @Synchronized fun update(id: String, title: String? = null, transcript: String? = null): Map<String, Any?> {
        val file = file(id)
        val json = JSONObject(sidecar(file).readText())
        if (title != null) { require(title.isNotBlank()); json.put("title", title.trim()) }
        if (transcript != null) json.put("transcript", transcript)
        write(file, json)
        changed()
        return asMap(json)
    }

    @Synchronized fun delete(id: String) {
        val file = file(id)
        require(file.delete()) { "Could not delete media." }
        sidecar(file).delete()
        changed()
    }

    private fun owns(file: File) = file.canonicalFile.parentFile == directory.canonicalFile
    private fun sidecar(file: File) = File(directory, "${file.name}.json")
    private fun write(file: File, json: JSONObject) {
        val temporary = File(directory, "${file.name}.json.tmp")
        temporary.writeText(json.toString())
        check(temporary.renameTo(sidecar(file))) { "Could not save media metadata." }
    }
    private fun asMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { json.get(it) }
    private fun changed() = CueEventBridge.emit(mapOf("type" to "mediaUpdated"))
}
