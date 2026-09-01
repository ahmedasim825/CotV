// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'journal_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class JournalEntryAdapter extends TypeAdapter<JournalEntry> {
  @override
  final typeId = 5;

  @override
  JournalEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return JournalEntry(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      content: fields[2] == null ? '' : fields[2] as String,
      mood: fields[3] == null ? JournalMood.neutral : fields[3] as JournalMood,
      tags: (fields[4] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, JournalEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.mood)
      ..writeByte(4)
      ..write(obj.tags);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class JournalMoodAdapter extends TypeAdapter<JournalMood> {
  @override
  final typeId = 6;

  @override
  JournalMood read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return JournalMood.great;
      case 1:
        return JournalMood.good;
      case 2:
        return JournalMood.neutral;
      case 3:
        return JournalMood.low;
      case 4:
        return JournalMood.difficult;
      default:
        return JournalMood.great;
    }
  }

  @override
  void write(BinaryWriter writer, JournalMood obj) {
    switch (obj) {
      case JournalMood.great:
        writer.writeByte(0);
      case JournalMood.good:
        writer.writeByte(1);
      case JournalMood.neutral:
        writer.writeByte(2);
      case JournalMood.low:
        writer.writeByte(3);
      case JournalMood.difficult:
        writer.writeByte(4);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalMoodAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
