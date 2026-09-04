// What Milo is told, and what it remembers.
//
// Two things under test: the one system prompt both engines are given, and
// the guard that stops the background summariser running on every turn.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/models/pc_command.dart';
import 'package:cotv/src/models/study_view.dart';
import 'package:cotv/src/services/milo/gemini_client.dart';
import 'package:cotv/src/services/milo/memory_summarizer.dart';
import 'package:cotv/src/services/milo/milo_context_builder.dart';

MiloContext _context({
  List<SubjectStudyTotal> studyToday = const [],
  int studyTodayMinutes = 0,
  String? activeStudySubject,
  Duration? activeStudyRemaining,
  List<String> subjectNames = const ['Physiology', 'Anatomy'],
  String? memorySummary,
  List<ChatTurn> recalledTurns = const [],
}) {
  return MiloContext(
    now: DateTime(2026, 9, 2, 15, 34),
    nextPrayer: 'Asr',
    nextPrayerTime: DateTime(2026, 9, 2, 16, 12),
    isLockedOut: false,
    openTaskCount: 2,
    nextTaskTitles: const ['Anatomy revision', 'Pharmacology deck'],
    studyToday: studyToday,
    studyTodayMinutes: studyTodayMinutes,
    activeStudySubject: activeStudySubject,
    activeStudyRemaining: activeStudyRemaining,
    subjectNames: subjectNames,
    memorySummary: memorySummary,
    recalledTurns: recalledTurns,
  );
}

SubjectStudyTotal _total(String name, int today) => SubjectStudyTotal(
      subjectId: name.toLowerCase(),
      subjectName: name,
      todayMinutes: today,
      weekMinutes: today,
      todaySessions: 1,
    );

ChatTurn _user(String text) => ChatTurn(role: MiloRole.user, text: text);
ChatTurn _milo(String text) => ChatTurn(role: MiloRole.assistant, text: text);

/// A Gemini stream returning [text] in one frame.
http.Client _gemini(String text, {List<http.Request>? capture}) {
  return MockClient.streaming((request, body) async {
    capture?.add(request as http.Request);
    final frame = 'data: ${jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
            },
          ],
        })}\n\n';
    return http.StreamedResponse(
      Stream.value(utf8.encode(frame)),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  });
}

void main() {
  const builder = MiloContextBuilder();

  group('MiloContextBuilder', () {
    test('carries the prayer and task facts the old prompt block did', () {
      final prompt = builder.build(context: _context(), history: const []);

      expect(prompt, contains('Next prayer: Asr at 16:12'));
      expect(prompt, contains('Prayer lockout: not active'));
      expect(prompt, contains('Open tasks: 2'));
      expect(prompt, contains('Anatomy revision'));
    });

    test("states today's study totals per subject", () {
      final prompt = builder.build(
        context: _context(
          studyToday: [_total('Physiology', 90), _total('Anatomy', 25)],
          studyTodayMinutes: 115,
        ),
        history: const [],
      );

      expect(prompt, contains('Studied today: 1h 55m'));
      expect(prompt, contains('Physiology 1h 30m'));
      expect(prompt, contains('Anatomy 25m'));
    });

    test('says so plainly when nothing has been studied', () {
      final prompt = builder.build(context: _context(), history: const []);

      expect(prompt, contains('Studied today: nothing yet'));
      expect(prompt, contains('Study timer: not running'));
    });

    test('names the running session and the time left on it', () {
      final prompt = builder.build(
        context: _context(
          activeStudySubject: 'Physiology',
          activeStudyRemaining: const Duration(minutes: 21, seconds: 30),
        ),
        history: const [],
      );

      expect(prompt, contains('Study timer: running on Physiology'));
      expect(prompt, contains('21m 30s left'));
    });

    test('lists the subjects that exist, so none has to be invented', () {
      final prompt = builder.build(context: _context(), history: const []);

      expect(prompt, contains('Subjects: Physiology, Anatomy'));
    });

    test('says when there are no subjects at all', () {
      final prompt = builder.build(
        context: _context(subjectNames: const []),
        history: const [],
      );

      expect(prompt, contains('Subjects: none set up yet'));
    });

    test('includes the memory summary under its own heading', () {
      final prompt = builder.build(
        context: _context(
          memorySummary: 'Studies medicine. Prefers 45-minute blocks.',
        ),
        history: const [],
      );

      expect(prompt, contains('WHAT YOU KNOW ABOUT THIS USER'));
      expect(prompt, contains('Prefers 45-minute blocks.'));
    });

    test('leaves the memory heading out when there is no summary', () {
      final prompt = builder.build(context: _context(), history: const []);

      expect(prompt, isNot(contains('WHAT YOU KNOW ABOUT THIS USER')));
    });

    test('treats a blank summary as no summary', () {
      final prompt = builder.build(
        context: _context(memorySummary: '   '),
        history: const [],
      );

      expect(prompt, isNot(contains('WHAT YOU KNOW ABOUT THIS USER')));
    });

    test('recalls earlier turns on a fresh session', () {
      final prompt = builder.build(
        context: _context(
          recalledTurns: [
            _user('how long did I do on physiology yesterday'),
            _milo('Ninety minutes across two sessions.'),
          ],
        ),
        // A fresh panel: nothing is being sent as live history.
        history: const [],
      );

      expect(prompt, contains('EARLIER CONVERSATION'));
      expect(prompt, contains('User: how long did I do on physiology'));
      expect(prompt, contains('Milo: Ninety minutes across two sessions.'));
    });

    test('does not repeat turns already being sent as live history', () {
      // The durable transcript contains the same two turns the panel is
      // sending, plus two older ones. Only the older pair should recall.
      final prompt = builder.build(
        context: _context(
          recalledTurns: [
            _user('older question'),
            _milo('older answer'),
            _user('live question'),
            _milo('live answer'),
          ],
        ),
        history: [_user('live question'), _milo('live answer')],
      );

      expect(prompt, contains('older question'));
      expect(prompt, contains('older answer'));
      expect(prompt, isNot(contains('live question')));
      expect(prompt, isNot(contains('live answer')));
    });

    test('drops the recall block entirely when history already covers it', () {
      final prompt = builder.build(
        context: _context(recalledTurns: [_user('a'), _milo('b')]),
        history: [_user('a'), _milo('b')],
      );

      expect(prompt, isNot(contains('EARLIER CONVERSATION')));
    });

    test('flattens a multi-line turn so it reads as one exchange', () {
      final prompt = builder.build(
        context: _context(
          recalledTurns: [_milo('One line.\n\nAnd another.')],
        ),
        history: const [],
      );

      expect(prompt, contains('Milo: One line. And another.'));
    });

    test('appends what the PC did when a command ran', () {
      // Kept from the prompt this builder absorbed — the engines still have
      // to be told what the PC did, or the reply describes an action it
      // knows nothing about.
      final prompt = builder.build(
        context: _context(),
        history: const [],
        pcResult: const PcCommandResult.success(
          PcCommand(
            kind: PcActionKind.openApp,
            target: 'Spotify',
            summary: 'Open Spotify',
          ),
          'Launched Spotify.',
        ),
      );

      expect(prompt, contains('PC ACTION'));
      expect(prompt, contains('Open Spotify'));
      expect(prompt, contains('Launched Spotify.'));
      expect(prompt, contains('It succeeded'));
    });

    test('says a failed PC command failed, and what to check', () {
      final prompt = builder.build(
        context: _context(),
        history: const [],
        pcResult: const PcCommandResult.failure(
          PcCommand(
            kind: PcActionKind.openApp,
            target: 'Spotify',
            summary: 'Open Spotify',
          ),
          'The agent did not answer.',
        ),
      );

      expect(prompt, contains('It failed: The agent did not answer.'));
    });

    test('leaves the PC block out when no command ran', () {
      final prompt = builder.build(context: _context(), history: const []);
      expect(prompt, isNot(contains('PC ACTION')));
    });
  });

  group('MemorySummarizer.shouldSummarize', () {
    final summarizer = MemorySummarizer(gemini: GeminiClient(
      httpClient: _gemini('unused'),
    ));

    test('waits until there is a window of conversation', () {
      expect(
        summarizer.shouldSummarize(messageCount: 19, lastSummarizedAt: 0),
        isFalse,
      );
      expect(
        summarizer.shouldSummarize(messageCount: 20, lastSummarizedAt: 0),
        isTrue,
      );
    });

    test('does not run again until the transcript has grown', () {
      // The re-entrancy guard that stops every message past the twentieth
      // triggering a call.
      expect(
        summarizer.shouldSummarize(messageCount: 20, lastSummarizedAt: 20),
        isFalse,
      );
      expect(
        summarizer.shouldSummarize(messageCount: 21, lastSummarizedAt: 20),
        isTrue,
      );
    });
  });

  group('MemorySummarizer.summarize', () {
    List<ChatMessage> transcript() => [
          ChatMessage(
            id: 'm1',
            isUser: true,
            text: 'set a physiology timer for 45',
            timestamp: DateTime(2026, 9, 2, 9),
          ),
          ChatMessage(
            id: 'm2',
            isUser: false,
            text: 'Started a 45-minute timer on Physiology.',
            timestamp: DateTime(2026, 9, 2, 9, 1),
          ),
        ];

    test('returns the condensed summary', () async {
      final summarizer = MemorySummarizer(
        gemini: GeminiClient(
          httpClient: _gemini('Studies medicine. Prefers 45-minute blocks.'),
        ),
      );

      final summary = await summarizer.summarize(
        apiKey: 'gemini_test',
        messages: transcript(),
      );

      expect(summary, 'Studies medicine. Prefers 45-minute blocks.');
    });

    test('sends the previous summary so it is updated, not rewritten',
        () async {
      final requests = <http.Request>[];
      final summarizer = MemorySummarizer(
        gemini: GeminiClient(httpClient: _gemini('Updated.', capture: requests)),
      );

      await summarizer.summarize(
        apiKey: 'gemini_test',
        messages: transcript(),
        previous: 'Studies medicine.',
      );

      expect(requests.single.body, contains('What is already known'));
      expect(requests.single.body, contains('Studies medicine.'));
    });

    test('reads NOTHING as an empty summary, not as content', () async {
      final summarizer = MemorySummarizer(
        gemini: GeminiClient(httpClient: _gemini('NOTHING')),
      );

      final summary = await summarizer.summarize(
        apiKey: 'gemini_test',
        messages: transcript(),
      );

      expect(summary, isEmpty);
    });

    test('throws rather than returning a blank summary', () async {
      // The caller keeps the previous summary on a throw; a silent empty
      // string would overwrite a real one with nothing.
      final summarizer = MemorySummarizer(
        gemini: GeminiClient(httpClient: _gemini('   ')),
      );

      expect(
        () => summarizer.summarize(
          apiKey: 'gemini_test',
          messages: transcript(),
        ),
        throwsA(isA<MiloException>()),
      );
    });
  });
}
