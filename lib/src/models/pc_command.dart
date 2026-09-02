/// What a [PcCommand] asks the Windows agent to do, and which of its three
/// endpoints carries it.
enum PcActionKind {
  /// `POST /open-app` — start an application the agent has in its allowlist.
  openApp,

  /// `POST /open-file` — reveal a file or directory in Windows Explorer.
  openPath,

  /// `POST /system-control` — a media key, volume step or workstation lock.
  system,
}

extension PcActionKindX on PcActionKind {
  /// The agent path this kind posts to.
  String get path {
    switch (this) {
      case PcActionKind.openApp:
        return '/open-app';
      case PcActionKind.openPath:
        return '/open-file';
      case PcActionKind.system:
        return '/system-control';
    }
  }

  /// The JSON field the agent reads the target out of.
  String get targetField {
    switch (this) {
      case PcActionKind.openApp:
        return 'app';
      case PcActionKind.openPath:
        return 'path';
      case PcActionKind.system:
        return 'control';
    }
  }
}

/// One instruction bound for the Windows agent.
///
/// [target] is symbolic for [PcActionKind.openApp] and
/// [PcActionKind.system] — an allowlist key such as `spotify` or
/// `play_pause`, never an executable path. The phone therefore cannot ask
/// the PC to run an arbitrary binary; the agent's own config decides what
/// each key resolves to. [PcActionKind.openPath] may carry a literal
/// Windows path, which the agent still has to match against its configured
/// roots before opening.
class PcCommand {
  const PcCommand({
    required this.kind,
    required this.target,
    required this.summary,
  });

  final PcActionKind kind;
  final String target;

  /// Sentence-case description of the request, shown on the receipt while
  /// the command is in flight and after it lands ("Open Spotify").
  final String summary;

  Map<String, dynamic> toJson() => {kind.targetField: target};

  @override
  String toString() => 'PcCommand(${kind.name}, $target)';
}

/// The outcome of one [PcCommand].
///
/// A failure arrives here rather than as a thrown exception: the assistant
/// renders it on the receipt and feeds it to the model so the reply can say
/// what actually happened, which a thrown error would abort before.
class PcCommandResult {
  const PcCommandResult({
    required this.command,
    required this.ok,
    required this.message,
  });

  /// The agent accepted and performed the command.
  const PcCommandResult.success(this.command, this.message) : ok = true;

  /// The command never ran: the agent was unreachable, rejected the token,
  /// or refused the target.
  const PcCommandResult.failure(this.command, this.message) : ok = false;

  final PcCommand command;
  final bool ok;

  /// What the agent reported, or why the call never got there. Written for
  /// the user, not for a log.
  final String message;
}
