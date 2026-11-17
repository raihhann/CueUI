import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/cue_models.dart';
import '../../services/media_service.dart';
import '../../services/nano_ai_service.dart';
import '../../services/routine_service.dart';
import '../app_theme.dart';

typedef RunCueTool = Future<void> Function(PlannedToolCall call, String label);

class MediaLibrary extends StatefulWidget {
  const MediaLibrary({super.key, required this.media, required this.run});
  final CueMediaService media;
  final RunCueTool run;
  @override
  State<MediaLibrary> createState() => _MediaLibraryState();
}

class _MediaLibraryState extends State<MediaLibrary> {
  String query = '';
  String? working;
  String? operation;
  Future<void> action(String name, CapturedMedia item) async {
    if (name == 'share') {
      final recipient = await _textDialog(
        context,
        'Send on WhatsApp',
        'Contact name or phone number',
      );
      if (recipient == null || recipient.trim().isEmpty) return;
      await widget.run(
        PlannedToolCall(
          tool: 'whatsapp_share_media',
          args: {'id': item.id, 'recipient': recipient, 'kind': item.kind},
        ),
        'Send ${item.title} to $recipient on WhatsApp',
      );
      return;
    }
    if (name == 'rename' || name == 'edit_transcript') {
      final text = await _textDialog(
        context,
        name == 'rename' ? 'Rename ${item.kind}' : 'Edit transcript',
        name == 'rename' ? 'Title' : 'Transcript',
        initial: name == 'rename' ? item.title : item.transcript,
        multiline: name != 'rename',
      );
      if (text == null) return;
      await widget.media.command(
        name == 'rename' ? 'rename' : 'save_transcript',
        {'id': item.id, name == 'rename' ? 'title' : 'transcript': text},
      );
      return;
    }
    if (name == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this item?'),
          content: Text(
            '“${item.title}” and its transcript will be removed from this phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      working = item.id;
      operation = name;
    });
    try {
      final result = await widget.media.command(name, {'id': item.id});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.summary)));
      }
    } finally {
      if (mounted) setState(() => working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.media.search(query), theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PageIntro(
          'Your ideas, kept.',
          'Photos, videos, recordings, and the words inside them.',
        ),
        const SizedBox(height: 20),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            hintText: 'Search titles and transcripts',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => widget.run(
                const PlannedToolCall(tool: 'record_audio_start'),
                'Start audio recording',
              ),
              icon: const Icon(Icons.mic),
              label: const Text('Record audio'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.run(
                const PlannedToolCall(tool: 'camera_photo'),
                'Take a photo',
              ),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Photo'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.run(
                const PlannedToolCall(tool: 'camera_video_start'),
                'Start video recording',
              ),
              icon: const Icon(Icons.videocam_outlined),
              label: const Text('Video'),
            ),
            TextButton(
              onPressed: widget.media.refresh,
              child: const Text('Refresh'),
            ),
            TextButton.icon(
              onPressed: () => widget.media.command('stop_playback'),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop playback'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (items.isEmpty)
          const CuePanel(
            child: Column(
              children: [
                Icon(Icons.graphic_eq_rounded, size: 44),
                SizedBox(height: 14),
                Text(
                  'Room for your next idea.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'Capture a photo or record something to see it here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CuePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: item.kind == 'photo'
                            ? Image.file(
                                File(item.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.image_outlined),
                              )
                            : Icon(
                                item.kind == 'audio'
                                    ? Icons.graphic_eq
                                    : Icons.movie_outlined,
                                color: theme.colorScheme.primary,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.kind.toUpperCase()} · ${_date(item.createdAt)}${item.durationMs > 0 ? ' · ${_duration(item.durationMs)}' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (working == item.id)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            if (operation == 'transcribe')
                              IconButton(
                                onPressed: () => widget.media.command(
                                  'cancel_transcription',
                                ),
                                tooltip: 'Cancel transcription',
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        )
                      else
                        PopupMenuButton<String>(
                          onSelected: (value) => action(value, item),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            if (item.kind == 'audio')
                              const PopupMenuItem(
                                value: 'edit_transcript',
                                child: Text('Edit transcript'),
                              ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Text('Send on WhatsApp'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: working == null
                            ? () => action('play', item)
                            : null,
                        icon: Icon(
                          item.kind == 'photo'
                              ? Icons.open_in_full
                              : Icons.play_arrow,
                        ),
                        label: Text(item.kind == 'photo' ? 'View' : 'Play'),
                      ),
                      if (item.kind == 'audio')
                        TextButton.icon(
                          onPressed: working == null
                              ? () => action('transcribe', item)
                              : null,
                          icon: const Icon(Icons.notes_rounded),
                          label: const Text('Transcribe'),
                        ),
                      TextButton.icon(
                        onPressed: () => action('share', item),
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Send'),
                      ),
                    ],
                  ),
                  if (item.transcript.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Transcript'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SelectableText(item.transcript),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Saved-audio transcription uses an on-device speech service on supported Android 13+ phones. Language data and file-input support are required. You can also add or edit a transcript manually.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _date(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${date.day}/${date.month}/${date.year}';
  }

  String _duration(int ms) =>
      '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
}

class RoutinesPanel extends StatelessWidget {
  const RoutinesPanel({super.key, required this.service, required this.run});
  final CueRoutineService service;
  final RunCueTool run;
  Future<void> edit(BuildContext context, [CueRoutine? routine]) async {
    final name = TextEditingController(text: routine?.name ?? '');
    final brightness = routine?.steps
        .where((step) => step.tool == 'set_brightness')
        .firstOrNull;
    final dnd = routine?.steps
        .where((step) => step.tool == 'set_dnd')
        .firstOrNull;
    final alarm = routine?.steps
        .where((step) => step.tool == 'set_alarm')
        .firstOrNull;
    double level = (brightness?.args['percent'] as num?)?.toDouble() ?? 40;
    bool includeAlarm = alarm != null,
        includeDnd = dnd != null,
        enableDnd = dnd?.args['enabled'] != false;
    TimeOfDay time = TimeOfDay(
      hour: (alarm?.args['hour'] as int?) ?? 7,
      minute: (alarm?.args['minute'] as int?) ?? 0,
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(routine == null ? 'Create a routine' : 'Make it yours'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Routine name'),
                ),
                const SizedBox(height: 16),
                Text('Brightness · ${level.round()}%'),
                Slider(
                  value: level,
                  min: 1,
                  max: 100,
                  onChanged: (value) => update(() => level = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Change Do Not Disturb'),
                  value: includeDnd,
                  onChanged: (value) => update(() => includeDnd = value),
                ),
                if (includeDnd)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Do Not Disturb'),
                    value: enableDnd,
                    onChanged: (value) => update(() => enableDnd = value),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set a wake-up alarm'),
                  value: includeAlarm,
                  onChanged: (value) => update(() => includeAlarm = value),
                ),
                if (includeAlarm)
                  TextButton(
                    onPressed: () async {
                      final selected = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (selected != null) update(() => time = selected);
                    },
                    child: Text(time.format(context)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save routine'),
            ),
          ],
        ),
      ),
    );
    if (save == true && name.text.trim().isNotEmpty) {
      try {
        await service.save(
          CueRoutine(name.text.trim(), [
            PlannedToolCall(
              tool: 'set_brightness',
              args: {'percent': level.round()},
            ),
            if (includeDnd)
              PlannedToolCall(tool: 'set_dnd', args: {'enabled': enableDnd}),
            if (includeAlarm)
              PlannedToolCall(
                tool: 'set_alarm',
                args: {
                  'hour': time.hour,
                  'minute': time.minute,
                  'label': '${name.text.trim()} alarm',
                },
              ),
          ]),
          originalName: routine?.name,
        );
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save routine: $error')),
          );
        }
      }
    }
    // The dialog's closing animation may still be using its controller.
    Future<void>.delayed(const Duration(milliseconds: 400), name.dispose);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const _PageIntro(
        'Small rituals.\nOne command.',
        'Tune a routine, then ask Cue to run it whenever you need it.',
      ),
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () => edit(context),
          icon: const Icon(Icons.add),
          label: const Text('New routine'),
        ),
      ),
      const SizedBox(height: 20),
      for (final routine in service.routines)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CuePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      routine.name.toLowerCase() == 'bedtime'
                          ? Icons.nights_stay_outlined
                          : Icons.auto_awesome_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        routine.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => edit(context, routine),
                      tooltip: 'Edit routine',
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final step in routine.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(switch (step.tool) {
                      'set_brightness' =>
                        'Brightness to ${step.args['percent']}%',
                      'set_dnd' =>
                        'Do Not Disturb ${step.args['enabled'] == true ? 'on' : 'off'}',
                      'set_alarm' =>
                        'Alarm at ${step.args['hour'].toString().padLeft(2, '0')}:${step.args['minute'].toString().padLeft(2, '0')}',
                      _ => 'Media control',
                    }),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => run(
                    PlannedToolCall(
                      tool: 'run_routine',
                      args: {'name': routine.name},
                    ),
                    'Run ${routine.name} routine',
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run routine'),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Routines run when you ask. Brightness and Do Not Disturb require their setup permissions. Alarm behavior is handled by your phone’s clock app.',
      ),
    ],
  );
}

class AppsPanel extends StatefulWidget {
  const AppsPanel({super.key, required this.apps, required this.launch});
  final List<LaunchableApp> apps;
  final void Function(String) launch;
  @override
  State<AppsPanel> createState() => _AppsPanelState();
}

class _AppsPanelState extends State<AppsPanel> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final apps = widget.apps
        .where((app) => app.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _PageIntro(
          'Everything, within reach.',
          'Your apps live here. Ask Cue to open one, or choose it below.',
        ),
        const SizedBox(height: 20),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            hintText: 'Find an app',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 20),
        if (apps.isEmpty) const CuePanel(child: Text('No matching apps.')),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth > 650 ? 6 : 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              mainAxisExtent: 125,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return InkWell(
                onTap: () => widget.launch(app.packageName),
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: app.iconBytes != null
                          ? Image.memory(app.iconBytes!)
                          : Icon(
                              Icons.apps_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      app.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.permissions,
    required this.ai,
    required this.mode,
    required this.onMode,
    required this.requestPermission,
    required this.setLauncher,
    required this.toggleBubble,
    required this.bubbleActive,
    required this.grantMissing,
  });
  final PermissionSnapshot permissions;
  final NanoAiService ai;
  final ThemeMode mode;
  final void Function(ThemeMode) onMode;
  final void Function(String) requestPermission;
  final VoidCallback setLauncher, toggleBubble, grantMissing;
  final bool bubbleActive;
  @override
  Widget build(BuildContext context) {
    final snap = ai.snapshot, theme = Theme.of(context);
    final entries = [
      ('MICROPHONE', 'Microphone', permissions.recordAudioGranted),
      ('CAMERA', 'Camera', permissions.cameraGranted),
      ('CONTACTS', 'Contacts', permissions.contactsGranted),
      ('CALL_PHONE', 'Phone calls', permissions.callPhoneGranted),
      ('ANSWER_CALLS', 'Manage calls', permissions.answerCallsGranted),
      ('SEND_SMS', 'Send texts', permissions.sendSmsGranted),
      ('READ_SMS', 'Read texts', permissions.readSmsGranted),
      (
        'POST_NOTIFICATIONS',
        'Notifications',
        permissions.postNotificationsGranted,
      ),
      ('ACCESSIBILITY', 'Control apps', permissions.accessibilityEnabled),
      ('OVERLAY', 'Floating assistant', permissions.overlayEnabled),
      (
        'NOTIFICATION_LISTENER',
        'Read notifications',
        permissions.notificationListenerEnabled,
      ),
      ('WRITE_SETTINGS', 'Change brightness', permissions.writeSettingsGranted),
      ('DND_ACCESS', 'Do Not Disturb', permissions.dndPolicyGranted),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _PageIntro(
          'Your phone. Your way.',
          'Appearance, access, and on-device understanding.',
        ),
        const SizedBox(height: 24),
        CuePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: theme.textTheme.titleMedium),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in [
                    (ThemeMode.system, 'System', Icons.brightness_auto),
                    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                  ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      avatar: Icon(entry.$3, size: 18),
                      showCheckmark: false,
                      selected: mode == entry.$1,
                      onSelected: (_) => onMode(entry.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CuePanel(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Floating assistant'),
                subtitle: const Text('Keep Cue available over other apps'),
                value: bubbleActive,
                onChanged: (_) => toggleBubble(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Home screen'),
                subtitle: Text(
                  permissions.isDefaultLauncher
                      ? 'Cue is your default launcher'
                      : 'Make Cue your phone’s home',
                ),
                trailing: TextButton(
                  onPressed: setLauncher,
                  child: Text(
                    permissions.isDefaultLauncher ? 'Selected' : 'Set home',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CuePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Permissions',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: grantMissing,
                    child: const Text('Grant missing'),
                  ),
                ],
              ),
              const Text('Enable the access needed for the actions you use.'),
              const SizedBox(height: 10),
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(entry.$2),
                  leading: Icon(
                    entry.$3
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    color: entry.$3
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  trailing: TextButton(
                    onPressed: () => requestPermission(entry.$1),
                    child: Text(entry.$3 ? 'Manage' : 'Enable'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CuePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'On-device understanding',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(snap.statusMessage),
              if (snap.status == AiModelStatus.downloading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(value: snap.downloadProgress),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: ai.autoDetectAndWarmLoad,
                    child: const Text('Find local models'),
                  ),
                  if (snap.isReady)
                    TextButton(
                      onPressed: ai.unloadModel,
                      child: const Text('Unload model'),
                    ),
                ],
              ),
              for (final model in NanoAiService.catalog)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(model.title),
                  subtitle: Text(
                    '${model.sizeMb} MB · local intent understanding',
                  ),
                  trailing: IconButton(
                    onPressed:
                        snap.status == AiModelStatus.downloading ||
                            snap.status == AiModelStatus.loading
                        ? null
                        : () => ai.downloadAndWarmModel(model),
                    tooltip: 'Download model',
                    icon: const Icon(Icons.download_outlined),
                  ),
                ),
              for (final file in snap.discoveredFiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(file.name),
                  trailing: TextButton(
                    onPressed: file.isLoaded
                        ? null
                        : () => ai.loadModelFromPath(file.path),
                    child: Text(file.isLoaded ? 'Active' : 'Load'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'CueUI · Agentic phone controls\nCommands run on your phone. Weather, news, and web answers use internet services. Saved-audio transcription depends on device support.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

Future<String?> _textDialog(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
  bool multiline = false,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: multiline ? 5 : 1,
        maxLines: multiline ? 12 : 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return value;
}
