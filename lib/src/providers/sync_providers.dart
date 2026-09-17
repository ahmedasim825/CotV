import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/habit.dart';
import '../models/study_log.dart';
import '../models/subject.dart';
import '../models/sync_stamped.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import '../repositories/chat_session_repository.dart';
import '../repositories/syncable_repository.dart';
import '../services/milo_sync_service.dart';
import '../services/sync_merge.dart';
import '../storage/local_storage.dart';
import '../storage/sync_metadata.dart';
import 'auth_providers.dart';
import 'chat_session_providers.dart';
import 'habit_providers.dart';
import 'nutrition_providers.dart' show syncErrorProvider;
import 'study_providers.dart';
import 'task_providers.dart';
import 'task_reminder_providers.dart';
import 'user_settings_providers.dart';

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
      // Subjects before study logs, so a log that arrives for a subject
      // made on the other device has something to point at by the time
      // anything renders it.
      await _syncSubjects(service);
      await _syncStudyLogs(service);
      await _syncTasks(service);
      await _syncHabits(service);
      await _syncSettings(service);
      await _syncChat(service);

      // Only after a clean cycle, and only while signed in. A device that
      // drops its tombstones before pushing them resurrects those rows on
      // the next pull.
      await _purgeTombstones();

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

  Future<void> _syncTasks(MiloSyncService service) => _syncEntity<Task>(
        name: 'tasks',
        repository: _syncable<Task>(ref.read(taskRepositoryProvider)),
        fetch: service.fetchTasks,
        push: service.pushTasks,
        onApplied: _reconcileReminder,
      );

  /// A notification is local to the device that scheduled it, so a task
  /// pulled from the phone has no reminder on the laptop until one is
  /// scheduled here. Without this, a reminder set on one device simply
  /// never fires on the other.
  ///
  /// Best-effort, following the convention the write paths already use: a
  /// refused notification permission must not fail the sync that carried
  /// the task.
  Future<void> _reconcileReminder(Task task) async {
    final reminders = ref.read(taskReminderControllerProvider);
    if (task.isDeleted) {
      await reminders.cancel(task.id);
    } else {
      // Handles both directions — it cancels when the task no longer wants
      // a reminder, which is what a completed-elsewhere task looks like.
      await reminders.sync(task);
    }
  }

  Future<void> _syncHabits(MiloSyncService service) => _syncEntity<Habit>(
        name: 'habits',
        repository: _syncable<Habit>(ref.read(habitRepositoryProvider)),
        fetch: service.fetchHabits,
        push: service.pushHabits,
        // The one entity that does not take the default rule: see
        // [mergeHabit] for why record-level LWW loses a check-in here.
        merge: (local, remote) => mergeHabit(local, remote, DateTime.now()),
      );

  /// Settings, which sync per key rather than per record.
  ///
  /// Different enough in shape from the others to be worth its own method:
  /// there is exactly one record, it is never deleted, and the unit that
  /// travels is a key rather than a row.
  Future<void> _syncSettings(MiloSyncService service) async {
    final domain = ref.read(userSettingsRepositoryProvider);
    final repository = _syncable<UserSettings>(domain);
    if (repository == null) return;
    final metadata = _metadata;

    const name = 'user_settings';
    final (incoming, cursor) =
        await service.fetchSettings(metadata.lastPulled(name));

    final local = domain.get();
    final result = mergeSettings(
      local: local,
      remote: incoming,
      base: metadata.settingsBase,
    );

    // Written only when something actually changed: the settings box is
    // watched by key, and a no-op write would rebuild every screen that
    // reads a preference on every sync tick.
    if (!mapEquals(settingsToRows(local), settingsToRows(result.merged))) {
      await repository.applyRemote(result.merged);
    }
    if (cursor != null) await metadata.setLastPulled(name, cursor);

    if (result.toPush.isNotEmpty) {
      // Only the keys this device actually changed, so it never writes a
      // preference it did not touch over the other device's.
      final stamp = local.updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
      await service.pushSettings(result.toPush, stamp);
      await repository.markSynced(result.merged.id, stamp);
    }

    // Recorded only once the push has succeeded: an ancestor claiming
    // agreement that never reached the server would make the next merge
    // treat this device's unsent changes as already shared, and drop them.
    await metadata.setSettingsBase(result.base);
  }

  /// How long a tombstone is kept after the server has acknowledged it.
  ///
  /// Long enough that a device offline for a normal stretch still learns
  /// about the deletion. The hazard at the far end is a device offline
  /// longer than this pushing its live copy back and resurrecting the row —
  /// unlikely on a two-device personal setup, and the failure is a
  /// reappearing row rather than a lost one.
  static const Duration tombstoneRetention = Duration(days: 30);

  Future<void> _purgeTombstones() async {
    final cutoff = DateTime.now().subtract(tombstoneRetention);
    for (final repository in [
      _syncable<Subject>(ref.read(subjectRepositoryProvider)),
      _syncable<StudyLog>(ref.read(studyLogRepositoryProvider)),
      _syncable<Task>(ref.read(taskRepositoryProvider)),
      _syncable<Habit>(ref.read(habitRepositoryProvider)),
    ]) {
      await repository?.purgeTombstonesBefore(cutoff.millisecondsSinceEpoch);
    }
  }

  /// Threads and their messages.
  ///
  /// Its own method rather than two calls to [_syncEntity], because the two
  /// tables are not independent: a message has a foreign key to its
  /// session, so sessions are applied first on the way down and pushed
  /// first on the way up, and the whole pull batch goes inside one
  /// [ChatSessionRepository.transaction] — which notifies exactly once at
  /// COMMIT. Applying a fifty-message thread outside one would re-query the
  /// session list fifty times and rebuild the drawer with it.
  Future<void> _syncChat(MiloSyncService service) async {
    final domain = ref.read(chatSessionRepositoryProvider);
    if (domain is! ChatSyncRepository) return;
    final repository = domain as ChatSyncRepository;
    final metadata = _metadata;

    final sessions =
        await service.fetchChatSessions(metadata.lastPulled('chat_sessions'));
    final messages =
        await service.fetchChatMessages(metadata.lastPulled('chat_messages'));

    String? sessionCursor;
    String? messageCursor;

    if (sessions.isNotEmpty || messages.isNotEmpty) {
      final touched = <String>{};

      await domain.transaction(() async {
        for (final incoming in sessions) {
          final id = incoming.record['id'] as String;
          final decision = resolveChatRow(
            local: repository.sessionRow(id),
            remote: incoming.record,
          );
          if (decision == MergeDecision.applyRemote) {
            repository.applyRemoteSession(incoming.record);
            touched.add(id);
          }
          sessionCursor = incoming.cursor;
        }

        for (final incoming in messages) {
          final sessionId = incoming.record['session_id'] as String;
          // The foreign key would refuse it, and the cursor must not move
          // past a row that was never applied — the session will arrive on
          // a later cycle and this message with it.
          if (repository.sessionRow(sessionId) == null) break;

          final id = incoming.record['id'] as String;
          final decision = resolveChatRow(
            local: repository.messageRow(id),
            remote: incoming.record,
          );
          if (decision == MergeDecision.applyRemote) {
            repository.applyRemoteMessage(incoming.record);
            touched.add(sessionId);
          }
          messageCursor = incoming.cursor;
        }

        // A thread both devices appended to has a transcript neither side's
        // stored timestamp describes. Recomputing also re-touches the
        // session row, which is what makes sessionMessagesProvider — a
        // plain Provider keyed off the session *list* — re-read the
        // messages that just arrived.
        for (final id in touched) {
          repository.refreshSessionTimestamp(id);
        }
      });
    }

    if (sessionCursor != null) {
      await metadata.setLastPulled('chat_sessions', sessionCursor!);
    }
    if (messageCursor != null) {
      await metadata.setLastPulled('chat_messages', messageCursor!);
    }

    // Sessions before messages here too, so the server's foreign key sees
    // the parent first.
    final pendingSessions = repository.pendingSessions();
    if (pendingSessions.isNotEmpty) {
      await service.pushChatSessions(pendingSessions);
      repository.markSessionsSynced(
        pendingSessions.map((row) => row['id'] as String),
      );
    }

    final pendingMessages = repository.pendingMessages();
    if (pendingMessages.isNotEmpty) {
      await service.pushChatMessages(pendingMessages);
      repository.markMessagesSynced(
        pendingMessages.map((row) => row['id'] as String),
      );
    }
  }

  /// Pull, merge, push for one entity.
  ///
  /// [merge] defaults to [resolveRecord]; only habits override it.
  /// [onApplied] runs for each record a pull actually changed, for the side
  /// effects a local write would have performed — scheduling a task's
  /// notification, in the one case that has any.
  Future<void> _syncEntity<T extends SyncStamped>({
    required String name,
    required SyncableRepository<T>? repository,
    required Future<List<RemoteRecord<T>>> Function(String?) fetch,
    required Future<void> Function(Iterable<T>) push,
    MergeResult<T> Function(T? local, T remote)? merge,
    Future<void> Function(T record)? onApplied,
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
          await onApplied?.call(result.value as T);
        case MergeDecision.applyAndPush:
          final value = result.value as T;
          await repository.applyRemote(value);
          await onApplied?.call(value);
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

/// Decides when [SyncController.syncAll] runs.
///
/// Kept alive by `ref.watch(syncSchedulerProvider)` in [AppShell], beside
/// the other notifiers watched there for the reason that file documents: a
/// Riverpod notifier nothing listens to is never constructed.
///
/// Its own [AppLifecycleListener] rather than borrowing `StudyNotifier`'s
/// or `SecurityGate`'s — two unrelated concerns sharing one observer is how
/// one of them ends up silently not running.
class SyncScheduler extends Notifier<void> {
  /// Long enough that a burst of edits — checking off four tasks in a row —
  /// is one cycle rather than four.
  static const Duration writeDebounce = Duration(seconds: 4);

  /// The backstop, and on Windows the main one.
  ///
  /// A desktop window is seldom "paused", so `resumed` rarely fires there
  /// and resume alone would mean a laptop left open never pulls at all.
  static const Duration pollInterval = Duration(minutes: 5);

  Timer? _debounce;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;

  SyncController get _sync => ref.read(syncControllerProvider.notifier);

  @override
  void build() {
    final signedIn = ref.watch(isSignedInProvider);

    ref.onDispose(() {
      _debounce?.cancel();
      _poll?.cancel();
      _lifecycle?.dispose();
    });

    if (!signedIn) {
      // Not a sign-out hook — this also runs on first build while signed
      // out. Cursors are reset by the sign-out path itself.
      return;
    }

    // Signing in is the one trigger that must pull everything: the cursors
    // start empty, so this is the full download.
    Future.microtask(_sync.syncAll);

    _lifecycle = AppLifecycleListener(onResume: _sync.syncAll);
    _poll = Timer.periodic(pollInterval, (_) => _sync.syncAll());

    // Driven off the domain streams rather than wrapping every write: a
    // write is a write however it got made, Siri and Milo's tools included.
    for (final listenable in [
      taskListProvider,
      habitListProvider,
      subjectListProvider,
      studyLogListProvider,
    ]) {
      ref.listen(listenable, (_, _) => _onLocalWrite());
    }
    ref.listen(userSettingsControllerProvider, (_, _) => _onLocalWrite());
  }

  void _onLocalWrite() {
    // The write that just landed may be one sync itself applied. Debounce
    // and idempotence would terminate that loop anyway; this saves the
    // round trip.
    if (_sync.isApplyingRemote) return;
    _debounce?.cancel();
    _debounce = Timer(writeDebounce, _sync.syncAll);
  }
}

final syncSchedulerProvider =
    NotifierProvider<SyncScheduler, void>(SyncScheduler.new);
