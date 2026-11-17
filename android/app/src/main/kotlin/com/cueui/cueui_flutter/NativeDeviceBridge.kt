package com.cueui.cueui_flutter

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import android.telephony.SmsManager
import android.view.KeyEvent
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class NativeDeviceBridge(private val context: Context) {

    private val phoneRegex = Regex("""^[+\d\s().-]{3,}$""")

    fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun looksLikePhoneNumber(value: String): Boolean = phoneRegex.matches(value.trim())

    private fun missingPermResult(kind: AppPermissionKind, summary: String): Map<String, Any?> = mapOf(
        "ok" to false,
        "summary" to summary,
        "data" to mapOf(
            "missingPermissionKey" to kind.key,
            "missingPermissionLabel" to kind.title,
        ),
    )

    private fun missingAppResult(
        displayName: String,
        packageName: String? = null,
        fallbackQuery: String? = null,
    ): Map<String, Any?> {
        val label = displayName.trim().ifBlank { "That app" }
        val data = mutableMapOf<String, Any?>("missingAppName" to label)
        if (!packageName.isNullOrBlank()) data["missingPackage"] = packageName
        if (!fallbackQuery.isNullOrBlank()) data["fallbackQuery"] = fallbackQuery
        return mapOf(
            "ok" to false,
            "summary" to "$label is not installed on this device.",
            "data" to data,
        )
    }

    fun findContacts(query: String): Map<String, Any?> {
        if (!hasPermission(Manifest.permission.READ_CONTACTS)) {
            return missingPermResult(AppPermissionKind.CONTACTS, "CueUI needs Contacts permission to look up people by name.")
        }
        val needle = query.trim().lowercase()
        val results = mutableListOf<Map<String, String>>()
        val seen = mutableSetOf<Pair<String, String>>()

        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            ),
            null,
            null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC",
        )?.use { cursor ->
            val nameIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (cursor.moveToNext() && results.size < 10) {
                val name = cursor.getString(nameIdx)?.trim().orEmpty()
                val num = cursor.getString(numIdx)?.trim().orEmpty()
                if (name.isEmpty() || num.isEmpty()) continue
                if (needle.isEmpty() || needle in name.lowercase()) {
                    if (seen.add(name to num)) {
                        results += mapOf("name" to name, "number" to num)
                    }
                }
            }
        }
        val summary = if (results.isEmpty()) {
            "No contact matching '$query'."
        } else {
            results.joinToString("\n") { "- ${it["name"]}: ${it["number"]}" }
        }
        return mapOf("ok" to true, "summary" to summary, "data" to mapOf("contacts" to results))
    }

    fun resolveRecipient(target: String): Map<String, Any?> {
        val cleaned = target.trim()
        if (looksLikePhoneNumber(cleaned)) {
            val digits = cleaned.replace(Regex("""[\s().-]"""), "")
            return mapOf("ok" to true, "label" to cleaned, "number" to digits)
        }
        if (!hasPermission(Manifest.permission.READ_CONTACTS)) {
            return missingPermResult(AppPermissionKind.CONTACTS, "CueUI needs Contacts permission to look up '$target'.")
        }
        val contactsRes = findContacts(cleaned)
        @Suppress("UNCHECKED_CAST")
        val list = ((contactsRes["data"] as? Map<String, Any?>)?.get("contacts") as? List<Map<String, String>>).orEmpty()
        val best = list.firstOrNull()
            ?: return mapOf("ok" to false, "summary" to "No contact matching '$target' found.")
        val number = best["number"].orEmpty().replace(Regex("""[\s().-]"""), "")
        return mapOf("ok" to true, "label" to "${best["name"]} (${best["number"]})", "number" to number)
    }

    fun placeCall(target: String, dialOnly: Boolean): Map<String, Any?> {
        val res = resolveRecipient(target)
        if (res["ok"] != true) return res
        val label = res["label"] as String
        val number = res["number"] as String
        if (dialOnly) {
            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            return mapOf("ok" to true, "summary" to "Opened dialer for $label.")
        }
        if (!hasPermission(Manifest.permission.CALL_PHONE)) {
            return missingPermResult(AppPermissionKind.CALL_PHONE, "CueUI needs Phone Calls permission to call $label directly.")
        }
        val callIntent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(callIntent)
        return mapOf("ok" to true, "summary" to "Calling $label.")
    }

    @SuppressLint("MissingPermission")
    fun answerCall(): Map<String, Any?> {
        if (!hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
            return missingPermResult(AppPermissionKind.ANSWER_CALLS, "CueUI needs Phone Call Management permission to answer incoming calls.")
        }
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        telecom.acceptRingingCall()
        return mapOf("ok" to true, "summary" to "Answered incoming call.")
    }

    @SuppressLint("MissingPermission")
    fun endCall(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return mapOf("ok" to false, "summary" to "Programmatic end_call requires Android 9+.")
        }
        if (!hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
            return missingPermResult(AppPermissionKind.ANSWER_CALLS, "CueUI needs Phone Call Management permission to end calls.")
        }
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        @Suppress("DEPRECATION")
        val ended = telecom.endCall()
        return mapOf("ok" to ended, "summary" to if (ended) "Ended call." else "No active call to end.")
    }

    fun sendSms(recipient: String, message: String): Map<String, Any?> {
        val res = resolveRecipient(recipient)
        if (res["ok"] != true) return res
        val label = res["label"] as String
        val number = res["number"] as String
        if (!hasPermission(Manifest.permission.SEND_SMS)) {
            return missingPermResult(AppPermissionKind.SEND_SMS, "CueUI needs Send SMS permission to text $label.")
        }
        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        } ?: return mapOf("ok" to false, "summary" to "SmsManager unavailable on this device.")

        val parts = smsManager.divideMessage(message)
        if (parts.size > 1) {
            smsManager.sendMultipartTextMessage(number, null, parts, null, null)
        } else {
            smsManager.sendTextMessage(number, null, message, null, null)
        }
        return mapOf("ok" to true, "summary" to "SMS sent to $label.")
    }

    fun readSms(limit: Int = 5): Map<String, Any?> {
        if (!hasPermission(Manifest.permission.READ_SMS)) {
            return missingPermResult(AppPermissionKind.READ_SMS, "CueUI needs Read SMS permission to check your text messages.")
        }
        val messages = mutableListOf<Map<String, String>>()
        val sdf = SimpleDateFormat("MMM d HH:mm", Locale.getDefault())
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            null,
            null,
            "${Telephony.Sms.DATE} DESC",
        )?.use { cursor ->
            val addrIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (cursor.moveToNext() && messages.size < limit.coerceIn(1, 20)) {
                val dateMs = cursor.getLong(dateIdx)
                messages += mapOf(
                    "from" to cursor.getString(addrIdx).orEmpty(),
                    "body" to cursor.getString(bodyIdx).orEmpty().take(180),
                    "time" to sdf.format(Date(dateMs)),
                )
            }
        }
        val summary = if (messages.isEmpty()) {
            "SMS inbox is empty."
        } else {
            messages.joinToString("\n") { "- ${it["from"]} (${it["time"]}): ${it["body"]}" }
        }
        return mapOf("ok" to true, "summary" to summary, "data" to mapOf("messages" to messages))
    }

    fun readNotifications(limit: Int = 10, packageFilter: String? = null): Map<String, Any?> {
        if (!CueNotificationListener.isConnected) {
            return missingPermResult(AppPermissionKind.NOTIFICATION_LISTENER, "CueUI needs Notification Reader access to check your notifications.")
        }
        val items = CueNotificationListener.latest(limit.coerceIn(1, 30)).let { list ->
            val filter = packageFilter?.trim()?.lowercase().orEmpty()
            if (filter.isEmpty()) list else list.filter { filter in it.packageName.lowercase() }
        }
        if (items.isEmpty()) {
            return mapOf(
                "ok" to true,
                "summary" to if (packageFilter.isNullOrBlank()) "No recent notifications captured." else "No recent $packageFilter notifications captured.",
            )
        }
        val summary = items.joinToString("\n") { n ->
            val replyTag = if (n.replyAction != null) " [replyable]" else ""
            "- [${n.packageName.substringAfterLast('.')}] ${n.title}: ${n.text.take(140)}$replyTag"
        }
        return mapOf("ok" to true, "summary" to summary)
    }

    fun readUnifiedMessages(limit: Int = 8, sourceFilter: String? = null): Map<String, Any?> {
        val filter = sourceFilter?.trim()?.lowercase().orEmpty()
        val sections = mutableListOf<String>()

        if (filter == "whatsapp" || filter.isEmpty()) {
            if (CueNotificationListener.isConnected) {
                val notifs = CueNotificationListener.latest(limit).filter { n ->
                    val pkg = n.packageName.lowercase()
                    if (filter == "whatsapp") "whatsapp" in pkg
                    else "whatsapp" in pkg || "messaging" in pkg || "mms" in pkg || "telegram" in pkg || n.replyAction != null
                }
                if (notifs.isNotEmpty()) {
                    val block = notifs.joinToString("\n") { n ->
                        val appLabel = when {
                            "whatsapp" in n.packageName.lowercase() -> "WhatsApp"
                            "telegram" in n.packageName.lowercase() -> "Telegram"
                            else -> n.packageName.substringAfterLast('.')
                        }
                        "- [$appLabel] ${n.title}: ${n.text.take(140)}"
                    }
                    sections += "Recent messages:\n$block"
                }
            } else if (filter == "whatsapp") {
                return missingPermResult(AppPermissionKind.NOTIFICATION_LISTENER, "CueUI needs Notification Reader access to read incoming WhatsApp messages.")
            }
        }

        if ((filter == "sms" || filter.isEmpty()) && hasPermission(Manifest.permission.READ_SMS)) {
            val smsRes = readSms(limit.coerceAtMost(5))
            val smsSummary = smsRes["summary"] as? String ?: ""
            if (smsRes["ok"] == true && smsSummary != "SMS inbox is empty.") {
                sections += "Recent SMS:\n$smsSummary"
            }
        } else if (filter == "sms") {
            return readSms(limit)
        }

        if (sections.isEmpty()) {
            if (!CueNotificationListener.isConnected && !hasPermission(Manifest.permission.READ_SMS)) {
                return missingPermResult(AppPermissionKind.READ_SMS, "CueUI needs SMS permission (or Notification Reader access) to read your messages.")
            }
            return mapOf("ok" to true, "summary" to "No recent incoming messages or texts found.")
        }
        return mapOf("ok" to true, "summary" to sections.joinToString("\n\n"))
    }

    fun replyNotification(senderQuery: String, message: String): Map<String, Any?> {
        if (!CueNotificationListener.isConnected) {
            return missingPermResult(AppPermissionKind.NOTIFICATION_LISTENER, "CueUI needs Notification Reader access to reply to notifications.")
        }
        return CueNotificationListener.sendInlineReply(senderQuery, message, context).fold(
            onSuccess = { mapOf("ok" to true, "summary" to it) },
            onFailure = { mapOf("ok" to false, "summary" to (it.message ?: "Inline reply failed.")) },
        )
    }

    fun findWhatsAppPackage(): String? {
        val pm = context.packageManager
        return listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull { pm.getLaunchIntentForPackage(it) != null }
    }

    fun launchWhatsAppChatByPhone(packageName: String, phoneDigits: String, message: String): Boolean = runCatching {
        val uri = Uri.parse("https://api.whatsapp.com/send?phone=$phoneDigits&text=${Uri.encode(message)}")
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        true
    }.getOrDefault(false)

    fun openApp(appQuery: String): Map<String, Any?> {
        val needle = appQuery.trim().lowercase()
        if (needle.isEmpty()) return mapOf("ok" to false, "summary" to "App name is empty.")
        val pm = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val candidates = pm.queryIntentActivities(mainIntent, 0).map { info ->
            info.loadLabel(pm).toString() to info.activityInfo.packageName
        }
        val best = candidates.firstOrNull { it.first.equals(appQuery.trim(), ignoreCase = true) }
            ?: candidates.firstOrNull { it.second.equals(appQuery.trim(), ignoreCase = true) }
            ?: candidates.firstOrNull { needle in it.first.lowercase() }
            ?: candidates.firstOrNull { needle in it.second.lowercase() }
            ?: run {
                val known = KNOWN_PACKAGES[needle]
                return missingAppResult(displayName = known?.second ?: appQuery.trim(), packageName = known?.first)
            }
        val launch = pm.getLaunchIntentForPackage(best.second)?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            ?: return mapOf("ok" to false, "summary" to "App '${best.first}' (${best.second}) has no launcher activity.")
        context.startActivity(launch)
        return mapOf("ok" to true, "summary" to "Opened ${best.first} (${best.second}).")
    }

    fun listInstalledApps(): Map<String, Any?> {
        val pm = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val labels = pm.queryIntentActivities(mainIntent, 0)
            .map { "${it.loadLabel(pm)} (${it.activityInfo.packageName})" }
            .distinct()
            .sorted()
        return mapOf(
            "ok" to true,
            "summary" to ("Installed apps (${labels.size}):\n" + labels.take(40).joinToString("\n")),
            "data" to mapOf("count" to labels.size),
        )
    }

    fun loadLaunchableApps(): List<Map<String, Any?>> {
        val pm = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(mainIntent, 0)
            .asSequence()
            .filter { it.activityInfo.packageName != context.packageName }
            .distinctBy { it.activityInfo.packageName }
            .map { info ->
                val label = info.loadLabel(pm).toString()
                val pkg = info.activityInfo.packageName
                val iconBytes = runCatching { drawableToPngBytes(info.loadIcon(pm)) }.getOrNull()
                mapOf("label" to label, "packageName" to pkg, "iconBytes" to iconBytes)
            }
            .sortedBy { (it["label"] as String).lowercase(Locale.US) }
            .toList()
    }

    private fun drawableToPngBytes(drawable: Drawable, sizePx: Int = 96): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, sizePx, sizePx, true)
        } else {
            Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888).also { bmp ->
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
        return out.toByteArray()
    }

    fun launchPackage(packageName: String): Map<String, Any?> {
        val launch = context.packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        } ?: return mapOf("ok" to false, "summary" to "Cannot launch $packageName.")
        context.startActivity(launch)
        return mapOf("ok" to true, "summary" to "Opened $packageName.")
    }

    fun youtubeSearch(query: String): Map<String, Any?> {
        val cleaned = query.trim()
        if (cleaned.isEmpty()) return openApp("YouTube")
        val url = "https://www.youtube.com/results?search_query=${Uri.encode(cleaned)}"
        val ytPkg = "com.google.android.youtube"
        val ytInstalled = context.packageManager.getLaunchIntentForPackage(ytPkg) != null
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (ytInstalled) setPackage(ytPkg)
        }
        return runCatching {
            context.startActivity(intent)
            mapOf("ok" to true, "summary" to "Opened YouTube search for '$cleaned'.")
        }.getOrElse {
            openUrl(url)
        }
    }

    fun spotifyPlayOrSearch(query: String): Map<String, Any?> {
        val cleaned = query.trim()
        if (cleaned.isEmpty()) return openApp("Spotify")
        val spotifyPkg = "com.spotify.music"
        val pm = context.packageManager
        if (pm.getLaunchIntentForPackage(spotifyPkg) == null) {
            return missingAppResult(displayName = "Spotify", packageName = spotifyPkg, fallbackQuery = cleaned)
        }
        val mediaIntent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
            setPackage(spotifyPkg)
            putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
            putExtra(SearchManager.QUERY, cleaned)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (mediaIntent.resolveActivity(pm) != null) {
            context.startActivity(mediaIntent)
            return mapOf("ok" to true, "summary" to "Sent playback search '$cleaned' to Spotify.")
        }
        val deepLink = Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:${Uri.encode(cleaned)}")).apply {
            setPackage(spotifyPkg)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(deepLink)
        return mapOf("ok" to true, "summary" to "Opened Spotify search for '$cleaned'.")
    }

    fun openPlayStore(packageName: String?, appName: String): Map<String, Any?> {
        val known = KNOWN_PACKAGES[appName.trim().lowercase()]
        val pkg = packageName?.trim()?.ifBlank { null } ?: known?.first.orEmpty()
        val label = known?.second ?: appName.trim().ifBlank { pkg.ifBlank { "app" } }

        val pm = context.packageManager
        if (pkg.isNotEmpty() && pm.getLaunchIntentForPackage(pkg) != null) {
            return mapOf(
                "ok" to true,
                "summary" to "$label is already installed on your phone.",
                "data" to mapOf("alreadyInstalled" to true, "installedPackage" to pkg),
            )
        }
        val installedMatch = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .firstOrNull { it.loadLabel(pm).toString().equals(label, ignoreCase = true) }
        if (installedMatch != null) {
            return mapOf(
                "ok" to true,
                "summary" to "${installedMatch.loadLabel(pm)} is already installed on your phone.",
                "data" to mapOf("alreadyInstalled" to true, "installedPackage" to installedMatch.activityInfo.packageName),
            )
        }

        val playPkg = "com.android.vending"
        val marketUri = if (pkg.isNotEmpty()) {
            Uri.parse("market://details?id=${Uri.encode(pkg)}")
        } else {
            Uri.parse("market://search?q=${Uri.encode(label)}&c=apps")
        }
        val marketIntent = Intent(Intent.ACTION_VIEW, marketUri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (pm.getLaunchIntentForPackage(playPkg) != null) setPackage(playPkg)
        }
        if (marketIntent.resolveActivity(pm) != null) {
            context.startActivity(marketIntent)
            return mapOf("ok" to true, "summary" to "Opened Google Play Store for $label.")
        }
        val webUrl = if (pkg.isNotEmpty()) {
            "https://play.google.com/store/apps/details?id=${Uri.encode(pkg)}"
        } else {
            "https://play.google.com/store/search?q=${Uri.encode(label)}&c=apps"
        }
        return openUrl(webUrl)
    }

    fun openWeatherAppFallback(errMsg: String): Map<String, Any?>? {
        val pm = context.packageManager
        val weatherApp = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .firstOrNull { info ->
                val pkg = info.activityInfo.packageName.lowercase()
                val lbl = info.loadLabel(pm).toString().lowercase()
                pkg != context.packageName && ("weather" in lbl || "weather" in pkg)
            } ?: return null
        val launch = pm.getLaunchIntentForPackage(weatherApp.activityInfo.packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) } ?: return null
        context.startActivity(launch)
        return mapOf("ok" to true, "summary" to "Opened ${weatherApp.loadLabel(pm)} for weather ($errMsg).")
    }

    fun openUrl(url: String): Map<String, Any?> {
        val normalized = if (url.startsWith("http://") || url.startsWith("https://")) url else "https://$url"
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(normalized)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return mapOf("ok" to true, "summary" to "Opened $normalized.")
    }

    fun setFlashlight(enabled: Boolean): Map<String, Any?> {
        val camManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = camManager.cameraIdList.firstOrNull { id ->
            val chars = camManager.getCameraCharacteristics(id)
            chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } ?: camManager.cameraIdList.firstOrNull { id ->
            camManager.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return mapOf("ok" to false, "summary" to "No camera flashlight found on this device.")
        return try {
            camManager.setTorchMode(cameraId, enabled)
            mapOf("ok" to true, "summary" to "Flashlight turned ${if (enabled) "ON" else "OFF"}.")
        } catch (t: Throwable) {
            mapOf("ok" to false, "summary" to "Failed to toggle flashlight: ${t.message}")
        }
    }

    fun setBrightness(percent: Int): Map<String, Any?> {
        if (!Settings.System.canWrite(context)) {
            return missingPermResult(AppPermissionKind.WRITE_SETTINGS, "CueUI needs Modify System Settings permission to adjust screen brightness.")
        }
        val clamped = percent.coerceIn(1, 100)
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, (clamped * 255) / 100)
        return mapOf("ok" to true, "summary" to "Set brightness to $clamped%.")
    }

    fun setDnd(enabled: Boolean): Map<String, Any?> {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.isNotificationPolicyAccessGranted) {
            return missingPermResult(AppPermissionKind.DND_ACCESS, "CueUI needs Do Not Disturb access to toggle DND mode.")
        }
        nm.setInterruptionFilter(
            if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL,
        )
        return mapOf("ok" to true, "summary" to "Do Not Disturb ${if (enabled) "enabled" else "disabled"}.")
    }

    fun openConnectivityPanel(setting: String, desired: Boolean?): Map<String, Any?> {
        val action = when (setting.lowercase()) {
            "wifi", "wi-fi" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS
            "internet", "mobile_data", "data" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_WIRELESS_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val hint = if (desired != null) " (toggle ${if (desired) "ON" else "OFF"})" else ""
        return mapOf("ok" to true, "summary" to "Opened $setting panel$hint — Android restricts background toggling on Android 10+.")
    }

    fun mediaControl(action: String): Map<String, Any?> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (action.lowercase()) {
            "volume_up" -> {
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                return mapOf("ok" to true, "summary" to "Increased media volume.")
            }
            "volume_down" -> {
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                return mapOf("ok" to true, "summary" to "Decreased media volume.")
            }
            "mute" -> {
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, AudioManager.FLAG_SHOW_UI)
                return mapOf("ok" to true, "summary" to "Muted media audio.")
            }
        }
        val keyCode = when (action.lowercase()) {
            "play_pause", "play", "pause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return mapOf("ok" to false, "summary" to "Unknown media action '$action'.")
        }
        val now = SystemClock.uptimeMillis()
        audio.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0))
        audio.dispatchMediaKeyEvent(KeyEvent(now, now + 10, KeyEvent.ACTION_UP, keyCode, 0))
        return mapOf("ok" to true, "summary" to "Sent media command: $action.")
    }

    fun setAlarm(hour: Int, minute: Int, label: String): Map<String, Any?> {
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
            putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
            putExtra(AlarmClock.EXTRA_MESSAGE, label.ifBlank { "CueUI Alarm" })
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            mapOf("ok" to true, "summary" to String.format(Locale.US, "Alarm set for %02d:%02d (%s).", hour, minute, label))
        } catch (t: Throwable) {
            mapOf("ok" to false, "summary" to "Failed to set alarm: ${t.message}")
        }
    }

    fun setTimer(seconds: Int, label: String): Map<String, Any?> {
        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceAtLeast(1))
            putExtra(AlarmClock.EXTRA_MESSAGE, label.ifBlank { "CueUI Timer" })
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            mapOf("ok" to true, "summary" to "Timer set for ${seconds}s ($label).")
        } catch (t: Throwable) {
            mapOf("ok" to false, "summary" to "Failed to set timer: ${t.message}")
        }
    }

    fun openCamera(mode: String): Map<String, Any?> {
        val normalized = mode.trim().lowercase()
        val action = if (normalized == "video") MediaStore.INTENT_ACTION_VIDEO_CAMERA else MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA
        val intent = Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (normalized == "selfie") {
                putExtra("android.intent.extras.CAMERA_FACING", 1)
                putExtra("android.intent.extras.LENS_FACING_FRONT", 1)
                putExtra("android.intent.extra.USE_FRONT_CAMERA", true)
            }
        }
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
            val label = when (normalized) {
                "video" -> "video camera"
                "selfie" -> "front selfie camera"
                else -> "camera"
            }
            return mapOf("ok" to true, "summary" to "Opened $label.")
        }
        return openApp("Camera")
    }

    fun openCalendar(): Map<String, Any?> {
        val calUri = CalendarContract.CONTENT_URI.buildUpon()
            .appendPath("time")
            .appendPath(System.currentTimeMillis().toString())
            .build()
        val intent = Intent(Intent.ACTION_VIEW, calUri).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
            return mapOf("ok" to true, "summary" to "Opened Calendar.")
        }
        return openApp("Calendar")
    }

    fun createCalendarEvent(title: String, hour: Int?, minute: Int, dayOffset: Int): Map<String, Any?> {
        val cleanTitle = title.trim().ifBlank { "CueUI Event" }
        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, cleanTitle)
            if (hour != null || dayOffset > 0) {
                val cal = Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, dayOffset.coerceAtLeast(0))
                    if (hour != null) {
                        set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
                        set(Calendar.MINUTE, minute.coerceIn(0, 59))
                        set(Calendar.SECOND, 0)
                    }
                }
                val startMs = cal.timeInMillis
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, startMs + 3600_000L)
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
            val timeNote = if (hour != null) String.format(Locale.US, " at %02d:%02d", hour.coerceIn(0, 23), minute.coerceIn(0, 59)) else ""
            val dayNote = when (dayOffset) {
                0 -> ""
                1 -> " for tomorrow"
                else -> " in $dayOffset days"
            }
            return mapOf("ok" to true, "summary" to "Opened Calendar to create \"$cleanTitle\"$dayNote$timeNote.")
        }
        return openCalendar()
    }

    fun getDeviceStatus(): Map<String, Any?> {
        val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val batteryPct = if (level >= 0 && scale > 0) (level * 100) / scale else -1
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val a11y = CueAccessibilityService.instance
        val activePkg = a11y?.currentPackageName?.ifBlank { "unknown" } ?: "accessibility-off"

        val summary = buildString {
            append("Battery: $batteryPct%${if (charging) " (charging)" else ""}, ")
            append("Screen: ${if (pm.isInteractive) "ON" else "OFF"}, ")
            append("Active app: $activePkg, ")
            append("Accessibility: ${if (a11y != null) "CONNECTED" else "OFF"}, ")
            append("Notifications: ${if (CueNotificationListener.isConnected) "CONNECTED" else "OFF"}")
        }
        return mapOf("ok" to true, "summary" to summary)
    }

    fun discoverExternalGgufPaths(): List<String> {
        val candidates = mutableListOf<String>()
        val roots = listOfNotNull(
            File("/data/local/tmp/llm"),
            File("/data/local/tmp"),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS) }.getOrNull(),
            context.getExternalFilesDir(null),
            context.filesDir,
        )
        for (dir in roots) {
            if (!dir.exists() || !dir.isDirectory) continue
            runCatching {
                dir.listFiles()?.forEach { f ->
                    if (f.isFile && f.name.endsWith(".gguf", ignoreCase = true) && f.canRead() && f.length() > 1_000_000L) {
                        candidates += f.absolutePath
                    }
                }
            }
        }
        return candidates.distinct()
    }

    companion object {
        private val KNOWN_PACKAGES: Map<String, Pair<String, String>> = mapOf(
            "spotify" to ("com.spotify.music" to "Spotify"),
            "whatsapp" to ("com.whatsapp" to "WhatsApp"),
            "instagram" to ("com.instagram.android" to "Instagram"),
            "telegram" to ("org.telegram.messenger" to "Telegram"),
            "discord" to ("com.discord" to "Discord"),
            "netflix" to ("com.netflix.mediaclient" to "Netflix"),
            "uber" to ("com.ubercab" to "Uber"),
            "youtube music" to ("com.google.android.apps.youtube.music" to "YouTube Music"),
            "twitter" to ("com.twitter.android" to "X (Twitter)"),
            "x" to ("com.twitter.android" to "X (Twitter)"),
        )
    }
}
