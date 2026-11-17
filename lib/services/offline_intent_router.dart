import '../models/cue_models.dart';
import 'extended_intent_router.dart';

class OfflineIntentRouter {
  static final _whatsappMessageFirstRe = RegExp(
    r'^send\s+(.+?)\s+to\s+(.+?)\s+(?:on|in|via)\s+whatsapp(?:\s+please)?$',
    caseSensitive: false,
  );
  static final _callRe = RegExp(
    r'^(?:please\s+)?(?:call|phone|ring)\s+(.+)$',
    caseSensitive: false,
  );
  static final _dialRe = RegExp(r'^dial\s+(.+)$', caseSensitive: false);
  static final _whatsappCallRe = RegExp(
    r'^(?:(?:(video)\s+)?call|voice\s+call|video\s+call)\s+(.+?)\s+(?:on|in|via)\s+whatsapp(?:\s+please)?$',
    caseSensitive: false,
  );
  static final _smsRe = RegExp(
    r'^(?:send\s+(?:an\s+)?(?:sms|text(?:\s+message)?|message)\s+to|text|sms)\s+(.+?)\s+(?:saying|that|message|:)\s+(.+)$',
    caseSensitive: false,
  );
  static final _whatsappToRe = RegExp(
    r'^(?:send\s+(?:a\s+)?whatsapp(?:\s+message)?\s+to|whatsapp(?:\s+message)?\s+to)\s+(.+?)\s+(?:saying|that|message|:)\s+(.+)$',
    caseSensitive: false,
  );
  static final _whatsappOpenAndMsgRe = RegExp(
    r'^(?:open|launch|start)\s+whatsapp(?:\s+and)?\s+(?:send\s+(?:a\s+)?message\s+to|message|text|tell|dm)\s+(.+?)\s+(?:saying|that|message|:)\s+(.+)$',
    caseSensitive: false,
  );
  static final _whatsappOnRe = RegExp(
    r'^(?:send\s+(?:a\s+)?(?:whatsapp\s+)?message\s+to|message|text|tell|dm|whatsapp|ping)\s+(.+?)\s+(?:on|in|via)\s+whatsapp(?:\s+(?:saying|that|:))?\s+(.+)$',
    caseSensitive: false,
  );
  static final _whatsappPrefixRe = RegExp(
    r'^(?:on|in)\s+whatsapp\s+(?:send\s+(?:a\s+)?message\s+to|message|text|tell)\s+(.+?)\s+(?:saying|that|:)\s+(.+)$',
    caseSensitive: false,
  );
  static final _whatsappDirectRe = RegExp(
    r'^whatsapp\s+(.+?)\s+(?:saying|that|:)\s+(.+)$',
    caseSensitive: false,
  );
  static final _whatsappPromptOnlyRe = RegExp(
    r'^(?:(?:open|launch|start)\s+whatsapp(?:\s+and)?\s+(?:send\s+(?:a\s+)?message\s+to|message|text|dm)\s+(.+)|(?:send\s+(?:a\s+)?(?:whatsapp\s+)?message\s+to|message|text|dm)\s+(.+?)\s+(?:on|in|via)\s+whatsapp(?:\s+please)?)$',
    caseSensitive: false,
  );
  static final _installAppRe = RegExp(
    r'^(?:install|download|get)\s+(?!the\s+model\b|model\b)(.+?)(?:\s+(?:from|on)\s+(?:google\s+)?play\s*store)?$',
    caseSensitive: false,
  );
  static final _replyNotifRe = RegExp(
    r'^reply\s+(?:to\s+)?(.+?)\s+(?:saying|with|:)\s+(.+)$',
    caseSensitive: false,
  );
  static final _alarmRe = RegExp(
    r'^set\s+(?:an\s+)?alarm\s+(?:for|at)\s+(\d{1,2})(?::(\d{2}))?(?:\s*(am|pm))?(?:\s+labeled?\s+(.+))?$',
    caseSensitive: false,
  );
  static final _timerRe = RegExp(
    r'^set\s+(?:a\s+)?(\d+)\s*(second|seconds|sec|s|minute|minutes|min|m|hour|hours|hr|h)\s+timer(?:\s+(?:for|called|labeled)\s+(.+))?$',
    caseSensitive: false,
  );
  static final _brightnessRe = RegExp(
    r'brightness(?:\s+to)?\s+(\d{1,3})\s*%?',
    caseSensitive: false,
  );
  static final _weatherRe = RegExp(
    r"^(?:(?:what(?:'?s|\s+is)\s+(?:the\s+)?|how(?:'?s|\s+is)\s+(?:the\s+)?|check\s+(?:the\s+)?|show\s+(?:the\s+)?|tell\s+me\s+(?:the\s+)?|get\s+(?:the\s+)?)?(?:weather|temperature|forecast)(?:\s+(?:in|for|at|of)\s+(.+?)|\s+([a-zA-Z\s.-]+))?|(?:is\s+it|will\s+it)\s+(?:rain|raining|snow|snowing|sunny|hot|cold|warm)(?:\s+(?:in|at)\s+(.+?))?)$",
    caseSensitive: false,
  );
  static final _newsRe = RegExp(
    r"^(?:(?:what(?:'?s|\s+is|\s+are)\s+(?:the\s+)?|show\s+(?:me\s+)?|check\s+(?:the\s+)?|tell\s+me\s+(?:the\s+)?|get\s+(?:the\s+)?)?(?:current\s+)?(?:hot|top|latest|breaking|trending)?\s*(?:news|headlines)(?:\s+(?:today|now|right\s+now))?(?:\s+(?:about|on|for|in)\s+(.+))?)$",
    caseSensitive: false,
  );
  static final _calendarAddRe = RegExp(
    r'^(?:add\s+(?:an?\s+)?(?:calendar\s+)?event|create\s+(?:an?\s+)?(?:calendar\s+)?event|schedule(?:\s+(?:a\s+)?(?:meeting|event))?|remind\s+me\s+to)\s+(.+)$',
    caseSensitive: false,
  );
  static final _calendarTimeSuffixRe = RegExp(
    r'^(.*?)(?:\s+(today|tomorrow))?\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$',
    caseSensitive: false,
  );
  static final _internetQuestionRe = RegExp(
    r"^(?:what\s+does\s+.+?\s+mean|what(?:'?s|\s+is)\s+(?:the\s+)?meaning\s+of\s+.+|(?:meaning|definition)\s+of\s+.+|define\s+.+|(?:who|what|when|where|why|how)(?:'?s|\s+(?:is|was|are|were|did|does|do|can|could|should|would))\s+.+|explain\s+.+|tell\s+me\s+about\s+.+|(?:search(?:\s+(?:google|the\s+web|online|internet))?\s+for|look\s+up|google)\s+.+)$",
    caseSensitive: false,
  );
  static final _openAppRe = RegExp(
    r'^(?:open|launch|start)\s+(?!my\s+|the\s+|a\s+)([a-z0-9._-]+(?:\s+[a-z0-9._-]+){0,3})$',
    caseSensitive: false,
  );
  static final _tapRe = RegExp(
    r'^(?:tap|click|press)\s+(?:on\s+)?(.+)$',
    caseSensitive: false,
  );
  static final _typeRe = RegExp(r'^type\s+(.+)$', caseSensitive: false);
  static final _youtubeRe = RegExp(
    r'^(?:(?:open|launch|start)\s+youtube(?:\s+and)?\s+(?:search(?:\s+for)?|find|play|watch)\s+(.+)|play\s+(.+?)\s+(?:on|in)\s+youtube|search\s+(?:on\s+)?youtube\s+for\s+(.+)|(?:search(?:\s+for)?|find|watch)\s+(.+?)\s+(?:on|in)\s+youtube|youtube\s+search(?:\s+for)?\s+(.+))$',
    caseSensitive: false,
  );
  static final _spotifyRe = RegExp(
    r'^(?:(?:open|launch|start)\s+spotify(?:\s+and)?\s+(?:search(?:\s+for)?|find|play|listen\s+to)\s+(.+)|play\s+(.+?)\s+(?:on|in)\s+spotify|search\s+(?:on\s+)?spotify\s+for\s+(.+)|(?:search(?:\s+for)?|find|listen(?:\s+to)?)\s+(.+?)\s+(?:on|in)\s+spotify|spotify\s+search(?:\s+for)?\s+(.+))$',
    caseSensitive: false,
  );
  static final _openUrlRe = RegExp(
    r'^(?:open|visit|go\s+to)\s+(https?://\S+|\S+\.(?:com|org|net|io|dev|edu|gov|in|de|uk)\S*)$',
    caseSensitive: false,
  );
  static final _clauseSplitRe = RegExp(
    r'\s*(?:;|,\s+and\s+then|\band\s+then\b|\bthen\b)\s*',
    caseSensitive: false,
  );
  static final _leadingPoliteRe = RegExp(
    r'^(?:hey\s+cueui|cueui|please|could\s+you|can\s+you|would\s+you|will\s+you|just|kindly)\s+',
    caseSensitive: false,
  );

  static const _weatherNoiseTokens = {
    'today',
    'tomorrow',
    'tonight',
    'now',
    'right now',
    'outside',
    'here',
    'like',
    'report',
    'please',
  };

  static List<PlannedToolCall>? route(String goal) {
    final raw = goal.trim();
    if (raw.isEmpty) return null;
    final clauses = raw
        .split(_clauseSplitRe)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (clauses.isEmpty) return null;

    final planned = <PlannedToolCall>[];
    for (final clause in clauses) {
      final match = _routeSingleClause(clause);
      if (match == null) return null;
      planned.add(match);
    }
    return planned;
  }

  static bool? _toggleValue(String lower) {
    if (['enable', 'turn on', 'switch on'].any(lower.contains) ||
        lower.endsWith(' on')) {
      return true;
    }
    if (['disable', 'turn off', 'switch off'].any(lower.contains) ||
        lower.endsWith(' off')) {
      return false;
    }
    return null;
  }

  static String _stripPolitePrefix(String raw) {
    var current = raw.trim().replaceAll(RegExp(r'[.!?,\;]+$'), '').trim();
    for (var i = 0; i < 2; i++) {
      current = current.replaceFirst(_leadingPoliteRe, '').trim();
    }
    return current;
  }

  static String _stripTrailingPlease(String value) => value
      .trim()
      .replaceFirst(RegExp(r'\s+please$', caseSensitive: false), '')
      .trim();

  static String _cleanRecipientPhrase(String raw) => raw
      .trim()
      .replaceFirst(RegExp(r'^(?:my|the)\s+', caseSensitive: false), '')
      .trim();

  static String _stripQuotes(String s) {
    var v = s.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }

  static PlannedToolCall? _routeSingleClause(String clause) {
    final text = _stripPolitePrefix(clause);
    final extended = ExtendedIntentRouter.route(text);
    if (extended != null) return extended;
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    final mentionsChatApp = [
      'whatsapp',
      'telegram',
      'instagram',
      'signal',
    ].any(lower.contains);

    // 1. Calls
    if (const {
      'answer',
      'answer call',
      'pick up',
      'pick up call',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'answer_call');
    }
    if (const {'end call', 'hang up', 'hangup'}.contains(lower)) {
      return const PlannedToolCall(tool: 'end_call');
    }
    final waCallMatch = _whatsappCallRe.firstMatch(text);
    if (waCallMatch != null) {
      final explicitVideo =
          (waCallMatch.group(1) ?? '').isNotEmpty ||
          lower.startsWith('video call');
      final recipient = _cleanRecipientPhrase(waCallMatch.group(2) ?? '');
      if (recipient.isNotEmpty) {
        return PlannedToolCall(
          tool: 'whatsapp_call',
          args: {'recipient': recipient, 'video': explicitVideo},
        );
      }
    }
    if (!mentionsChatApp) {
      final dialM = _dialRe.firstMatch(text);
      if (dialM != null) {
        final target = _stripTrailingPlease(dialM.group(1) ?? '');
        if (target.isNotEmpty) {
          return PlannedToolCall(
            tool: 'make_call',
            args: {'target': target, 'dialOnly': true},
          );
        }
      }
      final callM = _callRe.firstMatch(text);
      if (callM != null) {
        final target = _stripTrailingPlease(callM.group(1) ?? '');
        if (target.isNotEmpty) {
          return PlannedToolCall(
            tool: 'make_call',
            args: {'target': target, 'dialOnly': false},
          );
        }
      }
    }

    // 2. WhatsApp / Play Store / SMS / Notifications
    final messageFirst = _whatsappMessageFirstRe.firstMatch(text);
    if (messageFirst != null) {
      final message = _stripQuotes(messageFirst.group(1) ?? '');
      final recipient = _cleanRecipientPhrase(messageFirst.group(2) ?? '');
      // Recipient-first requests without a message still use the prompt below.
      if (!RegExp(
        r'^(?:a\s+)?(?:whatsapp\s+)?message$',
        caseSensitive: false,
      ).hasMatch(message)) {
        return PlannedToolCall(
          tool: 'whatsapp_send',
          args: {'recipient': recipient, 'message': message},
        );
      }
    }
    for (final re in [
      _whatsappToRe,
      _whatsappOpenAndMsgRe,
      _whatsappPrefixRe,
      _whatsappOnRe,
      _whatsappDirectRe,
    ]) {
      final m = re.firstMatch(text);
      if (m != null) {
        final recipient = _cleanRecipientPhrase(m.group(1) ?? '');
        final msg = _stripQuotes(m.group(2) ?? '');
        if (recipient.isNotEmpty &&
            msg.isNotEmpty &&
            msg.toLowerCase() != 'please') {
          return PlannedToolCall(
            tool: 'whatsapp_send',
            args: {'recipient': recipient, 'message': msg},
          );
        }
      }
    }
    final waPromptM = _whatsappPromptOnlyRe.firstMatch(text);
    if (waPromptM != null) {
      final rawRecipient = (waPromptM.group(1) ?? waPromptM.group(2) ?? '')
          .trim();
      final recipient = _cleanRecipientPhrase(
        _stripTrailingPlease(rawRecipient),
      );
      if (recipient.isNotEmpty) {
        return PlannedToolCall(
          tool: 'whatsapp_prompt_message',
          args: {'recipient': recipient},
        );
      }
    }
    final installM = _installAppRe.firstMatch(text);
    if (installM != null) {
      final appName = _stripTrailingPlease(installM.group(1) ?? '')
          .replaceFirst(RegExp(r'^(?:the|an|a)\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s+app$', caseSensitive: false), '')
          .trim();
      if (appName.isNotEmpty && appName.toLowerCase() != 'it') {
        return PlannedToolCall(
          tool: 'install_app_play_store',
          args: {'appName': appName},
        );
      }
    }
    if (!mentionsChatApp) {
      final smsM = _smsRe.firstMatch(text);
      if (smsM != null) {
        return PlannedToolCall(
          tool: 'send_sms',
          args: {
            'recipient': (smsM.group(1) ?? '').trim(),
            'message': _stripQuotes(smsM.group(2) ?? ''),
          },
        );
      }
    }
    final replyM = _replyNotifRe.firstMatch(text);
    if (replyM != null) {
      return PlannedToolCall(
        tool: 'reply_notification',
        args: {
          'senderQuery': (replyM.group(1) ?? '').trim(),
          'message': _stripQuotes(replyM.group(2) ?? ''),
        },
      );
    }
    if ([
      'read whatsapp',
      'check whatsapp',
      'whatsapp messages',
      'read my whatsapp',
    ].any(lower.contains)) {
      return const PlannedToolCall(
        tool: 'read_messages',
        args: {'limit': 8, 'source': 'whatsapp'},
      );
    }
    if ([
      'read sms',
      'check sms',
      'check text messages',
      'read text messages',
      'read my texts',
      'read inbox',
    ].any(lower.contains)) {
      return const PlannedToolCall(tool: 'read_sms', args: {'limit': 5});
    }
    if ([
      'read messages',
      'read my messages',
      'check messages',
      'new messages',
      'check my messages',
      'any messages',
    ].any(lower.contains)) {
      return const PlannedToolCall(tool: 'read_messages', args: {'limit': 8});
    }
    if ([
      'read notifications',
      'check notifications',
      'new notifications',
      'missed calls',
    ].any(lower.contains)) {
      return const PlannedToolCall(
        tool: 'read_notifications',
        args: {'limit': 10},
      );
    }

    // 2b. Weather & News
    final weatherM = _weatherRe.firstMatch(text);
    if (weatherM != null) {
      final rawCity =
          (weatherM.group(1) ?? weatherM.group(2) ?? weatherM.group(3) ?? '')
              .trim();
      final cleaned = _stripTrailingPlease(rawCity)
          .replaceFirst(RegExp(r'^(?:in|for|at)\s+', caseSensitive: false), '')
          .replaceFirst(
            RegExp(
              r'\s+(?:today|tomorrow|tonight|right\s+now|now|outside|like)$',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      final city = _weatherNoiseTokens.contains(cleaned.toLowerCase())
          ? ''
          : cleaned;
      return PlannedToolCall(tool: 'get_weather', args: {'location': city});
    }
    final newsM = _newsRe.firstMatch(text);
    if (newsM != null) {
      final rawTopic = _stripTrailingPlease(newsM.group(1) ?? '')
          .replaceFirst(
            RegExp(r'\s+(?:today|now|right\s+now)$', caseSensitive: false),
            '',
          )
          .trim();
      final topic =
          const {
            'today',
            'now',
            'right now',
            'headlines',
          }.contains(rawTopic.toLowerCase())
          ? ''
          : rawTopic;
      return PlannedToolCall(tool: 'get_news', args: {'topic': topic});
    }

    // 2c. Camera & Calendar
    switch (lower) {
      case 'open camera':
      case 'camera':
      case 'launch camera':
      case 'take photo':
      case 'take a photo':
      case 'take picture':
      case 'take a picture':
        return const PlannedToolCall(
          tool: 'open_camera',
          args: {'mode': 'photo'},
        );
      case 'take selfie':
      case 'take a selfie':
      case 'open selfie camera':
      case 'front camera':
        return const PlannedToolCall(
          tool: 'open_camera',
          args: {'mode': 'selfie'},
        );
      case 'record video':
      case 'record a video':
      case 'take video':
      case 'take a video':
      case 'open video camera':
        return const PlannedToolCall(
          tool: 'open_camera',
          args: {'mode': 'video'},
        );
      case 'open calendar':
      case 'calendar':
      case 'check calendar':
      case 'check my calendar':
      case 'my schedule':
      case 'check schedule':
      case 'upcoming events':
        return const PlannedToolCall(tool: 'open_calendar');
    }
    final calAddM = _calendarAddRe.firstMatch(text);
    if (calAddM != null) {
      final rawSpec = _stripTrailingPlease(calAddM.group(1) ?? '');
      final timeM = _calendarTimeSuffixRe.firstMatch(rawSpec);
      if (timeM != null) {
        var title = (timeM.group(1) ?? '').trim();
        final dayWord = (timeM.group(2) ?? '').toLowerCase();
        var hour = int.tryParse(timeM.group(3) ?? '') ?? 9;
        final minute = int.tryParse(timeM.group(4) ?? '') ?? 0;
        final ampm = (timeM.group(5) ?? '').toLowerCase();
        if (ampm == 'pm' && hour < 12) hour += 12;
        if (ampm == 'am' && hour == 12) hour = 0;
        if (title.isEmpty) title = 'Event';
        return PlannedToolCall(
          tool: 'add_calendar_event',
          args: {
            'title': title,
            'hour': hour,
            'minute': minute,
            'dayOffset': dayWord == 'tomorrow' ? 1 : 0,
          },
        );
      }
      final tomorrow = rawSpec.toLowerCase().endsWith(' tomorrow');
      final title = rawSpec
          .replaceFirst(
            RegExp(r'\s+(?:tomorrow|today)$', caseSensitive: false),
            '',
          )
          .trim();
      if (title.isNotEmpty) {
        return PlannedToolCall(
          tool: 'add_calendar_event',
          args: {'title': title, 'dayOffset': tomorrow ? 1 : 0},
        );
      }
    }

    // 3. Hardware & Quick Settings
    if (lower.contains('flashlight') || lower.contains('torch')) {
      final v = _toggleValue(lower);
      if (v != null) {
        return PlannedToolCall(tool: 'set_flashlight', args: {'enabled': v});
      }
    }
    if (lower.contains('wifi') || lower.contains('wi-fi')) {
      final v = _toggleValue(lower);
      if (v != null) {
        return PlannedToolCall(
          tool: 'open_connectivity_panel',
          args: {'setting': 'wifi', 'desired': v},
        );
      }
    }
    if (lower.contains('bluetooth')) {
      final v = _toggleValue(lower);
      if (v != null) {
        return PlannedToolCall(
          tool: 'open_connectivity_panel',
          args: {'setting': 'bluetooth', 'desired': v},
        );
      }
    }
    if (lower.contains('mobile data') || lower.contains('cellular data')) {
      final v = _toggleValue(lower);
      if (v != null) {
        return PlannedToolCall(
          tool: 'open_connectivity_panel',
          args: {'setting': 'internet', 'desired': v},
        );
      }
    }
    if (lower.contains('do not disturb') ||
        RegExp(r'\bdnd\b').hasMatch(lower)) {
      final v = _toggleValue(lower);
      if (v != null) {
        return PlannedToolCall(tool: 'set_dnd', args: {'enabled': v});
      }
    }
    final brightM = _brightnessRe.firstMatch(lower);
    if (brightM != null) {
      final pct = (int.tryParse(brightM.group(1) ?? '') ?? 50).clamp(0, 100);
      return PlannedToolCall(tool: 'set_brightness', args: {'percent': pct});
    }

    // 4. Media & Volume
    final hasComplexUi = const [
      'first video',
      'first result',
      'subscribe',
      'like ',
      'comment',
      'playlist',
      'queue',
      'skip ad',
    ].any(lower.contains);
    if (!hasComplexUi) {
      final ytM = _youtubeRe.firstMatch(text);
      if (ytM != null) {
        final q = [1, 2, 3, 4, 5]
            .map((i) => (ytM.group(i) ?? '').trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (q.isNotEmpty) {
          return PlannedToolCall(tool: 'youtube_search', args: {'query': q});
        }
      }
      final spM = _spotifyRe.firstMatch(text);
      if (spM != null) {
        final q = [1, 2, 3, 4, 5]
            .map((i) => (spM.group(i) ?? '').trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (q.isNotEmpty) {
          return PlannedToolCall(tool: 'spotify_play', args: {'query': q});
        }
      }
    }
    switch (lower) {
      case 'pause music':
      case 'play music':
      case 'pause media':
      case 'play pause':
      case 'resume music':
        return const PlannedToolCall(
          tool: 'media_control',
          args: {'action': 'play_pause'},
        );
      case 'next song':
      case 'next track':
      case 'skip song':
      case 'skip track':
        return const PlannedToolCall(
          tool: 'media_control',
          args: {'action': 'next'},
        );
      case 'previous song':
      case 'previous track':
      case 'prev song':
        return const PlannedToolCall(
          tool: 'media_control',
          args: {'action': 'previous'},
        );
      case 'volume up':
      case 'louder':
      case 'increase volume':
        return const PlannedToolCall(
          tool: 'media_control',
          args: {'action': 'volume_up'},
        );
      case 'volume down':
      case 'quieter':
      case 'lower volume':
      case 'decrease volume':
        return const PlannedToolCall(
          tool: 'media_control',
          args: {'action': 'volume_down'},
        );
      case 'mute':
      case 'mute phone':
      case 'mute volume':
        return const PlannedToolCall(
          tool: 'media_control',
          args: {'action': 'mute'},
        );
    }

    // 5. Alarms & Timers
    final alarmM = _alarmRe.firstMatch(text);
    if (alarmM != null) {
      var hour = int.parse(alarmM.group(1)!);
      final minute = int.tryParse(alarmM.group(2) ?? '') ?? 0;
      final ampm = (alarmM.group(3) ?? '').toLowerCase();
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
      final label = (alarmM.group(4) ?? '').trim();
      return PlannedToolCall(
        tool: 'set_alarm',
        args: {
          'hour': hour,
          'minute': minute,
          'label': label.isEmpty ? 'CueUI Alarm' : label,
        },
      );
    }
    final timerM = _timerRe.firstMatch(text);
    if (timerM != null) {
      final amount = int.parse(timerM.group(1)!);
      final unit = (timerM.group(2) ?? '').toLowerCase();
      final seconds = unit.startsWith('h')
          ? amount * 3600
          : unit.startsWith('m')
          ? amount * 60
          : amount;
      final label = (timerM.group(3) ?? '').trim();
      return PlannedToolCall(
        tool: 'set_timer',
        args: {
          'seconds': seconds,
          'label': label.isEmpty ? 'CueUI Timer' : label,
        },
      );
    }

    // 6. Status & System Navigation
    if ([
      'battery',
      'device status',
      'phone status',
      'screen status',
    ].any(lower.contains)) {
      return const PlannedToolCall(tool: 'get_device_status');
    }
    switch (lower) {
      case 'go back':
      case 'back':
      case 'press back':
        return const PlannedToolCall(tool: 'press_key', args: {'key': 'BACK'});
      case 'go home':
      case 'home':
      case 'home screen':
        return const PlannedToolCall(tool: 'press_key', args: {'key': 'HOME'});
      case 'recent apps':
      case 'recents':
      case 'app switcher':
        return const PlannedToolCall(
          tool: 'press_key',
          args: {'key': 'RECENTS'},
        );
      case 'open quick settings':
      case 'quick settings':
        return const PlannedToolCall(
          tool: 'press_key',
          args: {'key': 'QUICK_SETTINGS'},
        );
      case 'open notification shade':
      case 'pull down notifications':
        return const PlannedToolCall(
          tool: 'press_key',
          args: {'key': 'NOTIFICATIONS'},
        );
      case 'take screenshot':
      case 'screenshot':
      case 'capture screen':
        return const PlannedToolCall(tool: 'take_screenshot');
      case 'scroll down':
      case 'swipe down':
        return const PlannedToolCall(
          tool: 'scroll_screen',
          args: {'direction': 'down'},
        );
      case 'scroll up':
      case 'swipe up':
        return const PlannedToolCall(
          tool: 'scroll_screen',
          args: {'direction': 'up'},
        );
      case 'scroll left':
      case 'swipe left':
        return const PlannedToolCall(
          tool: 'scroll_screen',
          args: {'direction': 'left'},
        );
      case 'scroll right':
      case 'swipe right':
        return const PlannedToolCall(
          tool: 'scroll_screen',
          args: {'direction': 'right'},
        );
    }

    // 7. URL, App Launch, Tap, Type
    final urlM = _openUrlRe.firstMatch(text);
    if (urlM != null) {
      return PlannedToolCall(
        tool: 'open_url',
        args: {'url': (urlM.group(1) ?? '').trim()},
      );
    }
    final tapM = _tapRe.firstMatch(text);
    if (tapM != null) {
      final target = _stripQuotes(tapM.group(1) ?? '');
      if (target.isNotEmpty) {
        return PlannedToolCall(tool: 'tap_text', args: {'query': target});
      }
    }
    final typeM = _typeRe.firstMatch(text);
    if (typeM != null) {
      return PlannedToolCall(
        tool: 'type_text',
        args: {'text': _stripQuotes(typeM.group(1) ?? '')},
      );
    }
    final appM = _openAppRe.firstMatch(text);
    if (appM != null) {
      final candidate = _stripTrailingPlease(appM.group(1) ?? '');
      const blockedTokens = {'in', 'on', 'with', 'and', 'to', 'for'};
      if (candidate.isNotEmpty &&
          candidate
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .every((t) => !blockedTokens.contains(t))) {
        return PlannedToolCall(tool: 'open_app', args: {'app': candidate});
      }
    }

    // 8. Internet Q&A (defer first-person/device queries to Nano AI when loaded)
    if (_internetQuestionRe.hasMatch(text)) {
      final isPersonalOrDevice = RegExp(
        r'\b(?:i|my|me|phone|schedule|calendar|battery|brightness|wifi|bluetooth|whatsapp|spotify|youtube|message|messages|alarm)\b',
        caseSensitive: false,
      ).hasMatch(text);
      if (!isPersonalOrDevice) {
        return PlannedToolCall(tool: 'ask_internet', args: {'query': text});
      }
    }

    return null;
  }
}
