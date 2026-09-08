import '../../models/milo_models.dart';

/// Picks the engine for one prompt.
///
/// Deliberately a set of local rules rather than a classifier call: asking
/// a model which model to use would spend the exact latency the Groq route
/// exists to save, and would put a network failure in front of every turn.
/// The rules are ordered, first match wins, and each one carries the reason
/// the panel shows — so the decision is always attributable to a specific
/// signal in the prompt rather than to a score no one can read.
///
/// The default is the instant engine. Every rule below is a reason to send
/// a prompt to the slower, deeper one instead — a clinical term, a research
/// phrase, a synthesis verb, or sheer length.
class MiloRouter {
  const MiloRouter();

  /// A request longer than this is describing constraints ("around", "but
  /// not before", "unless") rather than naming one action, and the small
  /// model loses the thread partway through.
  static const int deepWordCount = 22;

  /// Clinical vocabulary. A medical question goes to the deep model
  /// whatever else it looks like, and length is no defence — "is 40mg
  /// amlodipine safe" is five words and is not a question to answer from
  /// the model picked for speed.
  ///
  /// Deliberately narrow. These are terms that carry clinical intent on
  /// their own; broader words like "pain" or "heart" appear in ordinary
  /// sentences about study and would route half the day's prompts off the
  /// device for nothing.
  static const Set<String> _medicalTerms = {
    'antibiotic',
    'contraindication',
    'contraindicated',
    'diagnose',
    'diagnosis',
    'dosage',
    'dose',
    'dosing',
    'etiology',
    'aetiology',
    'mg',
    'pathogenesis',
    'pathophysiology',
    'pharmacokinetics',
    'prognosis',
    'symptom',
    'symptoms',
    'syndrome',
    'treatment',
  };

  /// Multi-word clinical and research signals.
  static const List<String> _medicalPhrases = [
    'differential diagnosis',
    'drug interaction',
    'evidence for',
    'literature on',
    'meta-analysis',
    'peer reviewed',
    'side effect',
    'systematic review',
  ];

  /// Verbs that ask for something to be produced or worked out, as opposed
  /// to looked up or done.
  static const Set<String> _synthesisVerbs = {
    'analyse',
    'analyze',
    'brainstorm',
    'compare',
    'compose',
    'draft',
    'explain',
    'outline',
    'plan',
    'prioritise',
    'prioritize',
    'reflect',
    'rewrite',
    'strategise',
    'strategize',
    'summarise',
    'summarize',
    'summary',
  };

  /// Phrases that carry the same signal across more than one word.
  static const List<String> _synthesisPhrases = [
    ' around ',
    ' based on ',
    'break down',
    'help me think',
    'how should i',
    'walk me through',
    'what should i',
  ];

  /// Verbs and question openers that name a single action or a single fact.
  static const List<String> _instantSignals = [
    'add ',
    'how long',
    'launch ',
    'lock ',
    'mute',
    'next prayer',
    'open ',
    'pause',
    'play',
    'remind ',
    'skip',
    'start ',
    'volume',
    'what time',
    "what's next",
    'when is',
  ];

  /// [isPcCommand] comes from [PcIntentParser]: a prompt that already
  /// parsed into a machine instruction is answered instantly by
  /// construction, whatever else it looks like.
  RoutingDecision classify(String prompt, {required bool isPcCommand}) {
    final text = ' ${prompt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')} ';
    final words = RegExp(r"[a-z']+")
        .allMatches(text)
        .map((match) => match.group(0)!)
        .toList(growable: false);

    // Checked before the PC shortcut, and before anything else: a clinical
    // question that happens to contain "open" is still a clinical question.
    for (final word in words) {
      if (_medicalTerms.contains(word)) {
        return RoutingDecision(
          engine: MiloEngine.gemini,
          reason: '"$word" is a clinical term — answered by the deep model',
        );
      }
    }

    for (final phrase in _medicalPhrases) {
      if (text.contains(phrase)) {
        return RoutingDecision(
          engine: MiloEngine.gemini,
          reason: '"$phrase" asks for research, not recall',
        );
      }
    }

    if (isPcCommand) {
      return const RoutingDecision(
        engine: MiloEngine.groq,
        reason: 'PC command — the reply runs alongside the action',
      );
    }

    for (final word in words) {
      if (_synthesisVerbs.contains(word)) {
        return RoutingDecision(
          engine: MiloEngine.gemini,
          reason: '"$word" asks for synthesis, not a lookup',
        );
      }
    }

    for (final phrase in _synthesisPhrases) {
      if (text.contains(phrase)) {
        return RoutingDecision(
          engine: MiloEngine.gemini,
          reason: '"${phrase.trim()}" sets up a constraint to reason about',
        );
      }
    }

    if (words.length > deepWordCount) {
      return RoutingDecision(
        engine: MiloEngine.gemini,
        reason: '${words.length} words — long enough to need the deep model',
      );
    }

    for (final signal in _instantSignals) {
      if (text.contains(signal)) {
        return RoutingDecision(
          engine: MiloEngine.groq,
          reason: '"${signal.trim()}" is a direct command',
        );
      }
    }

    return const RoutingDecision(
      engine: MiloEngine.groq,
      reason: 'Short, nothing clinical — instant model is enough',
    );
  }
}
