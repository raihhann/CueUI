import 'package:flutter/foundation.dart';
import '../models/cue_models.dart';
import 'native_bridge.dart';

class CapturedMedia {
  const CapturedMedia({
    required this.id,
    required this.title,
    required this.kind,
    required this.path,
    required this.createdAt,
    this.durationMs = 0,
    this.transcript = '',
  });
  final String id, title, kind, path, transcript;
  final int createdAt, durationMs;
  factory CapturedMedia.fromMap(Map<dynamic, dynamic> map) => CapturedMedia(
    id: '${map['id']}',
    title: '${map['title']}',
    kind: '${map['kind']}',
    path: '${map['path']}',
    createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
    durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    transcript: '${map['transcript'] ?? ''}',
  );
}

class CueMediaService extends ChangeNotifier {
  CueMediaService(this.nativeApi);
  final CueNativeApi nativeApi;
  List<CapturedMedia> items = const [];
  Map<String, dynamic> recording = const {};
  bool videoActive = false;
  String? notice;
  bool _disposed = false;
  CapturedMedia? latest([String? kind]) =>
      items.where((item) => kind == null || item.kind == kind).firstOrNull;
  List<CapturedMedia> search(String query) => items
      .where(
        (item) => '${item.title} ${item.transcript}'.toLowerCase().contains(
          query.trim().toLowerCase(),
        ),
      )
      .toList();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void acceptResult(ToolExecutionResult result) {
    final saved = result.data['media'];
    if (saved is Map) {
      final item = CapturedMedia.fromMap(saved);
      if (item.kind == 'video') videoActive = false;
      items = [item, ...items.where((other) => other.id != item.id)]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final state = result.data['recording'];
    if (result.data.containsKey('videoActive')) {
      videoActive = result.data['videoActive'] == true;
    }
    if (state is Map) recording = Map<String, dynamic>.from(state);
    _notify();
  }

  Future<void> refresh() async {
    try {
      final result = await nativeApi.mediaCommand('list');
      if (result.ok) {
        final raw = result.data['items'];
        if (raw is List) {
          items = raw.whereType<Map>().map(CapturedMedia.fromMap).toList();
        }
        acceptResult(result);
      }
      final state = await nativeApi.mediaCommand('state');
      videoActive = state.data['videoActive'] == true;
      acceptResult(state);
    } catch (error) {
      notice = 'Media library unavailable: $error';
      _notify();
    }
  }

  Future<ToolExecutionResult> command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    try {
      final result = await nativeApi.mediaCommand(action, args);
      notice = result.summary;
      acceptResult(result);
      if (result.ok && action == 'start_video') videoActive = true;
      if (result.ok && action == 'stop_video') videoActive = false;
      if (result.ok && action == 'stop_audio') {
        recording = const {'active': false};
      }
      if (result.ok && action == 'delete') {
        items = items.where((item) => item.id != args['id']).toList();
      }
      _notify();
      return result;
    } catch (error) {
      notice = 'Media action failed: $error';
      _notify();
      return ToolExecutionResult(ok: false, summary: notice!);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
