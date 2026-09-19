// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] == null ? '' : fields[2] as String,
      dueDate: fields[3] as DateTime?,
      isCompleted: fields[4] == null ? false : fields[4] as bool,
      category: fields[5] == null ? 'General' : fields[5] as String,
      priority: fields[6] == null
          ? TaskPriority.none
          : fields[6] as TaskPriority,
      createdAt: fields[7] as DateTime?,
      hasReminder: fields[8] == null ? false : fields[8] as bool,
      isStudy: fields[12] == null ? false : fields[12] as bool,
      subjectId: fields[13] as String?,
      repeat: fields[14] == null ? TaskRepeat.never : fields[14] as TaskRepeat,
      earlyReminder: fields[15] == null
          ? TaskEarlyReminder.never
          : fields[15] as TaskEarlyReminder,
      updatedAtMillis: (fields[9] as num?)?.toInt(),
      isDeleted: fields[10] == null ? false : fields[10] as bool,
      syncedAtMillis: (fields[11] as num?)?.toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.dueDate)
      ..writeByte(4)
      ..write(obj.isCompleted)
      ..writeByte(5)
      ..write(obj.category)
      ..writeByte(6)
      ..write(obj.priority)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.hasReminder)
      ..writeByte(9)
      ..write(obj.updatedAtMillis)
      ..writeByte(10)
      ..write(obj.isDeleted)
      ..writeByte(11)
      ..write(obj.syncedAtMillis)
      ..writeByte(12)
      ..write(obj.isStudy)
      ..writeByte(13)
      ..write(obj.subjectId)
      ..writeByte(14)
      ..write(obj.repeat)
      ..writeByte(15)
      ..write(obj.earlyReminder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TaskPriorityAdapter extends TypeAdapter<TaskPriority> {
  @override
  final typeId = 1;

  @override
  TaskPriority read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskPriority.low;
      case 1:
        return TaskPriority.medium;
      case 2:
        return TaskPriority.high;
      case 3:
        return TaskPriority.none;
      default:
        return TaskPriority.low;
    }
  }

  @override
  void write(BinaryWriter writer, TaskPriority obj) {
    switch (obj) {
      case TaskPriority.low:
        writer.writeByte(0);
      case TaskPriority.medium:
        writer.writeByte(1);
      case TaskPriority.high:
        writer.writeByte(2);
      case TaskPriority.none:
        writer.writeByte(3);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskPriorityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TaskRepeatAdapter extends TypeAdapter<TaskRepeat> {
  @override
  final typeId = 2;

  @override
  TaskRepeat read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskRepeat.never;
      case 1:
        return TaskRepeat.hourly;
      case 2:
        return TaskRepeat.daily;
      case 3:
        return TaskRepeat.weekdays;
      case 4:
        return TaskRepeat.weekends;
      case 5:
        return TaskRepeat.weekly;
      case 6:
        return TaskRepeat.biweekly;
      case 7:
        return TaskRepeat.monthly;
      case 8:
        return TaskRepeat.everyThreeMonths;
      case 9:
        return TaskRepeat.everySixMonths;
      case 10:
        return TaskRepeat.yearly;
      default:
        return TaskRepeat.never;
    }
  }

  @override
  void write(BinaryWriter writer, TaskRepeat obj) {
    switch (obj) {
      case TaskRepeat.never:
        writer.writeByte(0);
      case TaskRepeat.hourly:
        writer.writeByte(1);
      case TaskRepeat.daily:
        writer.writeByte(2);
      case TaskRepeat.weekdays:
        writer.writeByte(3);
      case TaskRepeat.weekends:
        writer.writeByte(4);
      case TaskRepeat.weekly:
        writer.writeByte(5);
      case TaskRepeat.biweekly:
        writer.writeByte(6);
      case TaskRepeat.monthly:
        writer.writeByte(7);
      case TaskRepeat.everyThreeMonths:
        writer.writeByte(8);
      case TaskRepeat.everySixMonths:
        writer.writeByte(9);
      case TaskRepeat.yearly:
        writer.writeByte(10);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskRepeatAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TaskEarlyReminderAdapter extends TypeAdapter<TaskEarlyReminder> {
  @override
  final typeId = 3;

  @override
  TaskEarlyReminder read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskEarlyReminder.never;
      case 1:
        return TaskEarlyReminder.oneDay;
      case 2:
        return TaskEarlyReminder.twoDays;
      case 3:
        return TaskEarlyReminder.oneWeek;
      case 4:
        return TaskEarlyReminder.twoWeeks;
      case 5:
        return TaskEarlyReminder.oneMonth;
      case 6:
        return TaskEarlyReminder.threeMonths;
      case 7:
        return TaskEarlyReminder.sixMonths;
      default:
        return TaskEarlyReminder.never;
    }
  }

  @override
  void write(BinaryWriter writer, TaskEarlyReminder obj) {
    switch (obj) {
      case TaskEarlyReminder.never:
        writer.writeByte(0);
      case TaskEarlyReminder.oneDay:
        writer.writeByte(1);
      case TaskEarlyReminder.twoDays:
        writer.writeByte(2);
      case TaskEarlyReminder.oneWeek:
        writer.writeByte(3);
      case TaskEarlyReminder.twoWeeks:
        writer.writeByte(4);
      case TaskEarlyReminder.oneMonth:
        writer.writeByte(5);
      case TaskEarlyReminder.threeMonths:
        writer.writeByte(6);
      case TaskEarlyReminder.sixMonths:
        writer.writeByte(7);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskEarlyReminderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
