import '../../models/milo_models.dart';
import '../../models/pc_command.dart';
import 'gemini_client.dart';
import 'ollama_client.dart';
import 'milo_context_builder.dart';
import 'milo_credentials.dart';
import 'milo_tools.dart';
import 'pc_intent_parser.dart';
import 'pc_remote_service.dart';
import 'milo_router.dart';

/// The app snapshot and the prompt built from it are part of this service's
/// surface — callers construct one and never touch the builder directly.
export 'milo_context_builder.dart' show MiloContext, MiloContextBuilder;

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

/// A study tool ran. [summary] is what actually happened, written by the
/// app rather than by the model.
class MiloToolExecuted extends MiloEvent {
  const MiloToolExecuted(this.summary);

  final String summary;
}

/// A chunk of reply text.
class MiloTextDelta extends MiloEvent {
  const MiloTextDelta(this.text);

  final String text;
}

/// Milo's orchestration: strip the wake word, decide which engine answers,
/// carry out any PC command the prompt contained, then stream the reply —
/// running any study tool the model asks for along the way.
class MiloService {
  const MiloService({
    required this.local,
    required this.gemini,
    required this.pcRemote,
    this.tools,
    this.router = const MiloRouter(),
    this.parser = const PcIntentParser(),
    this.contextBuilder = const MiloContextBuilder(),
    this.localAvailability,
  });

  final OllamaClient local;
  final GeminiClient gemini;
  final PcRemoteService pcRemote;

  /// Whether the local brain can take a turn on this platform and this
  /// machine, checked once per turn that might go local.
  ///
  /// Injected rather than read from [local] directly because the answer is
  /// partly a platform fact — iOS has no local runtime at all, and asking
  /// Ollama about it would mean a doomed connection attempt per turn. Null
  /// means "ask the client", which is what Windows does.
  final Future<LocalBrainStatus> Function()? localAvailability;

  /// Null in tests and anywhere the study layer is not available, in which
  /// case no tools are offered and the turn is plain prose.
  final MiloTools? tools;

  final MiloRouter router;
  final PcIntentParser parser;
  final MiloContextBuilder contextBuilder;

  /// A leading "Milo", "Hey Milo" or "OK Milo", with the punctuation that
  /// usually follows it, and what speech-to-text tends to hear instead.
  ///
  /// Anchored at the start so "what did Milo say" is left alone.
  ///
  /// "Milo" is not in Whisper's everyday vocabulary, so a spoken
  /// "Hey Milo" comes back as "Hey Maido", "Mylo" or "Meelo".
  /// [LocalTranscriptionClient] biases the decoder against that, but
  /// biasing is not a guarantee, and a wake word that survives into the
  /// prompt is worse than one that was never said: the model is asked
  /// to answer a request addressed to someone called Maido.
  static final RegExp _wakeWord = RegExp(
    r'^\s*(?:hey\s+|ok(?:ay)?\s+|yo\s+|hi\s+)?'
    r'(?:milo|mylo|maido|meelo|mielo|milow|miloh|milo+)\b[\s,:;.!?-]*',
    caseSensitive: false,
  );

  static String stripWakeWord(String prompt) =>
      prompt.replaceFirst(_wakeWord, '').trim();

  /// What [transcript] asked Milo to do, or null if it was not addressed to
  /// Milo at all.
  ///
  /// The distinction [stripWakeWord] does not make, and the one always-on
  /// listening needs: that strips a wake word if present and passes
  /// everything else through, which is right when the user has already
  /// pressed a button to talk. When nothing was pressed, overheard speech
  /// has to be told from a request, and only the wake word does that.
  ///
  /// Returns the empty string for a bare "Milo" — addressed, but with
  /// nothing asked yet, so the caller can wait for the next sentence.
  static String? wakeWordCommand(String transcript) {
    final match = _wakeWord.firstMatch(transcript.trimLeft());
    if (match == null) return null;
    return transcript.trimLeft().substring(match.end).trim();
  }

  /// Runs one turn.
  ///
  /// Throws [MiloException] when the chosen engine has no key or the API
  /// refuses the call. Any [MiloPcExecuted] or [MiloToolExecuted] already
  /// yielded stays on the turn, so an action that worked is still reported
  /// even when the reply that would have described it fails.
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
    var decision = router.classify(prompt, isPcCommand: command != null);

    // Resolved before the rail is shown, so the badge names the engine that
    // is actually about to run rather than one that gets corrected a
    // second later.
    if (decision.engine == MiloEngine.local) {
      final status = await (localAvailability?.call() ?? local.probe());
      final why = status.reason;
      if (why != null) decision = router.fallback(decision, why);
    }

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

    final systemPrompt = contextBuilder.build(
      context: context,
      history: history,
      pcResult: pcResult,
    );

    switch (decision.engine) {
      case MiloEngine.local:
        yield* _localTurn(
          systemPrompt: systemPrompt,
          history: history,
          prompt: prompt,
          decision: decision,
        );

      case MiloEngine.gemini:
        final key = secrets.geminiApiKey;
        if (key == null) {
          throw MiloException(
            'No Gemini API key yet. Add one in Milo settings to answer '
            'requests that need the deep model.',
          );
        }
        yield* _plainTurn(
          gemini.streamReply(
            apiKey: key,
            systemPrompt: systemPrompt,
            history: history,
            prompt: prompt,
          ),
          decision,
        );
    }
  }

  /// The local turn, including one round of tool calls if the model asks.
  ///
  /// Exactly one round: the follow-up call is made without `tools`, so the
  /// model answers with the results rather than being able to ask again.
  /// A study command is one action, and a loop here would be a loop the
  /// user is waiting on.
  Stream<MiloEvent> _localTurn({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String prompt,
    required RoutingDecision decision,
  }) async* {
    final tools = this.tools;
    final calls = <MiloToolCall>[];
    var produced = false;

    await for (final delta in local.streamTurn(
      systemPrompt: systemPrompt,
      history: history,
      prompt: prompt,
      tools: tools == null ? null : MiloTools.schemas,
    )) {
      switch (delta) {
        case LocalText(:final text):
          produced = true;
          yield MiloTextDelta(text);
        case LocalToolCalls(calls: final requested):
          calls.addAll(requested);
      }
    }

    if (tools != null && calls.isNotEmpty) {
      final results = await tools.dispatchAll(calls);
      for (final call in calls) {
        final summary = results[call.id];
        if (summary != null) yield MiloToolExecuted(summary);
      }

      await for (final delta in local.streamTurn(
        systemPrompt: systemPrompt,
        history: history,
        prompt: prompt,
        exchange: MiloToolExchange(calls: calls, results: results),
      )) {
        if (delta is LocalText) {
          produced = true;
          yield MiloTextDelta(delta.text);
        }
      }
    }

    // An action that ran is its own answer — the receipt says what
    // happened — so silence is only a failure when nothing happened at all.
    if (!produced && calls.isEmpty) throw _silence(decision);
  }

  Stream<MiloEvent> _plainTurn(
    Stream<String> reply,
    RoutingDecision decision,
  ) async* {
    var produced = false;
    await for (final delta in reply) {
      produced = true;
      yield MiloTextDelta(delta);
    }
    if (!produced) throw _silence(decision);
  }

  /// A stream that closes without a single token is a real failure, and
  /// the common cause is a reply whose budget went entirely on internal
  /// reasoning. Silence would otherwise render as an empty bubble that
  /// looks like Milo had nothing to say.
  MiloException _silence(RoutingDecision decision) => MiloException(
        '${decision.engine.badge} returned no text. It may have used its '
        'whole output budget reasoning — try asking something shorter.',
      );
}
