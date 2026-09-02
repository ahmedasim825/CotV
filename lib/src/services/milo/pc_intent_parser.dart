import '../../models/pc_command.dart';

/// Turns a phrase into an instruction for the Windows agent, or returns
/// null when the phrase is not addressed to the PC at all.
///
/// The parser recognises the shape of a command and passes the target on as
/// the user said it. It deliberately holds no list of applications or
/// folders and does not normalise names: the agent resolves them the way
/// Windows itself does — its own `[apps]` pins first, then the path, then
/// PATH, then the registry's App Paths, then the shell — so anything on the
/// machine can be opened without both ends agreeing on a table first.
class PcIntentParser {
  const PcIntentParser();

  /// A phrase must name the machine before a media key or an app launch is
  /// sent to it — otherwise "pause" in ordinary conversation would reach
  /// out and stop the music, and "open settings" would leave the app.
  static final RegExp _machine =
      RegExp(r'\b(?:pc|laptop|computer|desktop|windows|machine)\b');

  /// Trailing "on my laptop", "over on the PC", and anything after it.
  static final RegExp _machineSuffix = RegExp(
    r'\s+(?:on|in|at|over(?:\s+on)?)\s+(?:my\s+|the\s+)?'
    r'(?:pc|laptop|computer|desktop|windows|machine)\b.*$',
    caseSensitive: false,
  );

  static final RegExp _openVerb = RegExp(
    r'^(?:please\s+)?(?:open|launch|start|run|fire\s+up|boot)\s+'
    r'(?:the\s+|my\s+)?(.+)$',
    caseSensitive: false,
  );

  static final RegExp _folderPhrase = RegExp(
    r'^(?:please\s+)?(?:open|show|reveal|bring\s+up)\s+(?:the\s+|my\s+)?'
    r'(.+?)\s+(?:folder|directory)\b',
    caseSensitive: false,
  );

  /// A literal Windows path, e.g. `D:\Study\Anatomy`. Matched against the
  /// original casing so the agent receives the path as the user wrote it.
  static final RegExp _literalPath = RegExp(r'[a-zA-Z]:[\\/][^\s"]*');

  /// An explicit URL. Bare domains are left alone on purpose: "open reddit
  /// on my pc" is far more likely to mean an app than a website.
  static final RegExp _url = RegExp(
    r'^(?:please\s+)?(?:open|launch|go\s+to|visit)\s+(https?://\S+)',
    caseSensitive: false,
  );

  static final RegExp _bareFolderAlias = RegExp(
    r'^(?:please\s+)?(?:open|show)\s+(?:my\s+|the\s+)?'
    r'(downloads|documents|pictures|videos)\b',
    caseSensitive: false,
  );

  /// Spoken forms of the media and system keys, mapped to the control name
  /// the agent's `/system-control` endpoint accepts. Matched longest-first,
  /// so "play media" wins over "play" and "skip track" over "skip".
  static const Map<String, String> _controls = {
    'play pause': 'play_pause',
    'play media': 'play_pause',
    'play music': 'play_pause',
    'next track': 'next_track',
    'next song': 'next_track',
    'skip track': 'next_track',
    'previous track': 'previous_track',
    'previous song': 'previous_track',
    'volume up': 'volume_up',
    'turn it up': 'volume_up',
    'volume down': 'volume_down',
    'turn it down': 'volume_down',
    'resume': 'play_pause',
    'unpause': 'play_pause',
    'louder': 'volume_up',
    'quieter': 'volume_down',
    'unmute': 'mute',
    'pause': 'play_pause',
    'play': 'play_pause',
    'skip': 'next_track',
    'mute': 'mute',
    'lock': 'lock_workstation',
  };

  static const Map<String, String> _controlSummaries = {
    'play_pause': 'Toggle play/pause',
    'next_track': 'Skip to the next track',
    'previous_track': 'Go back a track',
    'volume_up': 'Turn the volume up',
    'volume_down': 'Turn the volume down',
    'mute': 'Toggle mute',
    'lock_workstation': 'Lock the workstation',
  };

  /// A media phrase inside a longer sentence is almost always description
  /// rather than instruction ("my laptop keeps pausing the music"), so
  /// system control only fires on a short one.
  static const int _maxControlWords = 8;

  PcCommand? parse(String prompt) {
    final text = prompt.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    final namesMachine = _machine.hasMatch(lower);

    return _matchControl(lower, namesMachine) ??
        _matchUrl(text) ??
        _matchPath(text, lower) ??
        _matchApp(text, namesMachine);
  }

  PcCommand? _matchControl(String lower, bool namesMachine) {
    if (!namesMachine) return null;
    if (lower.split(RegExp(r'\s+')).length > _maxControlWords) return null;

    final phrases = _controls.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final phrase in phrases) {
      if (!RegExp('\\b${RegExp.escape(phrase)}\\b').hasMatch(lower)) continue;
      final control = _controls[phrase]!;
      return PcCommand(
        kind: PcActionKind.system,
        target: control,
        summary: _controlSummaries[control]!,
      );
    }
    return null;
  }

  /// A URL is unambiguous, so it needs no machine word — the phone would
  /// open it in its own browser only if the user had not said "open".
  PcCommand? _matchUrl(String text) {
    final match = _url.firstMatch(text);
    if (match == null) return null;
    final url = match.group(1)!;
    return PcCommand(
      kind: PcActionKind.openPath,
      target: url,
      summary: 'Open $url',
    );
  }

  /// Paths do not need the machine named: the phone has no "study folder"
  /// and no `D:` drive, so the request can only have meant the PC.
  PcCommand? _matchPath(String text, String lower) {
    final literal = _literalPath.firstMatch(text);
    if (literal != null && _openVerb.hasMatch(lower)) {
      final path = literal.group(0)!;
      return PcCommand(
        kind: PcActionKind.openPath,
        target: path,
        summary: 'Open $path',
      );
    }

    final folder = _folderPhrase.firstMatch(text);
    if (folder != null) {
      final name = folder.group(1)!.trim();
      return PcCommand(
        kind: PcActionKind.openPath,
        target: name,
        summary: 'Open the $name folder',
      );
    }

    final alias = _bareFolderAlias.firstMatch(text);
    if (alias != null) {
      final name = alias.group(1)!;
      return PcCommand(
        kind: PcActionKind.openPath,
        target: name,
        summary: 'Open $name',
      );
    }

    return null;
  }

  PcCommand? _matchApp(String text, bool namesMachine) {
    if (!namesMachine) return null;

    final withoutMachine = text.replaceFirst(_machineSuffix, '').trim();
    final match = _openVerb.firstMatch(withoutMachine);
    if (match == null) return null;

    final name = match.group(1)!.trim().replaceFirst(RegExp(r'[.!?,]+$'), '');
    if (name.isEmpty) return null;
    // Nothing was left but the machine word itself ("open my laptop").
    if (_machine.hasMatch(name.toLowerCase())) return null;

    return PcCommand(
      kind: PcActionKind.openApp,
      target: name,
      summary: 'Open $name',
    );
  }
}
