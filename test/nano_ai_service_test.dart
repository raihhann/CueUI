import 'package:cueui_flutter/services/nano_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('NanoAiService', () {
    test(
      'structured JSON schema validates cleanly against llamadart GBNF converter',
      () {
        final output = LlamaStructuredOutput.jsonSchema(
          schema: NanoAiService.intentJsonSchema,
          decoder: NanoAiService.parseAiToolJson,
          name: 'cue_intent',
        );
        expect(output.responseFormat['type'], 'json_schema');
      },
    );

    test(
      'parseAiToolJson maps casual NLU schema outputs into CueUI PlannedToolCalls',
      () {
        final wa = NanoAiService.parseAiToolJson({
          'tool': 'whatsapp_send',
          'target': 'Rahul',
          'message': 'reaching in 10 mins',
        })!;
        expect(wa.tool, 'whatsapp_send');
        expect(wa.source, 'nano_ai');
        expect(wa.args['recipient'], 'Rahul');
        expect(wa.args['message'], 'reaching in 10 mins');

        final waMissingMsg = NanoAiService.parseAiToolJson({
          'tool': 'whatsapp_send',
          'target': 'Rahul',
        })!;
        expect(waMissingMsg.tool, 'whatsapp_prompt_message');
        expect(waMissingMsg.args['recipient'], 'Rahul');

        final cal = NanoAiService.parseAiToolJson({
          'tool': 'add_calendar_event',
          'message': 'Dentist',
          'hour': 9,
          'minute': 30,
          'dayOffset': 1,
        })!;
        expect(cal.tool, 'add_calendar_event');
        expect(cal.args['title'], 'Dentist');
        expect(cal.args['hour'], 9);
        expect(cal.args['minute'], 30);
        expect(cal.args['dayOffset'], 1);

        expect(NanoAiService.parseAiToolJson({'tool': 'none'}), isNull);
      },
    );

    test(
      'extractJsonObject parses balanced raw, fenced, and prose-wrapped JSON cleanly',
      () {
        expect(
          NanoAiService.extractJsonObject(
            '{"tool":"whatsapp_send","target":"Ali","message":"reached"}',
          ),
          {'tool': 'whatsapp_send', 'target': 'Ali', 'message': 'reached'},
        );
        expect(
          NanoAiService.extractJsonObject(
            '```json\n{"tool": "weather", "target": "Tokyo"}\n```',
          ),
          {'tool': 'weather', 'target': 'Tokyo'},
        );
        expect(
          NanoAiService.extractJsonObject(
            'ignore {not json} -> {"tool":"play_store","target":"Discord","msg":"see {1}"} done',
          ),
          {'tool': 'play_store', 'target': 'Discord', 'msg': 'see {1}'},
        );
        expect(NanoAiService.extractJsonObject('no json here'), isNull);
        expect(NanoAiService.extractJsonObject('{"tool": "cut_off"'), isNull);
      },
    );
  });
}
