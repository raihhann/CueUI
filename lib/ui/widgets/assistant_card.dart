import 'package:flutter/material.dart';
import '../../models/cue_models.dart';
import '../cue_theme.dart';

class RatioAssistantCard extends StatelessWidget {
  const RatioAssistantCard({
    super.key,
    required this.state,
    required this.voiceState,
    required this.latestText,
    required this.isError,
    required this.onSelectChoice,
    required this.onOpenWebUrl,
    required this.onConfirm,
    required this.onCancelRunning,
    required this.onToggleTts,
    required this.onEnableBubble,
    required this.onDismiss,
  });

  final CueUiState state;
  final VoiceUiState voiceState;
  final String? latestText;
  final bool isError;
  final void Function(String choice) onSelectChoice;
  final void Function(String url) onOpenWebUrl;
  final void Function(bool approved) onConfirm;
  final VoidCallback onCancelRunning;
  final VoidCallback onToggleTts;
  final VoidCallback onEnableBubble;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final highlightedBorder = state.isAwaitingReply ||
        state.pendingConfirmationPrompt != null ||
        voiceState.isListening;

    final dotColor = isError
        ? CueColors.accentRed
        : (state.isRunning || voiceState.isListening || state.isAwaitingReply)
            ? CueColors.accentLime
            : CueColors.accentGreen;

    final headerText = voiceState.isListening
        ? 'Listening...'
        : state.isRunning
            ? state.statusLine
            : 'CueUI';

    final displayBody = voiceState.isListening
        ? (voiceState.partialTranscript.isNotEmpty
            ? voiceState.partialTranscript
            : 'Speak a command (e.g. "play lofi music on youtube")...')
        : (voiceState.statusNotice ?? latestText ?? '');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CueColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlightedBorder ? CueColors.accentLime.withValues(alpha: 0.5) : CueColors.subtleEdge,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        headerText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: CueColors.textSecondary,
                        ),
                      ),
                    ),
                    if (!state.isRunning && state.lastRouteBadge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252814),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: CueColors.accentLime.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          state.lastRouteBadge!,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: CueColors.accentLime,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleTts,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                tooltip: 'Voice replies',
                icon: Icon(
                  voiceState.ttsEnabled ? Icons.volume_up : Icons.volume_off,
                  size: 16,
                  color: voiceState.ttsEnabled ? CueColors.accentLime : CueColors.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close, size: 16, color: CueColors.textMuted),
              ),
            ],
          ),
          if (voiceState.isListening) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                width: double.infinity,
                child: LinearProgressIndicator(
                  value: voiceState.rmsLevel.clamp(0.08, 1.0),
                  backgroundColor: const Color(0xFF2B2B32),
                  valueColor: const AlwaysStoppedAnimation<Color>(CueColors.accentLime),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            displayBody,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: isError ? CueColors.accentRed : CueColors.textPrimary,
            ),
          ),
          if (voiceState.statusNotice != null && !state.bubbleActive) ...[
            const SizedBox(height: 6),
            RatioActionPill(
              label: 'Enable Floating Bubble',
              accent: true,
              onTap: onEnableBubble,
            ),
          ],
          if (state.pendingConfirmationPrompt != null) ...[
            const SizedBox(height: 8),
            Text(
              state.pendingConfirmationPrompt!,
              style: const TextStyle(
                fontSize: 12.5,
                color: CueColors.accentLime,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                RatioActionPill(label: 'Confirm', accent: true, onTap: () => onConfirm(true)),
                const SizedBox(width: 8),
                RatioActionPill(label: 'Cancel', accent: false, onTap: () => onConfirm(false)),
              ],
            ),
          ] else if (state.isRunning) ...[
            const SizedBox(height: 8),
            RatioActionPill(label: 'Stop', accent: false, onTap: onCancelRunning),
          ] else if (state.quickChoices.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < state.quickChoices.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Builder(
                      builder: (_) {
                        final choice = state.quickChoices[i];
                        final lower = choice.toLowerCase();
                        final isPrimary = lower.startsWith('yes') || lower.startsWith('grant');
                        return RatioActionPill(
                          label: choice,
                          accent: isPrimary,
                          onTap: () => onSelectChoice(choice),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ] else if (state.pendingWebUrl != null && state.pendingWebUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            RatioActionPill(
              label: 'Open in Browser',
              accent: true,
              onTap: () => onOpenWebUrl(state.pendingWebUrl!),
            ),
          ],
        ],
      ),
    );
  }
}
