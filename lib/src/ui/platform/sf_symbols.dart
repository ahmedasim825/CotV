import 'dart:io' show Platform;

/// Whether SF Symbol names will resolve to glyphs rather than to nothing.
///
/// `cupertino_native_better` renders a `CNSymbol` by handing its *name* to the
/// platform, which resolves it against the SF Symbols the running OS ships.
/// Off Apple platforms the widget falls back to Flutter, and there is no font
/// on the other side — the name resolves to an empty placeholder, and a tab bar
/// or a menu comes up with blanks where its icons should be. Every caller
/// therefore supplies a Phosphor `IconData` through the package's `customIcon`
/// slot when this is false.
///
/// Gated on `dart:io` rather than [ThemeData.platform], which is the rule
/// everywhere else in this codebase and is documented at `useLiquidGlass`. It
/// has to be, and the exception is the whole point: the package decides which
/// of its two paths to take from `Platform.isIOS` itself, so a gate reading the
/// theme would disagree with it exactly where the theme is faked — under
/// `flutter_test`, and in `tool/tasks_preview.dart`, which forces the iOS look
/// onto a Windows window. That disagreement is what puts the placeholders on
/// screen; it is not a hypothetical, it shipped once.
final bool hasSFSymbols = Platform.isIOS || Platform.isMacOS;
