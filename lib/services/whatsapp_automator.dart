import '../models/cue_models.dart';

abstract class WhatsAppUiDriver {
  Future<String?> findWhatsAppPackage();
  Future<bool> launchWhatsApp(String packageName);
  Future<bool> launchWhatsAppChatByPhone(
    String packageName,
    String phoneDigits,
    String message,
  );
  Future<String?> resolvePhoneDigits(String recipient);
  Future<List<UiNodeInfo>> captureNodes();
  Future<bool> tapNode(int nodeIndex);
  Future<bool> typeText(String text);
  Future<bool> goBack();
  Future<bool> startVoiceNote(int index);
  Future<bool> isWhatsAppForeground();
  Future<void> pauseMs(int ms);
}

class WhatsAppAutomator {
  WhatsAppAutomator(
    this.driver, {
    this.launchWaitMs = 1300,
    this.stepWaitMs = 650,
    this.searchWaitMs = 1000,
  });

  final WhatsAppUiDriver driver;
  final int launchWaitMs;
  final int stepWaitMs;
  final int searchWaitMs;

  static final _rawPhoneRe = RegExp(r'^[+\d][\d\s().-]{5,}$');
  static const _searchSectionLabels = {
    'chats',
    'contacts',
    'other contacts',
    'messages',
    'updates',
    'calls',
    'communities',
    'ask meta ai or search',
    'search',
    'search...',
    'unread',
    'favorites',
    'groups',
  };

  Future<ToolExecutionResult> sendMessage(
    String recipient,
    String message, {
    String? selectedChat,
    bool Function()? canContinue,
  }) async {
    final cleanRecipient = recipient.trim();
    final cleanMessage = message.trim();
    if (cleanRecipient.isEmpty || cleanMessage.isEmpty) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'WhatsApp recipient and message cannot be empty.',
      );
    }

    final waPkg = await driver.findWhatsAppPackage();
    if (waPkg == null) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'WhatsApp is not installed on this device.',
        data: {'missingAppName': 'WhatsApp', 'missingPackage': 'com.whatsapp'},
      );
    }

    final rawDigits = extractRawPhoneDigits(cleanRecipient);
    if (rawDigits != null &&
        await driver.launchWhatsAppChatByPhone(
          waPkg,
          rawDigits,
          cleanMessage,
        )) {
      await driver.pauseMs(launchWaitMs);
      final afterLaunch = await driver.captureNodes();
      final blocker = findOnboardingBlocker(afterLaunch);
      if (blocker != null) {
        return ToolExecutionResult(ok: false, summary: blocker);
      }
      final sendAfterLink = findSendButton(afterLaunch);
      if (canContinue?.call() == false) return _cancelled;
      if (!await driver.isWhatsAppForeground()) return _wrongApp;
      if (sendAfterLink != null && await driver.tapNode(sendAfterLink.index)) {
        return ToolExecutionResult(
          ok: true,
          summary: 'Sent WhatsApp message to $cleanRecipient: "$cleanMessage"',
        );
      }
      if (sendAfterLink != null) {
        return ToolExecutionResult(
          ok: false,
          summary: 'Opened chat for $cleanRecipient, but could not tap Send.',
        );
      }
    }

    final (contactLabel, openErr) = await _openChatInWhatsApp(
      waPkg,
      cleanRecipient,
      requireUnique: true,
      selectedChat: selectedChat,
    );
    if (openErr != null) {
      if (openErr.data['whatsappRecipients'] != null ||
          selectedChat != null ||
          openErr.data['doNotFallback'] == true) {
        return openErr;
      }
      final fallbackDigits = await driver.resolvePhoneDigits(cleanRecipient);
      if (fallbackDigits != null &&
          await driver.launchWhatsAppChatByPhone(
            waPkg,
            fallbackDigits,
            cleanMessage,
          )) {
        await driver.pauseMs(launchWaitMs);
        final linkNodes = await driver.captureNodes();
        final sendBtn = findSendButton(linkNodes);
        if (canContinue?.call() == false) return _cancelled;
        if (!await driver.isWhatsAppForeground()) return _wrongApp;
        if (sendBtn != null && await driver.tapNode(sendBtn.index)) {
          return ToolExecutionResult(
            ok: true,
            summary:
                'Sent WhatsApp message to $cleanRecipient: "$cleanMessage"',
          );
        }
      }
      return openErr;
    }

    final chatName = contactLabel ?? cleanRecipient;
    if (canContinue?.call() == false) return _cancelled;
    var nodes = await driver.captureNodes();
    final messageBox = findMessageInputField(nodes);
    if (messageBox == null) {
      return ToolExecutionResult(
        ok: false,
        summary:
            'Opened chat with "$chatName", but could not find the message input box.',
      );
    }
    if (!messageBox.focused) {
      await driver.tapNode(messageBox.index);
      await driver.pauseMs(stepWaitMs < 200 ? stepWaitMs : 200);
    }
    if (!await driver.typeText(cleanMessage)) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'Could not enter message text into WhatsApp chat.',
      );
    }
    await driver.pauseMs(stepWaitMs ~/ 2);

    nodes = await driver.captureNodes();
    if (canContinue?.call() == false) return _cancelled;
    if (!await driver.isWhatsAppForeground()) return _wrongApp;
    final sendBtn = findSendButton(nodes);
    if (sendBtn == null) {
      return ToolExecutionResult(
        ok: false,
        summary:
            'Typed message for "$chatName" in WhatsApp — tap Send if ready.',
      );
    }
    return await driver.tapNode(sendBtn.index)
        ? ToolExecutionResult(
            ok: true,
            summary: 'Sent WhatsApp message to $chatName: "$cleanMessage"',
          )
        : const ToolExecutionResult(
            ok: false,
            summary: 'Typed message in WhatsApp, but failed to tap Send.',
          );
  }

  static const _cancelled = ToolExecutionResult(
    ok: false,
    summary: 'WhatsApp message cancelled.',
  );
  static const _wrongApp = ToolExecutionResult(
    ok: false,
    summary: 'WhatsApp left the screen. Return to the chat and try again.',
    data: {'doNotFallback': true},
  );

  Future<ToolExecutionResult> sendSharedMedia(
    String recipient, {
    String? selectedChat,
    bool Function()? canContinue,
  }) async {
    final package = await driver.findWhatsAppPackage();
    if (package == null) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'WhatsApp is not installed.',
      );
    }
    final (name, error) = await _openChatInWhatsApp(
      package,
      recipient,
      requireUnique: true,
      selectedChat: selectedChat,
      launch: false,
    );
    if (error != null) return error;
    if (canContinue?.call() == false) return _cancelled;
    if (!await driver.isWhatsAppForeground()) return _wrongApp;
    await driver.pauseMs(stepWaitMs);
    var nodes = await driver.captureNodes();
    // The picker first advances to a media preview; the second Send submits it.
    if (_hasChatComposer(nodes)) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'WhatsApp opened a chat instead of the media-sharing picker. Please finish sharing in WhatsApp.',
      );
    }
    final pickerSend =
        findSendButton(nodes) ??
        nodes
            .where(
              (node) =>
                  node.clickable &&
                  {'next', 'forward'}.contains(node.primaryLabel.toLowerCase()),
            )
            .firstOrNull;
    if (pickerSend == null || !await driver.tapNode(pickerSend.index)) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'Selected the contact, but could not advance the WhatsApp media preview. Finish sharing in WhatsApp.',
      );
    }
    await driver.pauseMs(searchWaitMs);
    nodes = await driver.captureNodes();
    if (canContinue?.call() == false) return _cancelled;
    final send = findSendButton(nodes);
    if (!await driver.isWhatsAppForeground()) return _wrongApp;
    if (send != null && !_hasChatComposer(nodes)) {
      if (!await driver.tapNode(send.index)) {
        return const ToolExecutionResult(
          ok: false,
          summary: 'Could not send the WhatsApp media preview.',
        );
      }
    } else if (findMessageInputField(nodes) == null) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'WhatsApp did not show a recognizable media preview or chat. Check sharing in WhatsApp.',
      );
    }
    return ToolExecutionResult(
      ok: true,
      summary: 'Submitted media to ${name ?? recipient} on WhatsApp.',
      data: {'recipient': name ?? recipient},
    );
  }

  Future<ToolExecutionResult> startVoiceMessage(
    String recipient, {
    String? selectedChat,
    bool Function()? canContinue,
  }) async {
    final package = await driver.findWhatsAppPackage();
    if (package == null) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'WhatsApp is not installed.',
      );
    }
    final (name, error) = await _openChatInWhatsApp(
      package,
      recipient,
      requireUnique: true,
      selectedChat: selectedChat,
    );
    if (error != null) return error;
    final nodes = await driver.captureNodes();
    final entry = findMessageInputField(nodes);
    if (entry != null &&
        entry.text.trim().isNotEmpty &&
        entry.text.toLowerCase() != 'message') {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'There is an existing draft in this chat. Clear it in WhatsApp before recording a voice message.',
      );
    }
    final microphone = nodes
        .where(
          (node) =>
              node.clickable &&
              ('${node.viewId} ${node.contentDesc}'.toLowerCase().contains(
                    'voice_note',
                  ) ||
                  node.contentDesc.toLowerCase().contains('voice message') ||
                  node.contentDesc.toLowerCase().contains('record voice')),
        )
        .firstOrNull;
    if (canContinue?.call() == false) return _cancelled;
    if (microphone == null || !await driver.startVoiceNote(microphone.index)) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'Could not start a locked WhatsApp voice recording. Use the microphone in WhatsApp.',
      );
    }
    await driver.pauseMs(searchWaitMs);
    final after = await driver.captureNodes();
    final locked = hasVoiceRecordingControls(after);
    if (!locked) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'Recording could not be verified. Check WhatsApp before continuing.',
      );
    }
    return ToolExecutionResult(
      ok: true,
      summary:
          'Recording a WhatsApp voice message for ${name ?? recipient}. Type "send voice note" to send, or "cancel voice note" to discard.',
      data: {'recipient': name ?? recipient},
    );
  }

  Future<ToolExecutionResult> finishVoiceMessage({required bool cancel}) async {
    if (!await driver.isWhatsAppForeground()) return _wrongApp;
    final nodes = await driver.captureNodes();
    if (!hasVoiceRecordingControls(nodes)) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'WhatsApp no longer shows an active voice recording. If you finished it manually, no further action is needed.',
        data: {'recordingAbsent': true},
      );
    }
    final target = cancel
        ? nodes
              .where(
                (node) =>
                    node.clickable &&
                    RegExp(
                      r'^(?:delete|discard|cancel)(?: recording| voice message| voice note)?$',
                      caseSensitive: false,
                    ).hasMatch(node.primaryLabel),
              )
              .firstOrNull
        : findSendButton(nodes);
    if (target == null || !await driver.tapNode(target.index)) {
      return const ToolExecutionResult(
        ok: false,
        summary:
            'Could not find the WhatsApp recording control. Finish the voice message in WhatsApp.',
      );
    }
    return ToolExecutionResult(
      ok: true,
      summary: cancel
          ? 'Discarded the WhatsApp voice message.'
          : 'Submitted the WhatsApp voice message.',
    );
  }

  static bool hasVoiceRecordingControls(List<UiNodeInfo> nodes) =>
      findSendButton(nodes) != null &&
      nodes.any(
        (node) =>
            node.clickable &&
            RegExp(
              r'^(?:delete|discard|cancel|pause|stop)(?: recording| voice message| voice note)?$',
              caseSensitive: false,
            ).hasMatch(node.primaryLabel.trim()),
      );

  static bool _hasChatComposer(List<UiNodeInfo> nodes) => nodes.any(
    (node) =>
        node.editable &&
        (node.viewId.split('/').last == 'entry' ||
            node.primaryLabel.trim().toLowerCase() == 'message'),
  );

  Future<ToolExecutionResult> callContact(
    String recipient, {
    bool video = false,
  }) async {
    final cleanRecipient = recipient.trim();
    if (cleanRecipient.isEmpty) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'WhatsApp call recipient cannot be empty.',
      );
    }
    final waPkg = await driver.findWhatsAppPackage();
    if (waPkg == null) {
      return const ToolExecutionResult(
        ok: false,
        summary: 'WhatsApp is not installed on this device.',
        data: {'missingAppName': 'WhatsApp', 'missingPackage': 'com.whatsapp'},
      );
    }
    final (contactLabel, openErr) = await _openChatInWhatsApp(
      waPkg,
      cleanRecipient,
    );
    if (openErr != null) return openErr;

    final chatName = contactLabel ?? cleanRecipient;
    final nodes = await driver.captureNodes();
    final callBtn = findCallButton(nodes, video: video);
    if (callBtn == null) {
      return ToolExecutionResult(
        ok: false,
        summary:
            'Opened WhatsApp chat with $chatName, but could not find the ${video ? "Video" : "Voice"} call button.',
      );
    }
    return await driver.tapNode(callBtn.index)
        ? ToolExecutionResult(
            ok: true,
            summary:
                'Starting WhatsApp ${video ? "video" : "voice"} call with $chatName.',
          )
        : ToolExecutionResult(
            ok: false,
            summary: 'Opened chat with $chatName, but failed to tap Call.',
          );
  }

  Future<(String?, ToolExecutionResult?)> _openChatInWhatsApp(
    String waPkg,
    String recipient, {
    bool requireUnique = false,
    String? selectedChat,
    bool launch = true,
  }) async {
    if (launch && !await driver.launchWhatsApp(waPkg)) {
      return (
        null,
        ToolExecutionResult(
          ok: false,
          summary: 'Could not launch WhatsApp ($waPkg).',
        ),
      );
    }
    await driver.pauseMs(launchWaitMs);

    if (!await driver.isWhatsAppForeground()) return (null, _wrongApp);

    var nodes = await driver.captureNodes();
    final blocker = findOnboardingBlocker(nodes);
    if (blocker != null) {
      return (null, ToolExecutionResult(ok: false, summary: blocker));
    }
    if (!launch && _hasChatComposer(nodes)) {
      return (
        null,
        const ToolExecutionResult(
          ok: false,
          summary:
              'WhatsApp did not open the media recipient picker. Try sharing again.',
          data: {'doNotFallback': true},
        ),
      );

    }
    // WhatsApp may resume inside an existing chat, where Search searches that
    // conversation rather than contacts. Return to the chat list first.
    for (
      var attempt = 0;
      attempt < 2 && findMessageInputField(nodes) != null;
      attempt++
    ) {
      if (!await driver.goBack()) break;
      await driver.pauseMs(stepWaitMs);
      nodes = await driver.captureNodes();
    }
    if (findMessageInputField(nodes) != null) {
      return (
        null,
        const ToolExecutionResult(
          ok: false,
          summary:
              'Could not return to the WhatsApp chat list. Open Chats and try again.',
        ),
      );
    }

    var searchInput = findEditableSearchField(nodes);
    if (searchInput == null) {
      final trigger = findSearchTrigger(nodes);
      if (trigger == null) {
        return (
          null,
          ToolExecutionResult(
            ok: false,
            summary:
                'Opened WhatsApp, but could not find the Search button to look up "$recipient".',
          ),
        );
      }
      if (!await driver.tapNode(trigger.index)) {
        return (
          null,
          const ToolExecutionResult(
            ok: false,
            summary: 'Could not tap WhatsApp Search.',
          ),
        );
      }
      await driver.pauseMs(stepWaitMs);
      nodes = await driver.captureNodes();
      final blockerAfter = findOnboardingBlocker(nodes);
      if (blockerAfter != null) {
        return (null, ToolExecutionResult(ok: false, summary: blockerAfter));
      }
      searchInput = findEditableSearchField(nodes);
    }

    if (searchInput != null && !searchInput.focused) {
      await driver.tapNode(searchInput.index);
      await driver.pauseMs(stepWaitMs < 250 ? stepWaitMs : 250);
    }
    if (!await driver.typeText(recipient)) {
      return (
        null,
        ToolExecutionResult(
          ok: false,
          summary: 'Opened WhatsApp search, but could not type "$recipient".',
        ),
      );
    }
    await driver.pauseMs(searchWaitMs);

    nodes = await driver.captureNodes();
    searchInput = findEditableSearchField(nodes);
    final searchBoxBottom = searchInput?.bottom ?? 320;
    final matches = findMatchingChatRows(nodes, recipient, searchBoxBottom);
    UiNodeInfo? chatMatch;
    if (requireUnique) {
      final selected = selectedChat == null
          ? matches
          : matches
                .where(
                  (node) =>
                      node.primaryLabel.toLowerCase() ==
                      selectedChat.toLowerCase(),
                )
                .toList();
      if (selected.length == 1) {
        chatMatch = selected.single;
      } else if (matches.isNotEmpty) {
        return (
          null,
          ToolExecutionResult(
            ok: false,
            summary: selectedChat == null
                ? 'I found several WhatsApp matches for "$recipient". Which one should receive the message?'
                : 'The WhatsApp results changed or that name is still ambiguous. Please choose again or use a phone number.',
            data: {
              'whatsappRecipients': matches
                  .map((node) => node.primaryLabel)
                  .toList(),
            },
          ),
        );
      }
    } else {
      chatMatch = findMatchingChatRow(nodes, recipient, searchBoxBottom);
    }
    if (chatMatch == null) {
      return (
        null,
        ToolExecutionResult(
          ok: false,
          summary:
              'Searched WhatsApp for "$recipient", but no matching chat or contact appeared.',
        ),
      );
    }
    if (!await driver.tapNode(chatMatch.index)) {
      return (
        null,
        ToolExecutionResult(
          ok: false,
          summary: 'Found "$recipient" in WhatsApp, but failed to open chat.',
        ),
      );
    }
    await driver.pauseMs(stepWaitMs);
    return (
      chatMatch.primaryLabel.isEmpty ? recipient : chatMatch.primaryLabel,
      null,
    );
  }

  static String? extractRawPhoneDigits(String input) {
    final trimmed = input.trim();
    if (!_rawPhoneRe.hasMatch(trimmed)) return null;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 7 ? digits : null;
  }

  static String? findOnboardingBlocker(List<UiNodeInfo> nodes) {
    final textBlob = nodes
        .map((n) => '${n.text} ${n.contentDesc}')
        .join(' ')
        .toLowerCase();
    if (textBlob.contains('agree and continue') ||
        textBlob.contains('welcome to whatsapp')) {
      return 'WhatsApp is not set up on this phone yet. Open WhatsApp and sign in first.';
    }
    if (textBlob.contains('enter your phone number') ||
        textBlob.contains('verify your number')) {
      return 'WhatsApp needs account verification before CueUI can message contacts.';
    }
    if (textBlob.contains('whatsapp locked') ||
        textBlob.contains('unlock whatsapp')) {
      return 'WhatsApp is locked. Unlock WhatsApp first and try again.';
    }
    return null;
  }

  static UiNodeInfo? findEditableSearchField(List<UiNodeInfo> nodes) {
    for (final node in nodes) {
      if (!node.editable) continue;
      final combined = '${node.text} ${node.contentDesc} ${node.viewId}'
          .toLowerCase();
      final looksLikeMsg =
          combined.contains('entry') ||
          (combined.contains('message') && !combined.contains('search'));
      if (!looksLikeMsg &&
          (combined.contains('search') ||
              combined.contains('meta ai') ||
              node.top < 700)) {
        return node;
      }
    }
    return null;
  }

  static UiNodeInfo? findSearchTrigger(List<UiNodeInfo> nodes) {
    for (final node in nodes) {
      final desc = node.contentDesc.trim().toLowerCase();
      final id = node.viewId.split('/').last.toLowerCase();
      if ((node.clickable || node.editable) &&
          (desc == 'search' || id == 'menuitem_search' || id == 'search_bar') &&
          node.top < 500) {
        return node;
      }
    }
    for (final node in nodes) {
      final combined = '${node.text} ${node.contentDesc} ${node.viewId}'
          .toLowerCase();
      final short = node.viewId.split('/').last.toLowerCase();
      final idHasSearch =
          short == 'search' ||
          short == 'search_btn' ||
          short == 'search_bar_text';
      if (node.top < 550 &&
          (combined.contains('ask meta ai or search') ||
              combined.trim() == 'search' ||
              combined.contains('search...') ||
              idHasSearch)) {
        return node;
      }
    }
    return null;
  }

  static UiNodeInfo? findMatchingChatRow(
    List<UiNodeInfo> nodes,
    String recipient,
    int searchBoxBottom,
  ) {
    return findMatchingChatRows(nodes, recipient, searchBoxBottom).firstOrNull;
  }

  static List<UiNodeInfo> findMatchingChatRows(
    List<UiNodeInfo> nodes,
    String recipient,
    int searchBoxBottom,
  ) {
    final needle = recipient.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final needleTokens = needle
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final scored = <(UiNodeInfo, int)>[];
    for (final node in nodes) {
      if (node.editable || node.top <= searchBoxBottom) continue;
      final label = (node.text.trim().isNotEmpty ? node.text : node.contentDesc)
          .trim();
      if (label.isEmpty) continue;
      final lower = label.toLowerCase();
      if (_searchSectionLabels.contains(lower)) continue;
      if (lower.contains('meta ai') && !needle.contains('meta')) continue;
      final idShort = node.viewId.split('/').last.toLowerCase();
      if (idShort.contains('status') ||
          idShort.contains('timestamp') ||
          idShort.contains('date')) {
        continue;
      }
      final isContactName =
          idShort.contains('contact_name') ||
          idShort.contains('row_contact_picker') ||
          idShort.contains('conversation_name');
      if (!isContactName && !node.clickable) continue;
      if (idShort.contains('message') || idShort.contains('snippet')) continue;

      int? score;
      if (lower == needle) {
        score = 120;
      } else if (lower.startsWith(needle) &&
          label.length <= needle.length + 24) {
        score = 95;
      } else if (needleTokens.length > 1 &&
          needleTokens.every(lower.contains)) {
        score = 80;
      } else if (lower.contains(needle) && label.length <= needle.length + 32) {
        score = 65;
      }
      if (score == null) continue;

      if (idShort.contains('contact_name') ||
          idShort.contains('row_contact_picker') ||
          idShort.contains('conversations_row_contact_name')) {
        score += 20;
      }
      if (node.clickable) score += 8;
      score -= (node.top ~/ 350);

      scored.add((node, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final matches = <UiNodeInfo>[];
    for (final (node, _) in scored) {
      // Accessibility can expose a row and its label as overlapping nodes.
      final duplicate = matches.any(
        (other) =>
            other.primaryLabel.toLowerCase() ==
                node.primaryLabel.toLowerCase() &&
            other.top < node.bottom &&
            node.top < other.bottom,
      );
      if (!duplicate) matches.add(node);
    }
    return matches;
  }

  static UiNodeInfo? findMessageInputField(List<UiNodeInfo> nodes) {
    final editables = nodes.where((n) {
      if (!n.editable) return false;
      final combined = '${n.viewId} ${n.text} ${n.contentDesc}'.toLowerCase();
      return !combined.contains('search');
    }).toList();
    if (editables.isEmpty) return null;

    editables.sort((a, b) {
      int scoreOf(UiNodeInfo n) {
        final id = n.viewId.split('/').last.toLowerCase();
        final hint = '${n.text} ${n.contentDesc}'.toLowerCase();
        var s = n.centerY ~/ 10;
        if (id == 'entry') s += 200;
        if (hint.contains('message')) s += 120;
        if (id.contains('search') || hint.contains('search')) s -= 500;
        return s;
      }

      return scoreOf(b).compareTo(scoreOf(a));
    });
    return editables.first;
  }

  static UiNodeInfo? findSendButton(List<UiNodeInfo> nodes) {
    for (final node in nodes) {
      if (!node.clickable) continue;
      final id = node.viewId.split('/').last.toLowerCase();
      final label =
          (node.contentDesc.trim().isNotEmpty ? node.contentDesc : node.text)
              .trim()
              .toLowerCase();
      final isMic = label.contains('voice') || id == 'voice_note_btn';
      if (!isMic && (label == 'send' || id == 'send')) return node;
    }
    return null;
  }

  static UiNodeInfo? findCallButton(
    List<UiNodeInfo> nodes, {
    required bool video,
  }) {
    for (final node in nodes) {
      if (!node.clickable || node.top > 340) continue;
      final label =
          (node.contentDesc.trim().isNotEmpty ? node.contentDesc : node.text)
              .trim()
              .toLowerCase();
      final id = node.viewId.split('/').last.toLowerCase();
      if (video) {
        if (label.contains('video call') || id.contains('video_call')) {
          return node;
        }
      } else {
        if ((label.contains('voice call') ||
                label == 'call' ||
                id.contains('voice_call') ||
                id.contains('audio_call')) &&
            !label.contains('video')) {
          return node;
        }
      }
    }
    return null;
  }
}
