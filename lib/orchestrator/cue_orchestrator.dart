import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/cue_models.dart';
import '../services/nano_ai_service.dart';
import '../services/native_bridge.dart';
import '../services/offline_intent_router.dart';
import '../services/tool_dispatcher.dart';
import '../services/whatsapp_automator.dart';
import '../services/youtube_candidate_extractor.dart';

sealed class _PendingConversation {}

class _YouTubeSelection extends _PendingConversation {
  _YouTubeSelection({
    required this.query,
    required this.candidates,
    this.currentIndex = 0,
  });
  final String query;
  final List<VideoCandidate> candidates;
  final int currentIndex;
}

class _RefineSearch extends _PendingConversation {
  _RefineSearch(this.hintQuery);
  final String hintQuery;
}

class _InstallAppOffer extends _PendingConversation {
  _InstallAppOffer({
    required this.appName,
    this.packageName,
    this.fallbackQuery,
  });
  final String appName;
  final String? packageName;
  final String? fallbackQuery;
}

class _WeatherCityPrompt extends _PendingConversation {}

class _WhatsAppMessagePrompt extends _PendingConversation {
  _WhatsAppMessagePrompt(this.recipient);
  final String recipient;
}

class _WhatsAppRecipientPrompt extends _PendingConversation {
  _WhatsAppRecipientPrompt(
    this.recipient,
    this.message,
    this.names,
    this.remainingPlan,
  );
  final String recipient;
  final String message;
  final List<String> names;
  final List<PlannedToolCall> remainingPlan;

  List<String> get choices => [
    for (var i = 0; i < names.length; i++) '${i + 1}. ${names[i]}',
    'Cancel',
  ];
}

class _GrantPermissionPrompt extends _PendingConversation {
  _GrantPermissionPrompt({
    required this.originalGoal,
    required this.permissionKey,
    required this.permissionLabel,
  });
  final String originalGoal;
  final String permissionKey;
  final String permissionLabel;
}

class CueOrchestrator extends ChangeNotifier {
  CueOrchestrator({
    required this.nativeApi,
    required this.nanoAi,
    required this.dispatcher,
    this.postLaunchInspectDelayMs = 1400,
  });

  final CueNativeApi nativeApi;
  final NanoAiService nanoAi;
  final CueToolDispatcher dispatcher;
  final int postLaunchInspectDelayMs;

  CueUiState _state = CueUiState();
  CueUiState get state => _state;

  Completer<bool>? _confirmCompleter;
  _PendingConversation? _pendingConversation;
  _InstallAppOffer? _lastMissingAppOffer;
  int _activeRunToken = 0;
  String _currentGoal = '';

  static const _yesPhrases = {
    'yes',
    'yeah',
    'yep',
    'yup',
    'sure',
    'ok',
    'okay',
    'play',
    'play it',
    'play this',
    'play that',
    'yes play',
    'yes, play',
    'go ahead',
    'start',
  };
  static const _installYesPhrases = {
    'install',
    'install it',
    'download',
    'download it',
    'yes install',
    'yes, install',
    'open play store',
    'open playstore',
    'get it',
    'yes please',
  };
  static const _noOrNextPhrases = {
    'no',
    'nope',
    'nah',
    'next',
    'next one',
    'skip',
    'another',
    'different',
    'try another',
  };
  static const _cancelPhrases = {
    'cancel',
    'stop',
    'nevermind',
    'never mind',
    'forget it',
    'close',
  };

  void _emitState(CueUiState next) {
    _state = next;
    notifyListeners();
    unawaited(_syncOverlay());
  }

  Future<void> _syncOverlay() async {
    final latestText = _state.messages
        .takeLast(4)
        .map((e) {
          final prefix = switch (e.role) {
            ChatRole.user => '> ',
            ChatRole.tool => '· ',
            ChatRole.agent => 'CueUI: ',
            ChatRole.error => '! ',
          };
          return '$prefix${e.text}';
        })
        .join('\n');

    try {
      await nativeApi.syncOverlayState(
        statusLine: _state.statusLine,
        latestOutput: latestText,
        quickChoices: _state.quickChoices,
        isAwaitingReply: _state.isAwaitingReply,
        pendingPermissionKey: _state.pendingPermissionKey,
        pendingConfirmationPrompt: _state.pendingConfirmationPrompt,
      );
    } catch (_) {}
  }

  void setBubbleActive(bool active) {
    _emitState(_state.copyWith(bubbleActive: active));
  }

  void clearConversationState() {
    _pendingConversation = null;
    _emitState(
      _state.copyWith(
        quickChoices: const [],
        isAwaitingReply: false,
        pendingPermissionKey: null,
        pendingPermissionLabel: null,
        pendingWebUrl: null,
      ),
    );
  }

  Future<bool> requestUserConfirmation(String prompt) async {
    final c = Completer<bool>();
    _confirmCompleter = c;
    _emitState(
      _state.copyWith(
        pendingConfirmationPrompt: prompt,
        statusLine: 'Waiting for confirmation...',
      ),
    );
    try {
      return await c.future;
    } finally {
      _confirmCompleter = null;
      _emitState(_state.copyWith(pendingConfirmationPrompt: null));
    }
  }

  void resolveConfirmation(bool approved) {
    final c = _confirmCompleter;
    if (c != null && !c.isCompleted) c.complete(approved);
  }

  void cancelActiveGoal() {
    _activeRunToken++;
    resolveConfirmation(false);
    clearConversationState();
    _emitState(
      _state.copyWith(
        isRunning: false,
        pendingConfirmationPrompt: null,
        statusLine: 'Ready',
      ),
    );
  }

  Future<void> notifyPermissionResult(
    String permissionKey,
    bool granted,
  ) async {
    final pending = _pendingConversation;
    if (pending is! _GrantPermissionPrompt) return;
    if (pending.permissionKey.toLowerCase() !=
        permissionKey.trim().toLowerCase()) {
      return;
    }

    clearConversationState();
    if (granted && pending.originalGoal.isNotEmpty) {
      _appendMessage(ChatRole.agent, 'Granted ${pending.permissionLabel}.');
      await runGoal(pending.originalGoal, appendUserMessage: false);
    } else if (granted) {
      _replyFinal('Granted ${pending.permissionLabel}.');
    } else {
      _replyFinal(
        '${pending.permissionLabel} permission was not granted. You can enable it in Setup anytime.',
      );
    }
  }

  Future<void> submitGoal(String goalText) async {
    final goal = goalText.trim();
    if (goal.isEmpty) return;
    resolveConfirmation(false);
    await runGoal(goal);
  }

  Future<void> runGoal(String goal, {bool appendUserMessage = true}) async {
    final runToken = ++_activeRunToken;
    if (appendUserMessage) _appendMessage(ChatRole.user, goal);
    _emitState(
      _state.copyWith(
        isRunning: true,
        statusLine: 'Working...',
        pendingWebUrl: null,
        lastRouteBadge: null,
      ),
    );

    try {
      final pending = _pendingConversation;
      if (pending != null &&
          await _handlePendingConversation(pending, goal, runToken)) {
        return;
      }
      if (runToken != _activeRunToken) return;

      _currentGoal = goal;
      final bareNormalized = goal.trim().toLowerCase().replaceAll(
        RegExp(r'[.!?]+$'),
        '',
      );
      if (const {
        'install',
        'install it',
        'download',
        'download it',
      }.contains(bareNormalized)) {
        final recentOffer = _lastMissingAppOffer;
        if (recentOffer != null) {
          clearConversationState();
          await _installMissingAppFromPlayStore(recentOffer, runToken);
          return;
        }
      }

      if (_isVaguePlayRequest(goal)) {
        _pendingConversation = _RefineSearch('');
        _replyConversational(
          'What kind of music or video would you like to play on YouTube? Say something like chill lofi beats, ambient piano, or jazz.',
          const ['Lofi chill beats', 'Rainy ambient piano', 'Cancel'],
        );
        return;
      }

      // Tier 1: Fast (<5ms) deterministic rule routing
      var plan = OfflineIntentRouter.route(goal);
      String? routeBadge = plan != null ? 'Instant' : null;

      // Tier 2: Keep-warm Nano GGUF natural language investigation when Tier 1 does not match
      if (plan == null && nanoAi.isReady) {
        _emitState(
          _state.copyWith(statusLine: 'Investigating with Nano AI...'),
        );
        final aiCall = await nanoAi.parseNaturalLanguageQuery(goal);
        if (runToken != _activeRunToken) return;
        if (aiCall != null) {
          plan = [aiCall];
          final ms = nanoAi.snapshot.lastInferenceMs;
          routeBadge = ms != null ? 'Nano AI · ${ms}ms' : 'Nano AI';
        }
      }

      if (plan != null) {
        await _dispatchPlan(plan, runToken, routeBadge: routeBadge);
        return;
      }

      clearConversationState();
      if (goal.contains('?')) {
        await _executePlan(
          [
            PlannedToolCall(tool: 'ask_internet', args: {'query': goal}),
          ],
          runToken,
          routeBadge: 'Web',
        );
        return;
      }

      final aiHint = nanoAi.isReady
          ? ''
          : ' Tip: download a ~258MB Nano GGUF model in the AI tab for casual natural language understanding.';
      _replyFinal(
        "I didn't recognize that command. Try 'call Mom', 'open WhatsApp and message Ali saying hi', "
        "'play lofi on YouTube', 'install Spotify', 'take a photo', 'open calendar', 'what's the weather', or 'hot news'.$aiHint",
      );
    } finally {
      if (runToken == _activeRunToken) {
        _emitState(_state.copyWith(isRunning: false, statusLine: 'Ready'));
      }
    }
  }

  Future<void> _dispatchPlan(
    List<PlannedToolCall> plan,
    int runToken, {
    String? routeBadge,
  }) async {
    final single = plan.length == 1 ? plan.first : null;
    if (single != null) {
      switch (single.tool) {
        case 'youtube_search':
          await _executeYouTubeInteractiveSearch(
            (single.args['query'] ?? '').toString(),
            runToken,
            routeBadge: routeBadge,
          );
          return;
        case 'install_app_play_store':
          clearConversationState();
          await _installMissingAppFromPlayStore(
            _InstallAppOffer(
              appName: (single.args['appName'] ?? '').toString(),
              packageName:
                  (single.args['packageName'] ?? '').toString().trim().isEmpty
                  ? null
                  : single.args['packageName'].toString().trim(),
            ),
            runToken,
          );
          return;
        case 'whatsapp_prompt_message':
          final recipient = (single.args['recipient'] ?? '').toString();
          _pendingConversation = _WhatsAppMessagePrompt(recipient);
          _replyConversational(
            'What message would you like me to send to $recipient on WhatsApp?',
            const ['On my way', 'Call me when free', 'Cancel'],
            routeBadge: routeBadge,
          );
          return;
      }
    }
    clearConversationState();
    await _executePlan(plan, runToken, routeBadge: routeBadge);
  }

  Future<bool> _handlePendingConversation(
    _PendingConversation pending,
    String userReply,
    int runToken,
  ) async {
    final normalized = userReply.trim().toLowerCase().replaceAll(
      RegExp(r'[.!?]+$'),
      '',
    );
    if (_cancelPhrases.contains(normalized)) {
      clearConversationState();
      _replyFinal('Okay, cancelled.');
      return true;
    }

    switch (pending) {
      case _WhatsAppRecipientPrompt():
        final phone = WhatsAppAutomator.extractRawPhoneDigits(userReply);
        if (phone != null) {
          clearConversationState();
          await _executePlan([
            PlannedToolCall(
              tool: 'whatsapp_send',
              args: {'recipient': userReply.trim(), 'message': pending.message},
            ),
            ...pending.remainingPlan,
          ], runToken);
          return true;
        }
        final selectionReply = normalized
            .replaceFirst(RegExp(r'^the\s+'), '')
            .replaceFirst(RegExp(r'\s+one$'), '');
        final numbered = RegExp(
          r'^(?:(?:option|number)\s+)?(\d+)(?:[.)]\s*.*)?$',
        ).firstMatch(selectionReply);
        var index = numbered == null ? null : int.tryParse(numbered.group(1)!);
        index = index == null
            ? _parseExplicitOptionIndex(selectionReply, pending.names.length)
            : index - 1;
        if (index == null) {
          final named = pending.names.indexed
              .where((entry) => entry.$2.toLowerCase() == normalized)
              .toList();
          if (named.length == 1) index = named.single.$1;
        }
        if (index != null && index >= 0 && index < pending.names.length) {
          final selected = pending.names[index];
          if (pending.names
                  .where((name) => name.toLowerCase() == selected.toLowerCase())
                  .length >
              1) {
            _replyConversational(
              'More than one result is named "$selected". What is their phone number, including country code?',
              pending.choices,
            );
            return true;
          }
          clearConversationState();
          await _executePlan([
            PlannedToolCall(
              tool: 'whatsapp_send',
              args: {
                'recipient': pending.recipient,
                'message': pending.message,
                'selectedChat': selected,
              },
            ),
            ...pending.remainingPlan,
          ], runToken);
          return true;
        }
        if (_noOrNextPhrases.contains(normalized)) {
          clearConversationState();
          _replyFinal('Okay, cancelled the WhatsApp message.');
          return true;
        }
        if (_looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        _replyConversational(
          'Which ${pending.recipient}? Choose a name or say its number.',
          pending.choices,
        );
        return true;

      case _GrantPermissionPrompt():
        if (normalized == 'not now' || _noOrNextPhrases.contains(normalized)) {
          clearConversationState();
          _replyFinal('Okay, skipped ${pending.permissionLabel} for now.');
          return true;
        }
        if (normalized.startsWith('grant') ||
            _yesPhrases.contains(normalized) ||
            const {'allow', 'enable', 'open settings'}.contains(normalized)) {
          await nativeApi.requestPermission(pending.permissionKey);
          return true;
        }
        if (OfflineIntentRouter.route(userReply) != null ||
            _looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        _replyConversational(
          'Tap Grant ${pending.permissionLabel} below to allow it directly, or Not now.',
          ['Grant ${pending.permissionLabel}', 'Not now'],
        );
        return true;

      case _YouTubeSelection():
        if (_yesPhrases.contains(normalized)) {
          return _playYouTubeCandidate(
            pending.candidates[pending.currentIndex],
          );
        }
        final explicitIdx = _parseExplicitOptionIndex(
          normalized,
          pending.candidates.length,
        );
        if (explicitIdx != null) {
          return _playYouTubeCandidate(pending.candidates[explicitIdx]);
        }
        if (_noOrNextPhrases.contains(normalized)) {
          final nextIndex = pending.currentIndex + 1;
          if (nextIndex < pending.candidates.length) {
            final nextCand = pending.candidates[nextIndex];
            _pendingConversation = _YouTubeSelection(
              query: pending.query,
              candidates: pending.candidates,
              currentIndex: nextIndex,
            );
            _replyConversational(
              'How about "${nextCand.title}"? Would you like me to play this one?',
              const ['Yes, play', 'Next', 'Cancel'],
            );
          } else {
            _pendingConversation = _RefineSearch(pending.query);
            _replyConversational(
              'Those were the top results for "${pending.query}". What vibe or title should I search for instead?',
              const ['Chill study beats', 'Deep focus lofi', 'Cancel'],
            );
          }
          return true;
        }
        if (_looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        await _executeYouTubeInteractiveSearch(
          _buildRefinedQuery(pending.query, userReply),
          runToken,
        );
        return true;

      case _RefineSearch():
        if (normalized == 'no' || normalized == 'nope') {
          clearConversationState();
          _replyFinal('Okay, let me know whenever you want to search again.');
          return true;
        }
        if (_looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        await _executeYouTubeInteractiveSearch(userReply.trim(), runToken);
        return true;

      case _InstallAppOffer():
        const ytPhrases = {
          'try youtube',
          'youtube',
          'search on youtube',
          'play on youtube',
          'youtube instead',
        };
        if (ytPhrases.contains(normalized) &&
            pending.fallbackQuery != null &&
            pending.fallbackQuery!.isNotEmpty) {
          clearConversationState();
          await _executeYouTubeInteractiveSearch(
            pending.fallbackQuery!,
            runToken,
          );
          return true;
        }
        if (_installYesPhrases.contains(normalized) ||
            _yesPhrases.contains(normalized)) {
          clearConversationState();
          await _installMissingAppFromPlayStore(pending, runToken);
          return true;
        }
        if (_noOrNextPhrases.contains(normalized)) {
          clearConversationState();
          _replyFinal("Okay, I won't open the Play Store.");
          return true;
        }
        if (OfflineIntentRouter.route(userReply) != null ||
            _looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        _replyConversational(
          'Say yes to open Play Store and install ${pending.appName}, or cancel.',
          _installOfferChoices(pending.fallbackQuery),
        );
        return true;

      case _WeatherCityPrompt():
        if (_noOrNextPhrases.contains(normalized)) {
          clearConversationState();
          _replyFinal('Okay, skipped the weather check.');
          return true;
        }
        if (_looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        clearConversationState();
        final res = await dispatcher.execute(
          PlannedToolCall(
            tool: 'get_weather',
            args: {'location': userReply.trim()},
          ),
        );
        _appendMessage(
          res.ok ? ChatRole.tool : ChatRole.error,
          'get_weather: ${res.summary}',
        );
        _replyFinal(res.summary);
        return true;

      case _WhatsAppMessagePrompt():
        if (_noOrNextPhrases.contains(normalized)) {
          clearConversationState();
          _replyFinal('Okay, cancelled the WhatsApp message.');
          return true;
        }
        if (OfflineIntentRouter.route(userReply) != null ||
            _looksLikeNewCommand(userReply)) {
          clearConversationState();
          return false;
        }
        clearConversationState();
        var msg = userReply.trim();
        if (msg.length >= 2 &&
            ((msg.startsWith('"') && msg.endsWith('"')) ||
                (msg.startsWith("'") && msg.endsWith("'")))) {
          msg = msg.substring(1, msg.length - 1);
        }
        final res = await dispatcher.execute(
          PlannedToolCall(
            tool: 'whatsapp_send',
            args: {'recipient': pending.recipient, 'message': msg},
          ),
          canContinue: () => runToken == _activeRunToken,
        );
        _appendMessage(
          res.ok ? ChatRole.tool : ChatRole.error,
          'whatsapp_send: ${res.summary}',
        );
        if (runToken != _activeRunToken) return true;
        if (!res.ok && _handleToolSpecialPrompt(res)) return true;
        _replyFinal(res.summary);
        return true;
    }
  }

  Future<bool> _playYouTubeCandidate(VideoCandidate candidate) async {
    _emitState(_state.copyWith(statusLine: 'Playing video...'));
    final res = await dispatcher.execute(
      PlannedToolCall(
        tool: 'tap_element',
        args: {'index': candidate.nodeIndex},
      ),
    );
    _appendMessage(
      res.ok ? ChatRole.tool : ChatRole.error,
      'tap_element: ${res.summary}',
    );
    clearConversationState();
    if (res.ok) {
      _replyFinal('Playing "${candidate.title}" on YouTube.');
    } else {
      _replyFinal('Could not tap "${candidate.title}": ${res.summary}');
    }
    return true;
  }

  Future<void> _executeYouTubeInteractiveSearch(
    String query,
    int runToken, {
    String? routeBadge,
  }) async {
    final cleanQuery = query.trim().isEmpty ? 'lofi music' : query.trim();
    _emitState(
      _state.copyWith(statusLine: 'Searching YouTube for "$cleanQuery"...'),
    );
    final searchRes = await dispatcher.execute(
      PlannedToolCall(tool: 'youtube_search', args: {'query': cleanQuery}),
    );
    _appendMessage(
      searchRes.ok ? ChatRole.tool : ChatRole.error,
      'youtube_search: ${searchRes.summary}',
    );
    if (!searchRes.ok || runToken != _activeRunToken) {
      clearConversationState();
      _replyFinal(searchRes.summary, routeBadge: routeBadge);
      return;
    }

    if (postLaunchInspectDelayMs > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: postLaunchInspectDelayMs),
      );
    }
    var nodes = await dispatcher.captureUiNodes();
    var candidates = YouTubeCandidateExtractor.extract(
      nodes,
      query: cleanQuery,
      maxResults: 5,
    );

    if (postLaunchInspectDelayMs > 0 &&
        (candidates.isEmpty || candidates.first.yTop > 1800)) {
      final hasSponsored = nodes.any(
        (n) => '${n.contentDesc} ${n.text}'.toLowerCase().contains('sponsored'),
      );
      if (hasSponsored || (candidates.firstOrNull?.yTop ?? 0) > 1800) {
        await dispatcher.execute(
          const PlannedToolCall(
            tool: 'scroll_screen',
            args: {'direction': 'down'},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
      nodes = await dispatcher.captureUiNodes();
      candidates = YouTubeCandidateExtractor.extract(
        nodes,
        query: cleanQuery,
        maxResults: 5,
      );
    }

    if (candidates.isNotEmpty) {
      _pendingConversation = _YouTubeSelection(
        query: cleanQuery,
        candidates: candidates,
      );
      _replyConversational(
        'Would you like to hear "${candidates[0].title}"? Say yes to play, no for the next video, or describe another mood.',
        const ['Yes, play', 'Next', 'Cancel'],
        routeBadge: routeBadge,
      );
    } else {
      _pendingConversation = _RefineSearch(cleanQuery);
      _replyConversational(
        'I searched YouTube for "$cleanQuery". Which kind or vibe of music would you like next?',
        const ['Chill lofi radio', 'Ambient sleep beats', 'Cancel'],
        routeBadge: routeBadge,
      );
    }
  }

  Future<void> _executePlan(
    List<PlannedToolCall> plan,
    int runToken, {
    String? routeBadge,
  }) async {
    ToolExecutionResult? lastResult;
    for (var i = 0; i < plan.length; i++) {
      if (runToken != _activeRunToken) return;
      final step = plan[i];
      _emitState(
        _state.copyWith(
          statusLine: 'Running ${step.tool} (${i + 1}/${plan.length})...',
        ),
      );
      final res = await dispatcher.execute(
        step,
        canContinue: () => runToken == _activeRunToken,
      );
      if (runToken != _activeRunToken) return;
      _appendMessage(
        res.ok ? ChatRole.tool : ChatRole.error,
        '${step.tool}: ${res.summary}',
      );
      lastResult = res;
      if (!res.ok) {
        if (_handleToolSpecialPrompt(
          res,
          routeBadge: routeBadge,
          remainingPlan: plan.sublist(i + 1),
        )) {
          return;
        }
        break;
      }
      if (i < plan.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (lastResult != null && runToken == _activeRunToken) {
      final webUrl = (lastResult.data['openUrl'] ?? '').toString().trim();
      _replyFinal(
        lastResult.summary,
        webUrl: webUrl.isEmpty ? null : webUrl,
        routeBadge: routeBadge,
      );
    }
  }

  bool _handleToolSpecialPrompt(
    ToolExecutionResult result, {
    String? routeBadge,
    List<PlannedToolCall> remainingPlan = const [],
  }) {
    final recipients = result.data['whatsappRecipients'];
    if (recipients is List && recipients.isNotEmpty) {
      final pending = _WhatsAppRecipientPrompt(
        result.data['recipient'].toString(),
        result.data['message'].toString(),
        recipients.map((name) => name.toString()).toList(),
        remainingPlan,
      );
      _pendingConversation = pending;
      _replyConversational(
        '${result.summary}\n${pending.choices.take(pending.names.length).join('\n')}',
        pending.choices,
        routeBadge: routeBadge,
      );
      return true;
    }
    final permKey = result.data['missingPermissionKey']?.toString() ?? '';
    if (permKey.isNotEmpty) {
      final permLabel =
          (result.data['missingPermissionLabel']?.toString() ?? '')
              .trim()
              .isEmpty
          ? permKey
          : result.data['missingPermissionLabel'].toString().trim();
      _pendingConversation = _GrantPermissionPrompt(
        originalGoal: _currentGoal,
        permissionKey: permKey,
        permissionLabel: permLabel,
      );
      _emitState(
        _state.copyWith(
          pendingPermissionKey: permKey,
          pendingPermissionLabel: permLabel,
        ),
      );
      _replyConversational(
        '${result.summary} Tap Grant $permLabel below to enable it directly.',
        ['Grant $permLabel', 'Not now'],
        routeBadge: routeBadge,
      );
      return true;
    }

    final missingApp = result.data['missingAppName']?.toString() ?? '';
    if (missingApp.isNotEmpty) {
      final missingPkg = result.data['missingPackage']?.toString().trim();
      final fallbackQuery = result.data['fallbackQuery']?.toString().trim();
      final offer = _InstallAppOffer(
        appName: missingApp,
        packageName: (missingPkg == null || missingPkg.isEmpty)
            ? null
            : missingPkg,
        fallbackQuery: (fallbackQuery == null || fallbackQuery.isEmpty)
            ? null
            : fallbackQuery,
      );
      _lastMissingAppOffer = offer;
      _pendingConversation = offer;
      _replyConversational(
        '$missingApp is not installed on your phone. Do you want me to open the Play Store and install it for you?',
        _installOfferChoices(offer.fallbackQuery),
        routeBadge: routeBadge,
      );
      return true;
    }

    if (result.data['needsCity'] == true) {
      _pendingConversation = _WeatherCityPrompt();
      _replyConversational('Which city should I check the weather for?', const [
        'London',
        'New York',
        'Cancel',
      ]);
      return true;
    }
    return false;
  }

  List<String> _installOfferChoices(String? fallbackQuery) =>
      fallbackQuery != null && fallbackQuery.isNotEmpty
      ? const ['Yes, install', 'Try YouTube', 'No']
      : const ['Yes, install', 'No'];

  Future<void> _installMissingAppFromPlayStore(
    _InstallAppOffer offer,
    int runToken,
  ) async {
    final label = offer.appName.trim().isEmpty ? 'app' : offer.appName.trim();
    _emitState(_state.copyWith(statusLine: 'Opening Play Store for $label...'));
    final openRes = await dispatcher.execute(
      PlannedToolCall(
        tool: 'install_app_play_store',
        args: {
          'appName': label,
          if (offer.packageName != null && offer.packageName!.isNotEmpty)
            'packageName': offer.packageName,
        },
      ),
    );
    _appendMessage(
      openRes.ok ? ChatRole.tool : ChatRole.error,
      'install_app_play_store: ${openRes.summary}',
    );
    if (!openRes.ok ||
        openRes.data['alreadyInstalled'] == true ||
        runToken != _activeRunToken) {
      _replyFinal(openRes.summary);
      return;
    }

    if (postLaunchInspectDelayMs > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: postLaunchInspectDelayMs),
      );
    }
    var action = await _pollPlayStoreAction(label);
    if (action is _PlayClickSearchResult) {
      final tapRes = await dispatcher.execute(
        PlannedToolCall(tool: 'tap_element', args: {'index': action.nodeIndex}),
      );
      _appendMessage(
        tapRes.ok ? ChatRole.tool : ChatRole.error,
        'tap_element: ${tapRes.summary}',
      );
      if (tapRes.ok) {
        if (postLaunchInspectDelayMs > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: postLaunchInspectDelayMs),
          );
        }
        action = await _pollPlayStoreAction('');
      } else {
        action = _PlayManualNeeded();
      }
    }

    if (action is _PlayClickInstall) {
      final tapRes = await dispatcher.execute(
        PlannedToolCall(tool: 'tap_element', args: {'index': action.nodeIndex}),
      );
      _appendMessage(
        tapRes.ok ? ChatRole.tool : ChatRole.error,
        'tap_element: ${tapRes.summary}',
      );
      if (tapRes.ok) {
        if (postLaunchInspectDelayMs > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
        final after = await dispatcher.captureUiNodes();
        final downloading = after.any((n) {
          final t = '${n.text} ${n.contentDesc}'.toLowerCase();
          return t.contains('pending') ||
              t.contains('downloading') ||
              t.contains('cancel') ||
              t.contains('%');
        });
        _lastMissingAppOffer = null;
        _replyFinal(
          downloading
              ? 'Opened Google Play Store and started downloading $label.'
              : 'Opened Google Play Store and tapped Install for $label.',
        );
      } else {
        _replyFinal('Opened $label in Google Play Store — tap Install there.');
      }
    } else if (action is _PlaySignInRequired) {
      _replyFinal(
        'Opened $label in Google Play Store — sign in to Google Play and tap Install there.',
      );
    } else if (action is _PlayAlreadyInstalled) {
      _lastMissingAppOffer = null;
      _replyFinal(
        'Opened $label in Google Play Store — tap Open or Update there.',
      );
    } else {
      _replyFinal('Opened $label in Google Play Store — tap Install there.');
    }
  }

  Future<_PlayStoreAction> _pollPlayStoreAction(String targetAppName) async {
    var nodes = await dispatcher.captureUiNodes();
    var action = _findPlayStoreAction(nodes, targetAppName);
    if (postLaunchInspectDelayMs > 0 && action is _PlayManualNeeded) {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 850));
        nodes = await dispatcher.captureUiNodes();
        action = _findPlayStoreAction(nodes, targetAppName);
        if (action is! _PlayManualNeeded) break;
      }
    }
    return action;
  }

  _PlayStoreAction _findPlayStoreAction(
    List<UiNodeInfo> nodes,
    String targetAppName,
  ) {
    bool matchesInstall(UiNodeInfo node, {required bool requireClickable}) {
      if (requireClickable && !node.clickable) return false;
      final label = (node.text.trim().isNotEmpty ? node.text : node.contentDesc)
          .trim()
          .toLowerCase();
      final combined = '${node.text} ${node.contentDesc}'.toLowerCase();
      return (label == 'install' || label == 'install app') &&
          !combined.contains('sponsored') &&
          !combined.contains('uninstall') &&
          !combined.contains('install on more');
    }

    final installNode =
        nodes
            .where((n) => matchesInstall(n, requireClickable: true))
            .firstOrNull ??
        nodes
            .where((n) => matchesInstall(n, requireClickable: false))
            .firstOrNull;
    if (installNode != null) return _PlayClickInstall(installNode.index);

    final needsSignIn = nodes.any((n) {
      final label = (n.text.trim().isNotEmpty ? n.text : n.contentDesc)
          .trim()
          .toLowerCase();
      return label == 'sign in' || label.contains('sign in to');
    });
    if (needsSignIn) return _PlaySignInRequired();

    final hasOpen = nodes.any((n) {
      final label = (n.text.trim().isNotEmpty ? n.text : n.contentDesc)
          .trim()
          .toLowerCase();
      return (n.clickable || const {'open', 'update'}.contains(label)) &&
          const {'open', 'update', 'play'}.contains(label);
    });
    if (hasOpen) return _PlayAlreadyInstalled();

    final cleanTarget = targetAppName.trim().toLowerCase();
    if (cleanTarget.isNotEmpty) {
      final row = nodes.where((n) {
        final t = n.text.trim();
        final l = t.toLowerCase();
        return !n.editable &&
            n.top > 240 &&
            t.isNotEmpty &&
            l != 'search' &&
            !l.contains('sponsored') &&
            !l.contains('search apps') &&
            (l == cleanTarget || l.contains(cleanTarget));
      }).firstOrNull;
      if (row != null) return _PlayClickSearchResult(row.index);
    }
    return _PlayManualNeeded();
  }

  void _replyConversational(
    String text,
    List<String> choices, {
    String? routeBadge,
  }) {
    _appendMessage(ChatRole.agent, text);
    _emitState(
      _state.copyWith(
        quickChoices: choices,
        isAwaitingReply: true,
        pendingWebUrl: null,
        lastRouteBadge: routeBadge,
      ),
    );
    unawaited(nativeApi.speak(text));
  }

  void _replyFinal(String text, {String? webUrl, String? routeBadge}) {
    _appendMessage(ChatRole.agent, text);
    _emitState(
      _state.copyWith(
        quickChoices: const [],
        isAwaitingReply: false,
        pendingPermissionKey: null,
        pendingPermissionLabel: null,
        pendingWebUrl: webUrl,
        lastRouteBadge: routeBadge,
      ),
    );
    unawaited(nativeApi.speak(text));
  }

  void _appendMessage(ChatRole role, String text) {
    final current = List<ChatEntry>.from(_state.messages)
      ..add(ChatEntry(role: role, text: text));
    final trimmed = current.length > 60
        ? current.sublist(current.length - 60)
        : current;
    _emitState(_state.copyWith(messages: trimmed));
  }

  bool _looksLikeNewCommand(String input) {
    if (OfflineIntentRouter.route(input) != null) return true;
    final lower = input.trim().toLowerCase();
    const prefixes = [
      'open ',
      'launch ',
      'start ',
      'call ',
      'dial ',
      'send ',
      'text ',
      'message ',
      'reply ',
      'turn ',
      'set ',
      'read ',
      'check ',
      'close ',
      'install ',
      'download ',
      'get ',
      "what's ",
      'whats ',
      "how's ",
      'hows ',
      'take ',
      'record ',
      'schedule ',
      'add ',
      'define ',
      'explain ',
    ];
    if (prefixes.any(lower.startsWith)) return true;
    const targets = [
      'spotify',
      'whatsapp',
      'telegram',
      'gmail',
      'chrome',
      'instagram',
      'settings',
      'battery',
      'flashlight',
      'notification',
      'wifi',
      'bluetooth',
      'weather',
      'news',
      'camera',
      'calendar',
    ];
    return targets.any(lower.contains);
  }

  bool _isVaguePlayRequest(String goal) {
    final lower = goal.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), '');
    return const {
      'play music',
      'play some music',
      'play a song',
      'play songs',
      'play video',
      'play something',
      'play youtube',
    }.contains(lower);
  }

  int? _parseExplicitOptionIndex(String normalized, int count) {
    final idx = switch (normalized) {
      '1' || 'first' || 'one' || 'option 1' || 'number 1' => 0,
      '2' || 'second' || 'two' || 'option 2' || 'number 2' => 1,
      '3' || 'third' || 'three' || 'option 3' || 'number 3' => 2,
      _ => null,
    };
    return (idx != null && idx >= 0 && idx < count) ? idx : null;
  }

  String _buildRefinedQuery(String previousQuery, String reply) {
    var clean = reply.trim();
    for (final p in const ['something ', 'play ', 'try ']) {
      if (clean.toLowerCase().startsWith(p)) {
        clean = clean.substring(p.length).trim();
      }
    }
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return (words.length >= 3 || previousQuery.isEmpty)
        ? clean
        : '$previousQuery $clean'.trim();
  }
}

sealed class _PlayStoreAction {}

class _PlayClickInstall extends _PlayStoreAction {
  _PlayClickInstall(this.nodeIndex);
  final int nodeIndex;
}

class _PlayClickSearchResult extends _PlayStoreAction {
  _PlayClickSearchResult(this.nodeIndex);
  final int nodeIndex;
}

class _PlaySignInRequired extends _PlayStoreAction {}

class _PlayAlreadyInstalled extends _PlayStoreAction {}

class _PlayManualNeeded extends _PlayStoreAction {}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) =>
      length <= count ? this : skip(length - count);
}
