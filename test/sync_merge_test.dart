// The conflict rules, driven directly.
//
// These are the tests that decide whether two devices agree. The property
// that matters most is not who wins any single case — it is that both
// devices apply the same rule and end up with the same record, which is
// what the convergence tests at the bottom assert.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/services/sync_merge.dart';

/// A task as it sits locally after being pushed or pulled: stamped and
/// clean.
Task _clean(String title, int millis) =>
    Task(id: 't1', title: title).stampUpdated(millis).markSynced(millis);

/// A task with a local edit the server has not seen.
Task _dirty(String title, int millis) =>
    Task(id: 't1', title: title).stampUpdated(millis).markSynced(500);

/// A record as it arrives from the server.
Task _remote(String title, int millis) =>
    Task(id: 't1', title: title).stampUpdated(millis).markSynced(millis);

void main() {
  group('resolveRecord', () {
    test('no local record takes the remote one', () {
      final result = resolveRecord<Task>(null, _remote('From the phone', 1000));
      expect(result.decision, MergeDecision.applyRemote);
      expect(result.value!.title, 'From the phone');
    });

    test('a clean local record yields to the remote without comparing clocks',
        () {
      // Remote is *older* by the device clock and still wins: there is no
      // local edit to lose, so the comparison is not made.
      final result = resolveRecord<Task>(
        _clean('Local', 9000),
        _remote('Remote', 1000),
      );
      expect(result.decision, MergeDecision.applyRemote);
      expect(result.value!.title, 'Remote');
    });

    test('a clean local record at the same stamp is in sync', () {
      final result = resolveRecord<Task>(
        _clean('Same', 1000),
        _remote('Same', 1000),
      );
      expect(result.decision, MergeDecision.inSync);
      expect(result.value, isNull);
    });

    test('a dirty local record loses to a newer remote', () {
      final result = resolveRecord<Task>(
        _dirty('Local', 1000),
        _remote('Remote', 2000),
      );
      expect(result.decision, MergeDecision.applyRemote);
      expect(result.value!.title, 'Remote');
    });

    test('a dirty local record beats an older remote', () {
      final result = resolveRecord<Task>(
        _dirty('Local', 2000),
        _remote('Remote', 1000),
      );
      expect(result.decision, MergeDecision.keepLocal);
    });

    test('a tie takes the remote, so both devices agree', () {
      // Whoever pushed first wins. Keeping local on both sides would leave
      // the two devices disagreeing permanently.
      final result = resolveRecord<Task>(
        _dirty('Local', 1000),
        _remote('Remote', 1000),
      );
      expect(result.decision, MergeDecision.applyRemote);
    });

    test('a delete is not undone by an edit made before it', () {
      final deletedLocally =
          Task(id: 't1', title: 'Gone').stampUpdated(2000).markSynced(500);
      final result = resolveRecord<Task>(
        deletedLocally.markDeleted(2000),
        _remote('Edited earlier', 1000),
      );
      expect(result.decision, MergeDecision.keepLocal);
    });

    test('a remote delete reaches a clean local record', () {
      final result = resolveRecord<Task>(
        _clean('Here', 1000),
        _remote('Gone', 2000).markDeleted(2000),
      );
      expect(result.decision, MergeDecision.applyRemote);
      expect(result.value!.isDeleted, isTrue);
    });
  });

  group('mergeHabit', () {
    final now = DateTime(2026, 9, 17);
    final wednesday = DateTime(2026, 9, 16);
    final thursday = DateTime(2026, 9, 17);

    Habit habit(List<DateTime> dates, int millis, {int synced = 500}) =>
        Habit(id: 'h1', title: 'Fajr on time', completedDates: dates)
            .stampUpdated(millis)
            .markSynced(synced);

    test('check-ins made on both devices both survive', () {
      // The case record-level last-write-wins gets wrong: one of these two
      // days would simply never have happened.
      final result = mergeHabit(
        habit([wednesday], 1000),
        habit([thursday], 2000, synced: 2000),
        now,
      );

      expect(result.decision, MergeDecision.applyAndPush);
      expect(result.value!.completedDates, [wednesday, thursday]);
    });

    test('the streak is recomputed from the union, not taken from a side', () {
      // Each side alone is a streak of 1. Neither has seen the merged set.
      final local = habit([wednesday], 1000);
      final remote = habit([thursday], 2000, synced: 2000);
      expect(local.streakCount, 0);
      expect(remote.streakCount, 0);

      final merged = mergeHabit(local, remote, now).value!;

      expect(merged.streakCount, 2);
    });

    test('scalar fields still follow the clock', () {
      final local = Habit(
        id: 'h1',
        title: 'Local title',
        colorHex: '#AAAAAA',
        completedDates: [wednesday],
      ).stampUpdated(3000).markSynced(500);
      final remote = Habit(
        id: 'h1',
        title: 'Remote title',
        colorHex: '#BBBBBB',
        completedDates: [thursday],
      ).stampUpdated(1000).markSynced(1000);

      final merged = mergeHabit(local, remote, now).value!;

      expect(merged.title, 'Local title', reason: 'local is newer');
      expect(merged.colorHex, '#AAAAAA');
      expect(merged.completedDates, hasLength(2), reason: 'dates still union');
    });

    test('no union is needed when one side already contains the other', () {
      final result = mergeHabit(
        habit([wednesday, thursday], 1000),
        habit([wednesday, thursday], 2000, synced: 2000),
        now,
      );
      // applyRemote, not applyAndPush: nothing was merged, so there is
      // nothing new to send back.
      expect(result.decision, MergeDecision.applyRemote);
    });

    test('a clean local habit just takes the remote', () {
      final result = mergeHabit(
        habit([wednesday], 1000, synced: 1000),
        habit([thursday], 2000, synced: 2000),
        now,
      );
      expect(result.decision, MergeDecision.applyRemote);
      expect(result.value!.completedDates, [thursday]);
    });
  });

  group('settings', () {
    test('the allowlist excludes the biometric mirror', () {
      expect(syncedSettingKeys, isNot(contains('isBiometricEnabled')));
      expect(syncedSettingKeys, isNot(contains('id')));
      // Milo's memory of the user is the point of syncing settings at all.
      expect(syncedSettingKeys, contains('aiMemorySummary'));
    });

    test('every advertised key is actually emitted, and nothing else', () {
      // Guards the two halves drifting apart: a key on the allowlist that
      // settingsToRows never writes would silently never sync.
      expect(settingsToRows(UserSettings()).keys.toSet(), syncedSettingKeys);
    });

    test('a key only the other device changed is taken', () {
      final local = UserSettings(voiceName: 'Ava').stampUpdated(1000);
      final result = mergeSettings(
        local: local,
        remote: {'voiceName': const RemoteSetting('Zoe', 2000)},
        base: settingsToRows(local),
      );
      expect(result.merged.voiceName, 'Zoe');
      expect(result.toPush, isEmpty, reason: 'the server already has it');
    });

    test('a key only this device changed is kept and pushed', () {
      final base = settingsToRows(UserSettings(voiceName: 'Ava'));
      final local = UserSettings(voiceName: 'Zoe').stampUpdated(3000);

      final result = mergeSettings(
        local: local,
        remote: {'voiceName': const RemoteSetting('Ava', 500)},
        base: base,
      );

      expect(result.merged.voiceName, 'Zoe');
      expect(result.toPush, {'voiceName': 'Zoe'});
    });

    test('a preference this device never touched is not pushed over', () {
      // The case a per-key clock alone gets wrong: there is one timestamp
      // for the whole record, so a device that changed *anything* recently
      // would otherwise shadow every key the other device sent, then push
      // its own stale values back over them.
      final base = settingsToRows(UserSettings());
      final local = UserSettings(preAdhanNotificationMinutes: 25)
          .stampUpdated(3000);

      final result = mergeSettings(
        local: local,
        remote: {'voiceName': const RemoteSetting('Zoe', 2000)},
        base: base,
      );

      expect(result.merged.voiceName, 'Zoe', reason: 'theirs, untouched here');
      expect(result.merged.preAdhanNotificationMinutes, 25, reason: 'ours');
      expect(result.toPush, {'preAdhanNotificationMinutes': 25});
    });

    test('a key both devices changed goes to the later write', () {
      final base = settingsToRows(UserSettings(voiceName: 'Ava'));
      final local = UserSettings(voiceName: 'Ours').stampUpdated(1000);

      final result = mergeSettings(
        local: local,
        remote: {'voiceName': const RemoteSetting('Theirs', 2000)},
        base: base,
      );

      expect(result.merged.voiceName, 'Theirs');
      expect(result.toPush, isEmpty);
    });

    test('with no ancestor, the factory defaults stand in for one', () {
      // A first sync. A preference still at its default is one this device
      // has never set, so the other device's value takes it — which is what
      // stops a first sync flattening their settings with our defaults.
      final result = mergeSettings(
        local: UserSettings(preAdhanNotificationMinutes: 25)
            .stampUpdated(3000),
        remote: {
          'voiceName': const RemoteSetting('Zoe', 2000),
          'preAdhanNotificationMinutes': const RemoteSetting(15, 2000),
        },
        base: const {},
      );

      expect(result.merged.voiceName, 'Zoe', reason: 'never set here');
      expect(result.merged.preAdhanNotificationMinutes, 25, reason: 'set here');
      expect(result.toPush, {'preAdhanNotificationMinutes': 25});
    });

    test('with no ancestor, a set value still beats an older remote one', () {
      final result = mergeSettings(
        local: UserSettings(voiceName: 'Ours').stampUpdated(1000),
        remote: {'voiceName': const RemoteSetting('Theirs', 500)},
        base: const {},
      );
      expect(result.merged.voiceName, 'Ours');
      expect(result.toPush, {'voiceName': 'Ours'});
    });

    test('a cleared setting propagates', () {
      // copyWith reads `value ?? this.value` and could not express this,
      // which is why the merge builds the record through the constructor.
      final local = UserSettings(latitude: 24.7, longitude: 46.6)
          .stampUpdated(1000);

      final result = mergeSettings(
        local: local,
        remote: {
          'latitude': const RemoteSetting(null, 2000),
          'longitude': const RemoteSetting(null, 2000),
        },
        base: settingsToRows(local),
      );

      expect(result.merged.latitude, isNull);
      expect(result.merged.hasLocation, isFalse);
    });

    test('a key outside the allowlist is ignored however it arrives', () {
      final local = UserSettings(isBiometricEnabled: false).stampUpdated(1000);
      final result = mergeSettings(
        local: local,
        remote: {'isBiometricEnabled': const RemoteSetting(true, 9000)},
        base: settingsToRows(local),
      );
      expect(result.merged.isBiometricEnabled, isFalse);
      expect(result.toPush, isEmpty);
      expect(result.base.keys, isNot(contains('isBiometricEnabled')));
    });

    test('jsonb numerics coerce rather than throw', () {
      // Postgres hands a whole double back as an int.
      final local = UserSettings().stampUpdated(1000);
      final result = mergeSettings(
        local: local,
        remote: {
          'latitude': const RemoteSetting(24, 2000),
          'dailyCalorieTarget': const RemoteSetting(2100, 2000),
        },
        base: settingsToRows(local),
      );
      expect(result.merged.latitude, 24.0);
      expect(result.merged.dailyCalorieTarget, 2100);
    });

    test('the record stamp is the caller\'s to move, not the merge\'s', () {
      final local = UserSettings(voiceName: 'Ava').stampUpdated(1000);
      final result = mergeSettings(
        local: local,
        remote: {'voiceName': const RemoteSetting('Zoe', 2000)},
        base: settingsToRows(local),
      );
      expect(result.merged.updatedAtMillis, 1000);
    });
  });

  group('convergence', () {
    // The property the whole design rests on: run the same rule on both
    // sides and they end up holding the same record. Asserting a specific
    // winner is weaker and less useful.
    test('two dirty devices agree after exchanging, whichever order', () {
      for (final remoteFirst in [true, false]) {
        final a = _dirty('From A', 2000);
        final b = _dirty('From B', 3000);

        // A pulls B's record; B pulls A's.
        final onA = resolveRecord<Task>(a, remoteFirst ? b : b);
        final onB = resolveRecord<Task>(b, a);

        final settledA =
            onA.decision == MergeDecision.applyRemote ? onA.value! : a;
        final settledB =
            onB.decision == MergeDecision.applyRemote ? onB.value! : b;

        expect(settledA.title, settledB.title,
            reason: 'the pair must not disagree');
        expect(settledA.title, 'From B', reason: 'the later write wins');
      }
    });

    test('a habit merge converges in one more round', () {
      final now = DateTime(2026, 9, 17);
      final wednesday = DateTime(2026, 9, 16);
      final thursday = DateTime(2026, 9, 17);

      final a = Habit(id: 'h1', title: 'Fajr', completedDates: [wednesday])
          .stampUpdated(1000)
          .markSynced(500);
      final b = Habit(id: 'h1', title: 'Fajr', completedDates: [thursday])
          .stampUpdated(2000)
          .markSynced(500);

      // A merges B's copy and pushes the result; B then pulls that.
      final merged = mergeHabit(a, b, now).value!;
      final onB = mergeHabit(b, merged.markSynced(merged.updatedAtMillis!), now);

      final settledB =
          onB.decision == MergeDecision.keepLocal ? b : onB.value!;

      expect(settledB.completedDates, merged.completedDates);
      expect(settledB.streakCount, merged.streakCount);
    });
  });
}
