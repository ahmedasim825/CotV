import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_session.dart';
import '../../../providers/chat_session_providers.dart';
import '../../../providers/milo_providers.dart';
import '../../components/components.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The thread list, over the conversation.
///
/// A sheet rather than a second drawer: the panel is already a drawer, and
/// nesting one inside another gives two competing back gestures. This slides
/// down over the transcript and dismisses the same way anything else in the
/// app does.
Future<void> showSessionDrawer(BuildContext context) {
  return showStandardBottomSheet<void>(
    context,
    builder: (context) => const SessionDrawer(),
  );
}

class SessionDrawer extends ConsumerStatefulWidget {
  const SessionDrawer({super.key});

  @override
  ConsumerState<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends ConsumerState<SessionDrawer> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _search.removeListener(_onQueryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() =>
      ref.read(sessionSearchQueryProvider.notifier).set(_search.text);

  @override
  void deactivate() {
    // Cleared on the way out so reopening the sheet does not come back to
    // someone else's search from ten minutes ago.
    ref.read(sessionSearchQueryProvider.notifier).set('');
    super.deactivate();
  }

  Future<void> _newChat() async {
    await ref.read(miloConversationProvider.notifier).newSession();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _open(ChatSession session) async {
    await ref.read(miloConversationProvider.notifier).openSession(session.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _rename(ChatSession session) async {
    final name = await showRenameDialog(context, current: session.title);
    if (name == null) return;
    await ref.read(chatSessionRepositoryProvider).rename(session.id, name);
  }

  Future<void> _delete(ChatSession session) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete "${session.title}"?',
      message: session.messageCount == 0
          ? 'This thread is empty. Deleting it cannot be undone.'
          : 'Deletes the thread and its ${session.messageCount} messages. '
              'This cannot be undone, and it is not the same as making Milo '
              'forget — what it has learned stays.',
      confirmLabel: 'Delete',
      confirmIcon: PhLight.trash,
    );
    if (!confirmed) return;

    final wasActive = ref.read(activeSessionProvider) == session.id;
    await ref.read(chatSessionRepositoryProvider).deleteSession(session.id);

    // Deleting the thread on screen has to leave the panel somewhere, and
    // a blank one is the honest place — the messages behind it are gone.
    if (wasActive) {
      ref.read(miloConversationProvider.notifier).clear();
      ref.read(activeSessionProvider.notifier).select(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(filteredSessionListProvider);
    final active = ref.watch(activeSessionProvider);
    final searching = _search.text.trim().isNotEmpty;

    return StandardBottomSheet(
      title: 'Chats',
      subtitle: 'Each thread keeps its own history. Milo only reads the one '
          'you have open.',
      actions: PrimaryButton(
        label: 'New chat',
        icon: PhLight.plus,
        expand: true,
        onPressed: _newChat,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            autocorrect: false,
            style: context.typography.ui(size: 14),
            decoration: appInputDecoration(
              context,
              hint: 'Search chats',
              prefixIcon: Icon(
                PhLight.magnifyingGlass,
                size: 17,
                color: context.palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (sessions.isEmpty)
            _EmptyState(searching: searching)
          else
            for (final session in sessions) ...[
              _SessionRow(
                session: session,
                isActive: session.id == active,
                onOpen: () => unawaited(_open(session)),
                onRename: () => _rename(session),
                onDelete: () => _delete(session),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  /// Nothing found and nothing yet are different states, and a user who has
  /// just typed a query needs to know which one they are looking at.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.glassFill,
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching ? PhLight.magnifyingGlass : PhLight.sparkle,
              size: 19,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No chats match that' : 'No other chats yet',
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 13.5,
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.isActive,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final ChatSession session;
  final bool isActive;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// "4 messages · Today", or just the date on an empty thread.
  String get _subtitle {
    final when = formatDueLabel(session.updatedAt.toLocal(), DateTime.now());
    if (session.isEmpty) return 'Empty · $when';
    final count = session.messageCount;
    return '$count message${count == 1 ? '' : 's'} · $when';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      radius: 18,
      elevated: false,
      selected: isActive,
      accent: isActive ? palette.accent : null,
      padding: const EdgeInsets.fromLTRB(15, 12, 6, 12),
      onTap: onOpen,
      semanticLabel: '${session.title}, $_subtitle'
          '${isActive ? ', open' : ''}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 14,
                    weight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 11.5,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _RowAction(
            icon: PhLight.pencilSimple,
            tooltip: 'Rename',
            onTap: onRename,
          ),
          _RowAction(
            icon: PhLight.trash,
            tooltip: 'Delete',
            tint: palette.danger,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: minTouchTarget,
            height: minTouchTarget,
            child: Icon(
              icon,
              size: 16,
              color: tint ?? context.palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a new title, seeded with the current one.
///
/// Returns null when dismissed or left unchanged, so the caller can skip
/// the write rather than touching `updated_at` for nothing — that column
/// orders the list, and a cancelled rename must not reorder it.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String current,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(current: current),
  );

  final clean = result?.trim();
  if (clean == null || clean.isEmpty || clean == current) return null;
  return clean;
}

/// The rename dialog, which owns its own controller.
///
/// Stateful for a reason that is easy to get wrong: disposing the
/// controller straight after `showDialog` returns disposes it while the
/// route is still animating out, and the field rebuilds once more on the
/// way — "A TextEditingController was used after being disposed". Tying its
/// lifetime to the dialog's own State is what makes the teardown ordered.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text('Rename chat', style: context.typography.ui(size: 16)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        style: context.typography.ui(size: 14),
        decoration: appInputDecoration(context, hint: 'Chat name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: context.typography.ui(size: 13.5)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            'Rename',
            style: context.typography.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: palette.accentBright,
            ),
          ),
        ),
      ],
    );
  }
}
