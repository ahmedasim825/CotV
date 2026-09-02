import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/milo_models.dart';
import '../../providers/milo_providers.dart';
import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import 'milo_keys_sheet.dart';
import 'widgets/milo_turn.dart';

/// Milo's panel: the conversation, the composer, and the way into its keys.
///
/// Presented as the app shell's end drawer, so it slides in over whichever
/// screen the user was on and takes the back gesture and the scrim from
/// Flutter rather than reimplementing them.
class MiloAssistantScreen extends ConsumerWidget {
  const MiloAssistantScreen({super.key});

  /// Wide enough for a paragraph without crowding the screen it covers.
  static const double maxWidth = 440;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final conversation = ref.watch(miloConversationProvider);

    return Drawer(
      width: math.min(maxWidth, MediaQuery.sizeOf(context).width - 24),
      elevation: 0,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const _PanelHeader(),
            Expanded(
              child: conversation.isEmpty
                  ? const _EmptyState()
                  : _Transcript(messages: conversation.messages),
            ),
            _Composer(isBusy: conversation.isBusy),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final hasHistory = !ref.watch(miloConversationProvider).isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: palette.accentBright,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Milo',
              style: context.typography.display(size: 24, letterSpacing: -0.6),
            ),
          ),
          if (hasHistory)
            _HeaderChip(
              icon: PhLight.trash,
              tooltip: 'Clear conversation',
              onTap: () => ref.read(miloConversationProvider.notifier).clear(),
            ),
          _HeaderChip(
            icon: PhLight.gear,
            tooltip: 'Milo settings',
            onTap: () => showMiloKeysSheet(context),
          ),
          _HeaderChip(
            icon: PhLight.x,
            tooltip: 'Close Milo',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: minTouchTarget,
            height: minTouchTarget,
            child: Icon(icon, size: 18, color: context.palette.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Newest turn at the bottom, pinned there while a reply streams.
///
/// The list is built in reverse so growing the last message keeps the view
/// anchored to it, instead of needing a scroll controller to chase the
/// bottom on every token.
class _Transcript extends StatelessWidget {
  const _Transcript({required this.messages});

  final List<MiloMessage> messages;

  @override
  Widget build(BuildContext context) {
    final reversed = messages.reversed.toList(growable: false);

    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      itemCount: reversed.length,
      separatorBuilder: (context, index) => const SizedBox(height: 22),
      itemBuilder: (context, index) => MiloTurn(message: reversed[index]),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  /// One prompt per route, so the empty panel doubles as the explanation of
  /// what Milo can reach: the instant model, the deep model, and the PC.
  static const List<String> _examples = [
    "What's my next prayer?",
    'Open Spotify on my PC',
    'Plan a study block around Maghrib tonight',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final secrets = ref.watch(miloSecretsProvider).value;
    final needsKey =
        secrets != null && !secrets.hasGroq && !secrets.hasGemini;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            eyebrow: 'ASSISTANT',
            title: needsKey ? 'Milo needs a key' : 'Ask Milo.',
            titleSize: 26,
            subtitle: needsKey
                ? 'Add a Groq key for instant answers, a Gemini key for '
                    'planning, or both. Milo routes each request to '
                    'whichever fits.'
                : 'Say what you want. Short commands go to Groq, anything '
                    'that needs working out goes to Gemini, and anything '
                    'aimed at the laptop goes to your PC agent.',
          ),
          const SizedBox(height: 20),
          if (needsKey)
            PrimaryButton(
              label: 'Add keys',
              icon: PhLight.key,
              onPressed: () => showMiloKeysSheet(context),
            )
          else
            for (final example in _examples) ...[
              _ExampleChip(text: example),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 8),
          Text(
            'Say "Milo" first if you like — the wake word is stripped '
            'before the request is read.',
            style: context.typography.ui(
              size: 11.5,
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleChip extends ConsumerWidget {
  const _ExampleChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return CustomCard(
      radius: 18,
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      semanticLabel: 'Ask: $text',
      onTap: () => ref.read(miloConversationProvider.notifier).send(text),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: context.typography.ui(size: 13.5, height: 1.35),
            ),
          ),
          const SizedBox(width: 10),
          Icon(PhLight.caretRight, size: 14, color: palette.textMuted),
        ],
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.isBusy});

  final bool isBusy;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Rebuilds so Send enables the moment the field stops being empty.
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(miloConversationProvider.notifier).send(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canSend = _controller.text.trim().isNotEmpty && !widget.isBusy;

    return Padding(
      // Lifts the composer with the keyboard; the drawer itself does not
      // resize for it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: context.typography.ui(size: 14.5, height: 1.4),
                decoration: appInputDecoration(
                  context,
                  hint: 'Ask Milo',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              isBusy: widget.isBusy,
              canSend: canSend,
              onSend: _send,
              onStop: () => ref.read(miloConversationProvider.notifier).stop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Send, which becomes Stop for as long as a reply is streaming — one
/// control, because there is never a moment where both apply.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isBusy,
    required this.canSend,
    required this.onSend,
    required this.onStop,
  });

  final bool isBusy;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = isBusy || canSend;

    return Semantics(
      button: true,
      enabled: enabled,
      label: isBusy ? 'Stop Milo' : 'Send to Milo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isBusy ? onStop : (canSend ? onSend : null),
        child: SizedBox(
          width: minTouchTarget,
          height: minTouchTarget,
          child: Center(
            child: AnimatedContainer(
              duration: context.motion.fast,
              curve: AppMotion.spring,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: enabled ? palette.accent : palette.glassFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isBusy ? PhLight.stopCircle : PhLight.paperPlaneRight,
                size: 17,
                color: enabled ? palette.onAccent : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The control that opens Milo.
///
/// A glass pill rather than a filled one, and anchored to the left: every
/// screen's own primary action already lives as an accent pill in the
/// bottom-right corner, and Milo is a utility beside them, not a rival to
/// them.
class MiloLauncher extends StatefulWidget {
  const MiloLauncher({super.key});

  @override
  State<MiloLauncher> createState() => _MiloLauncherState();
}

class _MiloLauncherState extends State<MiloLauncher> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: 'Open Milo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () => Scaffold.of(context).openEndDrawer(),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: context.motion.fast,
          curve: AppMotion.spring,
          child: Container(
            height: minTouchTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                palette.accent.withValues(alpha: 0.14),
                palette.surface,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhLight.sparkle, size: 16, color: palette.accentBright),
                const SizedBox(width: 9),
                Text(
                  'Milo',
                  style: context.typography.ui(
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
