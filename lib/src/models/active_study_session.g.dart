// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_study_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActiveStudySessionAdapter extends TypeAdapter<ActiveStudySession> {
  @override
  final typeId = 11;

  @override
  ActiveStudySession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActiveStudySession(
      subjectId: fields[0] as String,
      subjectName: fields[1] as String,
      startedAt: fields[2] as DateTime,
      plannedSeconds: (fields[3] as num).toInt(),
      endsAt: fields[4] as DateTime?,
      remainingSeconds: (fields[5] as num?)?.toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, ActiveStudySession obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.subjectId)
      ..writeByte(1)
      ..write(obj.subjectName)
      ..writeByte(2)
      ..write(obj.startedAt)
      ..writeByte(3)
      ..write(obj.plannedSeconds)
      ..writeByte(4)
      ..write(obj.endsAt)
      ..writeByte(5)
      ..write(obj.remainingSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveStudySessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
