import 'package:flutter_test/flutter_test.dart';
import 'package:cotv/src/models/reminder.dart';

void main() {
  final now = DateTime(2026, 7, 28, 12, 0);

  test('a reminder due before now is overdue', () {
    final reminder = Reminder(
      id: 'a',
      title: 'Workout',
      dueAt: DateTime(2026, 7, 27, 3, 0),
    );
    expect(reminder.isOverdue(now), isTrue);
  });

  test('a reminder due later is not overdue', () {
    final reminder = Reminder(
      id: 'b',
      title: "Watch Dr.Bassant's Lecture",
      dueAt: DateTime(2026, 7, 28, 20, 0),
    );
    expect(reminder.isOverdue(now), isFalse);
  });

  test('a reminder due exactly now is not yet overdue', () {
    final reminder = Reminder(id: 'c', title: 'Edge', dueAt: now);
    expect(reminder.isOverdue(now), isFalse);
  });
}
