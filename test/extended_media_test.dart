import 'package:cueui_flutter/models/cue_models.dart';
import 'package:cueui_flutter/services/media_service.dart';
import 'package:cueui_flutter/services/native_bridge.dart';
import 'package:cueui_flutter/services/offline_intent_router.dart';
import 'package:cueui_flutter/services/routine_service.dart';
import 'package:cueui_flutter/services/tool_dispatcher.dart';
import 'package:cueui_flutter/services/internet_search_service.dart';
import 'package:cueui_flutter/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

class _MediaNative implements CueNativeApi {
  final actions = <String>[];
  bool failDnd = false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
  @override
  Future<ToolExecutionResult> mediaCommand(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    actions.add(action);
    return ToolExecutionResult(
      ok: true,
      summary: 'Done $action',
      data: {
        if (action == 'stop_audio' || action == 'take_photo')
          'media': {
            'id': 'sample.wav',
            'title': args['title'] ?? 'Idea',
            'kind': action == 'take_photo' ? 'photo' : 'audio',
            'path': '/private/sample.wav',
            'createdAt': 1,
            'durationMs': 3000,
            'transcript': 'remember the blue notebook',
          },
        if (action == 'start_audio')
          'recording': {'active': true, 'paused': false},
        if (action == 'pause_audio')
          'recording': {'active': true, 'paused': true},
        if (action == 'resume_audio')
          'recording': {'active': true, 'paused': false},
      },
    );
  }

  @override
  Future<ToolExecutionResult> setBrightness(int percent) async {
    actions.add('brightness:$percent');
    return const ToolExecutionResult(ok: true, summary: 'Brightness changed');
  }

  @override
  Future<ToolExecutionResult> setDnd(bool enabled) async {
    actions.add('dnd:$enabled');
    return ToolExecutionResult(
      ok: !failDnd,
      summary: failDnd ? 'DND permission required' : 'DND changed',
      data: failDnd ? {'missingPermissionKey': 'DND_ACCESS'} : {},
    );
  }

  @override
  Future<ToolExecutionResult> setAlarm({
    required int hour,
    required int minute,
    required String label,
  }) async {
    actions.add('alarm:$hour:$minute');
    return const ToolExecutionResult(ok: true, summary: 'Alarm set');
  }
}

void main() {
  test('routine edits persist and renaming replaces the old routine', () async {
    final directory = Directory(
      'build/routine-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/routines.json');
    final service = CueRoutineService(storageFile: () async => file);
    await service.save(
      const CueRoutine('Study', [
        PlannedToolCall(tool: 'set_brightness', args: {'percent': 35}),
      ]),
      originalName: 'Focus',
    );
    expect(service.find('Focus'), isNull);
    expect(service.find('Study'), isNotNull);
    final reloaded = CueRoutineService(storageFile: () async => file);
    await reloaded.load();
    expect(reloaded.find('Study')!.steps.single.args['percent'], 35);
    await file.delete();
    await directory.delete();
    service.dispose();
    reloaded.dispose();
  });
  test('routes the full recording lifecycle and named save', () {
    final cases = {
      'start recording': 'record_audio_start',
      'pause recording': 'record_audio_pause',
      'resume recording': 'record_audio_resume',
      'stop and save as meeting notes': 'record_audio_stop',
      'play the latest recording': 'media_play',
      'transcribe the latest recording': 'media_transcribe',
      'stop playback': 'media_stop_playback',
    };
    for (final entry in cases.entries) {
      expect(
        OfflineIntentRouter.route(entry.key)!.single.tool,
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      OfflineIntentRouter.route(
        'stop and save as meeting notes',
      )!.single.args['title'],
      'meeting notes',
    );
  });
  test('routes capture, countdown, switching, video and chained sharing', () {
    final plan = OfflineIntentRouter.route(
      'take a selfie in 3 seconds then send this photo to Raihan on WhatsApp',
    )!;
    expect(plan.map((call) => call.tool), [
      'camera_photo',
      'whatsapp_share_media',
    ]);
    expect(plan.first.args, {'lens': 'front', 'countdown': 3});
    expect(plan.last.args, {'kind': 'photo', 'recipient': 'Raihan'});
    for (final entry in {
      'switch camera': 'camera_switch',
      'start video recording': 'camera_video_start',
      'stop video': 'camera_video_stop',
      'cancel countdown': 'camera_cancel',
    }.entries) {
      expect(OfflineIntentRouter.route(entry.key)!.single.tool, entry.value);
    }
  });
  test(
    'recognizes voice messages, dictation, pronouns and custom routines',
    () {
      expect(
        OfflineIntentRouter.route(
          'record a voice message to Raihan on WhatsApp',
        )!.single.args['recipient'],
        'Raihan',
      );
      expect(
        OfflineIntentRouter.route('send voice note')!.single.tool,
        'whatsapp_finish_voice',
      );
      expect(
        OfflineIntentRouter.route('cancel voice note')!.single.tool,
        'whatsapp_cancel_voice',
      );
      expect(
        OfflineIntentRouter.route('dictate a message to Raihan')!.single.tool,
        'whatsapp_prompt_message',
      );
      expect(
        OfflineIntentRouter.route('send it to him')!.single.args['recipient'],
        'him',
      );
      expect(
        OfflineIntentRouter.route('run my bedtime routine')!.single.tool,
        'run_routine',
      );
      expect(
        OfflineIntentRouter.route('run routine Study')!.single.args['name'],
        'Study',
      );
    },
  );
  test(
    'recording state, saved files and transcript search work together',
    () async {
      final native = _MediaNative();
      final media = CueMediaService(native);
      await media.command('start_audio');
      expect(media.recording['active'], true);
      await media.command('pause_audio');
      expect(media.recording['paused'], true);
      await media.command('resume_audio');
      expect(media.recording['paused'], false);
      await media.command('stop_audio', {'title': 'Meeting notes'});
      expect(media.recording['active'], false);
      expect(media.latest('audio')!.title, 'Meeting notes');
      expect(media.search('BLUE').single.title, 'Meeting notes');
      await media.command('delete', {'id': 'sample.wav'});
      expect(media.items, isEmpty);
      media.dispose();
    },
  );
  test(
    'routines stop on a failed action without setting the later alarm',
    () async {
      final native = _MediaNative()..failDnd = true;
      final dispatcher = CueToolDispatcher(
        nativeApi: native,
        internetSearch: InternetSearchService(),
        weatherService: WeatherService(),
        confirmAction: (_) async => true,
      );
      final result = await dispatcher.execute(
        const PlannedToolCall(tool: 'run_routine', args: {'name': 'bedtime'}),
      );
      expect(result.ok, false);
      expect(native.actions, ['brightness:15', 'dnd:true']);
      expect(result.data['missingPermissionKey'], 'DND_ACCESS');
    },
  );
  test(
    'routine definitions reject actions that are not exposed by the editor',
    () {
      expect(
        () => CueRoutine.fromJson({
          'name': 'Bad',
          'steps': [
            {'tool': 'send_sms', 'args': {}},
          ],
        }),
        throwsFormatException,
      );
    },
  );
}
