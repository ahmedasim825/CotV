import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Emits the current contents of [box] immediately, then again every time
/// any entry in it changes — the reactive backbone every repository's
/// `watchAll()` is built on.
Stream<List<T>> watchBoxValues<T>(Box<T> box) async* {
  yield box.values.toList(growable: false);
  yield* box.watch().map((_) => box.values.toList(growable: false));
}
