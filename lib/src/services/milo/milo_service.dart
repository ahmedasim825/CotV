import '../../models/milo_models.dart';
import '../../models/pc_command.dart';
import '../../ui/format/time_format.dart';
import 'gemini_client.dart';
import 'groq_client.dart';
import 'milo_credentials.dart';
import 'pc_intent_parser.dart';
import 'pc_remote_service.dart';
import 'milo_router.dart';

/// A snapshot of the app taken when a turn starts.
///
/// Milo is told these facts rather than given tools to look them up: the
/// numbers are already in memory, and a round trip to fetch what the
/// process already knows would cost the latency the instant route exists
/// to protect.
class MiloContext {
  const MiloContext({
    required this.now,
    required this.nextPrayer,
    required this.nextPrayerTime,
    required this.isLockedOut,
    required this.openTaskCount,
    required this.nextTaskTitles,
  });

  final DateTime now;
  final String nextPrayer;
  final DateTime nextPrayerTime;

  /// True while the user is inside a prayer lockout block.
  final bool isLockedOut;

  final int openTaskCount;

  /// The soonest few open tasks, so "what should I do next" has something
  /// real to answer from.
  final List<String> nextTaskTitles;

  String get promptBlock {
    final until = nextPrayerTime.difference(now);
    return [
      'Now: ${formatShortDate(now)}, ${formatClock(now)}',
      'Next prayer: $nextPrayer at ${formatClock(nextPrayerTime)} '
          '(in ${formatCountdown(until)})',
      'Prayer lockout: ${isLockedOut ? 'active right now' : 'not active'}',
      'Open tasks: $openTaskCount'
          '${nextTaskTitles.isEmpty ? '' : ' — ${nextTaskTitles.join('; ')}'}',
    ].join('\n');
  }
}

/// One step of an assistant turn, in the order the panel applies them.
sealed class MiloEvent {
  const MiloEvent();
}

/// The engine has been chosen. Arrives before any token, so the routing
/// rail is on screen while the model is still thinking.
class MiloRouted extends MiloEvent {
  const MiloRouted(this.decision);

  final RoutingDecision decision;
}

/// A PC command finished, successfully or not.
class MiloPcExecuted extends MiloEvent {
  const MiloPcExecuted(this.result);

  final PcCommandResult result;
}

/// A chunk of reply text.
class MiloTextDelta extends MiloEvent {
  const MiloTextDelta(this.text);

  final String text;
}

/// Milo's orchestration: strip the wake word, decide which engine answers,
/// carry out any PC command the prompt contained, then stream the reply.
class MiloService {
  const MiloService({
    required this.groq,
    required this.gemini,
    required this.pcRemote,
    this.router = const MiloRouter(),
    this.parser = const PcIntentParser(),
  });

  final GroqClient groq;
  final GeminiClient gemini;
  final PcRemoteService pcRemote;
  final MiloRouter router;
  final PcIntentParser parser;

  /// A leading "Milo", "Hey Milo" or "OK Milo", with the punctuation that
  /// usually follows it. Anchored at the start so "what did Milo say" is
  /// left alone.
  static final RegExp _wakeWord = RegExp(
    r'^\s*(?:hey\s+|ok(?:ay)?\s+|yo\s+|hi\s+)?milo\b[\s,:;.!?-]*',
    caseSensitive: false,
  );

  static String stripWakeWord(String prompt) =>
      prompt.replaceFirst(_wakeWord, '').trim();

  /// Runs one turn.
  ///
  /// Throws [MiloException] when the chosen engine has no key or the API
  /// refuses the call. Any [MiloPcExecuted] already yielded stays on the
  /// turn, so an action that worked is still reported even when the reply
  /// that would have described it fails.
  Stream<MiloEvent> respond({
    required String rawPrompt,
    required MiloSecrets secrets,
    required MiloContext context,
    required List<ChatTurn> history,
  }) async* {
    final prompt = stripWakeWord(rawPrompt);
    if (prompt.isEmpty) {
      throw MiloException('Milo heard its name but no request.');
    }

    final command = parser.parse(prompt);
    final decision = router.classify(prompt, isPcCommand: command != null);
    yield MiloRouted(decision);

    PcCommandResult? pcResult;
    if (command != null) {
      final agent = secrets.pcAgent;
      pcResult = agent == null
          ? PcCommandResult.failure(
              command,
              'No PC agent is configured. Add its address and token in '
              'Milo settings.',
            )
          : await pcRemote.execute(command, agent: agent);
      yield MiloPcExecuted(pcResult);
    }

    final systemPrompt = _systemPrompt(context, pcResult);

    final Stream<String> reply;
    switch (decision.engine) {
      case MiloEngine.groq:
        final key = secrets.groqApiKey;
        if (key == null) {
          throw MiloException(
            'No Groq API key yet. Add one in Milo settings to answer '
            'instant requests.',
          );
        }
        reply = groq.streamReply(
          apiKey: key,
          systemPrompt: systemPrompt,
          history: history,
          prompt: prompt,
        );
      case MiloEngine.gemini:
        final key = secrets.geminiApiKey;
        if (key == null) {
          throw MiloException(
            'No Gemini API key yet. Add one in Milo settings to answer '
            'requests that need the deep model.',
          );
        }
        reply = gemini.streamReply(
          apiKey: key,
          systemPrompt: systemPrompt,
          history: history,
          prompt: prompt,
        );
    }

    var produced = false;
    await for (final delta in reply) {
      produced = true;
      yield MiloTextDelta(delta);
    }

    // A stream that closes without a single token is a real failure, and
    // the common cause is a reply whose budget went entirely on internal
    // reasoning. Silence would otherwise render as an empty bubble that
    // looks like Milo had nothing to say.
    if (!produced) {
      throw MiloException(
        '${decision.engine.badge} returned no text. It may have used its '
        'whole output budget reasoning — try asking something shorter.',
      );
    }
  }

  String _systemPrompt(MiloContext context, PcCommandResult? pcResult) {
    final buffer = StringBuffer()
      ..writeln(
        'You are Milo, the assistant inside Prayer Lockout — a prayer and '
        'productivity app on the user\'s iPhone.',
      )
      ..writeln(
        'Answer in at most three short sentences unless the user asks for '
        'a plan, a summary or a breakdown.',
      )
      ..writeln(
        'Use only the facts under CONTEXT for prayer times, tasks and '
        'habits. If something is not there, say you do not have it rather '
        'than estimating.',
      )
      ..writeln('Write plainly. No preamble, no bullet points under four '
          'items, no emoji.')
      ..writeln()
      ..writeln('CONTEXT')
      ..writeln(context.promptBlock);

    if (pcResult != null) {
      buffer
        ..writeln()
        ..writeln('PC ACTION')
        ..writeln(
          'The user asked for this on their Windows PC: '
          '"${pcResult.command.summary}".',
        )
        ..writeln(
          pcResult.ok
              ? 'It succeeded. The agent reported: ${pcResult.message} '
                  'Confirm it in one short sentence.'
              : 'It failed: ${pcResult.message} '
                  'Say what failed and what to check, in one or two '
                  'sentences.',
        );
    }

    return buffer.toString();
  }
}
