import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/study_log.dart';
import '../models/subject.dart';
import '../models/sync_stamped.dart';
import '../repositories/syncable_repository.dart';
import '../services/milo_sync_service.dart';
import '../services/sync_merge.dart';
import '../storage/local_storage.dart';
import '../storage/sync_metadata.dart';
import 'auth_providers.dart';
import 'nutrition_providers.dart' show syncErrorProvider;
import 'study_providers.dart';

/// The sync layer, or null when there is no backend or nobody signed in.
///
/// Null rather than throwing, for the same reason
/// [nutritionSyncServiceProvider] is: every caller null-checks, and that
/// null-check is what keeps "works offline" and "works signed out" the
/// same code path rather than two.
final miloSyncServiceProvider = Provider<MiloSyncService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null || !ref.watch(isSignedInProvider)) return null;
  return SupabaseMiloSyncService(client);
});

final syncMetadataProvider = Provider<SyncMetadata>(
  (ref) => SyncMetadata(Hive.box<dynamic>(HiveBoxes.syncMeta)),
);

/// Whose data this is, as a plain id.
///
/// A seam rather than reading [currentUserProvider] inside the controller:
/// the engine only ever needs the id, and a test that had to build a whole
/// gotrue `User` to stand up two devices would be testing the wrong thing.
final syncUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

/// What the account section renders.
class SyncStatus {
  const SyncStatus({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.blockedByAccountSwitch = false,
  });

  final bool isSyncing;
  final DateTime? lastSyncedAt;

  /// True when this device's local data belongs to a different Supabase
  /// account than the one currently signed in.
  ///
  /// Sync refuses to run in that state rather than merging one account's
  /// tasks into another's. Resolved by [SyncController.adoptCurrentAccount].
  final bool blockedByAccountSwitch;

  SyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    bool? blockedByAccountSwitch,
  }) =>
      SyncStatus(
        isSyncing: isSyncing ?? this.isSyncing,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        blockedByAccountSwitch:
            blockedByAccountSwitch ?? this.blockedByAccountSwitch,
      );
}

/// Pulls, merges and pushes each synced entity.
///
/// Order within a cycle is pull, merge, push — never the reverse. Pulling
/// first means a locally-dirty record is compared against the newest
/// remote version before it is sent, so a push cannot clobber something it
/// has not seen.
class SyncController extends Notifier<SyncStatus> {
  /// Guards against a sync-applied write triggering another sync. Debounce
  /// and idempotence would terminate that loop anyway; this saves the
  /// round trip.
  bool _applyingRemote = false;

  bool get isApplyingRemote => _applyingRemote;

  @override
  SyncStatus build() {
    // Re-runs on sign-in and sign-out.
    ref.watch(isSignedInProvider);
    return const SyncStatus();
  }

  MiloSyncService? get _service => ref.read(miloSyncServiceProvider);
  SyncMetadata get _metadata => ref.read(syncMetadataProvider);

  /// One full cycle across every synced entity.
  ///
  /// Does nothing at all when signed out or unconfigured, which is the
  /// normal state of a build with no Supabase defines.
  Future<void> syncAll() async {
    final service = _service;
    if (service == null || state.isSyncing) return;

    final userId = ref.read(syncUserIdProvider);
    if (userId == null) return;

    if (!await _claimAccount(userId)) return;

    state = state.copyWith(isSyncing: true);
    _applyingRemote = true;
    try {
      await _syncSubjects(service);
      await _syncStudyLogs(service);

      ref.read(syncErrorProvider.notifier).clear();
      state = SyncStatus(lastSyncedAt: DateTime.now());
    } on MiloSyncException catch (error) {
      // Left dirty on purpose: the records that did not go up are still
      // marked as needing to, and the next trigger retries them. There is
      // no backoff beyond "next trigger", and no offline detection —
      // a failed push is a failed push whatever the reason.
      ref.read(syncErrorProvider.notifier).set(error.message);
      state = state.copyWith(isSyncing: false);
    } finally {
      _applyingRemote = false;
      if (state.isSyncing) state = state.copyWith(isSyncing: false);
    }
  }

  /// Records which account this device's data belongs to, or refuses when
  /// it already belongs to another.
  ///
  /// Signing into a second account on a device full of the first one's
  /// tasks would otherwise push them all into the new account.
  Future<bool> _claimAccount(String userId) async {
    final last = _metadata.lastSyncedUserId;
    if (last == null) {
      await _metadata.setLastSyncedUserId(userId);
      return true;
    }
    if (last == userId) return true;

    state = state.copyWith(blockedByAccountSwitch: true);
    ref.read(syncErrorProvider.notifier).set(
          'This device holds data from a different account. Sync is paused '
          'so it is not merged into this one.',
        );
    return false;
  }

  /// Accepts the signed-in account as this device's, and starts again from
  /// an empty cursor so everything is re-read.
  ///
  /// Local records keep their own timestamps, so the merge decides what
  /// wins per record rather than one side flattening the other.
  Future<void> adoptCurrentAccount() async {
    final userId = ref.read(syncUserIdProvider);
    if (userId == null) return;
    await _metadata.setLastSyncedUserId(userId);
    await _metadata.resetCursors();
    state = state.copyWith(blockedByAccountSwitch: false);
    ref.read(syncErrorProvider.notifier).clear();
    await syncAll();
  }

  /// Forgets where each pull got to, without touching local records.
  ///
  /// Called on sign-out. Local data stays: unlike the food log, tasks and
  /// chat have a local store that is useful signed out, and deleting it
  /// would make signing out a destructive act.
  Future<void> forgetCursors() => _metadata.resetCursors();

  Future<void> _syncSubjects(MiloSyncService service) => _syncEntity<Subject>(
        name: 'subjects',
        repository: _syncable<Subject>(ref.read(subjectRepositoryProvider)),
        fetch: service.fetchSubjects,
        push: service.pushSubjects,
      );

  Future<void> _syncStudyLogs(MiloSyncService service) =>
      _syncEntity<StudyLog>(
        name: 'study_logs',
        repository: _syncable<StudyLog>(ref.read(studyLogRepositoryProvider)),
        fetch: service.fetchStudyLogs,
        push: service.pushStudyLogs,
      );

  /// Pull, merge, push for one entity.
  ///
  /// [merge] defaults to [resolveRecord]; only habits override it.
  Future<void> _syncEntity<T extends SyncStamped>({
    required String name,
    required SyncableRepository<T>? repository,
    required Future<List<RemoteRecord<T>>> Function(String?) fetch,
    required Future<void> Function(Iterable<T>) push,
    MergeResult<T> Function(T? local, T remote)? merge,
  }) async {
    if (repository == null) return;
    final resolve = merge ?? resolveRecord<T>;
    final metadata = _metadata;

    // ---- pull ----
    final incoming = await fetch(metadata.lastPulled(name));
    final local = {
      for (final record in repository.allIncludingDeleted()) record.id: record,
    };

    final merged = <String, T>{};
    String? cursor;
    for (final remote in incoming) {
      cursor = remote.cursor;
      final result = resolve(local[remote.record.id], remote.record);
      switch (result.decision) {
        // Nothing to write. keepLocal needs no action either: the record is
        // dirty, so the push below picks it up.
        case MergeDecision.inSync:
        case MergeDecision.keepLocal:
          break;
        case MergeDecision.applyRemote:
          // Only written when the value actually differs, so a steady-state
          // pull fires no box events and rebuilds nothing. Hive notifies
          // per key written, not per batch.
          await repository.applyRemote(result.value as T);
        case MergeDecision.applyAndPush:
          final value = result.value as T;
          await repository.applyRemote(value);
          // Neither side held this value, so the other device has not seen
          // it either — it has to go up as well as down.
          merged[value.id] = value;
      }
    }

    // Advanced only after every record in the batch has been applied. A
    // cursor moved first would skip the remainder on a crash.
    if (cursor != null) await metadata.setLastPulled(name, cursor);

    // ---- push ----
    final outgoing = <String, T>{
      for (final record in repository.allIncludingDeleted())
        if (record.isDirty) record.id: record,
      ...merged,
    };
    if (outgoing.isEmpty) return;

    await push(outgoing.values);
    for (final record in outgoing.values) {
      await repository.markSynced(record.id, record.updatedAtMillis ?? 0);
    }
  }
}

/// The repository as the engine sees it, or null when it is not a real one.
///
/// The domain providers hand back an abstract type, and a test fake
/// implements that interface without implementing [SyncableRepository].
/// Returning null there means such a fake simply does not sync, rather than
/// crashing a widget test that never asked to.
SyncableRepository<T>? _syncable<T extends SyncStamped>(Object repository) =>
    repository is SyncableRepository<T> ? repository : null;

final syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);
