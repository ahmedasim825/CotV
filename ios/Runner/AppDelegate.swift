import Flutter
import UIKit
import UserNotifications
import AppIntents
import flutter_app_intents

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so foreground presentation
    // options and notification-tap callbacks are delivered correctly.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

// MARK: - Study App Intents
//
// iOS discovers App Intents by scanning the compiled binary, not at run
// time, so every intent has to exist as a static Swift declaration here.
// `flutter_app_intents` generates none of these — it only carries the call
// across to Dart.
//
// The `identifier` strings below must match `StudyAppIntents.startIdentifier`
// and `.stopIdentifier` in lib/src/services/study_app_intents.dart, which in
// turn match the tool names Milo uses. One action, one name, three front
// doors.
//
// UNVERIFIED ON DEVICE: this file was written on Windows, where no Apple
// toolchain exists. CI proves it compiles; nobody has yet run it on an
// iPhone. See the README.

/// Raised when the Flutter side reports the action failed, so Siri says
/// what went wrong instead of claiming success.
enum StudyIntentError: Error {
    case executionFailed(String)
}

/// Starts a study timer for one of the user's existing subjects.
///
/// Runs without opening the app: starting a timer is a background action,
/// and being thrown into the UI to confirm it would defeat the point of
/// asking Siri. `ProvidesDialog` is what makes Siri read the result out —
/// which matters here, because "there is no subject called Physiolgy" is
/// the answer as often as "started".
@available(iOS 16.0, *)
struct StartStudyIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Study Timer"
    static var description = IntentDescription(
        "Start a study timer for one of your subjects."
    )
    static var isDiscoverable = true

    @Parameter(title: "Subject")
    var subject: String

    @Parameter(title: "Minutes")
    var minutes: Int?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let plugin = FlutterAppIntentsPlugin.shared
        let result = await plugin.handleIntentInvocation(
            identifier: "start_study_timer",
            parameters: [
                "subject": subject,
                // Matches MiloTools.defaultMinutes. Kept in step by hand:
                // Swift cannot read a Dart constant.
                "minutes": minutes ?? 25
            ]
        )

        if let success = result["success"] as? Bool, success {
            let value = result["value"] as? String ?? "Study timer started."
            return .result(value: value, dialog: IntentDialog(stringLiteral: value))
        }

        throw StudyIntentError.executionFailed(
            result["error"] as? String ?? "Could not start the study timer."
        )
    }
}

/// Stops the running study timer and logs the minutes actually studied.
@available(iOS 16.0, *)
struct StopStudyIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Study Timer"
    static var description = IntentDescription(
        "Stop the running study timer and log what was studied."
    )
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let plugin = FlutterAppIntentsPlugin.shared
        let result = await plugin.handleIntentInvocation(
            identifier: "stop_study_timer",
            parameters: [:]
        )

        if let success = result["success"] as? Bool, success {
            let value = result["value"] as? String ?? "Study timer stopped."
            return .result(value: value, dialog: IntentDialog(stringLiteral: value))
        }

        throw StudyIntentError.executionFailed(
            result["error"] as? String ?? "Could not stop the study timer."
        )
    }
}

// MARK: - App Shortcuts Provider
//
// What Siri offers without the user building a shortcut first. The phrases
// have to name the app — Apple requires `\(.applicationName)` in every one
// — so they read as "start studying with Milo" rather than "start
// studying".

@available(iOS 16.0, *)
struct StudyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStudyIntent(),
            phrases: [
                "Start a study timer with \(.applicationName)",
                "Start studying with \(.applicationName)",
                "Study with \(.applicationName)",
                "Begin a revision block in \(.applicationName)"
            ],
            shortTitle: "Start Studying",
            systemImageName: "timer"
        )

        AppShortcut(
            intent: StopStudyIntent(),
            phrases: [
                "Stop the study timer in \(.applicationName)",
                "Stop studying with \(.applicationName)",
                "End my study session in \(.applicationName)"
            ],
            shortTitle: "Stop Studying",
            systemImageName: "stop.circle"
        )
    }
}
