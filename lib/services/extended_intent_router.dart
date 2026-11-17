import '../models/cue_models.dart';

/// Media commands take priority over generic app-launch and web rules.
class ExtendedIntentRouter {
  static PlannedToolCall? route(String input) {
    final text = input
        .trim()
        .replaceFirst(
          RegExp(r'^(?:please|can you|could you)\s+', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'[.!?]+$'), '');
    final lower = text.toLowerCase();
    final sharing = RegExp(
      r'^(?:send|share)\s+(?:(?:this|the|my|last|latest)\s+)?(photo|picture|image|video|audio|recording|voice recording|it)\s+to\s+(.+?)(?:\s+(?:on|via|in)\s+whatsapp)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (sharing != null) {
      return PlannedToolCall(
        tool: 'whatsapp_share_media',
        args: {
          'kind': switch (sharing.group(1)!.toLowerCase()) {
            'photo' || 'picture' || 'image' => 'photo',
            'video' => 'video',
            'it' => '',
            _ => 'audio',
          },
          'recipient': sharing.group(2)!,
        },
      );
    }
    final voiceNote = RegExp(
      r'^(?:record|send|start)\s+(?:a\s+)?(?:whatsapp\s+)?voice\s+(?:note|message)\s+(?:to|for)\s+(.+?)(?:\s+(?:on|via)\s+whatsapp)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (voiceNote != null) {
      return PlannedToolCall(
        tool: 'whatsapp_start_voice',
        args: {'recipient': voiceNote.group(1)!},
      );
    }
    if (const {
      'send voice note',
      'send voice message',
      'stop and send voice note',
      'stop and send voice message',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'whatsapp_finish_voice');
    }
    if (const {
      'cancel voice note',
      'cancel voice message',
      'discard voice note',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'whatsapp_cancel_voice');
    }
    final dictation = RegExp(
      r'^(?:dictate|compose)\s+(?:a\s+)?(?:message|text)\s+(?:to|for)\s+(.+?)(?:\s+on\s+whatsapp)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (dictation != null) {
      return PlannedToolCall(
        tool: 'whatsapp_prompt_message',
        args: {'recipient': dictation.group(1)!},
      );
    }
    if (const {
      'start recording',
      'start audio recording',
      'record audio',
      'record a voice note',
      'start recorder',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'record_audio_start');
    }
    final audioStart = RegExp(
      r'^start (?:audio )?recording (?:as|called|named) (.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (audioStart != null) {
      return PlannedToolCall(
        tool: 'record_audio_start',
        args: {'title': audioStart.group(1)!},
      );
    }
    if (const {
      'pause',
      'pause recording',
      'pause audio',
      'pause audio recording',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'record_audio_pause');
    }
    if (const {
      'resume recording',
      'resume audio',
      'resume audio recording',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'record_audio_resume');
    }
    final stop = RegExp(
      r'^(?:stop(?: (?:audio )?recording)?(?: and save)?|save recording)(?: as (.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (stop != null) {
      return PlannedToolCall(
        tool: 'record_audio_stop',
        args: {if (stop.group(1) != null) 'title': stop.group(1)!},
      );
    }
    if (const {'stop playback', 'stop playing'}.contains(lower)) {
      return const PlannedToolCall(tool: 'media_stop_playback');
    }
    final playback = RegExp(
      r'^(?:play|play back|playback)\s+(?:the\s+)?(?:(?:last|latest|this)\s+)?(?:recording|audio)(?:\s+(?:called|named)\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (playback != null) {
      return PlannedToolCall(
        tool: 'media_play',
        args: {'query': playback.group(1) ?? '', 'kind': 'audio'},
      );
    }
    final transcribe = RegExp(
      r'^transcribe(?:\s+(?:the|my|this|last|latest))*(?:\s+(?:recording|audio))?(?:\s+(?:called|named)\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (transcribe != null) {
      return PlannedToolCall(
        tool: 'media_transcribe',
        args: {'query': transcribe.group(1) ?? '', 'kind': 'audio'},
      );
    }
    final photo = RegExp(
      r'^(?:take|capture|snap)\s+(?:a\s+)?(photo|picture|selfie)(?:\s+(?:in|after|with a)\s+(\d+)\s*(?:seconds?|s)(?:\s+countdown)?)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (photo != null) {
      return PlannedToolCall(
        tool: 'camera_photo',
        args: {
          if (photo.group(1)!.toLowerCase() == 'selfie') 'lens': 'front',
          'countdown': int.tryParse(photo.group(2) ?? '') ?? 0,
        },
      );
    }
    if (const {
      'start video',
      'start video recording',
      'record video',
      'record a video',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'camera_video_start');
    }
    if (const {
      'stop video',
      'stop video recording',
      'stop filming',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'camera_video_stop');
    }
    if (const {
      'cancel photo',
      'cancel countdown',
      'cancel capture',
    }.contains(lower)) {
      return const PlannedToolCall(tool: 'camera_cancel');
    }
    if (const {
      'switch camera',
      'flip camera',
      'front camera',
      'back camera',
      'switch to front camera',
      'switch to back camera',
    }.contains(lower)) {
      return PlannedToolCall(
        tool: 'camera_switch',
        args: {
          if (lower.contains('front')) 'lens': 'front',
          if (lower.contains('back')) 'lens': 'back',
        },
      );
    }
    final routine = RegExp(
      r'^(?:run\s+)?(?:my\s+)?(?:routine\s+)?(bedtime|morning|focus)(?:\s+routine)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (routine != null) {
      return PlannedToolCall(
        tool: 'run_routine',
        args: {'name': routine.group(1)!.toLowerCase()},
      );
    }
    final custom = RegExp(
      r'^run (?:my )?routine (.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (custom != null) {
      return PlannedToolCall(
        tool: 'run_routine',
        args: {'name': custom.group(1)!},
      );
    }
    return null;
  }
}
