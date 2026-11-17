import 'package:flutter/material.dart';
import '../../models/cue_models.dart';
import '../../orchestrator/cue_orchestrator.dart';
import '../../services/media_service.dart';
import '../app_theme.dart';

class AssistantHome extends StatefulWidget {
  const AssistantHome({
    super.key,
    required this.orchestrator,
    required this.voice,
    required this.media,
    required this.onMic,
    required this.onSpeakToggle,
    required this.onOpenUrl,
    required this.onPermission,
    required this.onCancel,
  });
  final CueOrchestrator orchestrator;
  final VoiceUiState voice;
  final CueMediaService media;
  final VoidCallback onMic, onSpeakToggle, onCancel;
  final void Function(String) onOpenUrl, onPermission;
  @override
  State<AssistantHome> createState() => _AssistantHomeState();
}

class _AssistantHomeState extends State<AssistantHome> {
  final input = TextEditingController();
  final scroll = ScrollController();
  int count = 0;
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send([String? override]) {
    final text = (override ?? input.text).trim();
    if (text.isEmpty) return;
    input.clear();
    FocusScope.of(context).unfocus();
    widget.orchestrator.submitGoal(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final state = widget.orchestrator.state;
    final messages = state.messages
        .where(
          (message) =>
              message.role == ChatRole.user || message.role == ChatRole.agent,
        )
        .toList();
    if (count != state.messages.length) {
      final shouldScroll = count > 0;
      count = state.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (shouldScroll && mounted && scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              Text(
                'A little less tapping.\nA lot more doing.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Capture an idea. Reach someone. Make your phone work for you.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.mic_rounded,
                      title: 'Record',
                      subtitle: 'Save an idea',
                      color: colors.secondary,
                      onTap: () => send('start audio recording'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Action(
                      icon: Icons.camera_alt_rounded,
                      title: 'Capture',
                      subtitle: 'Take a photo',
                      color: colors.primary,
                      onTap: () => send('take a photo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Action(
                      icon: Icons.nights_stay_rounded,
                      title: 'Unwind',
                      subtitle: 'Bedtime routine',
                      color: colors.tertiary,
                      onTap: () => send('run bedtime routine'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'YOUR CONVERSATION',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.8,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onSpeakToggle,
                    tooltip: 'Spoken replies',
                    icon: Icon(
                      widget.voice.ttsEnabled
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                      size: 20,
                    ),
                  ),
                ],
              ),
              for (final message in messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: message.role == ChatRole.user
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 650),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: message.role == ChatRole.user
                            ? colors.primaryContainer
                            : colors.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(
                            message.role == ChatRole.user ? 20 : 5,
                          ),
                          bottomRight: Radius.circular(
                            message.role == ChatRole.user ? 5 : 20,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.role == ChatRole.user ? 'YOU' : 'CUE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.6,
                              color: message.role == ChatRole.error
                                  ? colors.error
                                  : colors.primary,
                            ),
                          ),
                          const SizedBox(height: 7),
                          SelectableText(
                            message.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                              color: message.role == ChatRole.error
                                  ? colors.error
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (state.isRunning)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(state.statusLine)),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              if (state.pendingConfirmationPrompt != null)
                CuePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state.pendingConfirmationPrompt!),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                widget.orchestrator.resolveConfirmation(true),
                            child: const Text('Confirm'),
                          ),
                          TextButton(
                            onPressed: () =>
                                widget.orchestrator.resolveConfirmation(false),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (state.quickChoices.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in state.quickChoices)
                      ActionChip(
                        label: Text(choice),
                        onPressed: () {
                          if (choice.toLowerCase().startsWith('grant') &&
                              state.pendingPermissionKey != null) {
                            widget.onPermission(state.pendingPermissionKey!);
                          } else {
                            send(choice);
                          }
                        },
                      ),
                  ],
                ),
              if (state.pendingWebUrl != null)
                TextButton.icon(
                  onPressed: () => widget.onOpenUrl(state.pendingWebUrl!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open source in browser'),
                ),
              if (state.messages.length < 3)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final suggestion in [
                      'Take a selfie in 3 seconds',
                      'Send hi to Raihan on WhatsApp',
                      'What’s the weather?',
                    ])
                      ActionChip(
                        label: Text(suggestion),
                        onPressed: () => send(suggestion),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (widget.voice.statusNotice != null || widget.voice.isListening)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Text(
              widget.voice.partialTranscript.isNotEmpty
                  ? widget.voice.partialTranscript
                  : widget.voice.statusNotice ?? 'Listening…',
              style: TextStyle(color: colors.secondary),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: CuePanel(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: widget.onMic,
                  tooltip: widget.voice.isListening
                      ? 'Stop listening'
                      : 'Speak a command',
                  icon: Icon(
                    widget.voice.isListening
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    color: colors.primary,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask Cue to do something…',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: () => send(),
                  tooltip: 'Send command',
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .10),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
