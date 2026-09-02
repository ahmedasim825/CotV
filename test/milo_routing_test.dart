// The pure decision-making behind Milo: wake-word stripping, engine
// routing, PC intent parsing and SSE framing. None of these touch the
// network, so they are ordinary unit tests.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/models/pc_command.dart';
import 'package:cotv/src/services/milo/milo_router.dart';
import 'package:cotv/src/services/milo/milo_service.dart';
import 'package:cotv/src/services/milo/pc_intent_parser.dart';
import 'package:cotv/src/services/milo/sse_stream.dart';

void main() {
  group('wake word', () {
    test('strips the leading name and the punctuation after it', () {
      expect(
        MiloService.stripWakeWord('Milo, open Spotify on my PC'),
        'open Spotify on my PC',
      );
      expect(
        MiloService.stripWakeWord('Hey Milo what is my next prayer'),
        'what is my next prayer',
      );
      expect(MiloService.stripWakeWord('OK Milo: mute the laptop'),
          'mute the laptop');
      expect(MiloService.stripWakeWord('  milo   add a task  '), 'add a task');
    });

    test('leaves the name alone when it is not the wake word', () {
      // Anchored at the start, so a mid-sentence mention survives.
      expect(
        MiloService.stripWakeWord('what did Milo say about this'),
        'what did Milo say about this',
      );
      expect(MiloService.stripWakeWord('remilo the wall'), 'remilo the wall');
    });

    test('a bare wake word leaves nothing to answer', () {
      expect(MiloService.stripWakeWord('Milo'), isEmpty);
      expect(MiloService.stripWakeWord('Hey Milo!'), isEmpty);
    });
  });

  group('router', () {
    const router = MiloRouter();

    test('a parsed PC command always answers instantly', () {
      // Long enough to trip the word-count rule, and carrying a synthesis
      // verb, and still routed to Groq — the PC flag outranks both.
      final decision = router.classify(
        'plan to open Spotify and then work out what I should do for the '
        'rest of the evening around Maghrib on my laptop please',
        isPcCommand: true,
      );

      expect(decision.engine, MiloEngine.groq);
      expect(decision.reason, contains('PC command'));
    });

    test('synthesis verbs route to Gemini and name themselves', () {
      final decision =
          router.classify('summarize my notes', isPcCommand: false);

      expect(decision.engine, MiloEngine.gemini);
      expect(decision.reason, contains('summarize'));
    });

    test('a scheduling constraint routes to Gemini', () {
      final decision = router.classify(
        'fit revision around Maghrib tonight',
        isPcCommand: false,
      );

      expect(decision.engine, MiloEngine.gemini);
      expect(decision.reason, contains('around'));
    });

    test('a long request routes to Gemini on length alone', () {
      // 25 words, no synthesis verb and no constraint phrase: length is
      // the only signal, and the reason has to say so.
      final prompt = List.filled(25, 'word').join(' ');
      final decision = router.classify(prompt, isPcCommand: false);

      expect(decision.engine, MiloEngine.gemini);
      expect(decision.reason, contains('25 words'));
    });

    test('the same request one word under the threshold stays instant', () {
      final prompt = List.filled(MiloRouter.deepWordCount, 'word').join(' ');

      expect(
        router.classify(prompt, isPcCommand: false).engine,
        MiloEngine.groq,
      );
    });

    test('direct commands and lookups route to Groq', () {
      for (final prompt in [
        'add a task to revise anatomy',
        'when is Isha',
        'how long until Asr',
      ]) {
        expect(
          router.classify(prompt, isPcCommand: false).engine,
          MiloEngine.groq,
          reason: prompt,
        );
      }
    });
  });

  group('PC intent parser', () {
    const parser = PcIntentParser();

    test('an app launch needs the machine named', () {
      final command = parser.parse('Open Spotify on my PC');

      expect(command, isNotNull);
      expect(command!.kind, PcActionKind.openApp);
      expect(command.target, 'Spotify');
      expect(command.summary, 'Open Spotify');
      expect(command.toJson(), {'app': 'Spotify'});
      expect(command.kind.path, '/open-app');
    });

    test('app names travel as spoken, for the agent to resolve', () {
      // Not normalised here: the agent matches its own pins, then PATH,
      // then the registry, which needs the real name rather than a slug.
      expect(parser.parse('launch VS Code on the laptop')?.target, 'VS Code');
    });

    test('an explicit URL needs no machine word', () {
      final command = parser.parse('open https://groq.com/docs');

      expect(command!.kind, PcActionKind.openPath);
      expect(command.target, 'https://groq.com/docs');
    });

    test('a bare domain is treated as an app name, not a site', () {
      // "open reddit on my pc" almost always means the app.
      expect(parser.parse('open reddit on my pc')?.kind, PcActionKind.openApp);
    });

    test('the same phrase without a machine word is not a PC command', () {
      expect(parser.parse('open Spotify'), isNull);
      expect(parser.parse('pause'), isNull);
    });

    test('a folder needs no machine word — the phone has no folders', () {
      final command = parser.parse('Open study folder');

      expect(command!.kind, PcActionKind.openPath);
      expect(command.target, 'study');
      expect(command.summary, 'Open the study folder');
      expect(command.kind.path, '/open-file');
    });

    test('a literal path keeps its casing and separators', () {
      final command = parser.parse(r'open D:\Study\Anatomy on my pc');

      expect(command!.kind, PcActionKind.openPath);
      expect(command.target, r'D:\Study\Anatomy');
    });

    test('media phrases map to control keys, longest phrase first', () {
      expect(parser.parse('Play media on laptop')?.target, 'play_pause');
      expect(parser.parse('skip track on the pc')?.target, 'next_track');
      // "skip" alone would also match play/skip, so this proves the
      // longest-first ordering rather than dictionary order.
      expect(parser.parse('next track on the pc')?.target, 'next_track');
      expect(parser.parse('turn it up on my laptop')?.target, 'volume_up');
      expect(parser.parse('lock the computer')?.target, 'lock_workstation');
      expect(
        parser.parse('mute the laptop')?.kind,
        PcActionKind.system,
      );
    });

    test('a long sentence mentioning the laptop is description, not a key',
        () {
      // Nine words: over the control limit, so nothing is sent.
      expect(
        parser.parse('my laptop keeps deciding to pause the music by itself'),
        isNull,
      );
    });

    test('"open my laptop" has no target left once the machine is stripped',
        () {
      expect(parser.parse('open my laptop'), isNull);
    });
  });

  group('SSE decoding', () {
    Stream<List<int>> chunks(List<String> parts) =>
        Stream.fromIterable(parts.map(utf8.encode));

    test('yields one map per event and stops at the DONE sentinel', () async {
      final events = await decodeSseJson(
        chunks([
          'data: {"n":1}\n\n',
          'data: {"n":2}\n\n',
          'data: [DONE]\n\n',
          'data: {"n":3}\n\n',
        ]),
      ).toList();

      expect(events.map((event) => event['n']), [1, 2]);
    });

    test('reassembles an event split across chunk boundaries', () async {
      // The load-bearing case: a naive per-chunk JSON parse fails here, and
      // real responses split wherever the socket happens to.
      final events = await decodeSseJson(
        chunks(['data: {"n"', ':42}\n', '\ndata: {"n":43}\n\n']),
      ).toList();

      expect(events.map((event) => event['n']), [42, 43]);
    });

    test('ignores comments and non-data fields', () async {
      final events = await decodeSseJson(
        chunks([': keep-alive\n', 'event: message\n', 'data: {"n":7}\n\n']),
      ).toList();

      expect(events.single['n'], 7);
    });

    test('emits a trailing event when the body closes without a blank line',
        () async {
      final events = await decodeSseJson(chunks(['data: {"n":9}'])).toList();

      expect(events.single['n'], 9);
    });
  });
}
