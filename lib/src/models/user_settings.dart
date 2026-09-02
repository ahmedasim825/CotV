import 'package:hive_ce/hive_ce.dart';

part 'user_settings.g.dart';

/// Persisted app-wide preferences. There is exactly one record of this,
/// stored under [UserSettings.defaultId] — see `UserSettingsRepository`.
@HiveType(typeId: 7)
class UserSettings {
  UserSettings({
    this.id = UserSettings.defaultId,
    this.isBiometricEnabled = false,
    this.preAdhanNotificationMinutes = 15,
    this.latitude,
    this.longitude,
    this.themeId,
  });

  /// The single key this settings record is always stored under.
  static const String defaultId = 'default';

  @HiveField(0)
  final String id;

  @HiveField(1)
  final bool isBiometricEnabled;

  @HiveField(2)
  final int preAdhanNotificationMinutes;

  /// Null until a device location fix has been saved — callers should fall
  /// back to a default location (e.g. `PrayerService.fallbackCoordinates`).
  @HiveField(3)
  final double? latitude;

  @HiveField(4)
  final double? longitude;

  /// The chosen theme's stable id (see `AppThemeVariant.id`). Null until
  /// the user picks one, in which case the UI falls back to the default
  /// variant. Stored as an opaque string rather than an enum index so
  /// reordering the variants can never repoint a saved preference at a
  /// different theme — and so this model stays free of any UI import.
  @HiveField(5)
  final String? themeId;

  bool get hasLocation => latitude != null && longitude != null;

  UserSettings copyWith({
    bool? isBiometricEnabled,
    int? preAdhanNotificationMinutes,
    double? latitude,
    double? longitude,
    String? themeId,
  }) {
    return UserSettings(
      id: id,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      preAdhanNotificationMinutes:
          preAdhanNotificationMinutes ?? this.preAdhanNotificationMinutes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      themeId: themeId ?? this.themeId,
    );
  }
}
