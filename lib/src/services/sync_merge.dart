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
  final base = resolveRecord<Habit>(local, remote);

  // Only a genuine conflict unions. A clean local habit holds exactly what
  // the server last gave it, so the remote strictly supersedes it — and
  // unioning here would resurrect every date un-ticked on the other device,
  // which would stop un-ticks propagating at all rather than only losing
  // the rare simultaneous one.
  if (local == null || !local.isDirty) return base;
  if (base.decision == MergeDecision.inSync) return base;

  final union = <DateTime>{
    ...local.completedDates.map(normalizeDay),
    ...remote.completedDates.map(normalizeDay),
  };

  // Nothing to reconcile: one side's dates already contain the other's.
  final localDates = local.completedDates.map(normalizeDay).toSet();
  final remoteDates = remote.completedDates.map(normalizeDay).toSet();
  if (union.length == localDates.length && union.length == remoteDates.length) {
    return base;
  }

  // Whichever record won on the clock supplies the scalar fields; the dates
  // and the streak come from the union regardless.
  final winner =
      base.decision == MergeDecision.keepLocal ? local : remote;
  final sorted = union.toList()..sort();

  return MergeResult(
    MergeDecision.applyAndPush,
    winner.copyWith(
      completedDates: sorted,
      streakCount: computeStreak(union, winner.frequency, now),
    ),
  );
}

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

/// Folds remote settings into [local], key by key.
///
/// Settings are the worst case for record-level last-write-wins: one record
/// holding a dozen unrelated preferences, written by several independent
/// controllers. Two devices each changing a different preference offline
/// would lose one of them. Per-key is cheap here precisely because the
/// model is already a bag of independent scalars.
///
/// A remote key is taken only when its write is newer than the local
/// record's own `updatedAtMillis`. That is conservative toward local
/// recency — the local stamp is the time of the last change to *any* key,
/// so it may be later than the remote key's and shadow it. It is not
/// symmetric, and it does converge: both sides end up writing back the
/// newer value and pushing it, in at most two rounds.
///
/// Keys outside [syncedSettingKeys] are ignored, whatever the server sends.
UserSettings applyRemoteSettings(
  UserSettings local,
  Map<String, RemoteSetting> remote,
) {
  final localMillis = local.updatedAtMillis ?? 0;

  Object? pick(String key, Object? current) {
    if (!syncedSettingKeys.contains(key)) return current;
    final incoming = remote[key];
    if (incoming == null) return current;
    return incoming.clientUpdatedAtMillis > localMillis
        ? incoming.value
        : current;
  }

  // Built through the constructor rather than copyWith, because copyWith
  // reads `value ?? this.value` and so cannot carry a cleared setting
  // across. Clearing your location on one device has to clear it on the
  // other.
  return UserSettings(
    id: local.id,
    isBiometricEnabled: local.isBiometricEnabled,
    preAdhanNotificationMinutes: _int(
          pick('preAdhanNotificationMinutes', local.preAdhanNotificationMinutes),
        ) ??
        local.preAdhanNotificationMinutes,
    latitude: _double(pick('latitude', local.latitude)),
    longitude: _double(pick('longitude', local.longitude)),
    themeId: pick('themeId', local.themeId) as String?,
    speaksReplies:
        _bool(pick('speaksReplies', local.speaksReplies)) ?? local.speaksReplies,
    listensForWakeWord:
        _bool(pick('listensForWakeWord', local.listensForWakeWord)) ??
            local.listensForWakeWord,
    voiceName: pick('voiceName', local.voiceName) as String?,
    aiMemorySummary: pick('aiMemorySummary', local.aiMemorySummary) as String?,
    dailyCalorieTarget:
        _int(pick('dailyCalorieTarget', local.dailyCalorieTarget)),
    proteinTargetGrams:
        _int(pick('proteinTargetGrams', local.proteinTargetGrams)),
    carbTargetGrams: _int(pick('carbTargetGrams', local.carbTargetGrams)),
    fatTargetGrams: _int(pick('fatTargetGrams', local.fatTargetGrams)),
    updatedAtMillis: local.updatedAtMillis,
    syncedAtMillis: local.syncedAtMillis,
  );
}

// jsonb round-trips an integer as an int but a whole double as an int too,
// so every numeric read goes through `num` rather than casting.
int? _int(Object? value) => (value as num?)?.toInt();
double? _double(Object? value) => (value as num?)?.toDouble();
bool? _bool(Object? value) => value as bool?;
