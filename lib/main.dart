import 'dart:async';
import 'package:flutter/material.dart';
import 'models/cue_models.dart';
import 'orchestrator/cue_orchestrator.dart';
import 'services/internet_search_service.dart';
import 'services/nano_ai_service.dart';
import 'services/native_bridge.dart';
import 'services/tool_dispatcher.dart';
import 'services/weather_service.dart';
import 'ui/cue_theme.dart';
import 'ui/widgets/bento_home.dart';
import 'ui/widgets/nano_ai_tab.dart';
import 'ui/widgets/setup_tab.dart';

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
  late final CueNativeApi _nativeApi;
  late final NanoAiService _nanoAi;
  late final InternetSearchService _internetSearch;
  late final WeatherService _weatherService;
  late final CueToolDispatcher _dispatcher;
  late final CueOrchestrator _orchestrator;

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  int _selectedSection = 0; // 0 = Home, 1 = Setup, 2 = AI
  List<LaunchableApp> _apps = const [];
  PermissionSnapshot _permSnapshot = const PermissionSnapshot();
  VoiceUiState _voiceState = const VoiceUiState();

  @override
  void initState() {
    super.initState();
    _nativeApi = widget.nativeApi ?? MethodChannelNativeApi();
    _nanoAi = widget.nanoAi ?? NanoAiService(nativeApi: _nativeApi);
    _internetSearch = InternetSearchService();
    _weatherService = WeatherService();
    late CueOrchestrator orchestratorRef;
    _dispatcher = CueToolDispatcher(
      nativeApi: _nativeApi,
      internetSearch: _internetSearch,
      weatherService: _weatherService,
      confirmAction: (prompt) => orchestratorRef.requestUserConfirmation(prompt),
    );
    _orchestrator = CueOrchestrator(
      nativeApi: _nativeApi,
      nanoAi: _nanoAi,
      dispatcher: _dispatcher,
    );
    orchestratorRef = _orchestrator;

    _eventSub = _nativeApi.events.listen(_handleNativeEvent);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _refreshApps(),
      _refreshPermissions(),
      _refreshVoiceState(),
    ]);
    try {
      await _nativeApi.maybeAutoPromptStartupPermissions();
    } catch (_) {}
    if (widget.autoWarmAi) {
      unawaited(_nanoAi.autoDetectAndWarmLoad());
    }
  }

  Future<void> _refreshApps() async {
    try {
      final list = await _nativeApi.loadLaunchableApps();
      if (mounted) setState(() => _apps = list);
    } catch (_) {}
  }

  Future<void> _refreshPermissions() async {
    try {
      final snap = await _nativeApi.getPermissionSnapshot();
      if (mounted) setState(() => _permSnapshot = snap);
    } catch (_) {}
  }

  Future<void> _refreshVoiceState() async {
    try {
      final vs = await _nativeApi.getVoiceState();
      if (mounted) setState(() => _voiceState = vs);
    } catch (_) {}
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString() ?? '';
    switch (type) {
      case 'voiceState':
        setState(() => _voiceState = VoiceUiState.fromMap(event));
        break;
      case 'voiceResult':
        final text = (event['text'] ?? '').toString().trim();
        if (text.isNotEmpty) unawaited(_orchestrator.submitGoal(text));
        break;
      case 'missingPermission':
        final key = (event['key'] ?? '').toString();
        if (key.isNotEmpty) unawaited(_nativeApi.requestPermission(key));
        break;
      case 'permissionResult':
        final key = (event['key'] ?? '').toString();
        final granted = event['granted'] == true;
        unawaited(_refreshPermissions());
        unawaited(_orchestrator.notifyPermissionResult(key, granted));
        break;
      case 'appResumed':
        final rawSnap = event['snapshot'];
        if (rawSnap is Map) {
          setState(() => _permSnapshot = PermissionSnapshot.fromMap(rawSnap));
        } else {
          unawaited(_refreshPermissions());
        }
        unawaited(_refreshApps());
        break;
      case 'bubbleState':
        _orchestrator.setBubbleActive(event['active'] == true);
        break;
      case 'submitGoal':
        final text = (event['text'] ?? '').toString().trim();
        if (text.isNotEmpty) unawaited(_orchestrator.submitGoal(text));
        break;
      case 'resolveConfirm':
        _orchestrator.resolveConfirmation(event['approved'] == true);
        break;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    unawaited(_nanoAi.unloadModel(keepStatus: true));
    _nanoAi.dispose();
    _orchestrator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CueUI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: CueColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: CueColors.accentLime,
          surface: CueColors.tile,
          onPrimary: Color(0xFF111113),
          onSurface: CueColors.textPrimary,
        ),
        useMaterial3: true,
      ),
      home: PopScope(
        canPop: _selectedSection == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selectedSection != 0) {
            setState(() => _selectedSection = 0);
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: CueColors.bg,
          body: Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: _BackdropPainter())),
              SafeArea(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_orchestrator, _nanoAi]),
                  builder: (context, _) {
                    final missingCount = _permSnapshot.coreMissing.length;
                    final aiSnap = _nanoAi.snapshot;
                    return Column(
                      children: [
                        _UtilityHeader(
                          bubbleActive: _orchestrator.state.bubbleActive,
                          isDefaultLauncher: _permSnapshot.isDefaultLauncher,
                          missingCount: missingCount,
                          aiSnap: aiSnap,
                          selectedSection: _selectedSection,
                          onSelectSection: (s) => setState(() => _selectedSection = s),
                          onRequestDefaultLauncher: _nativeApi.requestDefaultLauncher,
                          onToggleBubble: _nativeApi.toggleBubble,
                        ),
                        Expanded(
                          child: switch (_selectedSection) {
                            0 => RatioBentoHome(
                                orchestrator: _orchestrator,
                                aiSnapshot: aiSnap,
                                voiceState: _voiceState,
                                permSnapshot: _permSnapshot,
                                apps: _apps,
                                onLaunchPackage: _nativeApi.launchPackage,
                                onOpenUrl: _nativeApi.openUrl,
                                onGrantMissingPermissions: _nativeApi.grantNextMissing,
                                onRequestPermissionKey: _nativeApi.requestPermission,
                                onOpenSetupTab: () => setState(() => _selectedSection = 1),
                                onOpenAiTab: () => setState(() => _selectedSection = 2),
                                onToggleBubble: _nativeApi.toggleBubble,
                                onMicClick: _nativeApi.startListening,
                                onToggleTts: _nativeApi.toggleTts,
                                onClearVoiceNotice: _nativeApi.clearVoiceNotice,
                              ),
                            1 => RatioSetupTab(
                                snap: _permSnapshot,
                                onGrantAllMissing: _nativeApi.grantNextMissing,
                                onRequestPermissionKey: _nativeApi.requestPermission,
                                onOpenAppDetails: _nativeApi.openAppDetailsSettings,
                                onRequestDefaultLauncher: _nativeApi.requestDefaultLauncher,
                              ),
                            _ => NanoAiTab(
                                aiService: _nanoAi,
                                onRunFullCommand: (q) {
                                  setState(() => _selectedSection = 0);
                                  unawaited(_orchestrator.submitGoal(q));
                                },
                              ),
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityHeader extends StatelessWidget {
  const _UtilityHeader({
    required this.bubbleActive,
    required this.isDefaultLauncher,
    required this.missingCount,
    required this.aiSnap,
    required this.selectedSection,
    required this.onSelectSection,
    required this.onRequestDefaultLauncher,
    required this.onToggleBubble,
  });

  final bool bubbleActive;
  final bool isDefaultLauncher;
  final int missingCount;
  final AiEngineSnapshot aiSnap;
  final int selectedSection;
  final void Function(int section) onSelectSection;
  final VoidCallback onRequestDefaultLauncher;
  final VoidCallback onToggleBubble;

  @override
  Widget build(BuildContext context) {
    final aiDot = switch (aiSnap.status) {
      AiModelStatus.ready => CueColors.accentGreen,
      AiModelStatus.downloading || AiModelStatus.loading || AiModelStatus.scanning => CueColors.accentLime,
      AiModelStatus.error => CueColors.accentRed,
      AiModelStatus.unloaded => CueColors.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SoftPillChip(
            label: 'Home',
            selected: selectedSection == 0,
            onTap: () => onSelectSection(0),
          ),
          const SizedBox(width: 6),
          SoftPillChip(
            label: missingCount > 0 ? 'Setup · $missingCount' : 'Setup',
            selected: selectedSection == 1,
            dotColor: missingCount > 0 ? CueColors.accentLime : CueColors.accentGreen,
            onTap: () => onSelectSection(1),
          ),
          const SizedBox(width: 6),
          SoftPillChip(
            label: 'AI',
            selected: selectedSection == 2,
            dotColor: aiDot,
            onTap: () => onSelectSection(2),
          ),
          const Spacer(),
          if (!isDefaultLauncher && selectedSection == 0) ...[
            SoftPillChip(
              label: 'Set Home',
              selected: false,
              onTap: onRequestDefaultLauncher,
            ),
            const SizedBox(width: 6),
          ],
          SoftPillChip(
            label: bubbleActive ? 'Bubble On' : 'Bubble',
            selected: bubbleActive,
            dotColor: bubbleActive ? CueColors.accentLime : CueColors.textMuted,
            onTap: onToggleBubble,
          ),
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = CueColors.bgSculptSoft;
    final mid = Paint()..color = CueColors.bgSculptMid;
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.14), size.width * 0.62, soft);
    canvas.drawCircle(Offset(size.width * 0.22, size.height * 0.52), size.width * 0.56, mid);
    canvas.drawCircle(Offset(size.width * 0.80, size.height * 0.86), size.width * 0.64, soft);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
