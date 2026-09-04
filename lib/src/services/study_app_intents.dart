import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_app_intents/flutter_app_intents.dart';

import 'milo/milo_tools.dart';

/// Registers the study App Intents that Siri and the Shortcuts app invoke.
///
/// The Dart half of the bridge. The other half is the static Swift in
/// `ios/Runner/AppDelegate.swift`: iOS discovers intents at compile time, so
/// they have to exist as Swift declarations, and this package generates
/// none of them. The Swift `perform()` calls back into these handlers by
/// [AppIntent.identifier].
///
/// Both halves drive [StudyToolTarget] — the same interface Milo's tools
/// use. Siri and a typed "start a physiology timer" are two front doors to
/// one action, and they cannot drift apart in behaviour because there is
/// only one implementation behind them.
class StudyAppIntents {
  const StudyAppIntents(this._study);

  final StudyToolTarget _study;

  /// Deliberately the same identifiers as [MiloTools.startStudyTimer] and
  /// [MiloTools.stopStudyTimer]: one action, one name, wherever it is
  /// invoked from. The Swift declarations pass these strings verbatim.
  static const String startIdentifier = MiloTools.startStudyTimer;
  static const String stopIdentifier = MiloTools.stopStudyTimer;

  /// App Intents are an iOS 16+ API and the plugin ships iOS only. Calling
  /// into it anywhere else would surface as a MissingPluginException on
  /// launch, which tells the user nothing they can act on.
  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  static final AppIntent startIntent = AppIntent(
    identifier: startIdentifier,
    title: 'Start Study Timer',
    description: 'Start a study timer for one of your subjects.',
    parameters: const [
      AppIntentParameter(
        name: 'subject',
        title: 'Subject',
        type: AppIntentParameterType.string,
        description: 'The subject to study.',
      ),
      AppIntentParameter(
        name: 'minutes',
        title: 'Minutes',
        type: AppIntentParameterType.integer,
        description: 'How long the session should run.',
        isOptional: true,
        defaultValue: MiloTools.defaultMinutes,
      ),
    ],
  );

  static final AppIntent stopIntent = AppIntent(
    identifier: stopIdentifier,
    title: 'Stop Study Timer',
    description: 'Stop the running study timer and log what was studied.',
  );

  /// Returns whether registration succeeded. False on an unsupported
  /// platform, and false rather than throwing if the plugin refuses —
  /// nothing else in the app depends on Shortcuts working.
  Future<bool> register() async {
    if (!isSupported) return false;

    try {
      return await FlutterAppIntentsClient.instance.registerIntents({
        startIntent: (parameters) async {
          final subject = parameters['subject'];
          if (subject is! String || subject.trim().isEmpty) {
            return AppIntentResult.failed(
              error: 'No subject was given, so no timer was started.',
            );
          }
          return AppIntentResult.successful(
            value: await _study.startTimer(
              subject: subject.trim(),
              minutes: _minutesOf(parameters['minutes']),
            ),
          );
        },
        stopIntent: (_) async =>
            AppIntentResult.successful(value: await _study.stopTimer()),
      });
    } catch (_) {
      return false;
    }
  }

  /// Shortcuts hands an integer parameter through as an int, but a value
  /// typed into a shortcut's text field arrives as a string.
  int _minutesOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null) return parsed;
    }
    return MiloTools.defaultMinutes;
  }
}
