import '../../models/milo_models.dart';

/// What the study tools act on.
///
/// An interface rather than a direct reach into the provider layer, so this
/// file stays free of Riverpod and can be exercised without a container.
/// The implementation lives in `study_providers.dart`, where the notifier
/// it drives already does.
abstract class StudyToolTarget {
  /// Starts a [minutes]-long session against the subject named [subject].
  ///
  /// Returns a sentence saying what happened, including the case where no
  /// such subject exists — that is a real answer, not an error, and the
  /// model has to be able to say so.
  Future<String> startTimer({required String subject, required int minutes});

  /// Ends the running session and logs the minutes actually studied.
  Future<String> stopTimer();
}

/// The functions Milo may call, and the dispatch that carries them out.
///
/// Only study actions get tools. PC control stays on the deterministic
/// parser: it works, it is tested, and it needs no model round trip. These
/// are here because a study command carries arguments — a subject and a
/// duration — that have to be extracted from prose, which is the one job a
/// parser would have to guess at.
class MiloTools {
  const MiloTools(this.study);

  final StudyToolTarget study;

  static const String startStudyTimer = 'start_study_timer';
  static const String stopStudyTimer = 'stop_study_timer';

  /// The default block length when the user names a subject but no
  /// duration. A Pomodoro, matching the middle option on the study screen.
  static const int defaultMinutes = 25;

  /// The `tools` array sent to the model.
  ///
  /// The subject description tells the model to use a name it was given in
  /// CONTEXT rather than one it inferred, because a subject that does not
  /// exist is the one failure this tool cannot recover from.
  static const List<Map<String, dynamic>> schemas = [
    {
      'type': 'function',
      'function': {
        'name': startStudyTimer,
        'description':
            'Start a study timer for one of the user\'s existing subjects. '
                'Use this whenever the user asks to study, revise or set a '
                'timer for a subject.',
        'parameters': {
          'type': 'object',
          'properties': {
            'subject': {
              'type': 'string',
              'description':
                  'The subject to study. Must be one of the subjects listed '
                      'under CONTEXT; do not invent one.',
            },
            'minutes': {
              'type': 'integer',
              'description':
                  'How long the session should run. Defaults to '
                      '$defaultMinutes if the user did not say.',
            },
          },
          'required': ['subject'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': stopStudyTimer,
        'description':
            'Stop the study timer that is currently running and log the '
                'minutes actually studied.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
  ];

  /// Runs [call] and returns what to hand back to the model.
  ///
  /// Never throws for a call the model got wrong: a missing argument or an
  /// unknown function name comes back as a sentence, because the model can
  /// act on a sentence and cannot act on an exception.
  Future<String> dispatch(MiloToolCall call) async {
    switch (call.name) {
      case startStudyTimer:
        final subject = call.stringArg('subject');
        if (subject == null) {
          return 'No subject was given, so no timer was started. Ask which '
              'subject.';
        }
        return study.startTimer(
          subject: subject,
          minutes: call.intArg('minutes') ?? defaultMinutes,
        );

      case stopStudyTimer:
        return study.stopTimer();

      default:
        return 'There is no tool called "${call.name}", so nothing was done.';
    }
  }

  /// Runs every call in [calls], keyed by id ready for [MiloToolExchange].
  ///
  /// Sequential rather than concurrent: both tools mutate the same single
  /// session, and running "start" and "stop" at once has no defined result.
  Future<Map<String, String>> dispatchAll(List<MiloToolCall> calls) async {
    final results = <String, String>{};
    for (final call in calls) {
      results[call.id] = await dispatch(call);
    }
    return results;
  }
}
