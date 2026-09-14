// Runs the app on this desktop with the iOS shell forced on.
//
//     flutter run -d windows -t tool/ios_preview.dart
//
// The iOS homepage — liquid-glass cards, the floating nav pill, Milo in the
// page — is gated on `context.useLiquidGlass`, which reads `ThemeData.platform`
// and so is false on a Windows build. This entrypoint flips the process-wide
// default before `runApp`, which makes `buildAppTheme()` report iOS all the
// way down and renders the whole iOS shell in a desktop window you can drag
// through 393 / 834 / 1194pt to see every breakpoint.
//
// **What this does and does not tell you.** It renders real `BackdropFilter`s
// over the real circadian ground, so it answers the questions that actually
// carry risk: whether anything above a card pushes a save layer and leaves it
// blurring nothing, and whether sigma 24 over `glassFill` reads like the mock.
// It tells you nothing about *performance* — Impeller on OpenGLES here is not
// Impeller on Metal there — and nothing about how the pill sits against a real
// home indicator. For those, push the branch: `.github/workflows/build.yml`
// builds a sideloadable IPA on every push.
//
// Not part of the app. `lib/main.dart` is the real entrypoint and is
// unaffected by this file's existence.

import 'package:flutter/foundation.dart';

import 'package:cotv/main.dart' as app;

Future<void> main() async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  await app.main();
}
