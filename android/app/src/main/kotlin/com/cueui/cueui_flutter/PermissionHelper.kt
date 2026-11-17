package com.cueui.cueui_flutter

import android.Manifest
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

enum class AppPermissionKind(
    val key: String,
    val title: String,
    val runtimePermissions: List<String> = emptyList(),
) {
    CONTACTS("CONTACTS", "Contacts", listOf(Manifest.permission.READ_CONTACTS)),
    CALL_PHONE("CALL_PHONE", "Phone Calls", listOf(Manifest.permission.CALL_PHONE)),
    ANSWER_CALLS("ANSWER_CALLS", "Answer & End Calls", listOf(Manifest.permission.ANSWER_PHONE_CALLS)),
    SEND_SMS("SEND_SMS", "Send SMS", listOf(Manifest.permission.SEND_SMS)),
    READ_SMS("READ_SMS", "Read SMS", listOf(Manifest.permission.READ_SMS)),
    MICROPHONE("MICROPHONE", "Microphone", listOf(Manifest.permission.RECORD_AUDIO)),
    POST_NOTIFICATIONS(
        "POST_NOTIFICATIONS",
        "Notifications",
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            emptyList()
        },
    ),
    ACCESSIBILITY("ACCESSIBILITY", "Accessibility Control"),
    OVERLAY("OVERLAY", "Floating Bubble Overlay"),
    NOTIFICATION_LISTENER("NOTIFICATION_LISTENER", "Notification Reader"),
    WRITE_SETTINGS("WRITE_SETTINGS", "Screen Brightness"),
    DND_ACCESS("DND_ACCESS", "Do Not Disturb Access"),
    ;

    val isRuntime: Boolean get() = runtimePermissions.isNotEmpty()

    companion object {
        fun fromKey(key: String?): AppPermissionKind? =
            entries.firstOrNull { it.key.equals(key?.trim(), ignoreCase = true) }
    }
}

object PermissionHelper {
    private const val PREFS_NAME = "cueui_setup_prefs"
    private const val KEY_AUTO_PROMPTED_RUNTIME = "auto_prompted_runtime_v1"

    fun requiredRuntimePermissions(): Array<String> = buildList {
        add(Manifest.permission.READ_CONTACTS)
        add(Manifest.permission.CALL_PHONE)
        add(Manifest.permission.ANSWER_PHONE_CALLS)
        add(Manifest.permission.SEND_SMS)
        add(Manifest.permission.READ_SMS)
        add(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    fun missingRuntimePermissions(context: Context): Array<String> =
        requiredRuntimePermissions().filter { perm ->
            ContextCompat.checkSelfPermission(context, perm) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

    fun hasAutoPromptedRuntime(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTO_PROMPTED_RUNTIME, false)

    fun markAutoPromptedRuntime(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_AUTO_PROMPTED_RUNTIME, true)
            .apply()
    }

    fun isGranted(context: Context, kind: AppPermissionKind): Boolean {
        if (kind.runtimePermissions.isNotEmpty()) {
            return kind.runtimePermissions.all { perm ->
                ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
            }
        }
        return when (kind) {
            AppPermissionKind.POST_NOTIFICATIONS -> true
            AppPermissionKind.ACCESSIBILITY -> isAccessibilityServiceEnabled(context)
            AppPermissionKind.OVERLAY -> Settings.canDrawOverlays(context)
            AppPermissionKind.NOTIFICATION_LISTENER -> isNotificationListenerEnabled(context)
            AppPermissionKind.WRITE_SETTINGS -> Settings.System.canWrite(context)
            AppPermissionKind.DND_ACCESS -> {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.isNotificationPolicyAccessGranted
            }
            else -> true
        }
    }

    fun openSpecialSettings(context: Context, kind: AppPermissionKind) {
        when (kind) {
            AppPermissionKind.ACCESSIBILITY ->
                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            AppPermissionKind.OVERLAY -> openOverlaySettings(context)
            AppPermissionKind.NOTIFICATION_LISTENER ->
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            AppPermissionKind.WRITE_SETTINGS ->
                context.startActivity(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            AppPermissionKind.DND_ACCESS ->
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            else -> openAppDetailsSettings(context)
        }
    }

    fun openOverlaySettings(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun openAppDetailsSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val fallback = Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.onFailure { context.startActivity(fallback) }
    }

    fun snapshotMap(context: Context): Map<String, Any?> {
        fun granted(perm: String) =
            ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val contacts = granted(Manifest.permission.READ_CONTACTS)
        val callPhone = granted(Manifest.permission.CALL_PHONE)
        val answerCalls = granted(Manifest.permission.ANSWER_PHONE_CALLS)
        val sendSms = granted(Manifest.permission.SEND_SMS)
        val readSms = granted(Manifest.permission.READ_SMS)
        val mic = granted(Manifest.permission.RECORD_AUDIO)
        val postNotif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            granted(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            true
        }
        val a11y = isAccessibilityServiceEnabled(context)
        val overlay = Settings.canDrawOverlays(context)
        val notifListener = isNotificationListenerEnabled(context)
        val writeSettings = Settings.System.canWrite(context)
        val dnd = nm.isNotificationPolicyAccessGranted

        val missing = buildList<Map<String, Any?>> {
            fun addIf(cond: Boolean, kind: AppPermissionKind) {
                if (!cond) add(mapOf("key" to kind.key, "title" to kind.title, "isRuntime" to kind.isRuntime))
            }
            addIf(contacts, AppPermissionKind.CONTACTS)
            addIf(callPhone, AppPermissionKind.CALL_PHONE)
            addIf(answerCalls, AppPermissionKind.ANSWER_CALLS)
            addIf(sendSms, AppPermissionKind.SEND_SMS)
            addIf(readSms, AppPermissionKind.READ_SMS)
            addIf(mic, AppPermissionKind.MICROPHONE)
            addIf(postNotif, AppPermissionKind.POST_NOTIFICATIONS)
            addIf(a11y, AppPermissionKind.ACCESSIBILITY)
            addIf(overlay, AppPermissionKind.OVERLAY)
            addIf(notifListener, AppPermissionKind.NOTIFICATION_LISTENER)
        }

        return mapOf(
            "isDefaultLauncher" to isDefaultLauncher(context),
            "accessibilityEnabled" to a11y,
            "overlayEnabled" to overlay,
            "notificationListenerEnabled" to notifListener,
            "contactsGranted" to contacts,
            "callPhoneGranted" to callPhone,
            "answerCallsGranted" to answerCalls,
            "sendSmsGranted" to sendSms,
            "readSmsGranted" to readSms,
            "recordAudioGranted" to mic,
            "postNotificationsGranted" to postNotif,
            "writeSettingsGranted" to writeSettings,
            "dndPolicyGranted" to dnd,
            "coreMissing" to missing,
        )
    }

    fun isDefaultLauncher(context: Context): Boolean {
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == context.packageName
    }

    fun createDefaultLauncherRequestIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = context.getSystemService(Context.ROLE_SERVICE) as? RoleManager
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_HOME) && !rm.isRoleHeld(RoleManager.ROLE_HOME)) {
                return rm.createRequestRoleIntent(RoleManager.ROLE_HOME)
            }
        }
        return null
    }

    fun openHomeLauncherSettings(context: Context) {
        val intent = Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val fallback = Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.onFailure { context.startActivity(fallback) }
    }

    fun isAccessibilityServiceEnabled(context: Context): Boolean {
        if (CueAccessibilityService.isConnected()) return true
        val expected = ComponentName(context, CueAccessibilityService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    fun isNotificationListenerEnabled(context: Context): Boolean {
        if (CueNotificationListener.isConnected) return true
        val expected = ComponentName(context, CueNotificationListener::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }
}
