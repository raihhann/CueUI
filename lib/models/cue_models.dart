import 'dart:typed_data';

enum ChatRole { user, agent, tool, error }

class ChatEntry {
  ChatEntry({
    required this.role,
    required this.text,
    this.sourceTag,
    int? id,
  }) : id = id ?? ++_nextId;

  static int _nextId = 0;

  final int id;
  final ChatRole role;
  final String text;
  final String? sourceTag;
}

class PlannedToolCall {
  const PlannedToolCall({
    required this.tool,
    this.args = const {},
    this.source = 'rule',
  });

  final String tool;
  final Map<String, dynamic> args;
  final String source;
}

class ToolExecutionResult {
  const ToolExecutionResult({
    required this.ok,
    required this.summary,
    this.data = const {},
  });

  final bool ok;
  final String summary;
  final Map<String, dynamic> data;

  factory ToolExecutionResult.fromMap(Map<dynamic, dynamic> raw) {
    final rawData = raw['data'];
    final dataMap = <String, dynamic>{};
    if (rawData is Map) {
      rawData.forEach((k, v) {
        dataMap[k.toString()] = v;
      });
    }
    return ToolExecutionResult(
      ok: raw['ok'] == true,
      summary: (raw['summary'] ?? '').toString(),
      data: dataMap,
    );
  }
}

class UiNodeInfo {
  const UiNodeInfo({
    required this.index,
    required this.className,
    required this.text,
    required this.contentDesc,
    required this.viewId,
    required this.clickable,
    required this.editable,
    required this.scrollable,
    required this.focused,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int index;
  final String className;
  final String text;
  final String contentDesc;
  final String viewId;
  final bool clickable;
  final bool editable;
  final bool scrollable;
  final bool focused;
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get centerX => (left + right) ~/ 2;
  int get centerY => (top + bottom) ~/ 2;

  String get primaryLabel {
    if (text.trim().isNotEmpty) return text.trim();
    if (contentDesc.trim().isNotEmpty) return contentDesc.trim();
    return viewId.contains('/') ? viewId.split('/').last : viewId;
  }

  factory UiNodeInfo.fromMap(Map<dynamic, dynamic> map) {
    return UiNodeInfo(
      index: (map['index'] as num?)?.toInt() ?? 0,
      className: (map['className'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      contentDesc: (map['contentDesc'] ?? '').toString(),
      viewId: (map['viewId'] ?? '').toString(),
      clickable: map['clickable'] == true,
      editable: map['editable'] == true,
      scrollable: map['scrollable'] == true,
      focused: map['focused'] == true,
      left: (map['left'] as num?)?.toInt() ?? 0,
      top: (map['top'] as num?)?.toInt() ?? 0,
      right: (map['right'] as num?)?.toInt() ?? 0,
      bottom: (map['bottom'] as num?)?.toInt() ?? 0,
    );
  }
}

class VideoCandidate {
  const VideoCandidate({
    required this.title,
    required this.nodeIndex,
    required this.yTop,
  });

  final String title;
  final int nodeIndex;
  final int yTop;
}

class LaunchableApp {
  const LaunchableApp({
    required this.label,
    required this.packageName,
    this.iconBytes,
  });

  final String label;
  final String packageName;
  final Uint8List? iconBytes;

  factory LaunchableApp.fromMap(Map<dynamic, dynamic> map) {
    final rawIcon = map['iconBytes'];
    return LaunchableApp(
      label: (map['label'] ?? '').toString(),
      packageName: (map['packageName'] ?? '').toString(),
      iconBytes: rawIcon is Uint8List ? rawIcon : null,
    );
  }
}

class MissingPermissionItem {
  const MissingPermissionItem({
    required this.key,
    required this.title,
    required this.isRuntime,
  });

  final String key;
  final String title;
  final bool isRuntime;

  factory MissingPermissionItem.fromMap(Map<dynamic, dynamic> map) {
    return MissingPermissionItem(
      key: (map['key'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      isRuntime: map['isRuntime'] == true,
    );
  }
}

class PermissionSnapshot {
  const PermissionSnapshot({
    this.isDefaultLauncher = false,
    this.accessibilityEnabled = false,
    this.overlayEnabled = false,
    this.notificationListenerEnabled = false,
    this.contactsGranted = false,
    this.callPhoneGranted = false,
    this.answerCallsGranted = false,
    this.sendSmsGranted = false,
    this.readSmsGranted = false,
    this.recordAudioGranted = false,
    this.postNotificationsGranted = false,
    this.writeSettingsGranted = false,
    this.dndPolicyGranted = false,
    this.coreMissing = const [],
  });

  final bool isDefaultLauncher;
  final bool accessibilityEnabled;
  final bool overlayEnabled;
  final bool notificationListenerEnabled;
  final bool contactsGranted;
  final bool callPhoneGranted;
  final bool answerCallsGranted;
  final bool sendSmsGranted;
  final bool readSmsGranted;
  final bool recordAudioGranted;
  final bool postNotificationsGranted;
  final bool writeSettingsGranted;
  final bool dndPolicyGranted;
  final List<MissingPermissionItem> coreMissing;

  bool get allRuntimeGranted =>
      contactsGranted &&
      callPhoneGranted &&
      answerCallsGranted &&
      sendSmsGranted &&
      readSmsGranted &&
      recordAudioGranted &&
      postNotificationsGranted;

  factory PermissionSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final rawMissing = (map['coreMissing'] as List<dynamic>?) ?? const [];
    return PermissionSnapshot(
      isDefaultLauncher: map['isDefaultLauncher'] == true,
      accessibilityEnabled: map['accessibilityEnabled'] == true,
      overlayEnabled: map['overlayEnabled'] == true,
      notificationListenerEnabled: map['notificationListenerEnabled'] == true,
      contactsGranted: map['contactsGranted'] == true,
      callPhoneGranted: map['callPhoneGranted'] == true,
      answerCallsGranted: map['answerCallsGranted'] == true,
      sendSmsGranted: map['sendSmsGranted'] == true,
      readSmsGranted: map['readSmsGranted'] == true,
      recordAudioGranted: map['recordAudioGranted'] == true,
      postNotificationsGranted: map['postNotificationsGranted'] == true,
      writeSettingsGranted: map['writeSettingsGranted'] == true,
      dndPolicyGranted: map['dndPolicyGranted'] == true,
      coreMissing: rawMissing
          .whereType<Map<dynamic, dynamic>>()
          .map(MissingPermissionItem.fromMap)
          .toList(),
    );
  }
}

class VoiceUiState {
  const VoiceUiState({
    this.isListening = false,
    this.partialTranscript = '',
    this.rmsLevel = 0.0,
    this.ttsEnabled = true,
    this.speechAvailable = true,
    this.statusNotice,
  });

  final bool isListening;
  final String partialTranscript;
  final double rmsLevel;
  final bool ttsEnabled;
  final bool speechAvailable;
  final String? statusNotice;

  factory VoiceUiState.fromMap(Map<dynamic, dynamic> map) {
    return VoiceUiState(
      isListening: map['isListening'] == true,
      partialTranscript: (map['partialTranscript'] ?? '').toString(),
      rmsLevel: (map['rmsLevel'] as num?)?.toDouble() ?? 0.0,
      ttsEnabled: map['ttsEnabled'] != false,
      speechAvailable: map['speechAvailable'] != false,
      statusNotice: map['statusNotice']?.toString(),
    );
  }
}

enum AiModelStatus { unloaded, scanning, downloading, loading, ready, error }

class AiCatalogEntry {
  const AiCatalogEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeMb,
    this.recommended = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String fileName;
  final String downloadUrl;
  final int sizeMb;
  final bool recommended;
}

class DiscoveredModelFile {
  const DiscoveredModelFile({
    required this.name,
    required this.path,
    required this.sizeMb,
    required this.isLoaded,
  });

  final String name;
  final String path;
  final double sizeMb;
  final bool isLoaded;
}

class AiEngineSnapshot {
  const AiEngineSnapshot({
    this.status = AiModelStatus.unloaded,
    this.loadedModelName,
    this.loadedModelPath,
    this.statusMessage = 'No local Nano GGUF loaded (using fast rule + web engine).',
    this.downloadProgress = 0.0,
    this.downloadingId,
    this.lastInferenceMs,
    this.lastParsedSummary,
    this.discoveredFiles = const [],
  });

  final AiModelStatus status;
  final String? loadedModelName;
  final String? loadedModelPath;
  final String statusMessage;
  final double downloadProgress;
  final String? downloadingId;
  final int? lastInferenceMs;
  final String? lastParsedSummary;
  final List<DiscoveredModelFile> discoveredFiles;

  bool get isReady => status == AiModelStatus.ready;
}

class CueUiState {
  CueUiState({
    List<ChatEntry>? messages,
    this.isRunning = false,
    this.statusLine = 'Ready',
    this.pendingConfirmationPrompt,
    this.bubbleActive = false,
    this.quickChoices = const [],
    this.isAwaitingReply = false,
    this.pendingPermissionKey,
    this.pendingPermissionLabel,
    this.pendingWebUrl,
    this.lastRouteBadge,
  }) : messages = messages ??
            [
              ChatEntry(
                role: ChatRole.agent,
                text: 'Ready. Speak or type naturally for WhatsApp, YouTube, Spotify, calls, weather, news, camera, calendar, or web Q&A.',
              ),
            ];

  final List<ChatEntry> messages;
  final bool isRunning;
  final String statusLine;
  final String? pendingConfirmationPrompt;
  final bool bubbleActive;
  final List<String> quickChoices;
  final bool isAwaitingReply;
  final String? pendingPermissionKey;
  final String? pendingPermissionLabel;
  final String? pendingWebUrl;
  final String? lastRouteBadge;

  CueUiState copyWith({
    List<ChatEntry>? messages,
    bool? isRunning,
    String? statusLine,
    Object? pendingConfirmationPrompt = _sentinel,
    bool? bubbleActive,
    List<String>? quickChoices,
    bool? isAwaitingReply,
    Object? pendingPermissionKey = _sentinel,
    Object? pendingPermissionLabel = _sentinel,
    Object? pendingWebUrl = _sentinel,
    Object? lastRouteBadge = _sentinel,
  }) {
    return CueUiState(
      messages: messages ?? this.messages,
      isRunning: isRunning ?? this.isRunning,
      statusLine: statusLine ?? this.statusLine,
      pendingConfirmationPrompt: identical(pendingConfirmationPrompt, _sentinel)
          ? this.pendingConfirmationPrompt
          : pendingConfirmationPrompt as String?,
      bubbleActive: bubbleActive ?? this.bubbleActive,
      quickChoices: quickChoices ?? this.quickChoices,
      isAwaitingReply: isAwaitingReply ?? this.isAwaitingReply,
      pendingPermissionKey: identical(pendingPermissionKey, _sentinel)
          ? this.pendingPermissionKey
          : pendingPermissionKey as String?,
      pendingPermissionLabel: identical(pendingPermissionLabel, _sentinel)
          ? this.pendingPermissionLabel
          : pendingPermissionLabel as String?,
      pendingWebUrl: identical(pendingWebUrl, _sentinel)
          ? this.pendingWebUrl
          : pendingWebUrl as String?,
      lastRouteBadge: identical(lastRouteBadge, _sentinel)
          ? this.lastRouteBadge
          : lastRouteBadge as String?,
    );
  }
}

const Object _sentinel = Object();
