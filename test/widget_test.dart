import 'dart:async';
import 'package:cueui_flutter/main.dart';
import 'package:cueui_flutter/models/cue_models.dart';
import 'package:cueui_flutter/orchestrator/cue_orchestrator.dart';
import 'package:cueui_flutter/services/internet_search_service.dart';
import 'package:cueui_flutter/services/nano_ai_service.dart';
import 'package:cueui_flutter/services/native_bridge.dart';
import 'package:cueui_flutter/services/tool_dispatcher.dart';
import 'package:cueui_flutter/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNativeApi implements CueNativeApi {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  bool contactsGranted = true;
  bool spotifyInstalled = true;
  List<UiNodeInfo> uiNodes = const [];
  final List<String> tappedQueries = [];
  String? requestedPermissionKey;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<PermissionSnapshot> getPermissionSnapshot() async =>
      PermissionSnapshot(
        contactsGranted: contactsGranted,
        callPhoneGranted: true,
        answerCallsGranted: true,
        sendSmsGranted: true,
        readSmsGranted: true,
        recordAudioGranted: true,
        postNotificationsGranted: true,
        accessibilityEnabled: false,
        overlayEnabled: false,
        notificationListenerEnabled: true,
        coreMissing: const [
          MissingPermissionItem(
            key: 'ACCESSIBILITY',
            title: 'Accessibility Control',
            isRuntime: false,
          ),
          MissingPermissionItem(
            key: 'OVERLAY',
            title: 'Floating Bubble Overlay',
            isRuntime: false,
          ),
        ],
      );

  @override
  Future<bool> maybeAutoPromptStartupPermissions() async => false;

  @override
  Future<void> requestPermission(String key) async {
    requestedPermissionKey = key;
  }

  @override
  Future<void> grantNextMissing() async {}

  @override
  Future<void> openAppDetailsSettings() async {}

  @override
  Future<void> requestDefaultLauncher() async {}

  @override
  Future<bool> toggleBubble() async => false;

  @override
  Future<void> collapseBubble() async {}

  @override
  Future<void> syncOverlayState({
    required String statusLine,
    required String latestOutput,
    required List<String> quickChoices,
    required bool isAwaitingReply,
    String? pendingPermissionKey,
    String? pendingConfirmationPrompt,
  }) async {}

  @override
  Future<List<LaunchableApp>> loadLaunchableApps() async => const [
    LaunchableApp(label: 'Phone', packageName: 'com.android.dialer'),
    LaunchableApp(label: 'Chrome', packageName: 'com.android.chrome'),
    LaunchableApp(label: 'Camera', packageName: 'com.android.camera2'),
    LaunchableApp(label: 'Settings', packageName: 'com.android.settings'),
  ];

  @override
  Future<ToolExecutionResult> launchPackage(String packageName) async =>
      ToolExecutionResult(ok: true, summary: 'Opened $packageName.');

  @override
  Future<ToolExecutionResult> openApp(String app) async =>
      ToolExecutionResult(ok: true, summary: 'Opened $app.');

  @override
  Future<ToolExecutionResult> listInstalledApps() async =>
      const ToolExecutionResult(ok: true, summary: '4 apps');

  @override
  Future<ToolExecutionResult> findContacts(String name) async =>
      const ToolExecutionResult(ok: true, summary: 'No contact');

  @override
  Future<Map<String, dynamic>> resolveRecipient(String target) async {
    if (!contactsGranted) {
      return {
        'ok': false,
        'summary': "CueUI needs Contacts permission to look up '$target'.",
        'data': {
          'missingPermissionKey': 'CONTACTS',
          'missingPermissionLabel': 'Contacts',
        },
      };
    }
    return {'ok': true, 'label': '$target (+123456)', 'number': '123456'};
  }

  @override
  Future<ToolExecutionResult> placeCall(
    String target, {
    bool dialOnly = false,
  }) async => ToolExecutionResult(ok: true, summary: 'Calling $target.');

  @override
  Future<ToolExecutionResult> answerCall() async =>
      const ToolExecutionResult(ok: true, summary: 'Answered.');

  @override
  Future<ToolExecutionResult> endCall() async =>
      const ToolExecutionResult(ok: true, summary: 'Ended.');

  @override
  Future<ToolExecutionResult> sendSms(String recipient, String message) async =>
      ToolExecutionResult(ok: true, summary: 'Sent SMS to $recipient.');

  @override
  Future<ToolExecutionResult> readSms({int limit = 5}) async =>
      const ToolExecutionResult(ok: true, summary: 'Empty');

  @override
  Future<ToolExecutionResult> readNotifications({
    int limit = 10,
    String? packageFilter,
  }) async => const ToolExecutionResult(ok: true, summary: 'None');

  @override
  Future<ToolExecutionResult> readUnifiedMessages({
    int limit = 8,
    String? source,
  }) async => const ToolExecutionResult(ok: true, summary: 'None');

  @override
  Future<ToolExecutionResult> replyNotification(
    String senderQuery,
    String message,
  ) async => const ToolExecutionResult(ok: true, summary: 'Replied.');

  @override
  Future<String?> findWhatsAppPackage() async => 'com.whatsapp';

  @override
  Future<bool> launchWhatsAppChatByPhone(
    String packageName,
    String phoneDigits,
    String message,
  ) async => false;

  @override
  Future<ToolExecutionResult> youtubeSearch(String query) async =>
      ToolExecutionResult(ok: true, summary: 'Searched YouTube $query.');

  @override
  Future<ToolExecutionResult> spotifyPlay(String query) async {
    if (!spotifyInstalled) {
      return ToolExecutionResult(
        ok: false,
        summary: 'Spotify is not installed on this device.',
        data: {
          'missingAppName': 'Spotify',
          'missingPackage': 'com.spotify.music',
          'fallbackQuery': query,
        },
      );
    }
    return ToolExecutionResult(ok: true, summary: 'Playing $query on Spotify.');
  }

  @override
  Future<ToolExecutionResult> openPlayStore({
    String? packageName,
    required String appName,
  }) async => ToolExecutionResult(
    ok: true,
    summary: 'Opened Google Play Store for $appName.',
  );

  @override
  Future<ToolExecutionResult?> openWeatherAppFallback(String errorMsg) async =>
      null;

  @override
  Future<ToolExecutionResult> openUrl(String url) async =>
      ToolExecutionResult(ok: true, summary: 'Opened $url');

  @override
  Future<ToolExecutionResult> setFlashlight(bool enabled) async =>
      const ToolExecutionResult(ok: true, summary: 'Flash ON');

  @override
  Future<ToolExecutionResult> setBrightness(int percent) async =>
      const ToolExecutionResult(ok: true, summary: 'Brightness');

  @override
  Future<ToolExecutionResult> setDnd(bool enabled) async =>
      const ToolExecutionResult(ok: true, summary: 'DND');

  @override
  Future<ToolExecutionResult> openConnectivityPanel(
    String setting, {
    bool? desired,
  }) async => const ToolExecutionResult(ok: true, summary: 'Panel opened');

  @override
  Future<ToolExecutionResult> mediaControl(String action) async =>
      const ToolExecutionResult(ok: true, summary: 'Media');

  @override
  Future<ToolExecutionResult> setAlarm({
    required int hour,
    required int minute,
    required String label,
  }) async => const ToolExecutionResult(ok: true, summary: 'Alarm set');

  @override
  Future<ToolExecutionResult> setTimer({
    required int seconds,
    required String label,
  }) async => const ToolExecutionResult(ok: true, summary: 'Timer set');

  @override
  Future<ToolExecutionResult> openCamera(String mode) async =>
      const ToolExecutionResult(ok: true, summary: 'Opened camera.');

  @override
  Future<ToolExecutionResult> openCalendar() async =>
      const ToolExecutionResult(ok: true, summary: 'Opened Calendar.');

  @override
  Future<ToolExecutionResult> createCalendarEvent({
    required String title,
    int? hour,
    int minute = 0,
    int dayOffset = 0,
  }) async => ToolExecutionResult(ok: true, summary: 'Created $title');

  @override
  Future<ToolExecutionResult> getDeviceStatus() async =>
      const ToolExecutionResult(ok: true, summary: 'Battery 100%');

  @override
  Future<List<String>> discoverExternalGgufPaths() async => const [];

  @override
  Future<bool> isAccessibilityConnected() async => true;

  @override
  Future<List<UiNodeInfo>> captureUiNodes() async => uiNodes;

  @override
  Future<String> getForegroundPackage() async => 'com.cueui.cueui_flutter';

  @override
  Future<ToolExecutionResult> tapElement(int index) async {
    tappedQueries.add('#$index');
    return ToolExecutionResult(ok: true, summary: 'Tapped #$index');
  }

  @override
  Future<ToolExecutionResult> tapText(String query) async {
    tappedQueries.add(query);
    return ToolExecutionResult(ok: true, summary: 'Tapped $query');
  }

  @override
  Future<ToolExecutionResult> typeText(String text) async =>
      const ToolExecutionResult(ok: true, summary: 'Typed');

  @override
  Future<ToolExecutionResult> scrollScreen(String direction) async =>
      const ToolExecutionResult(ok: true, summary: 'Scrolled');

  @override
  Future<ToolExecutionResult> pressKey(String key) async =>
      const ToolExecutionResult(ok: true, summary: 'Key');

  @override
  Future<ToolExecutionResult> takeScreenshot() async =>
      const ToolExecutionResult(ok: true, summary: 'Shot');

  @override
  Future<VoiceUiState> getVoiceState() async => const VoiceUiState();

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<VoiceUiState> toggleTts() async =>
      const VoiceUiState(ttsEnabled: false);

  @override
  Future<void> clearVoiceNotice() async {}

  @override
  Future<void> speak(String text) async {}
}

class _FakeNanoAiService extends NanoAiService {
  _FakeNanoAiService(CueNativeApi api) : super(nativeApi: api);

  @override
  bool get isReady => true;

  @override
  AiEngineSnapshot get snapshot => const AiEngineSnapshot(
    status: AiModelStatus.ready,
    loadedModelName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
    lastInferenceMs: 42,
  );

  @override
  Future<PlannedToolCall?> parseNaturalLanguageQuery(String query) async {
    return const PlannedToolCall(tool: 'open_calendar', source: 'nano_ai');
  }
}

class _RecipientChoiceDispatcher extends CueToolDispatcher {
  _RecipientChoiceDispatcher(CueNativeApi api)
    : super(
        nativeApi: api,
        internetSearch: InternetSearchService(),
        weatherService: WeatherService(),
        confirmAction: (_) async => true,
      );

  final calls = <PlannedToolCall>[];
  List<String> recipients = ['Raihan Ahmed', 'Raihan Khan'];

  @override
  Future<ToolExecutionResult> execute(
    PlannedToolCall call, {
    bool Function()? canContinue,
  }) async {
    calls.add(call);
    if (call.tool == 'whatsapp_send' &&
        call.args['selectedChat'] == null &&
        !RegExp(
          r'^[+\d][\d\s().-]{5,}$',
        ).hasMatch('${call.args['recipient']}')) {
      return ToolExecutionResult(
        ok: false,
        summary: 'Which Raihan should receive the message?',
        data: {
          'whatsappRecipients': recipients,
          'recipient': call.args['recipient'],
          'message': call.args['message'],
        },
      );
    }
    return ToolExecutionResult(
      ok: true,
      summary: call.tool == 'whatsapp_send'
          ? 'Sent to ${call.args['selectedChat']}: ${call.args['message']}'
          : 'Done ${call.tool}',
    );
  }
}

void main() {
  group('CueOrchestrator', () {
    test(
      'identical names require a phone number and retain the message',
      () async {
        final api = _FakeNativeApi();
        final dispatcher = _RecipientChoiceDispatcher(api)
          ..recipients = ['Raihan', 'Raihan'];
        final orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: NanoAiService(nativeApi: api),
          dispatcher: dispatcher,
        );
        await orch.submitGoal('send hi to raihan on whatsapp');
        await orch.submitGoal('1');
        expect(dispatcher.calls, hasLength(1));
        expect(orch.state.messages.last.text, contains('phone number'));
        await orch.submitGoal('+491234567890');
        expect(dispatcher.calls.last.args, {
          'recipient': '+491234567890',
          'message': 'hi',
        });
        expect(orch.state.isAwaitingReply, false);
      },
    );

    test(
      'retains WhatsApp message through invalid replies and sends to the selected recipient',
      () async {
        final api = _FakeNativeApi();
        final dispatcher = _RecipientChoiceDispatcher(api);
        final orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: NanoAiService(nativeApi: api),
          dispatcher: dispatcher,
        );
        await orch.submitGoal('send hi to raihan on whatsapp');
        expect(orch.state.isAwaitingReply, true);
        expect(orch.state.isRunning, false);
        expect(orch.state.quickChoices, [
          '1. Raihan Ahmed',
          '2. Raihan Khan',
          'Cancel',
        ]);
        await orch.submitGoal('yes');
        expect(dispatcher.calls, hasLength(1));
        expect(orch.state.isAwaitingReply, true);
        await orch.submitGoal('the second one');
        expect(dispatcher.calls.last.args, {
          'recipient': 'raihan',
          'message': 'hi',
          'selectedChat': 'Raihan Khan',
        });
        expect(orch.state.messages.last.text, 'Sent to Raihan Khan: hi');
        expect(orch.state.isAwaitingReply, false);
      },
    );

    test(
      'recipient choices accept chip labels and preserve remaining command steps',
      () async {
        final api = _FakeNativeApi();
        final dispatcher = _RecipientChoiceDispatcher(api);
        final orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: NanoAiService(nativeApi: api),
          dispatcher: dispatcher,
        );
        await orch.submitGoal('send hi to raihan on whatsapp then go home');
        expect(dispatcher.calls, hasLength(1));
        await orch.submitGoal('2. Raihan Khan');
        expect(dispatcher.calls.map((call) => call.tool), [
          'whatsapp_send',
          'whatsapp_send',
          'press_key',
        ]);
        expect(dispatcher.calls[1].args['selectedChat'], 'Raihan Khan');
      },
    );

    test(
      'cancels recipient selection and allows a new command without sending',
      () async {
        final api = _FakeNativeApi();
        final dispatcher = _RecipientChoiceDispatcher(api);
        final orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: NanoAiService(nativeApi: api),
          dispatcher: dispatcher,
        );
        await orch.submitGoal('send hi to raihan on whatsapp');
        await orch.submitGoal('cancel');
        expect(dispatcher.calls, hasLength(1));
        expect(orch.state.isAwaitingReply, false);
        await orch.submitGoal('send hi to raihan on whatsapp');
        await orch.submitGoal('open calendar');
        expect(dispatcher.calls.last.tool, 'open_calendar');
        expect(
          dispatcher.calls.where((call) => call.args['selectedChat'] != null),
          isEmpty,
        );
      },
    );

    test(
      'prompts missing Contacts permission, then auto-retries command upon grant',
      () async {
        final api = _FakeNativeApi()..contactsGranted = false;
        late CueOrchestrator orch;
        final dispatcher = CueToolDispatcher(
          nativeApi: api,
          internetSearch: InternetSearchService(),
          weatherService: WeatherService(),
          confirmAction: (_) async => true,
        );
        orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: NanoAiService(nativeApi: api),
          dispatcher: dispatcher,
          postLaunchInspectDelayMs: 0,
        );

        await orch.runGoal('call Mom');
        expect(orch.state.pendingPermissionKey, 'CONTACTS');
        expect(orch.state.quickChoices, ['Grant Contacts', 'Not now']);

        await orch.runGoal('Grant Contacts');
        expect(api.requestedPermissionKey, 'CONTACTS');

        api.contactsGranted = true;
        await orch.notifyPermissionResult('CONTACTS', true);
        expect(orch.state.messages.last.text, contains('Calling Mom'));
      },
    );

    test(
      'investigates casual NL query via NanoAiService when deterministic rules do not match',
      () async {
        final api = _FakeNativeApi();
        final dispatcher = CueToolDispatcher(
          nativeApi: api,
          internetSearch: InternetSearchService(),
          weatherService: WeatherService(),
          confirmAction: (_) async => true,
        );
        final orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: _FakeNanoAiService(api),
          dispatcher: dispatcher,
          postLaunchInspectDelayMs: 0,
        );

        await orch.runGoal(
          'what do i have lined up today please show schedule',
        );
        expect(orch.state.messages.last.text, 'Opened Calendar.');
        expect(orch.state.lastRouteBadge, contains('Nano AI'));
      },
    );

    test(
      'offers Play Store install when Spotify missing and auto-taps Install',
      () async {
        final api = _FakeNativeApi()
          ..spotifyInstalled = false
          ..uiNodes = const [
            UiNodeInfo(
              index: 7,
              className: 'android.widget.Button',
              text: 'Install',
              contentDesc: 'Install',
              viewId: 'install_btn',
              clickable: true,
              editable: false,
              scrollable: false,
              focused: false,
              left: 100,
              top: 400,
              right: 400,
              bottom: 500,
            ),
          ];
        final dispatcher = CueToolDispatcher(
          nativeApi: api,
          internetSearch: InternetSearchService(),
          weatherService: WeatherService(),
          confirmAction: (_) async => true,
        );
        final orch = CueOrchestrator(
          nativeApi: api,
          nanoAi: NanoAiService(nativeApi: api),
          dispatcher: dispatcher,
          postLaunchInspectDelayMs: 0,
        );

        await orch.runGoal('play jazz on spotify');
        expect(orch.state.quickChoices, contains('Yes, install'));

        await orch.runGoal('Yes, install');
        expect(api.tappedQueries, ['#7']);
        expect(
          orch.state.messages.last.text,
          contains('tapped Install for Spotify'),
        );
      },
    );
  });

  testWidgets(
    'CueUiFlutterApp renders Ratio header, missing perms strip, Home & AI tab',
    (tester) async {
      final api = _FakeNativeApi();
      await tester.pumpWidget(
        CueUiFlutterApp(nativeApi: api, autoWarmAi: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Setup · 2'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('2 permissions missing'), findsOneWidget);
      expect(find.text('Essentials'), findsOneWidget);
      expect(find.text('Favourites'), findsOneWidget);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      expect(find.text('Nano AI (Keep-Warm NLU)'), findsOneWidget);
      expect(find.text('SmolLM2 360M Instruct (Nano)'), findsOneWidget);
    },
  );
}
