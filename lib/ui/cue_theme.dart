import 'package:flutter/material.dart';
import '../models/cue_models.dart';

class CueColors {
  CueColors._();

  static const bg = Color(0xFF0A0A0B);
  static const bgSculptSoft = Color(0xFF131316);
  static const bgSculptMid = Color(0xFF17171B);
  static const tile = Color(0xFF1F1F24);
  static const tileSoft = Color(0xFF19191D);
  static const tileSelected = Color(0xFF28282E);
  static const dockBg = Color(0xFF1D1D22);
  static const searchBg = Color(0xFF151519);
  static const cardBg = Color(0xFF1A1A1F);
  static const accentLime = Color(0xFFDDEB3B);
  static const accentGreen = Color(0xFF4ADE80);
  static const accentRed = Color(0xFFF87171);
  static const textPrimary = Color(0xFFF4F4F6);
  static const textSecondary = Color(0xFF8C8C96);
  static const textMuted = Color(0xFF62626C);
  static const subtleEdge = Color(0x16FFFFFF);

  static const ColorFilter bwColorFilter = ColorFilter.matrix(<double>[
    0.299, 0.587, 0.114, 0, 0,
    0.299, 0.587, 0.114, 0, 0,
    0.299, 0.587, 0.114, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

class SoftPillChip extends StatelessWidget {
  const SoftPillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final Color? dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CueColors.tileSelected : CueColors.tileSoft,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? CueColors.textPrimary : CueColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RatioActionPill extends StatelessWidget {
  const RatioActionPill({
    super.key,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent ? CueColors.accentLime : const Color(0xFF28282F),
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent ? const Color(0xFF111113) : CueColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class RatioAppGlyph extends StatelessWidget {
  const RatioAppGlyph({
    super.key,
    required this.app,
    required this.tint,
    this.size = 24,
  });

  final LaunchableApp app;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final curated = iconForApp(app);
    if (curated != null) {
      return Icon(curated, color: tint, size: size);
    }
    if (app.iconBytes != null && app.iconBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColorFiltered(
          colorFilter: CueColors.bwColorFilter,
          child: Image.memory(
            app.iconBytes!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    return Icon(Icons.apps_outlined, color: tint, size: size);
  }
}

IconData? iconForApp(LaunchableApp app) {
  final key = '${app.label.toLowerCase()} ${app.packageName.toLowerCase()}';
  if (key.contains('phone') || key.contains('dialer')) return Icons.phone_outlined;
  if (key.contains('message') || key.contains('sms') || key.contains('whatsapp')) return Icons.chat_bubble_outline;
  if (key.contains('chrome') || key.contains('browser')) return Icons.public_outlined;
  if (key.contains('maps')) return Icons.place_outlined;
  if (key.contains('clock') || key.contains('deskclock')) return Icons.schedule_outlined;
  if (key.contains('files') || key.contains('documentsui')) return Icons.folder_outlined;
  if (key.contains('calendar')) return Icons.calendar_today_outlined;
  if (key.contains('settings')) return Icons.settings_outlined;
  if (key.contains('camera')) return Icons.camera_alt_outlined;
  if (key.contains('spotify') || key.contains('yt music')) return Icons.music_note_outlined;
  if (key.contains('youtube')) return Icons.play_circle_outline;
  if (key.contains('photos') || key.contains('gallery')) return Icons.photo_library_outlined;
  if (key.contains('gmail') || key.contains('mail')) return Icons.email_outlined;
  if (key.contains('contacts')) return Icons.person_outline;
  if (key.contains('drive') || key.contains('docs')) return Icons.description_outlined;
  if (key.contains('google')) return Icons.search;
  return null;
}

class EssentialsSlots {
  const EssentialsSlots({
    this.smallTop,
    this.wideDark,
    this.wideLime,
    this.gridRow = const [],
  });

  final LaunchableApp? smallTop;
  final LaunchableApp? wideDark;
  final LaunchableApp? wideLime;
  final List<LaunchableApp> gridRow;
}

class FavouritesSlots {
  const FavouritesSlots({
    this.squareLime,
    this.squareMidA,
    this.squareMidB,
    this.wideTile,
  });

  final LaunchableApp? squareLime;
  final LaunchableApp? squareMidA;
  final LaunchableApp? squareMidB;
  final LaunchableApp? wideTile;
}

EssentialsSlots buildEssentialsSelection(List<LaunchableApp> apps) {
  if (apps.isEmpty) return const EssentialsSlots();
  final taken = <String>{};

  LaunchableApp? pick(List<String> needles) {
    final found = apps.where((a) {
      if (taken.contains(a.packageName)) return false;
      final lbl = a.label.toLowerCase();
      final pkg = a.packageName.toLowerCase();
      return needles.any((n) => lbl.contains(n) || pkg.contains(n));
    }).firstOrNull ?? apps.where((a) => !taken.contains(a.packageName)).firstOrNull;
    if (found != null) taken.add(found.packageName);
    return found;
  }

  final smallTop = pick(['google', 'search', 'contacts']);
  final wideDark = pick(['maps', 'gmail', 'message']);
  final wideLime = pick(['chrome', 'browser']);
  final grid = [
    pick(['clock', 'deskclock']),
    pick(['files', 'documentsui']),
    pick(['calendar']),
    pick(['settings']),
  ].whereType<LaunchableApp>().toList();

  return EssentialsSlots(smallTop: smallTop, wideDark: wideDark, wideLime: wideLime, gridRow: grid);
}

FavouritesSlots buildFavouritesSelection(List<LaunchableApp> apps, EssentialsSlots essentials) {
  final taken = <String>{
    if (essentials.smallTop != null) essentials.smallTop!.packageName,
    if (essentials.wideDark != null) essentials.wideDark!.packageName,
    if (essentials.wideLime != null) essentials.wideLime!.packageName,
    for (final a in essentials.gridRow) a.packageName,
  };

  LaunchableApp? pick(List<String> needles) {
    final found = apps.where((a) {
      if (taken.contains(a.packageName)) return false;
      final lbl = a.label.toLowerCase();
      final pkg = a.packageName.toLowerCase();
      return needles.any((n) => lbl.contains(n) || pkg.contains(n));
    }).firstOrNull ?? apps.where((a) => !taken.contains(a.packageName)).firstOrNull;
    if (found != null) taken.add(found.packageName);
    return found;
  }

  return FavouritesSlots(
    squareLime: pick(['spotify', 'music', 'photos', 'camera']),
    squareMidA: pick(['photos', 'camera', 'gmail']),
    squareMidB: pick(['whatsapp', 'drive', 'contacts', 'phone']),
    wideTile: pick(['youtube', 'whatsapp', 'gmail', 'camera']),
  );
}

List<LaunchableApp> buildDockSelection(List<LaunchableApp> apps) {
  if (apps.isEmpty) return const [];
  final taken = <String>{};
  final result = <LaunchableApp>[];
  const groups = [
    ['phone', 'dialer'],
    ['message', 'sms', 'whatsapp', 'gmail'],
    ['chrome', 'browser'],
    ['maps'],
    ['spotify', 'youtube', 'music'],
  ];

  for (final needles in groups) {
    final match = apps.where((a) {
      if (taken.contains(a.packageName)) return false;
      final lbl = a.label.toLowerCase();
      final pkg = a.packageName.toLowerCase();
      return needles.any((n) => lbl.contains(n) || pkg.contains(n));
    }).firstOrNull;
    if (match != null) {
      taken.add(match.packageName);
      result.add(match);
    }
  }
  for (final fallback in apps) {
    if (result.length >= 5) break;
    if (taken.add(fallback.packageName)) result.add(fallback);
  }
  return result;
}
