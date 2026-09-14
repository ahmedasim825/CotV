import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/study_view.dart';
import '../../models/subject.dart';
import '../../providers/study_providers.dart';
import '../settings/option_picker_sheet.dart';
import 'widgets/subject_form_sheet.dart';

/// The session lengths offered when a subject is tapped.
///
/// Two Pomodoro-shaped options and three block lengths, rather than a free
/// number field: picking is one tap, and a study block is chosen from habit
/// far more often than it is calculated.
const List<int> studyDurationMinutes = [15, 25, 45, 60, 90];

/// Starts a session from anywhere: which subject, then how long.
///
/// Skips the first question when there is only one subject to ask about, and
/// sends someone with none to the subject form instead of to an empty picker.
///
/// Lives here rather than on the Study screen because two surfaces reach it
/// now — that screen's header button, and the dashboard Study card's plus on
/// iOS. Copying it would let the two drift over questions like "what happens
/// with no subjects yet", which is exactly the case a copy gets wrong.
///
/// Reads the subject list itself, so a caller that has not already loaded one
/// does not need to. Returns when the session has started, or as soon as any
/// sheet in the chain is dismissed.
Future<void> startAnySession(BuildContext context, WidgetRef ref) async {
  final subjects = ref.read(subjectListProvider).value ?? const <Subject>[];
  final summary = ref.read(studySummaryProvider);
  final ordered = sortSubjects(subjects, summary);

  if (ordered.isEmpty) {
    await showSubjectFormSheet(context);
    return;
  }
  if (ordered.length == 1) {
    await startSessionFor(context, ref, ordered.first);
    return;
  }

  final subject = await showOptionPicker<Subject>(
    context,
    title: 'Study',
    subtitle: 'What are you working on?',
    selected: ordered.first,
    options: [
      for (final subject in ordered)
        PickerOption(value: subject, label: subject.name),
    ],
  );
  if (subject == null || !context.mounted) return;

  await startSessionFor(context, ref, subject);
}

/// Asks how long, then starts. Returns without starting if the sheet was
/// dismissed.
Future<void> startSessionFor(
  BuildContext context,
  WidgetRef ref,
  Subject subject,
) async {
  final minutes = await showOptionPicker<int>(
    context,
    title: subject.name,
    subtitle: 'How long is this block?',
    selected: studyDurationMinutes[1],
    options: [
      for (final value in studyDurationMinutes)
        PickerOption(
          value: value,
          label: formatStudyMinutes(value),
          note: _durationNote(value),
        ),
    ],
  );
  if (minutes == null) return;

  await ref.read(studyProvider.notifier).start(subject, minutes: minutes);
}

String? _durationNote(int minutes) {
  switch (minutes) {
    case 25:
      return 'One Pomodoro.';
    case 90:
      return 'A full ultradian block.';
    default:
      return null;
  }
}
