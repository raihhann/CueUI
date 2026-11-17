import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/cue_models.dart';
import 'native_bridge.dart';

class NanoAiService extends ChangeNotifier {
  NanoAiService({required this.nativeApi, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final CueNativeApi nativeApi;
  final http.Client _httpClient;

  LlamaEngine? _engine;
  AiEngineSnapshot _snapshot = const AiEngineSnapshot();
  AiEngineSnapshot get snapshot => _snapshot;

  bool get isReady => _snapshot.isReady && _engine != null;

  static const List<AiCatalogEntry> catalog = [
    AiCatalogEntry(
      id: 'smollm2-360m',
      title: 'SmolLM2 360M Instruct (Nano)',
      subtitle: 'Smallest & fastest offline NL query parser (~258 MB Q4_K_M).',
      fileName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
      sizeMb: 258,
      recommended: true,
    ),
    AiCatalogEntry(
      id: 'qwen25-0.5b',
      title: 'Qwen 2.5 0.5B Instruct (Q4_K_M)',
      subtitle: 'Strong multi-language intent & slot accuracy (~379 MB).',
      fileName: 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
      sizeMb: 379,
    ),
    AiCatalogEntry(
      id: 'qwen3-0.6b',
      title: 'Qwen 3 0.6B (Q4_K_M)',
      subtitle: 'Compact Qwen3 model with no-think JSON mode (~378 MB).',
      fileName: 'Qwen3-0.6B-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
      sizeMb: 378,
    ),
  ];

  static const Map<String, dynamic> intentJsonSchema = {
    'type': 'object',
    'properties': {
      'tool': {
        'type': 'string',
        'enum': [
          'whatsapp_send',
          'whatsapp_call',
          'make_call',
          'send_sms',
          'open_app',
          'install_app_play_store',
          'spotify_play',
          'youtube_search',
          'open_camera',
          'open_calendar',
          'add_calendar_event',
          'set_alarm',
          'set_timer',
          'get_weather',
          'get_news',
          'ask_internet',
          'set_flashlight',
          'set_brightness',
          'set_dnd',
          'open_connectivity_panel',
          'media_control',
          'read_messages',
          'read_notifications',
          'reply_notification',
          'get_device_status',
          'record_audio_start',
          'record_audio_pause',
          'record_audio_resume',
          'record_audio_stop',
          'camera_photo',
          'camera_switch',
          'camera_video_start',
          'camera_video_stop',
          'camera_cancel',
          'whatsapp_share_media',
          'whatsapp_start_voice',
          'whatsapp_finish_voice',
          'whatsapp_cancel_voice',
          'media_play',
          'media_stop_playback',
          'media_transcribe',
          'run_routine',
          'none',
        ],
      },
      'target': {'type': 'string'},
      'message': {'type': 'string'},
      'query': {'type': 'string'},
      'enabled': {'type': 'boolean'},
      'hour': {'type': 'integer'},
      'minute': {'type': 'integer'},
      'seconds': {'type': 'integer'},
      'percent': {'type': 'integer'},
      'dayOffset': {'type': 'integer'},
      'countdown': {'type': 'integer'},
      'lens': {
        'type': 'string',
        'enum': ['front', 'back'],
      },
    },
    'required': ['tool'],
    'additionalProperties': false,
  };

  static const String _systemPrompt =
      'You map casual natural language phone commands to one JSON tool call.\n'
      'Tools:\n'
      '- whatsapp_send: message someone on WhatsApp (target=person, message=text)\n'
      '- whatsapp_call: call on WhatsApp (target=person, enabled=true if video)\n'
      '- make_call: phone call (target=person or number)\n'
      '- send_sms: send SMS text (target=person, message=text)\n'
      '- open_app: launch an app (target=app name)\n'
      '- install_app_play_store: install app (target=app name)\n'
      '- spotify_play: music on Spotify (query=song/artist/mood)\n'
      '- youtube_search: video/song on YouTube (query=search terms)\n'
      '- open_camera: camera (query=photo|selfie|video)\n'
      '- open_calendar: view schedule/calendar\n'
      '- add_calendar_event: schedule event/reminder (message=title, hour=0..23, minute=0..59, dayOffset=0 today|1 tomorrow)\n'
      '- set_alarm: alarm (hour=0..23, minute=0..59, message=label)\n'
      '- set_timer: countdown (seconds=total seconds, message=label)\n'
      '- get_weather: forecast (query=city or empty)\n'
      '- get_news: headlines (query=topic or empty)\n'
      '- ask_internet: general question or definition (query=question)\n'
      '- set_flashlight / set_dnd: (enabled=true|false)\n'
      '- set_brightness: (percent=0..100)\n'
      '- open_connectivity_panel: wifi/bluetooth/internet toggle (query=wifi|bluetooth|internet, enabled=bool)\n'
      '- media_control: (query=play_pause|next|previous|volume_up|volume_down|mute)\n'
      '- read_messages / read_notifications / get_device_status\n'
      '- reply_notification: reply to incoming notif (target=sender, message=reply)\n'
      '- record_audio_start / record_audio_pause / record_audio_resume / record_audio_stop: audio recording (message=title)\n'
      '- camera_photo: capture a photo (lens=front|back, countdown=seconds); camera_switch: lens=front|back\n'
      '- camera_video_start / camera_video_stop / camera_cancel: video recording or cancel photo countdown\n'
      '- whatsapp_share_media: send saved file (target=recipient, query=photo|audio|video or empty for latest)\n'
      '- whatsapp_start_voice: actual WhatsApp voice message (target=recipient); whatsapp_finish_voice / whatsapp_cancel_voice\n'
      '- media_play / media_transcribe: saved recording (query=title or empty for latest); media_stop_playback\n'
      '- run_routine: (target=bedtime|morning|focus or custom routine name)\n'
      '- none: if unclear.';

  Future<Directory> _modelsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _selectionFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/selected_gguf_model.txt');
  }

  void _updateSnapshot(AiEngineSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }

  Future<List<DiscoveredModelFile>> scanLocalModels() async {
    final results = <String, DiscoveredModelFile>{};
    final loadedPath = _snapshot.loadedModelPath;

    Future<void> addIfValid(File file) async {
      try {
        if (!file.path.toLowerCase().endsWith('.gguf')) return;
        if (!await file.exists()) return;
        final len = await file.length();
        if (len < 1000000) return;
        final name = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : file.path;
        results[file.path] = DiscoveredModelFile(
          name: name,
          path: file.path,
          sizeMb: len / (1024 * 1024),
          isLoaded: file.path == loadedPath && _snapshot.isReady,
        );
      } catch (_) {}
    }

    try {
      final dir = await _modelsDir();
      await for (final ent in dir.list()) {
        if (ent is File) await addIfValid(ent);
      }
    } catch (_) {}

    try {
      final external = await nativeApi.discoverExternalGgufPaths();
      for (final p in external) {
        await addIfValid(File(p));
      }
    } catch (_) {}

    final list = results.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _updateSnapshot(
      AiEngineSnapshot(
        status: _snapshot.status,
        loadedModelName: _snapshot.loadedModelName,
        loadedModelPath: _snapshot.loadedModelPath,
        statusMessage: _snapshot.statusMessage,
        downloadProgress: _snapshot.downloadProgress,
        downloadingId: _snapshot.downloadingId,
        lastInferenceMs: _snapshot.lastInferenceMs,
        lastParsedSummary: _snapshot.lastParsedSummary,
        discoveredFiles: list,
      ),
    );
    return list;
  }

  /// Auto-discovers any existing `.gguf` model on startup and warms it in memory cleanly.
  Future<void> autoDetectAndWarmLoad() async {
    _updateSnapshot(
      AiEngineSnapshot(
        status: AiModelStatus.scanning,
        statusMessage: 'Scanning for local Nano GGUF model...',
        discoveredFiles: _snapshot.discoveredFiles,
      ),
    );

    final files = await scanLocalModels();
    if (files.isEmpty) {
      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.unloaded,
          statusMessage:
              'No Nano GGUF found yet — download SmolLM2 360M or Qwen 0.5B in AI tab for offline NLU.',
          discoveredFiles: files,
        ),
      );
      return;
    }

    String? preferredPath;
    try {
      final sel = await _selectionFile();
      if (await sel.exists()) {
        preferredPath = (await sel.readAsString()).trim();
      }
    } catch (_) {}

    final match = files.firstWhere(
      (f) => f.path == preferredPath,
      orElse: () => files.first,
    );
    await loadModelFromPath(match.path);
  }

  Future<void> loadModelFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.error,
          statusMessage: 'Model file not found at $path',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
      return;
    }

    final fileName = file.uri.pathSegments.last;
    _updateSnapshot(
      AiEngineSnapshot(
        status: AiModelStatus.loading,
        loadedModelName: fileName,
        loadedModelPath: path,
        statusMessage: 'Warming $fileName in memory...',
        discoveredFiles: _snapshot.discoveredFiles,
      ),
    );

    await unloadModel(keepStatus: true);

    try {
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(path, format: ModelFormat.gguf)),
        params: const ModelParams(
          contextSize: 2048,
          device: ComputeDevice.cpu,
          gpuLayers: 0,
          numberOfThreads: 4,
          numberOfThreadsBatch: 4,
          batchSize: 256,
          microBatchSize: 128,
        ),
      );
      _engine = engine;
      try {
        await (await _selectionFile()).writeAsString(path);
      } catch (_) {}

      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.ready,
          loadedModelName: fileName,
          loadedModelPath: path,
          statusMessage: 'Keep-warm ready ($fileName)',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
      await scanLocalModels();
    } catch (e) {
      _engine = null;
      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.error,
          statusMessage: 'Could not load $fileName: $e',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
    }
  }

  Future<void> downloadAndWarmModel(AiCatalogEntry entry) async {
    if (_snapshot.status == AiModelStatus.downloading) return;

    final dir = await _modelsDir();
    final targetFile = File('${dir.path}/${entry.fileName}');
    if (await targetFile.exists() && await targetFile.length() > 10000000) {
      await scanLocalModels();
      await loadModelFromPath(targetFile.path);
      return;
    }

    final partFile = File('${targetFile.path}.part');
    IOSink? sink;

    try {
      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.downloading,
          downloadingId: entry.id,
          downloadProgress: 0.0,
          statusMessage: 'Downloading ${entry.title} (0%)...',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );

      final request = http.Request('GET', Uri.parse(entry.downloadUrl))
        ..headers['User-Agent'] = 'CueUI-Flutter/1.0';
      final response = await _httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? (entry.sizeMb * 1024 * 1024);
      var received = 0;
      var lastPct = -1;
      sink = partFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final frac = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        final pct = (frac * 100).round();
        if (pct != lastPct) {
          lastPct = pct;
          final mb = (received / (1024 * 1024)).toStringAsFixed(1);
          _updateSnapshot(
            AiEngineSnapshot(
              status: AiModelStatus.downloading,
              downloadingId: entry.id,
              downloadProgress: frac,
              statusMessage:
                  'Downloading ${entry.fileName} · $mb / ${entry.sizeMb} MB ($pct%)',
              discoveredFiles: _snapshot.discoveredFiles,
            ),
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (await partFile.length() < 10000000) {
        throw Exception('Downloaded file incomplete');
      }
      if (await targetFile.exists()) await targetFile.delete();
      await partFile.rename(targetFile.path);

      await scanLocalModels();
      await loadModelFromPath(targetFile.path);
    } catch (e) {
      await sink?.close();
      try {
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}
      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.error,
          statusMessage: 'Download failed for ${entry.title}: $e',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
    }
  }

  Future<void> unloadModel({bool keepStatus = false}) async {
    final old = _engine;
    _engine = null;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
    if (!keepStatus) {
      _updateSnapshot(
        AiEngineSnapshot(
          status: AiModelStatus.unloaded,
          statusMessage: 'Nano GGUF unloaded.',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
      await scanLocalModels();
    }
  }

  /// Extracts the first complete, balanced top-level JSON object from [raw].
  static Map<String, dynamic>? extractJsonObject(String raw) {
    var searchFrom = 0;
    while (searchFrom < raw.length) {
      final start = raw.indexOf('{', searchFrom);
      if (start == -1) return null;
      var depth = 0;
      var inString = false;
      var escaped = false;
      var matchedEnd = -1;
      for (var i = start; i < raw.length; i++) {
        final code = raw.codeUnitAt(i);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (code == 0x5C /* \ */ ) {
            escaped = true;
          } else if (code == 0x22 /* " */ ) {
            inString = false;
          }
          continue;
        }
        if (code == 0x22 /* " */ ) {
          inString = true;
        } else if (code == 0x7B /* { */ ) {
          depth++;
        } else if (code == 0x7D /* } */ ) {
          depth--;
          if (depth == 0) {
            matchedEnd = i;
            break;
          }
        }
      }
      if (matchedEnd == -1) return null;
      final candidate = raw.substring(start, matchedEnd + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Ignore non-JSON brace spans (e.g. prose) and scan after this '{'.
      }
      searchFrom = start + 1;
    }
    return null;
  }

  /// Investigates a messy/casual natural language query using the warm Nano GGUF model.
  Future<PlannedToolCall?> parseNaturalLanguageQuery(String query) async {
    final engine = _engine;
    final cleanQuery = query.trim();
    if (engine == null || !_snapshot.isReady || cleanQuery.isEmpty) return null;

    final sw = Stopwatch()..start();
    try {
      final messages = [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: _systemPrompt,
        ),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: cleanQuery),
      ];
      final buffer = StringBuffer();
      Map<String, dynamic>? jsonObj;
      await for (final chunk in engine.create(
        messages,
        enableThinking: false,
        responseFormat: LlamaStructuredOutput.jsonSchema(
          schema: intentJsonSchema,
          decoder: parseAiToolJson,
          name: 'cue_intent',
        ).responseFormat,
        params: const GenerationParams(
          maxTokens: 128,
          temp: 0.0,
          topK: 1,
          reusePromptPrefix: true,
        ),
      )) {
        final piece = chunk.text;
        if (piece.isEmpty) continue;
        buffer.write(piece);
        if (piece.contains('}')) {
          jsonObj = extractJsonObject(buffer.toString());
          if (jsonObj != null) break;
        }
      }
      final raw = buffer.toString().trim();
      jsonObj ??= extractJsonObject(raw);
      final call = jsonObj != null ? parseAiToolJson(jsonObj) : null;
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final rawPreview = raw.replaceAll(RegExp(r'\s+'), ' ');
      final shortRaw = rawPreview.length > 72
          ? '${rawPreview.substring(0, 72)}...'
          : rawPreview;
      final summary = call != null
          ? '${call.tool} ($ms ms)'
          : jsonObj != null
          ? 'none ($ms ms) · $shortRaw'
          : 'unparsed ($ms ms) · ${shortRaw.isEmpty ? "<empty>" : shortRaw}';
      debugPrint('[NanoAI] "$cleanQuery" -> $summary');
      _updateSnapshot(
        AiEngineSnapshot(
          status: _snapshot.status,
          loadedModelName: _snapshot.loadedModelName,
          loadedModelPath: _snapshot.loadedModelPath,
          statusMessage: _snapshot.statusMessage,
          lastInferenceMs: ms,
          lastParsedSummary: summary,
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
      return call;
    } catch (e, st) {
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final errText = e.toString().replaceAll(RegExp(r'\s+'), ' ');
      final shortErr = errText.length > 80
          ? '${errText.substring(0, 80)}...'
          : errText;
      debugPrint('[NanoAI] error on "$cleanQuery" ($ms ms): $e\n$st');
      _updateSnapshot(
        AiEngineSnapshot(
          status: _snapshot.status,
          loadedModelName: _snapshot.loadedModelName,
          loadedModelPath: _snapshot.loadedModelPath,
          statusMessage: _snapshot.statusMessage,
          lastInferenceMs: ms,
          lastParsedSummary: 'err ($ms ms): $shortErr',
          discoveredFiles: _snapshot.discoveredFiles,
        ),
      );
      return null;
    }
  }

  static PlannedToolCall? parseAiToolJson(Map<String, dynamic> json) {
    final tool = (json['tool'] ?? '').toString().trim();
    if (tool.isEmpty || tool == 'none') return null;

    final target = (json['target'] ?? '').toString().trim();
    final message = (json['message'] ?? '').toString().trim();
    final query = (json['query'] ?? '').toString().trim();
    final enabled = json['enabled'] is bool ? json['enabled'] as bool : null;
    final hour = (json['hour'] as num?)?.toInt();
    final minute = (json['minute'] as num?)?.toInt() ?? 0;
    final seconds = (json['seconds'] as num?)?.toInt();
    final percent = (json['percent'] as num?)?.toInt();
    final dayOffset = (json['dayOffset'] as num?)?.toInt() ?? 0;

    switch (tool) {
      case 'record_audio_start':
      case 'record_audio_stop':
        return PlannedToolCall(
          tool: tool,
          args: {if (message.isNotEmpty) 'title': message},
          source: 'nano_ai',
        );
      case 'record_audio_pause':
      case 'record_audio_resume':
      case 'camera_video_start':
      case 'camera_video_stop':
      case 'camera_cancel':
      case 'whatsapp_finish_voice':
      case 'whatsapp_cancel_voice':
      case 'media_stop_playback':
        return PlannedToolCall(tool: tool, source: 'nano_ai');
      case 'camera_photo':
      case 'camera_switch':
        return PlannedToolCall(
          tool: tool,
          args: {
            if (json['lens'] != null) 'lens': json['lens'],
            'countdown': ((json['countdown'] as num?)?.toInt() ?? 0).clamp(
              0,
              30,
            ),
          },
          source: 'nano_ai',
        );
      case 'whatsapp_share_media':
      case 'whatsapp_start_voice':
        if (target.isEmpty) return null;
        return PlannedToolCall(
          tool: tool,
          args: {
            'recipient': target,
            if (tool == 'whatsapp_share_media')
              'kind': {'photo', 'video', 'audio'}.contains(query) ? query : '',
          },
          source: 'nano_ai',
        );
      case 'media_play':
      case 'media_transcribe':
        return PlannedToolCall(
          tool: tool,
          args: {'query': query},
          source: 'nano_ai',
        );
      case 'run_routine':
        if (target.isEmpty && query.isEmpty) return null;
        return PlannedToolCall(
          tool: tool,
          args: {'name': target.isNotEmpty ? target : query},
          source: 'nano_ai',
        );
      case 'whatsapp_send':
        if (target.isEmpty) return null;
        if (message.isEmpty) {
          return PlannedToolCall(
            tool: 'whatsapp_prompt_message',
            args: {'recipient': target},
            source: 'nano_ai',
          );
        }
        return PlannedToolCall(
          tool: 'whatsapp_send',
          args: {'recipient': target, 'message': message},
          source: 'nano_ai',
        );
      case 'whatsapp_call':
        if (target.isEmpty) return null;
        return PlannedToolCall(
          tool: 'whatsapp_call',
          args: {'recipient': target, 'video': enabled ?? false},
          source: 'nano_ai',
        );
      case 'make_call':
        if (target.isEmpty) return null;
        return PlannedToolCall(
          tool: 'make_call',
          args: {'target': target, 'dialOnly': false},
          source: 'nano_ai',
        );
      case 'send_sms':
        if (target.isEmpty || message.isEmpty) return null;
        return PlannedToolCall(
          tool: 'send_sms',
          args: {'recipient': target, 'message': message},
          source: 'nano_ai',
        );
      case 'open_app':
        final app = target.isNotEmpty ? target : query;
        if (app.isEmpty) return null;
        return PlannedToolCall(
          tool: 'open_app',
          args: {'app': app},
          source: 'nano_ai',
        );
      case 'install_app_play_store':
        final app = target.isNotEmpty ? target : query;
        if (app.isEmpty) return null;
        return PlannedToolCall(
          tool: 'install_app_play_store',
          args: {'appName': app},
          source: 'nano_ai',
        );
      case 'spotify_play':
      case 'youtube_search':
      case 'ask_internet':
        final q = query.isNotEmpty ? query : target;
        if (q.isEmpty) return null;
        return PlannedToolCall(
          tool: tool,
          args: {'query': q},
          source: 'nano_ai',
        );
      case 'get_weather':
        return PlannedToolCall(
          tool: 'get_weather',
          args: {'location': query.isNotEmpty ? query : target},
          source: 'nano_ai',
        );
      case 'get_news':
        return PlannedToolCall(
          tool: 'get_news',
          args: {'topic': query.isNotEmpty ? query : target},
          source: 'nano_ai',
        );
      case 'open_camera':
        return PlannedToolCall(
          tool: 'open_camera',
          args: {'mode': query.isNotEmpty ? query : 'photo'},
          source: 'nano_ai',
        );
      case 'open_calendar':
      case 'read_messages':
      case 'read_notifications':
      case 'get_device_status':
        return PlannedToolCall(tool: tool, source: 'nano_ai');
      case 'add_calendar_event':
        final title = message.isNotEmpty
            ? message
            : (query.isNotEmpty ? query : 'CueUI Event');
        return PlannedToolCall(
          tool: 'add_calendar_event',
          args: {
            'title': title,
            'hour': ?hour,
            'minute': minute,
            'dayOffset': dayOffset,
          },
          source: 'nano_ai',
        );
      case 'set_alarm':
        if (hour == null) return null;
        return PlannedToolCall(
          tool: 'set_alarm',
          args: {
            'hour': hour,
            'minute': minute,
            'label': message.isNotEmpty ? message : 'CueUI Alarm',
          },
          source: 'nano_ai',
        );
      case 'set_timer':
        if (seconds == null || seconds <= 0) return null;
        return PlannedToolCall(
          tool: 'set_timer',
          args: {
            'seconds': seconds,
            'label': message.isNotEmpty ? message : 'CueUI Timer',
          },
          source: 'nano_ai',
        );
      case 'set_flashlight':
      case 'set_dnd':
        return PlannedToolCall(
          tool: tool,
          args: {'enabled': enabled ?? true},
          source: 'nano_ai',
        );
      case 'set_brightness':
        return PlannedToolCall(
          tool: 'set_brightness',
          args: {'percent': (percent ?? 50).clamp(0, 100)},
          source: 'nano_ai',
        );
      case 'open_connectivity_panel':
        final setting = query.isNotEmpty
            ? query
            : (target.isNotEmpty ? target : 'wifi');
        return PlannedToolCall(
          tool: tool,
          args: {'setting': setting, 'desired': enabled},
          source: 'nano_ai',
        );
      case 'media_control':
        final action = query.isNotEmpty
            ? query
            : (target.isNotEmpty ? target : 'play_pause');
        return PlannedToolCall(
          tool: tool,
          args: {'action': action},
          source: 'nano_ai',
        );
      case 'reply_notification':
        if (target.isEmpty || message.isEmpty) return null;
        return PlannedToolCall(
          tool: tool,
          args: {'senderQuery': target, 'message': message},
          source: 'nano_ai',
        );
      default:
        return null;
    }
  }
}
