import 'dart:async';
import 'package:flutter/material.dart';
import 'models/cue_models.dart';
import 'orchestrator/cue_orchestrator.dart';
import 'services/internet_search_service.dart';
import 'services/media_service.dart';
import 'services/nano_ai_service.dart';
import 'services/native_bridge.dart';
import 'services/routine_service.dart';
import 'services/tool_dispatcher.dart';
import 'services/weather_service.dart';
import 'ui/app_theme.dart';
import 'ui/widgets/assistant_home.dart';
import 'ui/widgets/workspace_panels.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CueUiFlutterApp());
}

class CueUiFlutterApp extends StatefulWidget {
  const CueUiFlutterApp({
    super.key,
    this.nativeApi,
    this.nanoAi,
    this.autoWarmAi = true,
  });
  final CueNativeApi? nativeApi;
  final NanoAiService? nanoAi;
  final bool autoWarmAi;
  @override
  State<CueUiFlutterApp> createState() => _CueUiFlutterAppState();
}

class _CueUiFlutterAppState extends State<CueUiFlutterApp> {
  late final CueNativeApi native;
  late final NanoAiService ai;
  late final CueMediaService media;
  late final CueRoutineService routines;
  late final CueOrchestrator orchestrator;
  StreamSubscription<Map<String, dynamic>>? events;
  Timer? polling;
  List<LaunchableApp> apps = const [];
  PermissionSnapshot permissions = const PermissionSnapshot();
  VoiceUiState voice = const VoiceUiState();
  ThemeMode mode = ThemeMode.system;
  int section = 0;

  @override
  void initState() {
    super.initState();
    native = widget.nativeApi ?? MethodChannelNativeApi();
    ai = widget.nanoAi ?? NanoAiService(nativeApi: native);
    media = CueMediaService(native);
    routines = CueRoutineService();
    late CueOrchestrator reference;
    final dispatcher = CueToolDispatcher(
      nativeApi: native,
      internetSearch: InternetSearchService(),
      weatherService: WeatherService(),
      media: media,
      routines: routines,
      confirmAction: (prompt) => reference.requestUserConfirmation(prompt),
    );
    orchestrator = CueOrchestrator(
      nativeApi: native,
      nanoAi: ai,
      dispatcher: dispatcher,
    );
    reference = orchestrator;
    events = native.events.listen(handleEvent);
    unawaited(bootstrap());
    polling = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (media.recording['active'] == true || media.videoActive) {
        try {
          final state = await native.mediaCommand('state');
          if (mounted) media.acceptResult(state);
        } catch (_) {}
      }
    });
  }

  Future<void> bootstrap() async {
    await Future.wait([
      refreshApps(),
      refreshPermissions(),
      refreshVoice(),
      media.refresh(),
    ]);
    try {
      await routines.load();
    } catch (_) {}
    try {
      final saved = await native.mediaCommand('load_preferences');
      if (mounted) {
        setState(
          () => mode =
              ThemeMode.values
                  .where((item) => item.name == saved.data['theme'])
                  .firstOrNull ??
              ThemeMode.system,
        );
      }
      await native.maybeAutoPromptStartupPermissions();
    } catch (_) {}
    if (widget.autoWarmAi) unawaited(ai.autoDetectAndWarmLoad());
  }

  Future<void> refreshApps() async {
    try {
      final value = await native.loadLaunchableApps();
      if (mounted) setState(() => apps = value);
    } catch (_) {}
  }

  Future<void> refreshPermissions() async {
    try {
      final value = await native.getPermissionSnapshot();
      if (mounted) setState(() => permissions = value);
    } catch (_) {}
  }

  Future<void> refreshVoice() async {
    try {
      final value = await native.getVoiceState();
      if (mounted) setState(() => voice = value);
    } catch (_) {}
  }

  void handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    switch (event['type']) {
      case 'voiceState':
        setState(() => voice = VoiceUiState.fromMap(event));
      case 'voiceResult':
      case 'submitGoal':
        final text = '${event['text'] ?? ''}'.trim();
        if (text.isNotEmpty) {
          unawaited(native.clearVoiceNotice());
          unawaited(orchestrator.submitGoal(text));
        }
      case 'missingPermission':
        unawaited(native.requestPermission('${event['key']}'));
      case 'permissionResult':
        unawaited(refreshPermissions());
        unawaited(
          orchestrator.notifyPermissionResult(
            '${event['key']}',
            event['granted'] == true,
          ),
        );
      case 'appResumed':
        unawaited(refreshApps());
        unawaited(refreshPermissions());
        unawaited(media.refresh());
      case 'bubbleState':
        orchestrator.setBubbleActive(event['active'] == true);
      case 'resolveConfirm':
        orchestrator.resolveConfirmation(event['approved'] == true);
      case 'mediaUpdated':
        unawaited(media.refresh());
      case 'recordingState':
        media.acceptResult(
          ToolExecutionResult(
            ok: true,
            summary: 'Recording updated',
            data: {'recording': event['recording']},
          ),
        );
      case 'mediaCaptureResult':
        final result = event['result'];
        if (result is Map) {
          media.acceptResult(ToolExecutionResult.fromMap(result));
        }
    }
  }

  void changeMode(ThemeMode value) {
    setState(() => mode = value);
    unawaited(native.mediaCommand('save_preferences', {'theme': value.name}));
  }

  Future<void> run(PlannedToolCall call, String label) async {
    setState(() => section = 0);
    await orchestrator.submitTool(call, label);
  }

  @override
  void dispose() {
    polling?.cancel();
    events?.cancel();
    orchestrator.cancelActiveGoal();
    orchestrator.dispose();
    media.dispose();
    routines.dispose();
    unawaited(ai.unloadModel(keepStatus: true));
    if (widget.nanoAi == null) ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CueUI',
    debugShowCheckedModeBanner: false,
    theme: CueAppTheme.build(Brightness.light),
    darkTheme: CueAppTheme.build(Brightness.dark),
    themeMode: mode,
    home: Builder(
      builder: (context) => PopScope(
        canPop: section == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => section = 0);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.blur_on_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'cue',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'PHONE, IN FLOW',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.6,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: mode == ThemeMode.dark
                    ? 'Use light mode'
                    : 'Use dark mode',
                onPressed: () => changeMode(
                  Theme.of(context).brightness == Brightness.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: Listenable.merge([orchestrator, ai, media, routines]),
              builder: (context, _) => Column(
                children: [
                  if (media.recording['active'] == true || media.videoActive)
                    _RecordingBar(
                      media: media,
                      onPause: () => media.command(
                        media.recording['paused'] == true
                            ? 'resume_audio'
                            : 'pause_audio',
                      ),
                      onStop: () => run(
                        PlannedToolCall(
                          tool: media.videoActive
                              ? 'camera_video_stop'
                              : 'record_audio_stop',
                        ),
                        'Stop and save recording',
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: switch (section) {
                          0 => AssistantHome(
                            orchestrator: orchestrator,
                            voice: voice,
                            media: media,
                            onMic: native.startListening,
                            onSpeakToggle: native.toggleTts,
                            onOpenUrl: native.openUrl,
                            onPermission: native.requestPermission,
                            onCancel: () {
                              orchestrator.cancelActiveGoal();
                              unawaited(media.command('cancel_capture'));
                              unawaited(media.command('cancel_transcription'));
                            },
                          ),
                          1 => MediaLibrary(media: media, run: run),
                          2 => RoutinesPanel(service: routines, run: run),
                          3 => AppsPanel(
                            apps: apps,
                            launch: native.launchPackage,
                          ),
                          _ => SettingsPanel(
                            permissions: permissions,
                            ai: ai,
                            mode: mode,
                            onMode: changeMode,
                            requestPermission: native.requestPermission,
                            setLauncher: native.requestDefaultLauncher,
                            toggleBubble: native.toggleBubble,
                            bubbleActive: orchestrator.state.bubbleActive,
                            grantMissing: native.grantNextMissing,
                          ),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: section,
            onDestinationSelected: (value) => setState(() => section = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'Assistant',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_open_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.waves_outlined),
                selectedIcon: Icon(Icons.waves),
                label: 'Routines',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Apps',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.media,
    required this.onPause,
    required this.onStop,
  });
  final CueMediaService media;
  final VoidCallback onPause, onStop;
  @override
  Widget build(BuildContext context) {
    final elapsed = (media.recording['elapsedMs'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.fiber_manual_record,
            size: 14,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              media.videoActive
                  ? 'Recording video'
                  : '${media.recording['paused'] == true ? 'Paused' : 'Recording audio'} · ${elapsed ~/ 60000}:${((elapsed ~/ 1000) % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (!media.videoActive)
            IconButton(
              onPressed: onPause,
              tooltip: media.recording['paused'] == true
                  ? 'Resume recording'
                  : 'Pause recording',
              icon: Icon(
                media.recording['paused'] == true
                    ? Icons.play_arrow
                    : Icons.pause,
              ),
            ),
          TextButton(onPressed: onStop, child: const Text('Stop & save')),
        ],
      ),
    );
  }
}
