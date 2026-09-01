import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/schedule_item.dart';
import 'hive_repository_utils.dart';

/// CRUD access to [ScheduleItem]s.
abstract class ScheduleRepository {
  Stream<List<ScheduleItem>> watchAll();

  List<ScheduleItem> getAll();

  ScheduleItem? getById(String id);

  Future<void> add(ScheduleItem item);

  Future<void> update(ScheduleItem item);

  Future<void> delete(String id);

  /// Existing items whose [start, end) range overlaps the given window.
  /// [excludeId] omits an item from the check (e.g. the one being edited).
  /// Callers use this to warn before double-booking over a prayer window.
  List<ScheduleItem> overlapping(DateTime start, DateTime end, {String? excludeId});
}

class HiveScheduleRepository implements ScheduleRepository {
  HiveScheduleRepository(this._box);

  final Box<ScheduleItem> _box;

  @override
  Stream<List<ScheduleItem>> watchAll() => watchBoxValues(_box);

  @override
  List<ScheduleItem> getAll() => _box.values.toList(growable: false);

  @override
  ScheduleItem? getById(String id) => _box.get(id);

  @override
  Future<void> add(ScheduleItem item) => _box.put(item.id, item);

  @override
  Future<void> update(ScheduleItem item) => _box.put(item.id, item);

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  List<ScheduleItem> overlapping(
    DateTime start,
    DateTime end, {
    String? excludeId,
  }) {
    return _box.values
        .where(
          (item) =>
              item.id != excludeId &&
              item.startTime.isBefore(end) &&
              start.isBefore(item.endTime),
        )
        .toList(growable: false);
  }
}
