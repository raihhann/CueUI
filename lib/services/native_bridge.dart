import 'package:flutter/services.dart';
import '../models/cue_models.dart';

abstract class CueNativeApi {
  Future<ToolExecutionResult> mediaCommand(
    String action, [
    Map<String, dynamic> args = const {},
  ]);
  Future<ToolExecutionResult> startWhatsAppVoiceNote(int index);
  Stream<Map<String, dynamic>> get events;

  Future<PermissionSnapshot> getPermissionSnapshot();
  Future<bool> maybeAutoPromptStartupPermissions();
  Future<void> requestPermission(String key);
  Future<void> grantNextMissing();
  Future<void> openAppDetailsSettings();
  Future<void> requestDefaultLauncher();

  Future<bool> toggleBubble();
  Future<void> collapseBubble();
  Future<void> syncOverlayState({
    required String statusLine,
    required String latestOutput,
    required List<String> quickChoices,
    required bool isAwaitingReply,
    String? pendingPermissionKey,
    String? pendingConfirmationPrompt,
  });

  Future<List<LaunchableApp>> loadLaunchableApps();
  Future<ToolExecutionResult> launchPackage(String packageName);
  Future<ToolExecutionResult> openApp(String app);
  Future<ToolExecutionResult> listInstalledApps();

  Future<ToolExecutionResult> findContacts(String name);
  Future<Map<String, dynamic>> resolveRecipient(String target);
  Future<ToolExecutionResult> placeCall(String target, {bool dialOnly = false});
  Future<ToolExecutionResult> answerCall();
  Future<ToolExecutionResult> endCall();
  Future<ToolExecutionResult> sendSms(String recipient, String message);
  Future<ToolExecutionResult> readSms({int limit = 5});
  Future<ToolExecutionResult> readNotifications({
    int limit = 10,
    String? packageFilter,
  });
  Future<ToolExecutionResult> readUnifiedMessages({
    int limit = 8,
    String? source,
  });
  Future<ToolExecutionResult> replyNotification(
    String senderQuery,
    String message,
  );

  Future<String?> findWhatsAppPackage();
  Future<bool> launchWhatsAppChatByPhone(
    String packageName,
    String phoneDigits,
    String message,
  );

  Future<ToolExecutionResult> youtubeSearch(String query);
  Future<ToolExecutionResult> spotifyPlay(String query);
  Future<ToolExecutionResult> openPlayStore({
    String? packageName,
    required String appName,
  });
  Future<ToolExecutionResult?> openWeatherAppFallback(String errorMsg);
  Future<ToolExecutionResult> openUrl(String url);

  Future<ToolExecutionResult> setFlashlight(bool enabled);
  Future<ToolExecutionResult> setBrightness(int percent);
  Future<ToolExecutionResult> setDnd(bool enabled);
  Future<ToolExecutionResult> openConnectivityPanel(
    String setting, {
    bool? desired,
  });
  Future<ToolExecutionResult> mediaControl(String action);
  Future<ToolExecutionResult> setAlarm({
    required int hour,
    required int minute,
    required String label,
  });
  Future<ToolExecutionResult> setTimer({
    required int seconds,
    required String label,
  });
  Future<ToolExecutionResult> openCamera(String mode);
  Future<ToolExecutionResult> openCalendar();
  Future<ToolExecutionResult> createCalendarEvent({
    required String title,
    int? hour,
    int minute = 0,
    int dayOffset = 0,
  });
  Future<ToolExecutionResult> getDeviceStatus();
  Future<List<String>> discoverExternalGgufPaths();

  Future<bool> isAccessibilityConnected();
  Future<List<UiNodeInfo>> captureUiNodes();
  Future<String> getForegroundPackage();
  Future<ToolExecutionResult> tapElement(int index);
  Future<ToolExecutionResult> tapText(String query);
  Future<ToolExecutionResult> typeText(String text);
  Future<ToolExecutionResult> scrollScreen(String direction);
  Future<ToolExecutionResult> pressKey(String key);
  Future<ToolExecutionResult> takeScreenshot();

  Future<VoiceUiState> getVoiceState();
  Future<void> startListening();
  Future<void> stopListening();
  Future<VoiceUiState> toggleTts();
  Future<void> clearVoiceNotice();
  Future<void> speak(String text);
}

class MethodChannelNativeApi implements CueNativeApi {
  @override
  Future<ToolExecutionResult> mediaCommand(
    String action, [
    Map<String, dynamic> args = const {},
  ]) => _invokeResult('mediaCommand', {'action': action, 'args': args});

  @override
  Future<ToolExecutionResult> startWhatsAppVoiceNote(int index) =>
      _invokeResult('startWhatsAppVoiceNote', {'index': index});
  static const MethodChannel _method = MethodChannel(
    'com.cueui.cueui_flutter/native',
  );
  static const EventChannel _event = EventChannel(
    'com.cueui.cueui_flutter/events',
  );

  Stream<Map<String, dynamic>>? _broadcastEvents;

  @override
  Stream<Map<String, dynamic>> get events {
    _broadcastEvents ??= _event
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .asBroadcastStream();
    return _broadcastEvents!;
  }

  Future<ToolExecutionResult> _invokeResult(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final res = await _method.invokeMethod<Map<dynamic, dynamic>>(method, args);
    return ToolExecutionResult.fromMap(
      res ?? const {'ok': false, 'summary': 'Empty native response.'},
    );
  }

  @override
  Future<PermissionSnapshot> getPermissionSnapshot() async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'getPermissionSnapshot',
    );
    return PermissionSnapshot.fromMap(raw ?? const {});
  }

  @override
  Future<bool> maybeAutoPromptStartupPermissions() async =>
      (await _method.invokeMethod<bool>('maybeAutoPromptStartupPermissions')) ==
      true;

  @override
  Future<void> requestPermission(String key) =>
      _method.invokeMethod<void>('requestPermission', {'key': key});

  @override
  Future<void> grantNextMissing() =>
      _method.invokeMethod<void>('grantNextMissing');

  @override
  Future<void> openAppDetailsSettings() =>
      _method.invokeMethod<void>('openAppDetailsSettings');

  @override
  Future<void> requestDefaultLauncher() =>
      _method.invokeMethod<void>('requestDefaultLauncher');

  @override
  Future<bool> toggleBubble() async =>
      (await _method.invokeMethod<bool>('toggleBubble')) == true;

  @override
  Future<void> collapseBubble() => _method.invokeMethod<void>('collapseBubble');

  @override
  Future<void> syncOverlayState({
    required String statusLine,
    required String latestOutput,
    required List<String> quickChoices,
    required bool isAwaitingReply,
    String? pendingPermissionKey,
    String? pendingConfirmationPrompt,
  }) => _method.invokeMethod<void>('syncOverlayState', {
    'statusLine': statusLine,
    'latestOutput': latestOutput,
    'quickChoices': quickChoices,
    'isAwaitingReply': isAwaitingReply,
    'pendingPermissionKey': pendingPermissionKey,
    'pendingConfirmationPrompt': pendingConfirmationPrompt,
  });

  @override
  Future<List<LaunchableApp>> loadLaunchableApps() async {
    final list = await _method.invokeMethod<List<dynamic>>(
      'loadLaunchableApps',
    );
    return (list ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(LaunchableApp.fromMap)
        .toList();
  }

  @override
  Future<ToolExecutionResult> launchPackage(String packageName) =>
      _invokeResult('launchPackage', {'packageName': packageName});

  @override
  Future<ToolExecutionResult> openApp(String app) =>
      _invokeResult('openApp', {'app': app});

  @override
  Future<ToolExecutionResult> listInstalledApps() =>
      _invokeResult('listInstalledApps');

  @override
  Future<ToolExecutionResult> findContacts(String name) =>
      _invokeResult('findContacts', {'name': name});

  @override
  Future<Map<String, dynamic>> resolveRecipient(String target) async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'resolveRecipient',
      {'target': target},
    );
    return Map<String, dynamic>.from(
      raw ?? const {'ok': false, 'summary': 'Contact resolution failed.'},
    );
  }

  @override
  Future<ToolExecutionResult> placeCall(
    String target, {
    bool dialOnly = false,
  }) => _invokeResult('placeCall', {'target': target, 'dialOnly': dialOnly});

  @override
  Future<ToolExecutionResult> answerCall() => _invokeResult('answerCall');

  @override
  Future<ToolExecutionResult> endCall() => _invokeResult('endCall');

  @override
  Future<ToolExecutionResult> sendSms(String recipient, String message) =>
      _invokeResult('sendSms', {'recipient': recipient, 'message': message});

  @override
  Future<ToolExecutionResult> readSms({int limit = 5}) =>
      _invokeResult('readSms', {'limit': limit});

  @override
  Future<ToolExecutionResult> readNotifications({
    int limit = 10,
    String? packageFilter,
  }) => _invokeResult('readNotifications', {
    'limit': limit,
    'packageFilter': packageFilter,
  });

  @override
  Future<ToolExecutionResult> readUnifiedMessages({
    int limit = 8,
    String? source,
  }) =>
      _invokeResult('readUnifiedMessages', {'limit': limit, 'source': source});

  @override
  Future<ToolExecutionResult> replyNotification(
    String senderQuery,
    String message,
  ) => _invokeResult('replyNotification', {
    'senderQuery': senderQuery,
    'message': message,
  });

  @override
  Future<String?> findWhatsAppPackage() =>
      _method.invokeMethod<String>('findWhatsAppPackage');

  @override
  Future<bool> launchWhatsAppChatByPhone(
    String packageName,
    String phoneDigits,
    String message,
  ) async =>
      (await _method.invokeMethod<bool>('launchWhatsAppChatByPhone', {
        'packageName': packageName,
        'phoneDigits': phoneDigits,
        'message': message,
      })) ==
      true;

  @override
  Future<ToolExecutionResult> youtubeSearch(String query) =>
      _invokeResult('youtubeSearch', {'query': query});

  @override
  Future<ToolExecutionResult> spotifyPlay(String query) =>
      _invokeResult('spotifyPlay', {'query': query});

  @override
  Future<ToolExecutionResult> openPlayStore({
    String? packageName,
    required String appName,
  }) => _invokeResult('openPlayStore', {
    'packageName': packageName,
    'appName': appName,
  });

  @override
  Future<ToolExecutionResult?> openWeatherAppFallback(String errorMsg) async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'openWeatherAppFallback',
      {'err': errorMsg},
    );
    return raw == null ? null : ToolExecutionResult.fromMap(raw);
  }

  @override
  Future<ToolExecutionResult> openUrl(String url) =>
      _invokeResult('openUrl', {'url': url});

  @override
  Future<ToolExecutionResult> setFlashlight(bool enabled) =>
      _invokeResult('setFlashlight', {'enabled': enabled});

  @override
  Future<ToolExecutionResult> setBrightness(int percent) =>
      _invokeResult('setBrightness', {'percent': percent});

  @override
  Future<ToolExecutionResult> setDnd(bool enabled) =>
      _invokeResult('setDnd', {'enabled': enabled});

  @override
  Future<ToolExecutionResult> openConnectivityPanel(
    String setting, {
    bool? desired,
  }) => _invokeResult('openConnectivityPanel', {
    'setting': setting,
    'desired': desired,
  });

  @override
  Future<ToolExecutionResult> mediaControl(String action) =>
      _invokeResult('mediaControl', {'action': action});

  @override
  Future<ToolExecutionResult> setAlarm({
    required int hour,
    required int minute,
    required String label,
  }) => _invokeResult('setAlarm', {
    'hour': hour,
    'minute': minute,
    'label': label,
  });

  @override
  Future<ToolExecutionResult> setTimer({
    required int seconds,
    required String label,
  }) => _invokeResult('setTimer', {'seconds': seconds, 'label': label});

  @override
  Future<ToolExecutionResult> openCamera(String mode) =>
      _invokeResult('openCamera', {'mode': mode});

  @override
  Future<ToolExecutionResult> openCalendar() => _invokeResult('openCalendar');

  @override
  Future<ToolExecutionResult> createCalendarEvent({
    required String title,
    int? hour,
    int minute = 0,
    int dayOffset = 0,
  }) => _invokeResult('createCalendarEvent', {
    'title': title,
    'hour': hour,
    'minute': minute,
    'dayOffset': dayOffset,
  });

  @override
  Future<ToolExecutionResult> getDeviceStatus() =>
      _invokeResult('getDeviceStatus');

  @override
  Future<List<String>> discoverExternalGgufPaths() async {
    final list = await _method.invokeMethod<List<dynamic>>(
      'discoverExternalGgufPaths',
    );
    return (list ?? const []).map((e) => e.toString()).toList();
  }

  @override
  Future<bool> isAccessibilityConnected() async =>
      (await _method.invokeMethod<bool>('isAccessibilityConnected')) == true;

  @override
  Future<List<UiNodeInfo>> captureUiNodes() async {
    final list = await _method.invokeMethod<List<dynamic>>('captureUiNodes');
    return (list ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(UiNodeInfo.fromMap)
        .toList();
  }

  @override
  Future<String> getForegroundPackage() async =>
      (await _method.invokeMethod<String>('getForegroundPackage')) ?? '';

  @override
  Future<ToolExecutionResult> tapElement(int index) =>
      _invokeResult('tapElement', {'index': index});

  @override
  Future<ToolExecutionResult> tapText(String query) =>
      _invokeResult('tapText', {'query': query});

  @override
  Future<ToolExecutionResult> typeText(String text) =>
      _invokeResult('typeText', {'text': text});

  @override
  Future<ToolExecutionResult> scrollScreen(String direction) =>
      _invokeResult('scrollScreen', {'direction': direction});

  @override
  Future<ToolExecutionResult> pressKey(String key) =>
      _invokeResult('pressKey', {'key': key});

  @override
  Future<ToolExecutionResult> takeScreenshot() =>
      _invokeResult('takeScreenshot');

  @override
  Future<VoiceUiState> getVoiceState() async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'getVoiceState',
    );
    return VoiceUiState.fromMap(raw ?? const {});
  }

  @override
  Future<void> startListening() => _method.invokeMethod<void>('startListening');

  @override
  Future<void> stopListening() => _method.invokeMethod<void>('stopListening');

  @override
  Future<VoiceUiState> toggleTts() async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>('toggleTts');
    return VoiceUiState.fromMap(raw ?? const {});
  }

  @override
  Future<void> clearVoiceNotice() =>
      _method.invokeMethod<void>('clearVoiceNotice');

  @override
  Future<void> speak(String text) =>
      _method.invokeMethod<void>('speak', {'text': text});
}
