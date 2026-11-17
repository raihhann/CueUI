import '../models/cue_models.dart';
import 'internet_search_service.dart';
import 'native_bridge.dart';
import 'weather_service.dart';
import 'whatsapp_automator.dart';
import 'media_service.dart';
import 'routine_service.dart';

typedef ConfirmActionFn = Future<bool> Function(String prompt);

class CueToolDispatcher {
  CueToolDispatcher({
    required this.nativeApi,
    required this.internetSearch,
    required this.weatherService,
    required this.confirmAction,
    CueMediaService? media,
    CueRoutineService? routines,
  }) {
    this.media = media ?? CueMediaService(nativeApi);
    this.routines = routines ?? CueRoutineService();
    _whatsAppAutomator = WhatsAppAutomator(_NativeWhatsAppDriver(nativeApi));
  }

  final CueNativeApi nativeApi;
  final InternetSearchService internetSearch;
  final WeatherService weatherService;
  final ConfirmActionFn confirmAction;
  late final WhatsAppAutomator _whatsAppAutomator;
  late final CueMediaService media;
  late final CueRoutineService routines;
  bool whatsAppVoiceActive = false;

  Future<List<UiNodeInfo>> captureUiNodes() => nativeApi.captureUiNodes();

  Future<ToolExecutionResult> execute(
    PlannedToolCall call, {
    bool Function()? canContinue,
  }) async {
    final args = call.args;
    switch (call.tool) {
      case 'record_audio_start':
        return media.command('start_audio', args);
      case 'record_audio_pause':
        return media.command('pause_audio');
      case 'record_audio_resume':
        return media.command('resume_audio');
      case 'record_audio_stop':
        if (media.videoActive) return media.command('stop_video');
        if (whatsAppVoiceActive) return _finishVoiceNote(false);
        return media.command('stop_audio', args);
      case 'camera_photo':
        return media.command('take_photo', args);
      case 'camera_video_start':
        return media.command('start_video', args);
      case 'camera_video_stop':
        return media.command('stop_video');
      case 'camera_switch':
        return media.command('switch_camera', args);
      case 'camera_cancel':
        return media.command('cancel_capture');
      case 'media_stop_playback':
        return media.command('stop_playback');
      case 'media_play':
      case 'media_transcribe':
        final query = _str(args, 'query').toLowerCase();
        final item = media.items
            .where(
              (item) =>
                  item.kind == 'audio' &&
                  item.title.toLowerCase().contains(query),
            )
            .firstOrNull;
        if (item == null) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'No matching saved audio recording.',
          );
        }
        return media.command(
          call.tool == 'media_play' ? 'play' : 'transcribe',
          {'id': item.id},
        );
      case 'run_routine':
        final routine = routines.find(_str(args, 'name'));
        if (routine == null) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'Routine not found. Create it in Routines first.',
          );
        }
        final summaries = <String>[];
        for (final step in routine.steps) {
          if (canContinue?.call() == false) {
            return const ToolExecutionResult(
              ok: false,
              summary: 'Routine stopped. Completed actions remain applied.',
            );
          }
          final result = await execute(step, canContinue: canContinue);
          summaries.add(result.summary);
          if (!result.ok) {
            return ToolExecutionResult(
              ok: false,
              summary: '${routine.name} stopped: ${summaries.join('\n')}',
              data: result.data,
            );
          }
        }
        return ToolExecutionResult(
          ok: true,
          summary: '${routine.name} completed:\n${summaries.join('\n')}',
        );
      case 'whatsapp_share_media':
      case 'whatsapp_start_voice':
        final recipient = _str(args, 'recipient');
        final package = await nativeApi.findWhatsAppPackage();
        if (package == null) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'WhatsApp is not installed.',
            data: {
              'missingAppName': 'WhatsApp',
              'missingPackage': 'com.whatsapp',
            },
          );
        }
        if (!await nativeApi.isAccessibilityConnected()) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'Enable Accessibility to select a WhatsApp recipient.',
            data: {
              'missingPermissionKey': 'ACCESSIBILITY',
              'missingPermissionLabel': 'Accessibility Control',
            },
          );
        }
        if (recipient.isEmpty) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'Who should receive it? Give a contact name.',
          );
        }
        await nativeApi.collapseBubble();
        ToolExecutionResult result;
        if (call.tool == 'whatsapp_share_media') {
          final id = _str(args, 'id').isNotEmpty
              ? _str(args, 'id')
              : media
                    .latest(
                      _str(args, 'kind').isEmpty ? null : _str(args, 'kind'),
                    )
                    ?.id;
          if (id == null) {
            return const ToolExecutionResult(
              ok: false,
              summary:
                  'Capture or record something first, or select an item in Library.',
            );
          }
          final opened = await media.command('share', {
            'id': id,
            'package': package,
            'caption': _str(args, 'caption'),
          });
          if (!opened.ok) return opened;
          await Future<void>.delayed(const Duration(milliseconds: 800));
          result = await _whatsAppAutomator.sendSharedMedia(
            recipient,
            selectedChat: args['selectedChat']?.toString(),
            canContinue: canContinue,
          );
          return _recipientResult(result, call, extraArgs: {'id': id});
        }
        result = await _whatsAppAutomator.startVoiceMessage(
          recipient,
          selectedChat: args['selectedChat']?.toString(),
          canContinue: canContinue,
        );
        if (result.ok) {
          whatsAppVoiceActive = true;
          await nativeApi.mediaCommand('external_voice_state', {
            'active': true,
          });
        }
        return _recipientResult(result, call);
      case 'whatsapp_finish_voice':
        return _finishVoiceNote(false);
      case 'whatsapp_cancel_voice':
        return _finishVoiceNote(true);
      case 'find_contact':
        return nativeApi.findContacts(_str(args, 'name'));

      case 'make_call':
        final target = _str(args, 'target');
        final dialOnly = _bool(args, 'dialOnly', false);
        if (!dialOnly) {
          final snap = await nativeApi.getPermissionSnapshot();
          if (!snap.callPhoneGranted) {
            return const ToolExecutionResult(
              ok: false,
              summary:
                  'CueUI needs Phone Calls permission to place calls directly.',
              data: {
                'missingPermissionKey': 'CALL_PHONE',
                'missingPermissionLabel': 'Phone Calls',
              },
            );
          }
          final resolved = await nativeApi.resolveRecipient(target);
          if (resolved['ok'] != true) {
            return ToolExecutionResult.fromMap(resolved);
          }
          final label = (resolved['label'] ?? target).toString();
          if (!await confirmAction('Call $label?')) {
            return ToolExecutionResult(
              ok: false,
              summary: 'Call to $label cancelled by user.',
            );
          }
        }
        return nativeApi.placeCall(target, dialOnly: dialOnly);

      case 'answer_call':
        return nativeApi.answerCall();

      case 'end_call':
        return nativeApi.endCall();

      case 'send_sms':
        final recipient = _str(args, 'recipient');
        final message = _str(args, 'message');
        final snap = await nativeApi.getPermissionSnapshot();
        if (!snap.sendSmsGranted) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'CueUI needs Send SMS permission to text contacts.',
            data: {
              'missingPermissionKey': 'SEND_SMS',
              'missingPermissionLabel': 'Send SMS',
            },
          );
        }
        final resolved = await nativeApi.resolveRecipient(recipient);
        if (resolved['ok'] != true) {
          return ToolExecutionResult.fromMap(resolved);
        }
        final label = (resolved['label'] ?? recipient).toString();
        if (!await confirmAction('Send SMS to $label?\n"$message"')) {
          return ToolExecutionResult(
            ok: false,
            summary: 'SMS to $label cancelled by user.',
          );
        }
        return nativeApi.sendSms(recipient, message);

      case 'read_sms':
        return nativeApi.readSms(limit: _int(args, 'limit', 5));

      case 'read_notifications':
        return nativeApi.readNotifications(
          limit: _int(args, 'limit', 10),
          packageFilter: _str(args, 'packageFilter').isEmpty
              ? null
              : _str(args, 'packageFilter'),
        );

      case 'read_messages':
        return nativeApi.readUnifiedMessages(
          limit: _int(args, 'limit', 8),
          source: _str(args, 'source').isEmpty ? null : _str(args, 'source'),
        );

      case 'whatsapp_send':
        final recipient = _str(args, 'recipient');
        final message = _str(args, 'message');
        if (recipient.isEmpty || message.isEmpty) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'WhatsApp requires both recipient and message.',
          );
        }
        if (await nativeApi.findWhatsAppPackage() == null) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'WhatsApp is not installed on this device.',
            data: {
              'missingAppName': 'WhatsApp',
              'missingPackage': 'com.whatsapp',
            },
          );
        }
        if (!await nativeApi.isAccessibilityConnected()) {
          return const ToolExecutionResult(
            ok: false,
            summary:
                'CueUI needs Accessibility permission to message inside WhatsApp.',
            data: {
              'missingPermissionKey': 'ACCESSIBILITY',
              'missingPermissionLabel': 'Accessibility Control',
            },
          );
        }
        await nativeApi.collapseBubble();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final result = await _whatsAppAutomator.sendMessage(
          recipient,
          message,
          selectedChat: args['selectedChat']?.toString(),
          canContinue: canContinue,
        );
        if (result.data['whatsappRecipients'] != null) {
          return ToolExecutionResult(
            ok: false,
            summary: result.summary,
            data: {...result.data, 'recipient': recipient, 'message': message},
          );
        }
        return result;

      case 'whatsapp_call':
        final recipient = _str(args, 'recipient');
        final video = _bool(args, 'video', false);
        if (recipient.isEmpty) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'WhatsApp call requires a contact name.',
          );
        }
        if (await nativeApi.findWhatsAppPackage() == null) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'WhatsApp is not installed on this device.',
            data: {
              'missingAppName': 'WhatsApp',
              'missingPackage': 'com.whatsapp',
            },
          );
        }
        if (!await nativeApi.isAccessibilityConnected()) {
          return const ToolExecutionResult(
            ok: false,
            summary:
                'CueUI needs Accessibility permission to call inside WhatsApp.',
            data: {
              'missingPermissionKey': 'ACCESSIBILITY',
              'missingPermissionLabel': 'Accessibility Control',
            },
          );
        }
        final resolved = await nativeApi.resolveRecipient(recipient);
        final displayName = resolved['ok'] == true
            ? (resolved['label'] ?? recipient).toString()
            : recipient;
        if (!await confirmAction(
          'Start WhatsApp ${video ? "video" : "voice"} call with $displayName?',
        )) {
          return ToolExecutionResult(
            ok: false,
            summary: 'WhatsApp call to $displayName cancelled by user.',
          );
        }
        await nativeApi.collapseBubble();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return _whatsAppAutomator.callContact(recipient, video: video);

      case 'open_camera':
        await nativeApi.collapseBubble();
        return media.command('preview', {
          'lens': _str(args, 'mode') == 'selfie' ? 'front' : 'back',
        });

      case 'open_calendar':
        await nativeApi.collapseBubble();
        return nativeApi.openCalendar();

      case 'add_calendar_event':
        await nativeApi.collapseBubble();
        return nativeApi.createCalendarEvent(
          title: _str(args, 'title'),
          hour: args['hour'] is num
              ? (args['hour'] as num).toInt()
              : int.tryParse('${args['hour'] ?? ''}'),
          minute: _int(args, 'minute', 0),
          dayOffset: _int(args, 'dayOffset', 0),
        );

      case 'ask_internet':
        return internetSearch.answerQuestion(_str(args, 'query'));

      case 'get_news':
        return internetSearch.fetchNews(topic: _str(args, 'topic'));

      case 'get_weather':
        final reqLoc = _str(args, 'location').isNotEmpty
            ? _str(args, 'location')
            : _str(args, 'city');
        final city = reqLoc.isNotEmpty
            ? reqLoc
            : await weatherService.savedCity();
        if (city.isEmpty) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'Need a city name to check the weather.',
            data: {'needsCity': true},
          );
        }
        try {
          final report = await weatherService.fetchWeather(city);
          return ToolExecutionResult(ok: true, summary: report);
        } catch (e) {
          final fallback = await nativeApi.openWeatherAppFallback('$e');
          if (fallback != null) return fallback;
          return ToolExecutionResult(
            ok: false,
            summary:
                'Could not check weather for "$city" ($e). Connect to internet or install a Weather app.',
          );
        }

      case 'reply_notification':
        final snap = await nativeApi.getPermissionSnapshot();
        if (!snap.notificationListenerEnabled) {
          return const ToolExecutionResult(
            ok: false,
            summary:
                'CueUI needs Notification Reader access to reply to notifications.',
            data: {
              'missingPermissionKey': 'NOTIFICATION_LISTENER',
              'missingPermissionLabel': 'Notification Reader',
            },
          );
        }
        final sender = _str(args, 'senderQuery');
        final message = _str(args, 'message');
        if (!await confirmAction(
          'Reply to notification from \'$sender\'?\n"$message"',
        )) {
          return const ToolExecutionResult(
            ok: false,
            summary: 'Notification reply cancelled by user.',
          );
        }
        return nativeApi.replyNotification(sender, message);

      case 'tap_element':
        await nativeApi.collapseBubble();
        return nativeApi.tapElement(_int(args, 'index', -1));

      case 'tap_text':
        await nativeApi.collapseBubble();
        return nativeApi.tapText(_str(args, 'query'));

      case 'type_text':
        await nativeApi.collapseBubble();
        return nativeApi.typeText(_str(args, 'text'));

      case 'press_key':
        return nativeApi.pressKey(_str(args, 'key'));

      case 'scroll_screen':
        await nativeApi.collapseBubble();
        return nativeApi.scrollScreen(
          _str(args, 'direction').isEmpty ? 'down' : _str(args, 'direction'),
        );

      case 'take_screenshot':
        await nativeApi.collapseBubble();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return nativeApi.takeScreenshot();

      case 'open_app':
        await nativeApi.collapseBubble();
        final res = await nativeApi.openApp(_str(args, 'app'));
        if (res.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
        return res;

      case 'youtube_search':
        await nativeApi.collapseBubble();
        final res = await nativeApi.youtubeSearch(_str(args, 'query'));
        if (res.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
        return res;

      case 'spotify_play':
        await nativeApi.collapseBubble();
        final res = await nativeApi.spotifyPlay(_str(args, 'query'));
        if (res.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
        return res;

      case 'install_app_play_store':
        await nativeApi.collapseBubble();
        final appName = _str(args, 'appName');
        final pkg = _str(args, 'packageName').isEmpty
            ? null
            : _str(args, 'packageName');
        final res = await nativeApi.openPlayStore(
          packageName: pkg,
          appName: appName,
        );
        if (res.ok && res.data['alreadyInstalled'] != true) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
        return res;

      case 'list_apps':
        return nativeApi.listInstalledApps();

      case 'open_url':
        return nativeApi.openUrl(_str(args, 'url'));

      case 'set_flashlight':
        return nativeApi.setFlashlight(_bool(args, 'enabled', true));

      case 'open_connectivity_panel':
        return nativeApi.openConnectivityPanel(
          _str(args, 'setting'),
          desired: args['desired'] is bool ? args['desired'] as bool : null,
        );

      case 'set_brightness':
        return nativeApi.setBrightness(_int(args, 'percent', 50));

      case 'set_dnd':
        return nativeApi.setDnd(_bool(args, 'enabled', true));

      case 'media_control':
        return nativeApi.mediaControl(_str(args, 'action'));

      case 'set_alarm':
        return nativeApi.setAlarm(
          hour: _int(args, 'hour', 7),
          minute: _int(args, 'minute', 0),
          label: _str(args, 'label').isEmpty
              ? 'CueUI Alarm'
              : _str(args, 'label'),
        );

      case 'set_timer':
        return nativeApi.setTimer(
          seconds: _int(args, 'seconds', 60),
          label: _str(args, 'label').isEmpty
              ? 'CueUI Timer'
              : _str(args, 'label'),
        );

      case 'get_device_status':
        return nativeApi.getDeviceStatus();

      default:
        return ToolExecutionResult(
          ok: false,
          summary: "Unknown tool '${call.tool}'.",
        );
    }
  }

  ToolExecutionResult _recipientResult(
    ToolExecutionResult result,
    PlannedToolCall call, {
    Map<String, dynamic> extraArgs = const {},
  }) => ToolExecutionResult(
    ok: result.ok,
    summary: result.summary,
    data: {
      ...result.data,
      'recipient': call.args['selectedChat'] ?? call.args['recipient'],
      if (result.data['whatsappRecipients'] != null) 'retryTool': call.tool,
      if (result.data['whatsappRecipients'] != null)
        'retryArgs': {...call.args, ...extraArgs},
    },
  );

  Future<ToolExecutionResult> _finishVoiceNote(bool cancel) async {
    if (!whatsAppVoiceActive) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'No WhatsApp voice message is being recorded.',
      );
    }
    await nativeApi.collapseBubble();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!{
      'com.whatsapp',
      'com.whatsapp.w4b',
    }.contains(await nativeApi.getForegroundPackage())) {
      final package = await nativeApi.findWhatsAppPackage();
      if (package == null) {
        return const ToolExecutionResult(
          ok: false,
          summary: 'WhatsApp is unavailable.',
        );
      }
      await nativeApi.launchPackage(package);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    final result = await _whatsAppAutomator.finishVoiceMessage(cancel: cancel);
    if (result.ok || result.data['recordingAbsent'] == true) {
      whatsAppVoiceActive = false;
      await nativeApi.mediaCommand('external_voice_state', {'active': false});
    }
    return result;
  }

  static String _str(Map<String, dynamic> args, String key) =>
      (args[key] ?? '').toString().trim();
  static int _int(Map<String, dynamic> args, String key, int def) =>
      args[key] is num
      ? (args[key] as num).toInt()
      : int.tryParse('${args[key] ?? ''}') ?? def;
  static bool _bool(Map<String, dynamic> args, String key, bool def) =>
      args[key] is bool ? args[key] as bool : def;
}

class _NativeWhatsAppDriver implements WhatsAppUiDriver {
  _NativeWhatsAppDriver(this._api);
  final CueNativeApi _api;
  @override
  Future<bool> isWhatsAppForeground() async => {
    'com.whatsapp',
    'com.whatsapp.w4b',
  }.contains(await _api.getForegroundPackage());
  @override
  Future<bool> startVoiceNote(int index) async =>
      (await _api.startWhatsAppVoiceNote(index)).ok;

  @override
  Future<bool> goBack() async => (await _api.pressKey('BACK')).ok;

  @override
  Future<String?> findWhatsAppPackage() => _api.findWhatsAppPackage();

  @override
  Future<bool> launchWhatsApp(String packageName) async =>
      (await _api.launchPackage(packageName)).ok;

  @override
  Future<bool> launchWhatsAppChatByPhone(
    String packageName,
    String phoneDigits,
    String message,
  ) => _api.launchWhatsAppChatByPhone(packageName, phoneDigits, message);

  @override
  Future<String?> resolvePhoneDigits(String recipient) async {
    final rawDigits = WhatsAppAutomator.extractRawPhoneDigits(recipient);
    if (rawDigits != null) return rawDigits;
    final result = await _api.findContacts(recipient);
    final contacts = result.data['contacts'];
    if (!result.ok || contacts is! List) return null;
    final numbers = contacts
        .whereType<Map>()
        .map(
          (contact) => (contact['number'] ?? '').toString().replaceAll(
            RegExp(r'[^0-9]'),
            '',
          ),
        )
        .where((number) => number.length >= 7)
        .toSet();
    // Never fall back to the first similarly named address-book entry.
    return numbers.length == 1 ? numbers.single : null;
  }

  @override
  Future<List<UiNodeInfo>> captureNodes() => _api.captureUiNodes();

  @override
  Future<bool> tapNode(int nodeIndex) async =>
      (await _api.tapElement(nodeIndex)).ok;

  @override
  Future<bool> typeText(String text) async => (await _api.typeText(text)).ok;

  @override
  Future<void> pauseMs(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
}
