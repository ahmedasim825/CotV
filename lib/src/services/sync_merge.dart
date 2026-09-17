// Every conflict rule in the sync engine, as pure functions.
//
// Nothing here touches Hive, Supabase or Riverpod, which is what makes the
// two-device tests cheap: a test drives these directly with two record
// values and asserts the pair converges, rather than standing up two
// devices to find out.

import '../models/habit.dart';
import '../models/habit_view.dart';
import '../models/sync_stamped.dart';
import '../models/user_settings.dart';

/// What to do with a record once both sides have been compared.
enum MergeDecision {
  /// Both sides already agree. Write nothing and push nothing.
  ///
  /// The common case by a wide margin, and worth detecting: Hive fires a
  /// change event per key written, so a pull that re-put every row it
  /// received would rebuild the UI once per record for no reason.
  inSync,

  /// Take the remote value: write it locally and mark it synced.
  applyRemote,

  /// Local wins. Nothing to write; the push will send it.
  keepLocal,

  /// Neither side's value survives intact — write the merged one locally
  /// *and* push it, so the other device converges on the same thing.
  applyAndPush,
}

class MergeResult<T> {
  const MergeResult(this.decision, this.value);

  const MergeResult.inSync() : decision = MergeDecision.inSync, value = null;

  const MergeResult.keepLocal()
      : decision = MergeDecision.keepLocal,
        value = null;

  final MergeDecision decision;

  /// The record to write locally. Null for [MergeDecision.inSync] and
  /// [MergeDecision.keepLocal], which write nothing.
  final T? value;
}

/// The default rule: per-record last-write-wins, skew-proof.
///
/// Three cases, and only one of them compares clocks across devices:
///
/// * **No local record** — take the remote one. Absence is not a deletion:
///   a fresh install has no tombstones, so it cannot push its emptiness
///   over the other device's data.
/// * **Local is clean** — the remote wins unconditionally. There is no
///   local edit to lose, so no comparison is needed or made.
/// * **Local is dirty** — a real conflict, and the only place a device
///   clock meets another device's. Skew is exposed here and nowhere else,
///   and short of vector clocks it is unavoidable.
///
/// A tie takes the remote, deliberately. Both devices apply the same rule,
/// so whoever pushed first wins and the pair converges; keeping local on
/// both sides would leave them disagreeing forever.
///
/// Server arrival order is *not* used as the tiebreak. A device that has
/// been offline for three days arrives last and would always win, which is
/// the wrong answer.
///
/// Accepted loss: two devices editing *different fields* of one record
/// while both are offline. The later write's whole record wins and the
/// earlier device's field edit is gone. [mergeHabit] is the one entity
/// where that was too expensive to accept.
MergeResult<T> resolveRecord<T extends SyncStamped>(T? local, T remote) {
  if (local == null) return MergeResult(MergeDecision.applyRemote, remote);

  final localMillis = local.updatedAtMillis ?? 0;
  final remoteMillis = remote.updatedAtMillis ?? 0;

  if (!local.isDirty) {
    return localMillis == remoteMillis
        ? const MergeResult.inSync()
        : MergeResult(MergeDecision.applyRemote, remote);
  }

  return remoteMillis >= localMillis
      ? MergeResult(MergeDecision.applyRemote, remote)
      : const MergeResult.keepLocal();
}

/// Habits, where the default rule loses data outright.
///
/// `completedDates` is rewritten wholesale on every toggle, so record-level
/// last-write-wins silently drops a check-in: tick Monday on the laptop and
/// Tuesday on the phone while both are offline, and one of them simply
/// never happened. So the dates are unioned, and `streakCount` is
/// recomputed from the merged set rather than taken from either side —
/// neither side's count describes a set neither side has seen.
///
/// Everything else on the habit (title, cadence, colour) still follows
/// [resolveRecord]'s clock comparison.
///
/// **Accepted loss:** un-ticking a day on one device is undone if the other
/// still holds that date and syncs afterwards. That failure is visible —
/// the tick reappears and can be undone again — where the record-LWW
/// failure is the silent loss of a completed day.
///
/// A `removedDates` tombstone list looks like the fix and is not: A removes
/// Monday, B later re-ticks Monday, and `union(completed) - union(removed)`
/// drops B's newer action. Making that converge needs a timestamp per date,
/// which is the `habit_check_ins` table in the plan — worth doing whole,
/// later, rather than half-built now.
MergeResult<Habit> mergeHabit(Habit? local, Habit remote, DateTime now) {
  // `streakCount` is derived from the dates and so is not a column — a
  // habit off the wire always arrives with zero. Recomputing here, before
  // anything compares or stores it, is what stops a pulled habit showing a
  // streak of nothing on the second device.
  final incoming = _withStreak(remote, now);
  final base = resolveRecord<Habit>(local, incoming);

  // Only a genuine conflict unions. A clean local habit holds exactly what
  // the server last gave it, so the remote strictly supersedes it — and
  // unioning here would resurrect every date un-ticked on the other device,
  // which would stop un-ticks propagating at all rather than only losing
  // the rare simultaneous one.
  if (local == null || !local.isDirty) return base;
  if (base.decision == MergeDecision.inSync) return base;

  final localDates = local.completedDates.map(normalizeDay).toSet();
  final remoteDates = incoming.completedDates.map(normalizeDay).toSet();
  final union = {...localDates, ...remoteDates};

  // Nothing to reconcile: the two sides already hold the same days.
  if (union.length == localDates.length && union.length == remoteDates.length) {
    return base;
  }

  // Whichever record won on the clock supplies the scalar fields; the dates
  // and the streak come from the union regardless.
  final winner = base.decision == MergeDecision.keepLocal ? local : incoming;
  final sorted = union.toList()..sort();

  return MergeResult(
    MergeDecision.applyAndPush,
    winner.copyWith(
      completedDates: sorted,
      streakCount: computeStreak(union, winner.frequency, now),
    ),
  );
}

Habit _withStreak(Habit habit, DateTime now) => habit.copyWith(
      streakCount: computeStreak(
        habit.completedDates.map(normalizeDay).toSet(),
        habit.frequency,
        now,
      ),
    );

/// [resolveRecord]'s rule, over a chat row rather than a model.
///
/// The same three cases, read off SQLite columns instead of [SyncStamped]:
/// `sync_state` carries dirtiness — a row the server has not seen is
/// `pending_upload` — and `client_updated_at` is device milliseconds.
///
/// Note `client_updated_at`, never `updated_at`. On a session the latter
/// means *last activity* and a rename deliberately does not move it, so
/// comparing it would make a renamed thread tie with the server's copy
/// forever.
///
/// Sessions carry a title that can be renamed on either device, so they
/// genuinely conflict. Messages are immutable in content and only ever move
/// to be tombstoned, so for them this decides a deletion and nothing else.
MergeDecision resolveChatRow({
  required Map<String, Object?>? local,
  required Map<String, Object?> remote,
}) {
  if (local == null) return MergeDecision.applyRemote;

  final localMillis = (local['client_updated_at'] as num?)?.toInt() ?? 0;
  final remoteMillis = (remote['client_updated_at'] as num?)?.toInt() ?? 0;

  if (local['sync_state'] != pendingUploadWire) {
    return localMillis == remoteMillis
        ? MergeDecision.inSync
        : MergeDecision.applyRemote;
  }

  return remoteMillis >= localMillis
      ? MergeDecision.applyRemote
      : MergeDecision.keepLocal;
}

/// `SyncState.pendingUpload.wire`, repeated rather than imported so this
/// file stays free of the storage layer and testable without a database.
const String pendingUploadWire = 'pending_upload';

/// The settings keys that leave the device.
///
/// An allowlist, not a denylist: the next field added to [UserSettings]
/// should not start syncing because nobody remembered to exclude it.
///
/// `isBiometricEnabled` is absent on purpose — the Keychain holds the
/// authoritative copy and the Hive field only mirrors it, so syncing it
/// would push one device's biometric state onto hardware that may not have
/// the sensor. `id` is absent because there is only ever one record.
///
/// `aiMemorySummary` *is* here: Milo's memory of the user is the thing most
/// worth having follow them between devices.
const Set<String> syncedSettingKeys = {
  'preAdhanNotificationMinutes',
  'latitude',
  'longitude',
  'themeId',
  'speaksReplies',
  'listensForWakeWord',
  'voiceName',
  'aiMemorySummary',
  'dailyCalorieTarget',
  'proteinTargetGrams',
  'carbTargetGrams',
  'fatTargetGrams',
};

/// [settings] as one row per key, ready to upsert.
Map<String, Object?> settingsToRows(UserSettings settings) => {
      'preAdhanNotificationMinutes': settings.preAdhanNotificationMinutes,
      'latitude': settings.latitude,
      'longitude': settings.longitude,
      'themeId': settings.themeId,
      'speaksReplies': settings.speaksReplies,
      'listensForWakeWord': settings.listensForWakeWord,
      'voiceName': settings.voiceName,
      'aiMemorySummary': settings.aiMemorySummary,
      'dailyCalorieTarget': settings.dailyCalorieTarget,
      'proteinTargetGrams': settings.proteinTargetGrams,
      'carbTargetGrams': settings.carbTargetGrams,
      'fatTargetGrams': settings.fatTargetGrams,
    };

/// One remote setting, with the device clock of the write that made it.
class RemoteSetting {
  const RemoteSetting(this.value, this.clientUpdatedAtMillis);

  final Object? value;
  final int clientUpdatedAtMillis;
}

/// The outcome of reconciling one device's settings with the server's.
class SettingsMerge {
  const SettingsMerge({
    required this.merged,
    required this.toPush,
    required this.base,
  });

  /// What this device should now hold.
  final UserSettings merged;

  /// The keys this device changed and the server has not seen. Only these
  /// are sent, so a device never overwrites a preference it did not touch.
  final Map<String, Object?> toPush;

  /// [merged]'s values, to be recorded as the new common ancestor once the
  /// push succeeds.
  final Map<String, Object?> base;
}

/// Reconciles settings key by key, against the last state known to be on
/// the server.
///
/// Settings are the worst case for record-level last-write-wins: one record
/// holding a dozen unrelated preferences, written by several independent
/// controllers. Two devices each changing a *different* preference offline
/// would lose one of them.
///
/// Per-key alone is not enough either, and the reason is worth stating.
/// There is one timestamp for the whole record — the time of the last
/// change to any key — so "is this remote key newer than my record?" says
/// nothing about whether *this device* ever touched that key. A device that
/// changed one preference a moment ago would shadow every other preference
/// the other device sent, then push its own stale values back over them.
/// Both devices converge, on the wrong values.
///
/// So the merge is three-way, against [base]: the values this device last
/// agreed with the server about. A key only counts as changed on a side if
/// it differs from that ancestor, which makes "I changed this" and "they
/// changed this" separately answerable, and only a key both sides changed
/// is a real conflict to resolve on the clock.
///
/// Keys outside [syncedSettingKeys] are ignored, whatever the server sends.
SettingsMerge mergeSettings({
  required UserSettings local,
  required Map<String, RemoteSetting> remote,
  required Map<String, Object?> base,
}) {
  final localRows = settingsToRows(local);
  final localMillis = local.updatedAtMillis ?? 0;

  // With no recorded ancestor — a first sync, or just after an account
  // switch — the factory defaults stand in for one. A preference still
  // sitting at its default is one this device has almost certainly never
  // set, and treating the whole record as locally-changed instead is what
  // makes a first sync flatten the other device's preferences with this
  // one's untouched defaults.
  //
  // The case it gets wrong is deliberately setting a preference *back* to
  // its default, on a device that has never synced, while the other device
  // holds something else. That edit is ignored once; any later edit syncs
  // normally, because by then there is a real ancestor.
  final ancestor = base.isEmpty ? settingsToRows(UserSettings()) : base;

  final resolved = <String, Object?>{};
  final toPush = <String, Object?>{};

  for (final key in syncedSettingKeys) {
    final localValue = localRows[key];
    final incoming = remote[key];

    final localChanged = localValue != ancestor[key];
    final remoteChanged =
        incoming != null && incoming.value != ancestor[key];

    if (remoteChanged && !localChanged) {
      resolved[key] = incoming.value;
    } else if (localChanged && !remoteChanged) {
      resolved[key] = localValue;
      toPush[key] = localValue;
    } else if (localChanged && remoteChanged) {
      // The only genuine conflict, and the only place a clock is consulted.
      if (incoming.clientUpdatedAtMillis > localMillis) {
        resolved[key] = incoming.value;
      } else {
        resolved[key] = localValue;
        toPush[key] = localValue;
      }
    } else {
      resolved[key] = localValue;
    }
  }

  return SettingsMerge(
    merged: _settingsFrom(local, resolved),
    toPush: toPush,
    base: resolved,
  );
}

/// [local] with [values] applied over it.
///
/// Built through the constructor rather than copyWith, because copyWith
/// reads `value ?? this.value` and so could never carry a *cleared* setting
/// across. Clearing your location on one device has to clear it on the
/// other.
UserSettings _settingsFrom(UserSettings local, Map<String, Object?> values) =>
    UserSettings(
      id: local.id,
      isBiometricEnabled: local.isBiometricEnabled,
      preAdhanNotificationMinutes:
          _int(values['preAdhanNotificationMinutes']) ??
              local.preAdhanNotificationMinutes,
      latitude: _double(values['latitude']),
      longitude: _double(values['longitude']),
      themeId: values['themeId'] as String?,
      speaksReplies: _bool(values['speaksReplies']) ?? local.speaksReplies,
      listensForWakeWord:
          _bool(values['listensForWakeWord']) ?? local.listensForWakeWord,
      voiceName: values['voiceName'] as String?,
      aiMemorySummary: values['aiMemorySummary'] as String?,
      dailyCalorieTarget: _int(values['dailyCalorieTarget']),
      proteinTargetGrams: _int(values['proteinTargetGrams']),
      carbTargetGrams: _int(values['carbTargetGrams']),
      fatTargetGrams: _int(values['fatTargetGrams']),
      updatedAtMillis: local.updatedAtMillis,
      syncedAtMillis: local.syncedAtMillis,
    );

// jsonb round-trips an integer as an int but a whole double as an int too,
// so every numeric read goes through `num` rather than casting.
int? _int(Object? value) => (value as num?)?.toInt();
double? _double(Object? value) => (value as num?)?.toDouble();
bool? _bool(Object? value) => value as bool?;
