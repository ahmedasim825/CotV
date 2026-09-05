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
    this.speaksReplies = false,
    this.listensForWakeWord = false,
    this.voiceName,
    this.aiMemorySummary,
    this.dailyCalorieTarget,
    this.proteinTargetGrams,
    this.carbTargetGrams,
    this.fatTargetGrams,
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

  /// Whether Milo reads its replies aloud.
  ///
  /// Off by default: a device that starts talking without being asked is a
  /// worse first impression than one that stays quiet, and speech is the
  /// one output the user cannot silently ignore in a room with other
  /// people in it.
  @HiveField(6)
  final bool speaksReplies;

  /// Whether Milo keeps the microphone open waiting to hear its name.
  ///
  /// Off by default, and deliberately harder to turn on than the speaker
  /// toggle: silence is held on the device, but any speech loud enough to
  /// cross the gate is uploaded to be transcribed, whether or not it was
  /// meant for Milo. That is a decision the user has to make knowingly.
  @HiveField(7)
  final bool listensForWakeWord;

  /// The platform voice Milo speaks with, by name.
  ///
  /// Null means whatever the OS picked. Stored as the name rather than an
  /// index because the installed set changes when the user adds a voice in
  /// system settings, and an index would then point at a different one.
  @HiveField(8)
  final String? voiceName;

  /// What Milo has learned about the user, in condensed prose.
  ///
  /// Rewritten in the background once the conversation grows past the
  /// window that fits in a prompt, so long-lived facts ("studies medicine",
  /// "prefers 45-minute physiology blocks") survive being pushed out of the
  /// recent-message history. Null until there has been enough to summarise.
  @HiveField(9)
  final String? aiMemorySummary;

  /// The daily nutrition goals the dashboard ring and macro bars are
  /// measured against.
  ///
  /// Null means "not configured", which is what lets `NutritionTargets`
  /// fall back per field: setting a calorie goal alone leaves the three
  /// macro goals on their defaults rather than zeroing them. Records
  /// written before these fields existed read back as null, which is
  /// exactly that state.
  @HiveField(10)
  final int? dailyCalorieTarget;

  @HiveField(11)
  final int? proteinTargetGrams;

  @HiveField(12)
  final int? carbTargetGrams;

  @HiveField(13)
  final int? fatTargetGrams;

  bool get hasLocation => latitude != null && longitude != null;

  UserSettings copyWith({
    bool? isBiometricEnabled,
    int? preAdhanNotificationMinutes,
    double? latitude,
    double? longitude,
    String? themeId,
    bool? speaksReplies,
    bool? listensForWakeWord,
    String? voiceName,
    String? aiMemorySummary,
    int? dailyCalorieTarget,
    int? proteinTargetGrams,
    int? carbTargetGrams,
    int? fatTargetGrams,
  }) {
    return UserSettings(
      id: id,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      preAdhanNotificationMinutes:
          preAdhanNotificationMinutes ?? this.preAdhanNotificationMinutes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      themeId: themeId ?? this.themeId,
      speaksReplies: speaksReplies ?? this.speaksReplies,
      listensForWakeWord: listensForWakeWord ?? this.listensForWakeWord,
      voiceName: voiceName ?? this.voiceName,
      aiMemorySummary: aiMemorySummary ?? this.aiMemorySummary,
      dailyCalorieTarget: dailyCalorieTarget ?? this.dailyCalorieTarget,
      proteinTargetGrams: proteinTargetGrams ?? this.proteinTargetGrams,
      carbTargetGrams: carbTargetGrams ?? this.carbTargetGrams,
      fatTargetGrams: fatTargetGrams ?? this.fatTargetGrams,
    );
  }
}
