import '../models/cue_models.dart';

class YouTubeCandidateExtractor {
  static const _noiseExact = {
    'search', 'search youtube', 'navigate up', 'voice search', 'clear', 'home',
    'shorts', 'subscriptions', 'library', 'you', 'explore', 'all', 'filters',
    'videos', 'channels', 'playlists', 'recently uploaded', 'watched', 'live',
    'more options', 'action menu', 'cast', 'notifications', 'create', 'sign in',
    'open app', 'skip', 'share', 'download', 'save', 'sponsored', 'about these results',
    'herunterladen', 'install', 'watch', 'start now',
  };

  static const _blockedSubstrings = [
    'sponsored',
    'link opens in new window',
    'about these results',
    'searching youtube for',
    'opened youtube search',
    'awaiting reply',
    'cueui',
    'tap the mic',
    'command or reply',
    'tap to watch live',
  ];

  static final _durationSuffixRe = RegExp(
    r'\s+-\s+\d+\s+(?:hours?|minutes?|seconds?|hr|min|sec)\b.*$',
    caseSensitive: false,
  );
  static final _durationOrCountOnly = RegExp(
    r'^(\d{1,2}:)?\d{1,2}:\d{2}$|^[\d.,]+[KMBkmb]?\s*(views?|watching|subscribers?).*$',
  );

  static List<VideoCandidate> extract(
    List<UiNodeInfo> nodes, {
    String query = '',
    int maxResults = 5,
  }) {
    final cleanedQuery = query.trim().toLowerCase();

    final eligibleNodes = nodes
        .where((n) => !n.editable && n.top >= 200)
        .where((n) {
          final cls = n.className.toLowerCase();
          return !cls.contains('imagebutton') && !cls.contains('imageview');
        })
        .toList();

    final explicitVideoNodes = eligibleNodes.where((node) {
      final combined = '${node.contentDesc} ${node.text}'.toLowerCase();
      return (combined.contains('play video') || combined.contains('- go to channel')) &&
          !_blockedSubstrings.any(combined.contains);
    }).toList();

    final sourceNodes = (explicitVideoNodes.isNotEmpty ? explicitVideoNodes : eligibleNodes)
      ..sort((a, b) => a.top.compareTo(b.top));

    final seenTitles = <String>{};
    final candidates = <VideoCandidate>[];

    for (final node in sourceNodes) {
      final raw = (node.contentDesc.trim().isNotEmpty ? node.contentDesc : node.text).trim();
      if (raw.length < 10 || raw.length > 360) continue;
      final rawLower = raw.toLowerCase();
      if (_blockedSubstrings.any(rawLower.contains)) continue;

      final title = _sanitizeAccessibilityTitle(raw);
      if (title.length < 10) continue;
      final lower = title.toLowerCase();

      if (_noiseExact.contains(lower)) continue;
      if (lower == cleanedQuery) continue;
      if (_durationOrCountOnly.hasMatch(lower)) continue;
      if (lower.startsWith('search ') || lower.startsWith('filter ')) continue;
      if (lower.endsWith(' seconds') && lower.length < 24) continue;
      if (explicitVideoNodes.isEmpty && !node.clickable) continue;

      final dedupKey = lower.length > 60 ? lower.substring(0, 60) : lower;
      if (!seenTitles.add(dedupKey)) continue;

      candidates.add(VideoCandidate(title: title, nodeIndex: node.index, yTop: node.top));
      if (candidates.length >= maxResults) break;
    }
    return candidates;
  }

  static String _sanitizeAccessibilityTitle(String raw) {
    final firstLine = raw
        .split('\n')
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    var cut = firstLine;
    for (final marker in const [' -  -  - ', ' - Go to channel', ' - play video', ' - Play video']) {
      final idx = cut.indexOf(marker);
      if (idx >= 0) cut = cut.substring(0, idx);
    }
    cut = cut.replaceAll(_durationSuffixRe, '').trim();
    cut = cut.replaceAll(RegExp(r'[-\s]+$'), '');
    return cut.length > 96 ? cut.substring(0, 96) : cut;
  }
}
