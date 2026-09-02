// Pure-Dart tests for the Part 3 view models and the journal's markdown
// parser. No Hive, no widgets — these are the transforms the habit grid,
// the journal list and the writer preview are built on.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/habit_view.dart';
import 'package:cotv/src/models/journal_entry.dart';
import 'package:cotv/src/models/journal_view.dart';
import 'package:cotv/src/ui/journal/markdown/markdown_view.dart';

Habit _habit({
  String id = 'h1',
  String title = 'Dhikr',
  HabitFrequency frequency = HabitFrequency.daily,
  List<DateTime>? completed,
  int streak = 0,
}) {
  return Habit(
    id: id,
    title: title,
    frequency: frequency,
    completedDates: completed,
    streakCount: streak,
  );
}

void main() {
  group('HabitX periods', () {
    final now = DateTime(2026, 9, 2, 14, 30);

    test('a daily habit is complete only on the exact day', () {
      final habit = _habit(completed: [DateTime(2026, 9, 2)]);

      expect(habit.isCompletedNow(now), isTrue);
      expect(habit.isCompletedOn(DateTime(2026, 9, 1)), isFalse);
    });

    test('a weekly habit counts any day in the same Monday-start week', () {
      // 2026-08-31 is the Monday of the week containing 2026-09-02.
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        completed: [DateTime(2026, 8, 31)],
      );

      expect(habit.isCompletedNow(now), isTrue);
      // The previous week is untouched.
      expect(habit.isCompletedOn(DateTime(2026, 8, 26)), isFalse);
    });

    test('completionDateIn returns the day actually recorded', () {
      // This is what lets the grid un-complete a weekly habit: it has to
      // remove Monday's entry, not add today's on top of it.
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        completed: [DateTime(2026, 8, 31)],
      );

      expect(habit.completionDateIn(now), DateTime(2026, 8, 31));
      expect(habit.completionDateIn(DateTime(2026, 8, 20)), isNull);
    });

    test('recentHistory ends on the current period', () {
      final habit = _habit(completed: [
        DateTime(2026, 9, 2),
        DateTime(2026, 8, 31),
      ]);

      final history = habit.recentHistory(now, count: 4);

      // Oldest first: Aug 30, Aug 31, Sep 1, Sep 2.
      expect(history, [false, true, false, true]);
    });
  });

  group('summarizeHabits', () {
    final now = DateTime(2026, 9, 2, 9);

    test('counts completions, the best streak and running streaks', () {
      final summary = summarizeHabits([
        _habit(id: 'a', completed: [DateTime(2026, 9, 2)], streak: 5),
        _habit(id: 'b', streak: 0),
        _habit(id: 'c', completed: [DateTime(2026, 9, 2)], streak: 12),
      ], now);

      expect(summary.total, 3);
      expect(summary.completedThisPeriod, 2);
      expect(summary.bestStreak, 12);
      expect(summary.activeStreaks, 2);
      expect(summary.completionRate, closeTo(2 / 3, 1e-9));
    });

    test('an empty list has a zero rate rather than dividing by zero', () {
      final summary = summarizeHabits(const [], now);

      expect(summary.isEmpty, isTrue);
      expect(summary.completionRate, 0);
    });
  });

  group('sortHabits', () {
    final now = DateTime(2026, 9, 2, 9);

    test('outstanding first, then longest streak, then alphabetical', () {
      final sorted = sortHabits([
        _habit(id: 'done', title: 'Done one', completed: [DateTime(2026, 9, 2)]),
        _habit(id: 'b', title: 'Beta', streak: 1),
        _habit(id: 'a', title: 'Alpha', streak: 9),
        _habit(id: 'c', title: 'Alpha two', streak: 1),
      ], now);

      expect(sorted.map((h) => h.title), [
        'Alpha',
        'Alpha two',
        'Beta',
        'Done one',
      ]);
    });
  });

  group('journalExcerpt', () {
    test('strips block markers and inline emphasis', () {
      const source = '# Heading\n\n'
          'Some **bold** and *italic* and `code`.\n'
          '- a bullet\n'
          '> a quote';

      expect(
        journalExcerpt(source),
        'Heading Some bold and italic and code. a bullet a quote',
      );
    });

    test('keeps a link label and drops its target', () {
      expect(
        journalExcerpt('See [the notes](https://example.com/x) later'),
        'See the notes later',
      );
    });

    test('truncates with an ellipsis', () {
      final excerpt = journalExcerpt('a' * 300, maxChars: 20);

      expect(excerpt.length, 21);
      expect(excerpt.endsWith('…'), isTrue);
    });
  });

  group('normalizeTag', () {
    test('lower-cases, drops a leading hash and hyphenates spaces', () {
      expect(normalizeTag('  #Deep Work '), 'deep-work');
      expect(normalizeTag('Salah'), 'salah');
    });

    test('empty and marker-only input normalises to empty', () {
      expect(normalizeTag('   '), '');
      expect(normalizeTag('##'), '');
    });
  });

  group('journal filtering', () {
    JournalEntry entry(
      String id,
      DateTime date, {
      String content = '',
      JournalMood mood = JournalMood.neutral,
      List<String> tags = const [],
    }) {
      return JournalEntry(
        id: id,
        date: date,
        content: content,
        mood: mood,
        tags: tags,
      );
    }

    final entries = [
      entry('1', DateTime(2026, 9, 1),
          content: 'Long day at the hospital', mood: JournalMood.low,
          tags: ['work']),
      entry('2', DateTime(2026, 9, 3),
          content: 'Good khutbah today', mood: JournalMood.great,
          tags: ['salah', 'work']),
      entry('3', DateTime(2026, 9, 2), content: 'Quiet'),
    ];

    test('sorts newest first', () {
      expect(sortJournalByDate(entries).map((e) => e.id), ['2', '3', '1']);
    });

    test('query matches content and tags, case-insensitively', () {
      expect(filterJournal(entries, query: 'KHUTBAH').map((e) => e.id), ['2']);
      expect(filterJournal(entries, query: 'salah').map((e) => e.id), ['2']);
    });

    test('filters combine', () {
      final result = filterJournal(
        entries,
        tag: 'work',
        mood: JournalMood.low,
      );

      expect(result.map((e) => e.id), ['1']);
    });

    test('collectTags orders by use, then alphabetically', () {
      expect(collectTags(entries), ['work', 'salah']);
    });
  });

  group('parseMarkdownBlocks', () {
    test('joins consecutive lines into one paragraph', () {
      final blocks = parseMarkdownBlocks('one\ntwo\n\nthree');

      expect(blocks.length, 2);
      expect(blocks[0].kind, MarkdownBlockKind.paragraph);
      expect(blocks[0].text, 'one two');
      expect(blocks[1].text, 'three');
    });

    test('reads heading levels', () {
      final blocks = parseMarkdownBlocks('# One\n## Two\n### Three');

      expect(blocks.map((b) => b.level), [1, 2, 3]);
      expect(blocks.every((b) => b.kind == MarkdownBlockKind.heading), isTrue);
    });

    test('bullets and ordered items carry their marker', () {
      final blocks = parseMarkdownBlocks('- first\n2. second');

      expect(blocks[0].kind, MarkdownBlockKind.bullet);
      expect(blocks[0].marker, '•');
      expect(blocks[0].text, 'first');
      expect(blocks[1].marker, '2.');
      expect(blocks[1].text, 'second');
    });

    test('a fenced block keeps its newlines verbatim', () {
      final blocks = parseMarkdownBlocks('```\nline one\n  line two\n```');

      expect(blocks.single.kind, MarkdownBlockKind.code);
      expect(blocks.single.text, 'line one\n  line two');
    });

    test('an unterminated fence runs to the end rather than failing', () {
      final blocks = parseMarkdownBlocks('```\nstill open');

      expect(blocks.single.kind, MarkdownBlockKind.code);
      expect(blocks.single.text, 'still open');
    });

    test('rules and quotes are their own blocks', () {
      final blocks = parseMarkdownBlocks('> quoted\n\n---\n\ntail');

      expect(blocks.map((b) => b.kind), [
        MarkdownBlockKind.quote,
        MarkdownBlockKind.rule,
        MarkdownBlockKind.paragraph,
      ]);
      expect(blocks[0].text, 'quoted');
    });

    test('empty input produces no blocks', () {
      expect(parseMarkdownBlocks(''), isEmpty);
      expect(parseMarkdownBlocks('\n\n  \n'), isEmpty);
    });
  });
}
