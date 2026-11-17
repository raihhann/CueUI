package com.cueui.cueui_flutter

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

data class CapturedNotification(
    val key: String,
    val packageName: String,
    val title: String,
    val text: String,
    val timestampMs: Long,
    val replyAction: Notification.Action?,
)

class CueNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        activeNotifications?.forEach(::recordNotification)
    }

    override fun onListenerDisconnected() {
        isConnected = false
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) recordNotification(sbn)
    }

    private fun recordNotification(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        val replyAction = sbn.notification?.actions?.firstOrNull { action ->
            action.remoteInputs?.isNotEmpty() == true && action.actionIntent != null
        }

        val entry = CapturedNotification(
            key = sbn.key,
            packageName = sbn.packageName,
            title = title,
            text = text,
            timestampMs = sbn.postTime,
            replyAction = replyAction,
        )

        synchronized(lock) {
            buffer.removeAll { it.key == entry.key }
            buffer.addFirst(entry)
            while (buffer.size > MAX_BUFFER) {
                buffer.removeLast()
            }
        }
    }

    companion object {
        private const val MAX_BUFFER = 40
        private val lock = Any()
        private val buffer = ArrayDeque<CapturedNotification>()

        @Volatile
        var isConnected: Boolean = false
            private set

        fun latest(limit: Int = 10): List<CapturedNotification> = synchronized(lock) {
            buffer.take(limit.coerceIn(1, MAX_BUFFER))
        }

        fun sendInlineReply(senderQuery: String, message: String, context: Context): Result<String> {
            val needle = senderQuery.trim().lowercase()
            val match = synchronized(lock) {
                buffer.firstOrNull { n ->
                    n.replyAction != null &&
                        (needle in n.title.lowercase() || needle in n.packageName.lowercase())
                }
            } ?: return Result.failure(IllegalStateException("No replyable notification matching '$senderQuery' found."))

            val action = match.replyAction ?: return Result.failure(IllegalStateException("Notification has no reply action."))
            val remoteInputs = action.remoteInputs ?: return Result.failure(IllegalStateException("Missing RemoteInput."))
            val intent = Intent()
            val bundle = Bundle()
            for (input in remoteInputs) {
                bundle.putCharSequence(input.resultKey, message)
            }
            RemoteInput.addResultsToIntent(remoteInputs, intent, bundle)
            return try {
                action.actionIntent.send(context, 0, intent)
                Result.success("Replied to '${match.title}' (${match.packageName}).")
            } catch (e: PendingIntent.CanceledException) {
                Result.failure(e)
            }
        }
    }
}
