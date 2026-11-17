package com.cueui.cueui_flutter

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private lateinit var deviceBridge: NativeDeviceBridge
    private lateinit var voiceBridge: VoiceBridge
    private val ioExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingRuntimeKey: String? = null
    private var pendingSpecialKey: String? = null
    private var runtimePromptTimeMs: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deviceBridge = NativeDeviceBridge(applicationContext)
        voiceBridge = VoiceBridge(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    CueEventBridge.attachSink(events)
                    val extraPerm = intent?.getStringExtra(EXTRA_PERMISSION_KEY)
                    if (!extraPerm.isNullOrBlank()) {
                        intent?.removeExtra(EXTRA_PERMISSION_KEY)
                        requestPermissionByKey(extraPerm)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    CueEventBridge.attachSink(null)
                }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val extraPerm = intent.getStringExtra(EXTRA_PERMISSION_KEY)
        if (!extraPerm.isNullOrBlank()) {
            intent.removeExtra(EXTRA_PERMISSION_KEY)
            requestPermissionByKey(extraPerm)
        }
    }

    override fun onResume() {
        super.onResume()
        CueEventBridge.emit(mapOf("type" to "appResumed", "snapshot" to PermissionHelper.snapshotMap(this)))
        val specialKey = pendingSpecialKey
        if (specialKey != null) {
            pendingSpecialKey = null
            val kind = AppPermissionKind.fromKey(specialKey)
            val granted = kind != null && PermissionHelper.isGranted(this, kind)
            CueEventBridge.emit(mapOf("type" to "permissionResult", "key" to specialKey, "granted" to granted))
        }
    }

    override fun onDestroy() {
        voiceBridge.shutdown()
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPermissionSnapshot" -> result.success(PermissionHelper.snapshotMap(this))
            "maybeAutoPromptStartupPermissions" -> {
                val missing = PermissionHelper.missingRuntimePermissions(this)
                if (missing.isNotEmpty() && !PermissionHelper.hasAutoPromptedRuntime(this)) {
                    PermissionHelper.markAutoPromptedRuntime(this)
                    pendingRuntimeKey = null
                    runtimePromptTimeMs = SystemClock.elapsedRealtime()
                    requestPermissions(missing, REQ_RUNTIME_PERMS)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "requestPermission" -> {
                val key = call.argument<String>("key").orEmpty()
                requestPermissionByKey(key)
                result.success(true)
            }
            "grantNextMissing" -> {
                val missing = PermissionHelper.missingRuntimePermissions(this)
                if (missing.isNotEmpty()) {
                    pendingRuntimeKey = null
                    runtimePromptTimeMs = SystemClock.elapsedRealtime()
                    requestPermissions(missing, REQ_RUNTIME_PERMS)
                } else {
                    @Suppress("UNCHECKED_CAST")
                    val coreMissing = PermissionHelper.snapshotMap(this)["coreMissing"] as? List<Map<String, Any?>>
                    val firstKey = coreMissing?.firstOrNull()?.get("key") as? String
                    if (firstKey != null) requestPermissionByKey(firstKey)
                }
                result.success(true)
            }
            "openAppDetailsSettings" -> {
                PermissionHelper.openAppDetailsSettings(this)
                result.success(true)
            }
            "requestDefaultLauncher" -> {
                val roleIntent = PermissionHelper.createDefaultLauncherRequestIntent(this)
                if (roleIntent != null) {
                    @Suppress("DEPRECATION")
                    startActivityForResult(roleIntent, REQ_HOME_ROLE)
                } else {
                    PermissionHelper.openHomeLauncherSettings(this)
                }
                result.success(true)
            }
            "toggleBubble" -> {
                if (CueEventBridge.bubbleActive) {
                    FloatingBubbleService.stop(this)
                } else if (Settings.canDrawOverlays(this)) {
                    FloatingBubbleService.start(this)
                } else {
                    pendingSpecialKey = AppPermissionKind.OVERLAY.key
                    PermissionHelper.openOverlaySettings(this)
                }
                result.success(CueEventBridge.bubbleActive)
            }
            "collapseBubble" -> {
                FloatingBubbleService.collapseIfRunning(this)
                result.success(true)
            }
            "syncOverlayState" -> {
                CueEventBridge.updateOverlayState(
                    statusLine = call.argument<String>("statusLine") ?: "Ready",
                    latestOutput = call.argument<String>("latestOutput") ?: "",
                    quickChoices = call.argument<List<String>>("quickChoices") ?: emptyList(),
                    isAwaitingReply = call.argument<Boolean>("isAwaitingReply") ?: false,
                    pendingPermissionKey = call.argument<String>("pendingPermissionKey"),
                    pendingConfirmationPrompt = call.argument<String>("pendingConfirmationPrompt"),
                )
                result.success(true)
            }
            "loadLaunchableApps" -> ioExecutor.execute {
                val apps = deviceBridge.loadLaunchableApps()
                mainHandler.post { result.success(apps) }
            }
            "launchPackage" -> result.success(deviceBridge.launchPackage(call.argument<String>("packageName").orEmpty()))
            "openApp" -> result.success(deviceBridge.openApp(call.argument<String>("app").orEmpty()))
            "listInstalledApps" -> ioExecutor.execute {
                val res = deviceBridge.listInstalledApps()
                mainHandler.post { result.success(res) }
            }
            "findContacts" -> ioExecutor.execute {
                val res = deviceBridge.findContacts(call.argument<String>("name").orEmpty())
                mainHandler.post { result.success(res) }
            }
            "resolveRecipient" -> ioExecutor.execute {
                val res = deviceBridge.resolveRecipient(call.argument<String>("target").orEmpty())
                mainHandler.post { result.success(res) }
            }
            "placeCall" -> result.success(
                deviceBridge.placeCall(
                    target = call.argument<String>("target").orEmpty(),
                    dialOnly = call.argument<Boolean>("dialOnly") ?: false,
                ),
            )
            "answerCall" -> result.success(deviceBridge.answerCall())
            "endCall" -> result.success(deviceBridge.endCall())
            "sendSms" -> result.success(
                deviceBridge.sendSms(
                    recipient = call.argument<String>("recipient").orEmpty(),
                    message = call.argument<String>("message").orEmpty(),
                ),
            )
            "readSms" -> ioExecutor.execute {
                val res = deviceBridge.readSms(call.argument<Int>("limit") ?: 5)
                mainHandler.post { result.success(res) }
            }
            "readNotifications" -> result.success(
                deviceBridge.readNotifications(
                    limit = call.argument<Int>("limit") ?: 10,
                    packageFilter = call.argument<String>("packageFilter"),
                ),
            )
            "readUnifiedMessages" -> ioExecutor.execute {
                val res = deviceBridge.readUnifiedMessages(
                    limit = call.argument<Int>("limit") ?: 8,
                    sourceFilter = call.argument<String>("source"),
                )
                mainHandler.post { result.success(res) }
            }
            "replyNotification" -> result.success(
                deviceBridge.replyNotification(
                    senderQuery = call.argument<String>("senderQuery").orEmpty(),
                    message = call.argument<String>("message").orEmpty(),
                ),
            )
            "findWhatsAppPackage" -> result.success(deviceBridge.findWhatsAppPackage())
            "launchWhatsAppChatByPhone" -> result.success(
                deviceBridge.launchWhatsAppChatByPhone(
                    packageName = call.argument<String>("packageName").orEmpty(),
                    phoneDigits = call.argument<String>("phoneDigits").orEmpty(),
                    message = call.argument<String>("message").orEmpty(),
                ),
            )
            "youtubeSearch" -> result.success(deviceBridge.youtubeSearch(call.argument<String>("query").orEmpty()))
            "spotifyPlay" -> result.success(deviceBridge.spotifyPlayOrSearch(call.argument<String>("query").orEmpty()))
            "openPlayStore" -> result.success(
                deviceBridge.openPlayStore(
                    packageName = call.argument<String>("packageName"),
                    appName = call.argument<String>("appName").orEmpty(),
                ),
            )
            "openWeatherAppFallback" -> result.success(deviceBridge.openWeatherAppFallback(call.argument<String>("err") ?: "offline"))
            "openUrl" -> result.success(deviceBridge.openUrl(call.argument<String>("url").orEmpty()))
            "setFlashlight" -> result.success(deviceBridge.setFlashlight(call.argument<Boolean>("enabled") ?: true))
            "setBrightness" -> result.success(deviceBridge.setBrightness(call.argument<Int>("percent") ?: 50))
            "setDnd" -> result.success(deviceBridge.setDnd(call.argument<Boolean>("enabled") ?: true))
            "openConnectivityPanel" -> result.success(
                deviceBridge.openConnectivityPanel(
                    setting = call.argument<String>("setting").orEmpty(),
                    desired = call.argument<Boolean>("desired"),
                ),
            )
            "mediaControl" -> result.success(deviceBridge.mediaControl(call.argument<String>("action").orEmpty()))
            "setAlarm" -> result.success(
                deviceBridge.setAlarm(
                    hour = call.argument<Int>("hour") ?: 7,
                    minute = call.argument<Int>("minute") ?: 0,
                    label = call.argument<String>("label") ?: "CueUI Alarm",
                ),
            )
            "setTimer" -> result.success(
                deviceBridge.setTimer(
                    seconds = call.argument<Int>("seconds") ?: 60,
                    label = call.argument<String>("label") ?: "CueUI Timer",
                ),
            )
            "openCamera" -> result.success(deviceBridge.openCamera(call.argument<String>("mode") ?: "photo"))
            "openCalendar" -> result.success(deviceBridge.openCalendar())
            "createCalendarEvent" -> result.success(
                deviceBridge.createCalendarEvent(
                    title = call.argument<String>("title").orEmpty(),
                    hour = call.argument<Int>("hour"),
                    minute = call.argument<Int>("minute") ?: 0,
                    dayOffset = call.argument<Int>("dayOffset") ?: 0,
                ),
            )
            "getDeviceStatus" -> result.success(deviceBridge.getDeviceStatus())
            "discoverExternalGgufPaths" -> ioExecutor.execute {
                val paths = deviceBridge.discoverExternalGgufPaths()
                mainHandler.post { result.success(paths) }
            }
            "isAccessibilityConnected" -> result.success(CueAccessibilityService.isConnected())
            "captureUiNodes" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(emptyList<Map<String, Any?>>())
                } else {
                    result.success(a11y.captureUiNodes())
                }
            }
            "getForegroundPackage" -> result.success(CueAccessibilityService.instance?.currentPackageName ?: "")
            "tapElement" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(missingAccessibilityMap("tap UI elements"))
                } else {
                    a11y.tapElementByIndex(call.argument<Int>("index") ?: -1) { result.success(it) }
                }
            }
            "tapText" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(missingAccessibilityMap("tap UI elements"))
                } else {
                    a11y.tapByQuery(call.argument<String>("query").orEmpty()) { result.success(it) }
                }
            }
            "typeText" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(missingAccessibilityMap("type text into apps"))
                } else {
                    result.success(a11y.typeIntoFocusedOrEditable(call.argument<String>("text").orEmpty()))
                }
            }
            "scrollScreen" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(missingAccessibilityMap("scroll on screen"))
                } else {
                    a11y.scrollScreen(call.argument<String>("direction") ?: "down") { result.success(it) }
                }
            }
            "pressKey" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(missingAccessibilityMap("press system navigation keys"))
                } else {
                    result.success(a11y.performGlobalKey(call.argument<String>("key").orEmpty()))
                }
            }
            "takeScreenshot" -> {
                val a11y = CueAccessibilityService.instance
                if (a11y == null) {
                    result.success(missingAccessibilityMap("capture screenshots"))
                } else {
                    val out = File(getExternalFilesDir(null) ?: filesDir, "screenshots/screen_${System.currentTimeMillis()}.png")
                    a11y.captureScreenshotToFile(out) { result.success(it) }
                }
            }
            "getVoiceState" -> result.success(voiceBridge.currentStateMap())
            "startListening" -> {
                voiceBridge.startListening()
                result.success(true)
            }
            "stopListening" -> {
                voiceBridge.stopListening()
                result.success(true)
            }
            "toggleTts" -> result.success(voiceBridge.toggleTts())
            "clearVoiceNotice" -> {
                voiceBridge.clearNotice()
                result.success(true)
            }
            "speak" -> {
                voiceBridge.speakIfEnabled(call.argument<String>("text").orEmpty())
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun missingAccessibilityMap(hint: String): Map<String, Any?> = mapOf(
        "ok" to false,
        "summary" to "CueUI needs Accessibility permission to $hint.",
        "data" to mapOf(
            "missingPermissionKey" to AppPermissionKind.ACCESSIBILITY.key,
            "missingPermissionLabel" to AppPermissionKind.ACCESSIBILITY.title,
        ),
    )

    private fun requestPermissionByKey(key: String) {
        val kind = AppPermissionKind.fromKey(key) ?: return
        if (kind.isRuntime) {
            pendingRuntimeKey = kind.key
            runtimePromptTimeMs = SystemClock.elapsedRealtime()
            requestPermissions(kind.runtimePermissions.toTypedArray(), REQ_RUNTIME_PERMS)
        } else {
            pendingSpecialKey = kind.key
            PermissionHelper.openSpecialSettings(this, kind)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_RUNTIME_PERMS) return
        val elapsedMs = SystemClock.elapsedRealtime() - runtimePromptTimeMs
        val targetKey = pendingRuntimeKey
        pendingRuntimeKey = null
        val anyGranted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        val noDialogShown = elapsedMs < 350L && !anyGranted

        CueEventBridge.emit(mapOf("type" to "appResumed", "snapshot" to PermissionHelper.snapshotMap(this)))

        if (targetKey != null) {
            val kind = AppPermissionKind.fromKey(targetKey)
            val granted = kind != null && PermissionHelper.isGranted(this, kind)
            if (!granted && noDialogShown) {
                pendingSpecialKey = targetKey
                PermissionHelper.openAppDetailsSettings(this)
            } else {
                CueEventBridge.emit(mapOf("type" to "permissionResult", "key" to targetKey, "granted" to granted))
            }
        } else if (noDialogShown && PermissionHelper.missingRuntimePermissions(this).isNotEmpty()) {
            PermissionHelper.openAppDetailsSettings(this)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_HOME_ROLE) {
            CueEventBridge.emit(mapOf("type" to "appResumed", "snapshot" to PermissionHelper.snapshotMap(this)))
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "com.cueui.cueui_flutter/native"
        private const val EVENT_CHANNEL = "com.cueui.cueui_flutter/events"
        private const val REQ_RUNTIME_PERMS = 9001
        private const val REQ_HOME_ROLE = 9002
        const val EXTRA_PERMISSION_KEY = "extra_permission_key"
    }
}
