import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/schedule_item.dart';
import '../repositories/schedule_repository.dart';
import '../storage/local_storage.dart';

final scheduleBoxProvider =
    Provider<Box<ScheduleItem>>((ref) => Hive.box<ScheduleItem>(HiveBoxes.scheduleItems));

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return HiveScheduleRepository(ref.watch(scheduleBoxProvider));
});

class ScheduleListNotifier extends StreamNotifier<List<ScheduleItem>> {
  ScheduleRepository get _repository => ref.read(scheduleRepositoryProvider);

  @override
  Stream<List<ScheduleItem>> build() => _repository.watchAll();

  Future<void> addItem(ScheduleItem item) => _repository.add(item);

  Future<void> updateItem(ScheduleItem item) => _repository.update(item);

  Future<void> deleteItem(String id) => _repository.delete(id);

  List<ScheduleItem> overlapping(DateTime start, DateTime end, {String? excludeId}) =>
      _repository.overlapping(start, end, excludeId: excludeId);
}

final scheduleListProvider =
    StreamNotifierProvider<ScheduleListNotifier, List<ScheduleItem>>(
  ScheduleListNotifier.new,
);
