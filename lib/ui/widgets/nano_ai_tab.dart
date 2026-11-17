import 'package:flutter/material.dart';
import '../../models/cue_models.dart';
import '../../services/nano_ai_service.dart';
import '../cue_theme.dart';

class NanoAiTab extends StatefulWidget {
  const NanoAiTab({
    super.key,
    required this.aiService,
    required this.onRunFullCommand,
  });

  final NanoAiService aiService;
  final void Function(String query) onRunFullCommand;

  @override
  State<NanoAiTab> createState() => _NanoAiTabState();
}

class _NanoAiTabState extends State<NanoAiTab> {
  final TextEditingController _probeCtrl = TextEditingController();
  String _probeOutput = '';
  bool _probing = false;

  @override
  void dispose() {
    _probeCtrl.dispose();
    super.dispose();
  }

  Future<void> _runProbe() async {
    final q = _probeCtrl.text.trim();
    if (q.isEmpty || !widget.aiService.isReady) return;
    setState(() {
      _probing = true;
      _probeOutput = 'Running local Nano LLM intent extraction...';
    });
    final call = await widget.aiService.parseNaturalLanguageQuery(q);
    if (!mounted) return;
    final snap = widget.aiService.snapshot;
    final ms = snap.lastInferenceMs;
    final trace = snap.lastParsedSummary;
    setState(() {
      _probing = false;
      _probeOutput = call == null
          ? 'No tool matched (${ms ?? 0} ms)${trace != null ? "\nTrace: $trace" : ""}'
          : 'Tool: ${call.tool}\nArgs: ${call.args}\nTime: ${ms ?? 0} ms';
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.aiService.snapshot;
    final isDownloading = snap.status == AiModelStatus.downloading;
    final isLoading = snap.status == AiModelStatus.loading || snap.status == AiModelStatus.scanning;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Nano AI (Keep-Warm NLU)',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: CueColors.textPrimary),
              ),
            ),
            RatioActionPill(
              label: 'Scan',
              accent: false,
              onTap: () => widget.aiService.autoDetectAndWarmLoad(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tier 1 handles crisp commands in <5ms. When phrasing is casual or unusual, this tiny GGUF model investigates it 100% offline using grammar-constrained JSON.',
          style: TextStyle(fontSize: 12, color: CueColors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),

        // Engine status card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CueColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: snap.isReady
                  ? CueColors.accentGreen.withValues(alpha: 0.45)
                  : CueColors.accentLime.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: snap.isReady
                          ? CueColors.accentGreen
                          : snap.status == AiModelStatus.error
                              ? CueColors.accentRed
                              : CueColors.accentLime,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snap.loadedModelName ?? 'Nano NLU Standby',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: CueColors.textPrimary),
                    ),
                  ),
                  if (snap.isReady)
                    RatioActionPill(
                      label: 'Unload',
                      accent: false,
                      onTap: () => widget.aiService.unloadModel(),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(snap.statusMessage, style: const TextStyle(fontSize: 12, color: CueColors.textSecondary)),
              if (snap.lastParsedSummary != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last NL trace: ${snap.lastParsedSummary}',
                  style: const TextStyle(fontSize: 11.5, color: CueColors.accentLime),
                ),
              ],
              if (isDownloading || isLoading) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isDownloading ? snap.downloadProgress : null,
                    backgroundColor: const Color(0xFF282830),
                    valueColor: const AlwaysStoppedAnimation<Color>(CueColors.accentLime),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Quick NL probe tester when ready
        if (snap.isReady) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: CueColors.tile, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Test Natural Language Query',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: CueColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _probeCtrl,
                  style: const TextStyle(color: CueColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. "yo ping mom on wa saying reached safely"',
                    hintStyle: const TextStyle(color: CueColors.textMuted, fontSize: 12.5),
                    filled: true,
                    fillColor: CueColors.searchBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    RatioActionPill(
                      label: _probing ? 'Testing...' : 'Parse Only',
                      accent: true,
                      onTap: _probing ? () {} : _runProbe,
                    ),
                    const SizedBox(width: 8),
                    RatioActionPill(
                      label: 'Run on Home',
                      accent: false,
                      onTap: () {
                        final q = _probeCtrl.text.trim();
                        if (q.isNotEmpty) widget.onRunFullCommand(q);
                      },
                    ),
                  ],
                ),
                if (_probeOutput.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_probeOutput, style: const TextStyle(fontSize: 12, color: CueColors.textPrimary)),
                ],
              ],
            ),
          ),
        ],

        // Auto-discovered local GGUF files
        if (snap.discoveredFiles.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Detected Local Models (.gguf)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CueColors.textPrimary),
          ),
          const SizedBox(height: 8),
          for (final file in snap.discoveredFiles) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: CueColors.tile, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: CueColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${file.sizeMb.toStringAsFixed(0)} MB · ${file.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: CueColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RatioActionPill(
                    label: file.isLoaded ? 'Loaded' : 'Warm Load',
                    accent: !file.isLoaded,
                    onTap: file.isLoaded ? () {} : () => widget.aiService.loadModelFromPath(file.path),
                  ),
                ],
              ),
            ),
          ],
        ],

        const SizedBox(height: 14),
        const Text(
          'Fast Nano Models Catalog',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CueColors.textPrimary),
        ),
        const SizedBox(height: 8),
        for (final entry in NanoAiService.catalog) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: CueColors.tile, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.title,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: CueColors.textPrimary),
                            ),
                          ),
                          if (entry.recommended) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF252814),
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: const Text(
                                'FASTEST',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: CueColors.accentLime),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(entry.subtitle, style: const TextStyle(fontSize: 11.5, color: CueColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RatioActionPill(
                  label: snap.downloadingId == entry.id
                      ? 'Downloading...'
                      : (snap.loadedModelName == entry.fileName && snap.isReady)
                          ? 'Active'
                          : 'Download',
                  accent: snap.loadedModelName != entry.fileName || !snap.isReady,
                  onTap: isDownloading ? () {} : () => widget.aiService.downloadAndWarmModel(entry),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
