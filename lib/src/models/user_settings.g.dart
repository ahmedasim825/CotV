// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserSettingsAdapter extends TypeAdapter<UserSettings> {
  @override
  final typeId = 7;

  @override
  UserSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserSettings(
      id: fields[0] == null ? UserSettings.defaultId : fields[0] as String,
      isBiometricEnabled: fields[1] == null ? false : fields[1] as bool,
      preAdhanNotificationMinutes: fields[2] == null
          ? 15
          : (fields[2] as num).toInt(),
      latitude: (fields[3] as num?)?.toDouble(),
      longitude: (fields[4] as num?)?.toDouble(),
      themeId: fields[5] as String?,
      speaksReplies: fields[6] == null ? false : fields[6] as bool,
      listensForWakeWord: fields[7] == null ? false : fields[7] as bool,
      voiceName: fields[8] as String?,
      aiMemorySummary: fields[9] as String?,
      dailyCalorieTarget: (fields[10] as num?)?.toInt(),
      proteinTargetGrams: (fields[11] as num?)?.toInt(),
      carbTargetGrams: (fields[12] as num?)?.toInt(),
      fatTargetGrams: (fields[13] as num?)?.toInt(),
      updatedAtMillis: (fields[14] as num?)?.toInt(),
      syncedAtMillis: (fields[15] as num?)?.toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, UserSettings obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.isBiometricEnabled)
      ..writeByte(2)
      ..write(obj.preAdhanNotificationMinutes)
      ..writeByte(3)
      ..write(obj.latitude)
      ..writeByte(4)
      ..write(obj.longitude)
      ..writeByte(5)
      ..write(obj.themeId)
      ..writeByte(6)
      ..write(obj.speaksReplies)
      ..writeByte(7)
      ..write(obj.listensForWakeWord)
      ..writeByte(8)
      ..write(obj.voiceName)
      ..writeByte(9)
      ..write(obj.aiMemorySummary)
      ..writeByte(10)
      ..write(obj.dailyCalorieTarget)
      ..writeByte(11)
      ..write(obj.proteinTargetGrams)
      ..writeByte(12)
      ..write(obj.carbTargetGrams)
      ..writeByte(13)
      ..write(obj.fatTargetGrams)
      ..writeByte(14)
      ..write(obj.updatedAtMillis)
      ..writeByte(15)
      ..write(obj.syncedAtMillis);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
