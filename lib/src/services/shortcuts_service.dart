import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';

/// Opens the iOS Shortcuts app.
///
/// Gated on platform the same way [CalendarSyncService.isSupported] is, and
/// for the same reason: `shortcuts://` resolves to nothing on Windows or
/// Android, so a row offering it there can only fail. The setting is hidden
/// rather than shown-and-broken.
class ShortcutsService {
  const ShortcutsService();

  /// Apple's URL scheme for the Shortcuts app. Bare, with no path: opening
  /// the app is all this does — building the shortcut is the user's job,
  /// and there is no public scheme for creating one on their behalf.
  static final Uri _shortcuts = Uri.parse('shortcuts://');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Returns whether Shortcuts actually opened.
  ///
  /// False rather than throwing when the platform is wrong or the app is
  /// missing — the caller is a settings row, and a row that throws is worse
  /// than a row that reports it did nothing.
  Future<bool> open() async {
    if (!isSupported) return false;
    try {
      return await launchUrl(_shortcuts);
    } catch (_) {
      return false;
    }
  }
}
