import 'package:flutter/material.dart';
import '../../models/cue_models.dart';
import '../cue_theme.dart';

class RatioSetupTab extends StatelessWidget {
  const RatioSetupTab({
    super.key,
    required this.snap,
    required this.onGrantAllMissing,
    required this.onRequestPermissionKey,
    required this.onOpenAppDetails,
    required this.onRequestDefaultLauncher,
  });

  final PermissionSnapshot snap;
  final VoidCallback onGrantAllMissing;
  final void Function(String key) onRequestPermissionKey;
  final VoidCallback onOpenAppDetails;
  final VoidCallback onRequestDefaultLauncher;

  @override
  Widget build(BuildContext context) {
    final coreReadyCount = [
      snap.allRuntimeGranted,
      snap.isDefaultLauncher,
      snap.accessibilityEnabled,
      snap.overlayEnabled,
      snap.notificationListenerEnabled,
      snap.writeSettingsGranted,
      snap.dndPolicyGranted,
    ].where((b) => b).length;

    final totalMissing = snap.coreMissing.length;

    final runtimeItems = [
      ('CONTACTS', 'Contacts', snap.contactsGranted),
      ('CALL_PHONE', 'Phone Calls', snap.callPhoneGranted),
      ('ANSWER_CALLS', 'Answer & End Calls', snap.answerCallsGranted),
      ('SEND_SMS', 'Send SMS', snap.sendSmsGranted),
      ('READ_SMS', 'Read SMS', snap.readSmsGranted),
      ('MICROPHONE', 'Microphone', snap.recordAudioGranted),
      ('POST_NOTIFICATIONS', 'Notifications', snap.postNotificationsGranted),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Setup',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: CueColors.textPrimary),
              ),
            ),
            Text(
              '$coreReadyCount / 7 ready',
              style: const TextStyle(fontSize: 12.5, color: CueColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              value: coreReadyCount / 7.0,
              backgroundColor: const Color(0xFF232329),
              valueColor: const AlwaysStoppedAnimation<Color>(CueColors.accentLime),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!snap.allRuntimeGranted || totalMissing > 0) ...[
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: CueColors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CueColors.accentLime.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        totalMissing > 0 ? '$totalMissing missing permissions' : 'Runtime permissions needed',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: CueColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Tap Grant Missing to allow needed permissions directly from CueUI.',
                        style: TextStyle(fontSize: 11.5, color: CueColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RatioActionPill(label: 'Grant Missing', accent: true, onTap: onGrantAllMissing),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: CueColors.tile,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App Permissions (Tap any to grant)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: CueColors.textPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Microphone, Contacts, Calls, SMS & Notifications.',
                          style: TextStyle(fontSize: 11.5, color: CueColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RatioActionPill(
                    label: snap.allRuntimeGranted ? 'Granted' : 'Grant All',
                    accent: !snap.allRuntimeGranted,
                    onTap: snap.allRuntimeGranted ? onOpenAppDetails : onGrantAllMissing,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < runtimeItems.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      SoftPillChip(
                        label: runtimeItems[i].$2,
                        selected: runtimeItems[i].$3,
                        dotColor: runtimeItems[i].$3 ? CueColors.accentGreen : CueColors.accentLime,
                        onTap: () {
                          if (!runtimeItems[i].$3) {
                            onRequestPermissionKey(runtimeItems[i].$1);
                          } else {
                            onOpenAppDetails();
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SetupRow(
          title: 'Default Home Launcher',
          subtitle: 'Replaces home screen with CueUI voice & Bento apps.',
          ready: snap.isDefaultLauncher,
          actionLabel: snap.isDefaultLauncher ? 'Default' : 'Set',
          onAction: onRequestDefaultLauncher,
        ),
        const SizedBox(height: 10),
        _SetupRow(
          title: 'Accessibility Control',
          subtitle: 'Navigates YouTube, Play Store, WhatsApp & screen actions.',
          ready: snap.accessibilityEnabled,
          onAction: () => onRequestPermissionKey('ACCESSIBILITY'),
        ),
        const SizedBox(height: 10),
        _SetupRow(
          title: 'Floating Bubble Overlay',
          subtitle: 'Summons CueUI keyboard & actions over any app.',
          ready: snap.overlayEnabled,
          onAction: () => onRequestPermissionKey('OVERLAY'),
        ),
        const SizedBox(height: 10),
        _SetupRow(
          title: 'Notification Listener',
          subtitle: 'Reads and replies to WhatsApp/SMS notifications on-device.',
          ready: snap.notificationListenerEnabled,
          onAction: () => onRequestPermissionKey('NOTIFICATION_LISTENER'),
        ),
        const SizedBox(height: 10),
        _SetupRow(
          title: 'Screen Brightness',
          subtitle: 'Optional system write access for brightness commands.',
          ready: snap.writeSettingsGranted,
          onAction: () => onRequestPermissionKey('WRITE_SETTINGS'),
        ),
        const SizedBox(height: 10),
        _SetupRow(
          title: 'Do Not Disturb',
          subtitle: 'Optional policy access to toggle silent/DND mode.',
          ready: snap.dndPolicyGranted,
          onAction: () => onRequestPermissionKey('DND_ACCESS'),
        ),
      ],
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.title,
    required this.subtitle,
    required this.ready,
    required this.onAction,
    this.actionLabel,
  });

  final String title;
  final String subtitle;
  final bool ready;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final btnLabel = actionLabel ?? (ready ? 'On' : 'Open');
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CueColors.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: ready ? const Color(0xFF142A1D) : const Color(0xFF28282F),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: ready
                  ? const Icon(Icons.check, size: 16, color: CueColors.accentGreen)
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: CueColors.accentLime, shape: BoxShape.circle),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: CueColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: CueColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RatioActionPill(label: btnLabel, accent: !ready, onTap: onAction),
        ],
      ),
    );
  }
}
