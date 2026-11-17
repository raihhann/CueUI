import 'package:flutter/material.dart';
import '../../models/cue_models.dart';
import '../../orchestrator/cue_orchestrator.dart';
import '../cue_theme.dart';
import 'assistant_card.dart';

class RatioBentoHome extends StatefulWidget {
  const RatioBentoHome({
    super.key,
    required this.orchestrator,
    required this.aiSnapshot,
    required this.voiceState,
    required this.permSnapshot,
    required this.apps,
    required this.onLaunchPackage,
    required this.onOpenUrl,
    required this.onGrantMissingPermissions,
    required this.onRequestPermissionKey,
    required this.onOpenSetupTab,
    required this.onOpenAiTab,
    required this.onToggleBubble,
    required this.onMicClick,
    required this.onToggleTts,
    required this.onClearVoiceNotice,
  });

  final CueOrchestrator orchestrator;
  final AiEngineSnapshot aiSnapshot;
  final VoiceUiState voiceState;
  final PermissionSnapshot permSnapshot;
  final List<LaunchableApp> apps;
  final void Function(String packageName) onLaunchPackage;
  final void Function(String url) onOpenUrl;
  final VoidCallback onGrantMissingPermissions;
  final void Function(String key) onRequestPermissionKey;
  final VoidCallback onOpenSetupTab;
  final VoidCallback onOpenAiTab;
  final VoidCallback onToggleBubble;
  final VoidCallback onMicClick;
  final VoidCallback onToggleTts;
  final VoidCallback onClearVoiceNotice;

  @override
  State<RatioBentoHome> createState() => _RatioBentoHomeState();
}

class _RatioBentoHomeState extends State<RatioBentoHome> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  int? _lastDismissedMessageId;
  bool _permBannerDismissed = false;
  bool _allAppsExpanded = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _submitCommand([String? override]) {
    final trimmed = (override ?? _searchCtrl.text).trim();
    if (trimmed.isEmpty) return;
    widget.onClearVoiceNotice();
    if (override == null) {
      _searchCtrl.clear();
      _searchFocus.unfocus();
    }
    setState(() => _lastDismissedMessageId = null);
    widget.orchestrator.submitGoal(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.orchestrator.state;
    final query = _searchCtrl.text;
    final hasQuery = query.trim().isNotEmpty;

    final latestReply = state.messages
        .where((m) => m.role == ChatRole.agent || m.role == ChatRole.error)
        .lastOrNull;

    final showReplyBanner = state.isRunning ||
        state.isAwaitingReply ||
        state.pendingConfirmationPrompt != null ||
        widget.voiceState.isListening ||
        widget.voiceState.statusNotice != null ||
        (state.messages.length > 1 && latestReply != null && latestReply.id != _lastDismissedMessageId);

    final essentials = buildEssentialsSelection(widget.apps);
    final favourites = buildFavouritesSelection(widget.apps, essentials);
    final dockApps = buildDockSelection(widget.apps);

    final qLower = query.trim().toLowerCase();
    final matchingApps = qLower.isEmpty
        ? const <LaunchableApp>[]
        : widget.apps
            .where((a) => a.label.toLowerCase().contains(qLower) || a.packageName.toLowerCase().contains(qLower))
            .toList();

    final missingKinds = widget.permSnapshot.coreMissing;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              if (hasQuery) ...[
                Material(
                  color: CueColors.accentLime,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _submitCommand,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.send, size: 18, color: Color(0xFF111113)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Run command: "${query.trim()}"',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111113),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (matchingApps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Matching Apps (${matchingApps.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: CueColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < matchingApps.length; i += 4) ...[
                    _FourColumnSquareRow(
                      items: matchingApps.sublist(i, (i + 4).clamp(0, matchingApps.length)),
                      onLaunch: (app) => widget.onLaunchPackage(app.packageName),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ] else ...[
                if (missingKinds.isNotEmpty && !_permBannerDismissed) ...[
                  _MissingPermBanner(
                    missingKinds: missingKinds,
                    onGrant: widget.onGrantMissingPermissions,
                    onHide: () => setState(() => _permBannerDismissed = true),
                  ),
                  const SizedBox(height: 10),
                ],
                _SectionTitleRow(
                  title: 'Essentials',
                  caption: widget.aiSnapshot.isReady
                      ? 'Nano AI · On'
                      : widget.aiSnapshot.status == AiModelStatus.downloading
                          ? 'AI ${(widget.aiSnapshot.downloadProgress * 100).round()}%'
                          : 'Nano AI',
                  accentCaption: widget.aiSnapshot.isReady,
                  onCaptionTap: widget.onOpenAiTab,
                ),
                const SizedBox(height: 6),
                _EssentialsTopBentoRow(
                  slotSmall: essentials.smallTop,
                  slotWideDark: essentials.wideDark,
                  slotWideLime: essentials.wideLime,
                  onLaunchApp: (app) => widget.onLaunchPackage(app.packageName),
                  onRunCommand: _submitCommand,
                  onOpenSetupTab: widget.onOpenSetupTab,
                ),
                if (essentials.gridRow.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _FourColumnSquareRow(
                    items: essentials.gridRow,
                    onLaunch: (app) => widget.onLaunchPackage(app.packageName),
                  ),
                ],
                const SizedBox(height: 14),
                _SectionTitleRow(
                  title: 'Favourites',
                  caption: '${widget.apps.length} apps',
                  onCaptionTap: () => setState(() => _allAppsExpanded = !_allAppsExpanded),
                ),
                const SizedBox(height: 6),
                _FavouritesBentoRow(
                  slotLime: favourites.squareLime,
                  slotMidA: favourites.squareMidA,
                  slotMidB: favourites.squareMidB,
                  slotWide: favourites.wideTile,
                  onLaunchApp: (app) => widget.onLaunchPackage(app.packageName),
                  onRunCommand: _submitCommand,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => setState(() => _allAppsExpanded = !_allAppsExpanded),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'All Apps',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CueColors.textSecondary),
                          ),
                        ),
                        Text(
                          _allAppsExpanded ? 'Collapse' : 'Browse all ${widget.apps.length}',
                          style: const TextStyle(fontSize: 12, color: CueColors.textSecondary),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _allAppsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 16,
                          color: CueColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_allAppsExpanded) ...[
                  const SizedBox(height: 6),
                  for (var i = 0; i < widget.apps.length; i += 4) ...[
                    _FourColumnSquareRow(
                      items: widget.apps.sublist(i, (i + 4).clamp(0, widget.apps.length)),
                      onLaunch: (app) => widget.onLaunchPackage(app.packageName),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: showReplyBanner
              ? RatioAssistantCard(
                  state: state,
                  voiceState: widget.voiceState,
                  latestText: latestReply?.text,
                  isError: latestReply?.role == ChatRole.error,
                  onSelectChoice: (choice) {
                    widget.onClearVoiceNotice();
                    setState(() => _lastDismissedMessageId = null);
                    final permKey = state.pendingPermissionKey;
                    if (permKey != null && choice.toLowerCase().startsWith('grant')) {
                      widget.onRequestPermissionKey(permKey);
                    } else {
                      widget.orchestrator.submitGoal(choice);
                    }
                  },
                  onOpenWebUrl: widget.onOpenUrl,
                  onConfirm: widget.orchestrator.resolveConfirmation,
                  onCancelRunning: widget.orchestrator.cancelActiveGoal,
                  onToggleTts: widget.onToggleTts,
                  onEnableBubble: widget.onToggleBubble,
                  onDismiss: () {
                    widget.onClearVoiceNotice();
                    widget.orchestrator.cancelActiveGoal();
                    setState(() => _lastDismissedMessageId = latestReply?.id);
                  },
                )
              : const SizedBox.shrink(),
        ),
        if (dockApps.isNotEmpty && !hasQuery)
          _RatioBottomDock(
            dockApps: dockApps,
            onLaunchApp: (app) => widget.onLaunchPackage(app.packageName),
          ),
        _RatioBottomSearchBar(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          isListening: widget.voiceState.isListening,
          isRunning: state.isRunning,
          onChanged: (_) => setState(() {}),
          onSubmit: () => _submitCommand(),
          onCancelRunning: widget.orchestrator.cancelActiveGoal,
          onMicClick: () {
            if (_searchCtrl.text.trim().isNotEmpty) {
              _submitCommand();
            } else {
              setState(() => _lastDismissedMessageId = null);
              widget.onMicClick();
            }
          },
        ),
      ],
    );
  }
}

class _MissingPermBanner extends StatelessWidget {
  const _MissingPermBanner({
    required this.missingKinds,
    required this.onGrant,
    required this.onHide,
  });

  final List<MissingPermissionItem> missingKinds;
  final VoidCallback onGrant;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final preview = missingKinds.take(3).map((e) => e.title).join(', ');
    final extra = missingKinds.length - 3;
    final detail = extra > 0 ? '$preview +$extra' : preview;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: CueColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CueColors.accentLime.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: CueColors.accentLime, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${missingKinds.length} permissions missing',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: CueColors.textPrimary),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: CueColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RatioActionPill(label: 'Grant', accent: true, onTap: onGrant),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onHide,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            tooltip: 'Hide',
            icon: const Icon(Icons.close, size: 14, color: CueColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SectionTitleRow extends StatelessWidget {
  const _SectionTitleRow({
    required this.title,
    required this.caption,
    required this.onCaptionTap,
    this.accentCaption = false,
  });

  final String title;
  final String caption;
  final bool accentCaption;
  final VoidCallback onCaptionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: CueColors.textPrimary,
            ),
          ),
        ),
        InkWell(
          onTap: onCaptionTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 12,
                fontWeight: accentCaption ? FontWeight.w600 : FontWeight.w400,
                color: accentCaption ? CueColors.accentLime : CueColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EssentialsTopBentoRow extends StatelessWidget {
  const _EssentialsTopBentoRow({
    required this.slotSmall,
    required this.slotWideDark,
    required this.slotWideLime,
    required this.onLaunchApp,
    required this.onRunCommand,
    required this.onOpenSetupTab,
  });

  final LaunchableApp? slotSmall;
  final LaunchableApp? slotWideDark;
  final LaunchableApp? slotWideLime;
  final void Function(LaunchableApp app) onLaunchApp;
  final void Function(String cmd) onRunCommand;
  final VoidCallback onOpenSetupTab;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (slotSmall != null) ...[
          Expanded(
            flex: 19,
            child: _RatioSquareTile(
              app: slotSmall!,
              highlighted: false,
              showLimeBar: true,
              subLabel: 'app',
              height: 94,
              onTap: () => onLaunchApp(slotSmall!),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (slotWideDark != null) ...[
          Expanded(
            flex: 29,
            child: Builder(
              builder: (_) {
                final isMaps = slotWideDark!.label.toLowerCase().contains('map');
                return _RatioWideTile(
                  title: slotWideDark!.label,
                  app: slotWideDark,
                  highlighted: false,
                  pillOne: isMaps ? 'Home' : 'Read',
                  pillTwo: isMaps ? 'Work' : 'Reply',
                  onTileTap: () => onLaunchApp(slotWideDark!),
                  onPillOne: () => isMaps ? onLaunchApp(slotWideDark!) : onRunCommand('read messages'),
                  onPillTwo: () => isMaps ? onLaunchApp(slotWideDark!) : onRunCommand('read notifications'),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 30,
          child: _RatioWideTile(
            title: slotWideLime?.label ?? 'CueUI',
            app: slotWideLime,
            highlighted: true,
            pillOne: slotWideLime != null ? 'Open' : 'Setup',
            pillTwo: 'News',
            onTileTap: () => slotWideLime != null ? onLaunchApp(slotWideLime!) : onOpenSetupTab(),
            onPillOne: () => slotWideLime != null ? onLaunchApp(slotWideLime!) : onOpenSetupTab(),
            onPillTwo: () => onRunCommand('what is the current hot news'),
          ),
        ),
      ],
    );
  }
}

class _FavouritesBentoRow extends StatelessWidget {
  const _FavouritesBentoRow({
    required this.slotLime,
    required this.slotMidA,
    required this.slotMidB,
    required this.slotWide,
    required this.onLaunchApp,
    required this.onRunCommand,
  });

  final LaunchableApp? slotLime;
  final LaunchableApp? slotMidA;
  final LaunchableApp? slotMidB;
  final LaunchableApp? slotWide;
  final void Function(LaunchableApp app) onLaunchApp;
  final void Function(String cmd) onRunCommand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (slotLime != null) ...[
          Expanded(
            flex: 19,
            child: _RatioSquareTile(
              app: slotLime!,
              highlighted: true,
              showLimeBar: false,
              subLabel: 'fav',
              height: 94,
              onTap: () => onLaunchApp(slotLime!),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (slotMidA != null) ...[
          Expanded(
            flex: 18,
            child: _RatioSquareTile(
              app: slotMidA!,
              highlighted: false,
              showLimeBar: false,
              subLabel: null,
              height: 94,
              onTap: () => onLaunchApp(slotMidA!),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (slotMidB != null) ...[
          Expanded(
            flex: 18,
            child: _RatioSquareTile(
              app: slotMidB!,
              highlighted: false,
              showLimeBar: false,
              subLabel: null,
              height: 94,
              onTap: () => onLaunchApp(slotMidB!),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (slotWide != null)
          Expanded(
            flex: 29,
            child: Builder(
              builder: (_) {
                final isYt = slotWide!.label.toLowerCase().contains('youtube');
                return _RatioWideTile(
                  title: slotWide!.label,
                  app: slotWide,
                  highlighted: false,
                  pillOne: isYt ? 'Lofi' : 'Status',
                  pillTwo: isYt ? 'Music' : 'Open',
                  onTileTap: () => onLaunchApp(slotWide!),
                  onPillOne: () => isYt ? onRunCommand('play lofi music on youtube') : onRunCommand('device status'),
                  onPillTwo: () => isYt ? onRunCommand('play chill jazz on youtube') : onLaunchApp(slotWide!),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _FourColumnSquareRow extends StatelessWidget {
  const _FourColumnSquareRow({required this.items, required this.onLaunch});

  final List<LaunchableApp> items;
  final void Function(LaunchableApp app) onLaunch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: i < items.length
                ? _RatioSquareTile(
                    app: items[i],
                    highlighted: false,
                    showLimeBar: false,
                    subLabel: null,
                    height: 88,
                    onTap: () => onLaunch(items[i]),
                  )
                : const SizedBox(height: 88),
          ),
        ],
      ],
    );
  }
}

class _RatioSquareTile extends StatelessWidget {
  const _RatioSquareTile({
    required this.app,
    required this.highlighted,
    required this.showLimeBar,
    required this.subLabel,
    required this.height,
    required this.onTap,
  });

  final LaunchableApp app;
  final bool highlighted;
  final bool showLimeBar;
  final String? subLabel;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? CueColors.accentLime : CueColors.tile;
    final fg = highlighted ? const Color(0xFF121214) : CueColors.textPrimary;
    final muted = highlighted ? const Color(0xFF3E4211) : CueColors.textSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              if (showLimeBar)
                Positioned(
                  top: 10,
                  right: 8,
                  child: Container(
                    width: 20,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: highlighted ? const Color(0xFF121214) : CueColors.accentLime,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RatioAppGlyph(app: app, tint: fg, size: 24),
                      const SizedBox(height: 6),
                      Text(
                        app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                      if (subLabel != null)
                        Text(
                          subLabel!,
                          maxLines: 1,
                          style: TextStyle(fontSize: 9.5, color: muted),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatioWideTile extends StatelessWidget {
  const _RatioWideTile({
    required this.title,
    required this.app,
    required this.highlighted,
    required this.pillOne,
    required this.pillTwo,
    required this.onTileTap,
    required this.onPillOne,
    required this.onPillTwo,
  });

  final String title;
  final LaunchableApp? app;
  final bool highlighted;
  final String pillOne;
  final String pillTwo;
  final VoidCallback onTileTap;
  final VoidCallback onPillOne;
  final VoidCallback onPillTwo;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? CueColors.accentLime : CueColors.tile;
    final fg = highlighted ? const Color(0xFF121214) : CueColors.textPrimary;
    final pillBorder = highlighted ? const Color(0xFF282C08) : const Color(0xFF33333C);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTileTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 94,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (app != null)
                    RatioAppGlyph(app: app!, tint: fg, size: 17)
                  else
                    Icon(Icons.public_outlined, color: fg, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ),
                  Container(
                    width: 18,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: highlighted ? const Color(0xFF121214) : CueColors.accentLime,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _TileInnerPill(label: pillOne, fg: fg, borderColor: pillBorder, onTap: onPillOne),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _TileInnerPill(label: pillTwo, fg: fg, borderColor: pillBorder, onTap: onPillTwo),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileInnerPill extends StatelessWidget {
  const _TileInnerPill({
    required this.label,
    required this.fg,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final Color fg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
        ),
      ),
    );
  }
}

class _RatioBottomDock extends StatelessWidget {
  const _RatioBottomDock({required this.dockApps, required this.onLaunchApp});

  final List<LaunchableApp> dockApps;
  final void Function(LaunchableApp app) onLaunchApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(color: CueColors.dockBg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final app in dockApps.take(5))
            InkWell(
              onTap: () => onLaunchApp(app),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        RatioAppGlyph(app: app, tint: const Color(0xFFDCDCE2), size: 24),
                        Positioned(
                          top: -1,
                          right: -2,
                          child: Container(
                            width: 4.5,
                            height: 4.5,
                            decoration: const BoxDecoration(color: CueColors.accentLime, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      app.label.length > 8 ? app.label.substring(0, 8) : app.label,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 9.5, color: CueColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RatioBottomSearchBar extends StatelessWidget {
  const _RatioBottomSearchBar({
    required this.controller,
    required this.focusNode,
    required this.isListening,
    required this.isRunning,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancelRunning,
    required this.onMicClick,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isListening;
  final bool isRunning;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancelRunning;
  final VoidCallback onMicClick;

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.trim().isNotEmpty;
    final circleColor = (isListening || hasQuery) ? CueColors.accentLime : CueColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: GestureDetector(
        onTap: () => focusNode.requestFocus(),
        child: Container(
          padding: const EdgeInsets.only(left: 18, right: 6, top: 5, bottom: 5),
          decoration: BoxDecoration(
            color: CueColors.searchBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: CueColors.subtleEdge),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmit(),
                  textInputAction: TextInputAction.send,
                  cursorColor: CueColors.accentLime,
                  style: const TextStyle(color: CueColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: isListening ? 'Listening...' : 'Tap to search apps or ask CueUI',
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: isListening ? CueColors.accentLime : CueColors.textMuted,
                    ),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  icon: const Icon(Icons.close, size: 16, color: CueColors.textMuted),
                ),
              const SizedBox(width: 4),
              Material(
                color: circleColor,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: hasQuery
                      ? onSubmit
                      : isRunning
                          ? onCancelRunning
                          : onMicClick,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: hasQuery
                          ? const Icon(Icons.send, size: 18, color: Color(0xFF111113))
                          : isRunning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF111113),
                                  ),
                                )
                              : isListening
                                  ? const Icon(Icons.stop, size: 20, color: Color(0xFF111113))
                                  : const Icon(Icons.mic_none, size: 20, color: Color(0xFF111113)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
