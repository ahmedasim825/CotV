// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'study_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StudyLogAdapter extends TypeAdapter<StudyLog> {
  @override
  final typeId = 9;

  @override
  StudyLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StudyLog(
      id: fields[0] as String,
      subjectId: fields[1] as String,
      subjectName: fields[2] as String,
      durationMinutes: (fields[3] as num).toInt(),
      timestamp: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, StudyLog obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.subjectId)
      ..writeByte(2)
      ..write(obj.subjectName)
      ..writeByte(3)
      ..write(obj.durationMinutes)
      ..writeByte(4)
      ..write(obj.timestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudyLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
