import 'package:cueui_flutter/services/offline_intent_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineIntentRouter', () {
    test('routes message-first WhatsApp requests without a local AI model', () {
      final call = OfflineIntentRouter.route(
        'send hi to raihan on whatsapp',
      )!.single;
      expect(call.tool, 'whatsapp_send');
      expect(call.args, {'recipient': 'raihan', 'message': 'hi'});
      final quoted = OfflineIntentRouter.route(
        'please send "Hello there" to Raihan Khan via WhatsApp please',
      )!.single;
      expect(quoted.args, {
        'recipient': 'Raihan Khan',
        'message': 'Hello there',
      });
      expect(
        OfflineIntentRouter.route(
          'send a message to Raihan on WhatsApp',
        )!.single.tool,
        'whatsapp_prompt_message',
      );
    });
    test('routes calls, WhatsApp, Spotify, YouTube, Play Store', () {
      final wa = OfflineIntentRouter.route(
        'open WhatsApp and message Ali saying hey there',
      )!;
      expect(wa.single.tool, 'whatsapp_send');
      expect(wa.single.args['recipient'], 'Ali');
      expect(wa.single.args['message'], 'hey there');

      final waCall = OfflineIntentRouter.route('video call Sara on WhatsApp')!;
      expect(waCall.single.tool, 'whatsapp_call');
      expect(waCall.single.args['recipient'], 'Sara');
      expect(waCall.single.args['video'], true);

      final sp = OfflineIntentRouter.route('play chill jazz on spotify')!;
      expect(sp.single.tool, 'spotify_play');
      expect(sp.single.args['query'], 'chill jazz');

      final yt = OfflineIntentRouter.route('play lofi music on youtube')!;
      expect(yt.single.tool, 'youtube_search');
      expect(yt.single.args['query'], 'lofi music');

      final install = OfflineIntentRouter.route(
        'install Spotify from Play Store',
      )!;
      expect(install.single.tool, 'install_app_play_store');
      expect(install.single.args['appName'], 'Spotify');
    });

    test(
      'routes camera, calendar, alarm, timer, weather, news, and web QA',
      () {
        final cam = OfflineIntentRouter.route('take a selfie')!;
        expect(cam.single.tool, 'camera_photo');
        expect(cam.single.args['lens'], 'front');

        final cal = OfflineIntentRouter.route(
          'schedule Team Sync tomorrow at 3:30 pm',
        )!;
        expect(cal.single.tool, 'add_calendar_event');
        expect(cal.single.args['title'], 'Team Sync');
        expect(cal.single.args['hour'], 15);
        expect(cal.single.args['minute'], 30);
        expect(cal.single.args['dayOffset'], 1);

        final alarm = OfflineIntentRouter.route(
          'set an alarm for 6:45 am labeled Wake up',
        )!;
        expect(alarm.single.tool, 'set_alarm');
        expect(alarm.single.args['hour'], 6);
        expect(alarm.single.args['minute'], 45);
        expect(alarm.single.args['label'], 'Wake up');

        final timer = OfflineIntentRouter.route(
          'set a 5 minute timer for Tea',
        )!;
        expect(timer.single.tool, 'set_timer');
        expect(timer.single.args['seconds'], 300);

        final news = OfflineIntentRouter.route('what is the current hot news')!;
        expect(news.single.tool, 'get_news');
        expect(news.single.args['topic'], '');

        final def = OfflineIntentRouter.route('what does ephemeral mean?')!;
        expect(def.single.tool, 'ask_internet');

        final weather = OfflineIntentRouter.route(
          "what's the weather in Tokyo",
        )!;
        expect(weather.single.tool, 'get_weather');
        expect(weather.single.args['location'], 'Tokyo');
      },
    );

    test(
      'routes multi-clause chains and returns null on casual unstructured NL',
      () {
        final chain = OfflineIntentRouter.route(
          'turn on flashlight and then go home',
        )!;
        expect(chain.length, 2);
        expect(chain[0].tool, 'set_flashlight');
        expect(chain[0].args['enabled'], true);
        expect(chain[1].tool, 'press_key');
        expect(chain[1].args['key'], 'HOME');

        expect(
          OfflineIntentRouter.route(
            'yo could you drop rahul a quick ping i am five mins away',
          ),
          isNull,
        );
      },
    );
  });
}
