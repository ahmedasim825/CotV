import '../../models/milo_models.dart';
import '../../models/pc_command.dart';
import '../../models/study_view.dart';
import '../../ui/format/time_format.dart';

/// A snapshot of the app taken when a turn starts.
///
/// Milo is told these facts rather than given tools to look them up: the
/// numbers are already in memory, and a round trip to fetch what the
/// process already knows would cost the latency the instant route exists
/// to protect. Tools are reserved for the things that *change* state.
class MiloContext {
  const MiloContext({
    required this.now,
    required this.nextPrayer,
    required this.nextPrayerTime,
    required this.isLockedOut,
    required this.openTaskCount,
    required this.nextTaskTitles,
    this.studyToday = const [],
    this.studyTodayMinutes = 0,
    this.activeStudySubject,
    this.activeStudyRemaining,
    this.subjectNames = const [],
    this.memorySummary,
    this.recalledTurns = const [],
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

  /// Today's minutes per subject, busiest first.
  final List<SubjectStudyTotal> studyToday;

  final int studyTodayMinutes;

  /// The subject of the session running right now, if one is.
  final String? activeStudySubject;

  final Duration? activeStudyRemaining;

  /// Every subject that exists, so the model starts a timer against one
  /// that is real rather than inventing a name from the user's phrasing.
  final List<String> subjectNames;

  /// What Milo has learned about the user over time, in condensed prose.
  final String? memorySummary;

  /// Turns recalled from the durable transcript, oldest first.
  ///
  /// These are what the panel is *not* showing: a relaunch opens on an
  /// empty panel, so without this a new session starts knowing nothing that
  /// was said yesterday.
  final List<ChatTurn> recalledTurns;
}

/// Builds the one system prompt both engines are given.
///
/// There is a single prompt on purpose: [GroqClient] passes it as
/// `messages[0]` and [GeminiClient] as `systemInstruction`, and the two
/// answers are only comparable if they were told the same thing.
class MiloContextBuilder {
  const MiloContextBuilder();

  /// How many recalled turns are worth carrying. Enough to pick up
  /// yesterday's thread, short enough that the window does not crowd out
  /// the request itself.
  static const int recallWindow = 12;

  String build({
    required MiloContext context,
    required List<ChatTurn> history,
    PcCommandResult? pcResult,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'You are Milo, the assistant inside a prayer and '
        'productivity app on the user\'s iPhone.',
      )
      ..writeln(
        'Answer in at most three short sentences unless the user asks for '
        'a plan, a summary or a breakdown.',
      )
      ..writeln(
        'Use only the facts under CONTEXT for prayer times, tasks, habits '
        'and study. If something is not there, say you do not have it '
        'rather than estimating.',
      )
      ..writeln('Write plainly. No preamble, no bullet points under four '
          'items, no emoji.')
      ..writeln()
      ..writeln('CONTEXT')
      ..writeln(_contextBlock(context));

    final memory = context.memorySummary?.trim();
    if (memory != null && memory.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('WHAT YOU KNOW ABOUT THIS USER')
        ..writeln(
          'Long-lived facts, distilled from past conversations. Treat them '
          'as background, not as something to recite.',
        )
        ..writeln(memory);
    }

    final recalled = _recallBeyond(context.recalledTurns, history);
    if (recalled.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('EARLIER CONVERSATION')
        ..writeln(
          'From previous sessions, oldest first. The panel is not showing '
          'these; do not assume the user can see them.',
        );
      for (final turn in recalled) {
        buffer.writeln(
          '${turn.role == MiloRole.user ? 'User' : 'Milo'}: '
          '${_oneLine(turn.text)}',
        );
      }
    }

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

  String _contextBlock(MiloContext context) {
    final until = context.nextPrayerTime.difference(context.now);
    final lines = [
      'Now: ${formatShortDate(context.now)}, ${formatClock(context.now)}',
      'Next prayer: ${context.nextPrayer} at '
          '${formatClock(context.nextPrayerTime)} '
          '(in ${formatCountdown(until)})',
      'Prayer lockout: '
          '${context.isLockedOut ? 'active right now' : 'not active'}',
      'Open tasks: ${context.openTaskCount}'
          '${context.nextTaskTitles.isEmpty ? '' : ' — ${context.nextTaskTitles.join('; ')}'}',
      'Subjects: '
          '${context.subjectNames.isEmpty ? 'none set up yet' : context.subjectNames.join(', ')}',
      'Studied today: ${_studyLine(context)}',
    ];

    final active = context.activeStudySubject;
    if (active != null) {
      final remaining = context.activeStudyRemaining;
      lines.add(
        'Study timer: running on $active'
        '${remaining == null ? '' : ', ${formatCountdown(remaining)} left'}',
      );
    } else {
      lines.add('Study timer: not running');
    }

    return lines.join('\n');
  }

  String _studyLine(MiloContext context) {
    if (context.studyToday.isEmpty) return 'nothing yet';
    final parts = [
      for (final total in context.studyToday)
        '${total.subjectName} ${formatStudyMinutes(total.todayMinutes)}',
    ];
    return '${formatStudyMinutes(context.studyTodayMinutes)} '
        '(${parts.join(', ')})';
  }

  /// The recalled turns that are not already being sent as live history.
  ///
  /// [history] is the current session, and the durable transcript contains
  /// those same turns — it was written as they happened. Sending both would
  /// spend the prompt saying everything twice, and give the model two
  /// slightly different renderings of one exchange to reconcile.
  List<ChatTurn> _recallBeyond(
    List<ChatTurn> recalled,
    List<ChatTurn> history,
  ) {
    final older = recalled.length - history.length;
    if (older <= 0) return const [];
    return recalled.sublist(0, older);
  }

  /// Collapses a turn to a single line — the block is a reminder of what
  /// was said, not a transcript, and newlines inside it would read as
  /// separate turns.
  String _oneLine(String text) {
    final flattened = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flattened.length <= 240
        ? flattened
        : '${flattened.substring(0, 240)}…';
  }
}
