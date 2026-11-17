import 'package:cueui_flutter/models/cue_models.dart';
import 'package:cueui_flutter/services/whatsapp_automator.dart';
import 'package:cueui_flutter/services/youtube_candidate_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWhatsAppDriver implements WhatsAppUiDriver {
  bool foreground = true;
  @override
  Future<bool> isWhatsAppForeground() async => foreground;
  final voiceStarts = <int>[];
  @override
  Future<bool> startVoiceNote(int index) async {
    voiceStarts.add(index);
    return true;
  }

  _FakeWhatsAppDriver(this.stepNodes);

  final List<List<UiNodeInfo>> stepNodes;
  int _captureCall = 0;
  final List<int> tappedIndices = [];
  String? typedText;
  int fallbackLookups = 0;
  int backPresses = 0;

  @override
  Future<bool> goBack() async {
    backPresses++;
    return true;
  }

  @override
  Future<String?> findWhatsAppPackage() async => 'com.whatsapp';

  @override
  Future<bool> launchWhatsApp(String packageName) async => true;

  @override
  Future<bool> launchWhatsAppChatByPhone(
    String packageName,
    String phoneDigits,
    String message,
  ) async => false;

  @override
  Future<String?> resolvePhoneDigits(String recipient) async {
    fallbackLookups++;
    return null;
  }

  @override
  Future<List<UiNodeInfo>> captureNodes() async {
    final idx = _captureCall < stepNodes.length
        ? _captureCall
        : stepNodes.length - 1;
    _captureCall++;
    return stepNodes[idx];
  }

  @override
  Future<bool> tapNode(int nodeIndex) async {
    tappedIndices.add(nodeIndex);
    return true;
  }

  @override
  Future<bool> typeText(String text) async {
    typedText = text;
    return true;
  }

  @override
  Future<void> pauseMs(int ms) async {}
}

UiNodeInfo _node({
  required int index,
  String className = 'android.widget.TextView',
  String text = '',
  String desc = '',
  String id = '',
  bool clickable = false,
  bool editable = false,
  bool focused = false,
  int top = 300,
}) => UiNodeInfo(
  index: index,
  className: className,
  text: text,
  contentDesc: desc,
  viewId: id,
  clickable: clickable,
  editable: editable,
  scrollable: false,
  focused: focused,
  left: 0,
  top: top,
  right: 1000,
  bottom: top + 100,
);

void main() {
  group('WhatsAppAutomator', () {
    test(
      'a stale chat cannot turn media sharing into sending its text draft',
      () async {
        final driver = _FakeWhatsAppDriver([
          [
            _node(
              index: 1,
              text: 'existing draft',
              id: 'entry',
              editable: true,
              top: 2000,
            ),
            _node(
              index: 2,
              desc: 'Send',
              id: 'send',
              clickable: true,
              top: 2000,
            ),
          ],
        ]);
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
        ).sendSharedMedia('Raihan');
        expect(result.ok, false);
        expect(driver.tappedIndices, isEmpty);
        expect(driver.typedText, isNull);
      },
    );
    List<List<UiNodeInfo>> searchSteps(List<UiNodeInfo> results) => [
      [
        _node(
          index: 0,
          desc: 'Search',
          id: 'menuitem_search',
          clickable: true,
          top: 120,
        ),
      ],
      [
        _node(
          index: 1,
          text: 'Search...',
          id: 'search_src_text',
          editable: true,
          focused: true,
          top: 130,
        ),
      ],
      [
        _node(
          index: 1,
          text: 'Raihan',
          id: 'search_src_text',
          editable: true,
          focused: true,
          top: 130,
        ),
        ...results,
      ],
    ];

    final raihans = [
      _node(
        index: 2,
        text: 'Raihan',
        id: 'contact_name',
        clickable: true,
        top: 380,
      ),
      _node(
        index: 3,
        text: 'Raihan Khan',
        id: 'contact_name',
        clickable: true,
        top: 580,
      ),
    ];

    test('media sharing selects a contact then submits the preview', () async {
      final driver = _FakeWhatsAppDriver([
        ...searchSteps([raihans.first]),
        [_node(index: 4, desc: 'Send', id: 'send', clickable: true, top: 2000)],
        [_node(index: 5, desc: 'Send', id: 'send', clickable: true, top: 2000)],
      ]);
      final result = await WhatsAppAutomator(
        driver,
        launchWaitMs: 0,
        stepWaitMs: 0,
        searchWaitMs: 0,
      ).sendSharedMedia('Raihan');
      expect(result.ok, true);
      expect(driver.tappedIndices, [0, 2, 4, 5]);
    });
    test(
      'media sharing stops before preview when recipient is ambiguous',
      () async {
        final driver = _FakeWhatsAppDriver(searchSteps(raihans));
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendSharedMedia('Raihan');
        expect(result.ok, false);
        expect(result.data['whatsappRecipients'], ['Raihan', 'Raihan Khan']);
        expect(driver.tappedIndices, [0]);
      },
    );
    test(
      'locked WhatsApp voice recording is verified before sending',
      () async {
        final driver = _FakeWhatsAppDriver([
          ...searchSteps([raihans.first]),
          [
            _node(
              index: 3,
              text: 'Message',
              id: 'entry',
              editable: true,
              top: 2000,
            ),
            _node(
              index: 4,
              desc: 'Voice message',
              id: 'voice_note_btn',
              clickable: true,
              top: 2000,
            ),
          ],
          [
            _node(
              index: 5,
              desc: 'Send',
              id: 'send',
              clickable: true,
              top: 2000,
            ),
            _node(
              index: 6,
              desc: 'Delete voice message',
              clickable: true,
              top: 2000,
            ),
          ],
        ]);
        final automator = WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        );
        final started = await automator.startVoiceMessage('Raihan');
        expect(started.ok, true);
        expect(driver.voiceStarts, [4]);
        final sent = await automator.finishVoiceMessage(cancel: false);
        expect(sent.ok, true);
        expect(driver.tappedIndices.last, 5);
      },
    );
    test(
      'finished voice note never sends an unrelated existing text draft',
      () async {
        final driver = _FakeWhatsAppDriver([
          [
            _node(
              index: 5,
              desc: 'Send',
              id: 'send',
              clickable: true,
              top: 2000,
            ),
          ],
        ]);
        final result = await WhatsAppAutomator(
          driver,
        ).finishVoiceMessage(cancel: false);
        expect(result.ok, false);
        expect(result.data['recordingAbsent'], true);
        expect(driver.tappedIndices, isEmpty);
      },
    );
    test(
      'does not type or send after WhatsApp leaves the foreground',
      () async {
        final driver = _FakeWhatsAppDriver(searchSteps([raihans.first]))
          ..foreground = false;
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendMessage('Raihan', 'hi');
        expect(result.ok, false);
        expect(driver.typedText, isNull);
        expect(driver.tappedIndices, isEmpty);
      },
    );

    test(
      'returns from an existing chat before searching for the recipient',
      () async {
        final driver = _FakeWhatsAppDriver([
          [
            _node(
              index: 9,
              text: 'Message',
              id: 'entry',
              editable: true,
              top: 2000,
            ),
          ],
          ...searchSteps(raihans),
        ]);
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendMessage('Raihan', 'hi');
        expect(driver.backPresses, 1);
        expect(result.data['whatsappRecipients'], ['Raihan', 'Raihan Khan']);
        expect(driver.tappedIndices, [0]);
      },
    );

    test(
      'asks about multiple matches, even with an exact match, without opening or sending',
      () async {
        final driver = _FakeWhatsAppDriver(searchSteps(raihans));
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendMessage('Raihan', 'hi');
        expect(result.ok, false);
        expect(result.data['whatsappRecipients'], ['Raihan', 'Raihan Khan']);
        expect(driver.tappedIndices, [0]);
        expect(driver.typedText, 'Raihan');
        expect(driver.fallbackLookups, 0);
      },
    );

    test(
      'rechecks search results and sends the original message only to the chosen name',
      () async {
        final driver = _FakeWhatsAppDriver([
          ...searchSteps(raihans),
          [
            _node(
              index: 4,
              text: 'Message',
              id: 'entry',
              editable: true,
              focused: true,
              top: 2000,
            ),
          ],
          [
            _node(
              index: 5,
              desc: 'Send',
              id: 'send',
              clickable: true,
              top: 2000,
            ),
          ],
        ]);
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendMessage('Raihan', 'hi', selectedChat: 'Raihan Khan');
        expect(result.ok, true);
        expect(driver.tappedIndices, [0, 3, 5]);
        expect(driver.typedText, 'hi');
        expect(result.summary, contains('Raihan Khan'));
      },
    );

    test(
      'does not substitute another recipient if the selected name disappears',
      () async {
        final driver = _FakeWhatsAppDriver(searchSteps([raihans.first]));
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendMessage('Raihan', 'hi', selectedChat: 'Raihan Khan');
        expect(result.ok, false);
        expect(driver.tappedIndices, [0]);
        expect(driver.fallbackLookups, 0);
      },
    );

    test(
      'deduplicates overlapping labels but keeps separate people with identical names',
      () {
        final matches = WhatsAppAutomator.findMatchingChatRows(
          [
            raihans.first,
            _node(index: 4, text: 'Raihan', id: 'contact_name', top: 390),
            _node(index: 5, text: 'Raihan', id: 'contact_name', top: 580),
            _node(
              index: 6,
              text: 'Raihan sent a photo',
              id: 'message_snippet',
              clickable: true,
              top: 780,
            ),
          ],
          'Raihan',
          230,
        );
        expect(matches.map((node) => node.index), [2, 5]);
      },
    );

    test(
      'does not send when the command is cancelled during automation',
      () async {
        final driver = _FakeWhatsAppDriver([
          ...searchSteps([raihans.first]),
          [
            _node(
              index: 4,
              text: 'Message',
              id: 'entry',
              editable: true,
              focused: true,
              top: 2000,
            ),
          ],
          [
            _node(
              index: 5,
              desc: 'Send',
              id: 'send',
              clickable: true,
              top: 2000,
            ),
          ],
        ]);
        final result = await WhatsAppAutomator(
          driver,
          launchWaitMs: 0,
          stepWaitMs: 0,
          searchWaitMs: 0,
        ).sendMessage('Raihan', 'hi', canContinue: () => false);
        expect(result.ok, false);
        expect(driver.tappedIndices, isNot(contains(5)));
        expect(driver.typedText, 'Raihan');
      },
    );

    test('opens chat from search, enters message, and taps Send', () async {
      final driver = _FakeWhatsAppDriver([
        [
          _node(
            index: 0,
            desc: 'Search',
            id: 'menuitem_search',
            clickable: true,
            top: 120,
          ),
        ],
        [
          _node(
            index: 1,
            text: 'Search...',
            id: 'search_src_text',
            editable: true,
            focused: true,
            top: 130,
          ),
        ],
        [
          _node(
            index: 1,
            text: 'Ali',
            id: 'search_src_text',
            editable: true,
            focused: true,
            top: 130,
          ),
          _node(
            index: 2,
            text: 'Ali Khan',
            id: 'contact_name',
            clickable: true,
            top: 380,
          ),
        ],
        [
          _node(
            index: 3,
            text: 'Message',
            id: 'entry',
            editable: true,
            focused: true,
            top: 2000,
          ),
        ],
        [
          _node(
            index: 3,
            text: 'hello there',
            id: 'entry',
            editable: true,
            focused: true,
            top: 2000,
          ),
          _node(index: 4, desc: 'Send', id: 'send', clickable: true, top: 2000),
        ],
      ]);

      final automator = WhatsAppAutomator(
        driver,
        launchWaitMs: 0,
        stepWaitMs: 0,
        searchWaitMs: 0,
      );
      final res = await automator.sendMessage('Ali', 'hello there');
      expect(res.ok, true);
      expect(res.summary, contains('Ali Khan'));
      expect(driver.typedText, 'hello there');
      expect(driver.tappedIndices, [0, 2, 4]);
    });
  });

  group('YouTubeCandidateExtractor', () {
    test(
      'skips sponsored ads and CueUI chrome while keeping real video candidates',
      () {
        final nodes = [
          _node(
            index: 0,
            desc: 'Sponsored Ad Buy Now - Go to site',
            clickable: true,
            top: 280,
          ),
          _node(
            index: 1,
            desc:
                'Lofi Hip Hop Radio - Beats to Study to - play video - 2 hours',
            clickable: true,
            top: 640,
          ),
          _node(
            index: 2,
            text: 'CueUI listening...',
            clickable: true,
            top: 900,
          ),
        ];
        final list = YouTubeCandidateExtractor.extract(nodes, query: 'lofi');
        expect(list.length, 1);
        expect(list.single.title, 'Lofi Hip Hop Radio - Beats to Study to');
        expect(list.single.nodeIndex, 1);
      },
    );
  });
}
