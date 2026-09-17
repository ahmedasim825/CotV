import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/sync_stamped.dart';

/// Emits the current contents of [box] immediately, then again every time
/// any entry in it changes — the reactive backbone every repository's
/// `watchAll()` is built on.
Stream<List<T>> watchBoxValues<T>(Box<T> box) async* {
  yield box.values.toList(growable: false);
  yield* box.watch().map((_) => box.values.toList(growable: false));
}

/// [watchBoxValues] with tombstones filtered out.
///
/// Every domain read path uses this rather than the raw version: a deleted
/// record stays in the box so the deletion itself can be pushed to the
/// other device, and nothing above the repository should ever see it.
Stream<List<T>> watchLiveBoxValues<T extends SyncStamped>(Box<T> box) =>
    watchBoxValues(box).map(liveValues);

/// The records of [values] that are not tombstones.
List<T> liveValues<T extends SyncStamped>(Iterable<T> values) =>
    values.where((value) => !value.isDeleted).toList(growable: false);

/// The wall clock a repository stamps its writes from, in epoch
/// milliseconds.
///
/// Injectable so a test can pin it: every conflict rule in the sync engine
/// turns on comparing two of these, and a test that cannot control them
/// can only assert on timing luck.
typedef SyncClock = int Function();

int systemSyncClock() => DateTime.now().millisecondsSinceEpoch;
