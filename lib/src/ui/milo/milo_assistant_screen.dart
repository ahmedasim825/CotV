import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/milo_models.dart';
import '../../providers/milo_providers.dart';
import '../../providers/user_settings_providers.dart';
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
    final speaks = ref.watch(miloSpeaksProvider);

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
          _HeaderChip(
            // Reads as a switch rather than a button: it reports a standing
            // state, and the slashed glyph is what tells you which.
            icon: speaks ? PhLight.speakerHigh : PhLight.speakerSlash,
            tooltip: speaks ? 'Milo speaks replies' : 'Milo replies silently',
            tint: speaks ? palette.accentBright : null,
            onTap: () {
              // Turning it off mid-sentence should stop that sentence, not
              // only the next one.
              if (speaks) unawaited(ref.read(miloSpeechProvider).stop());
              unawaited(
                ref
                    .read(userSettingsControllerProvider.notifier)
                    .setSpeaksReplies(!speaks),
              );
            },
          ),
          if (hasHistory)
            _HeaderChip(
              icon: PhLight.trash,
              tooltip: 'Clear conversation',
              onTap: () => ref.read(miloConversationProvider.notifier).clear(),
            ),
          // Distinct from clearing, and confirmed, because it is the only
          // control that reaches what Milo has kept: the durable transcript
          // and the summary distilled from it. Clearing tidies the screen;
          // this is the one the user needs when the answer to "what does it
          // know about me" has to be "nothing".
          _HeaderChip(
            icon: PhLight.brain,
            tooltip: 'Forget what Milo knows',
            onTap: () => _confirmForget(context, ref),
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

/// Confirms, then erases the durable transcript and the memory summary.
///
/// Behind a confirmation because it is not undoable and because the icon
/// beside it clears the screen — two adjacent controls, one recoverable and
/// one not, need the destructive one to ask.
Future<void> _confirmForget(BuildContext context, WidgetRef ref) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Forget what Milo knows?',
    message: 'Erases the saved conversation and the summary Milo has built '
        'from it. The next turn starts from nothing. Your prayer times, '
        'tasks, habits and study logs are not touched.',
    confirmLabel: 'Forget',
    confirmIcon: PhLight.brain,
  );
  if (!confirmed) return;

  await ref.read(miloConversationProvider.notifier).forget();
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Set when the chip is showing an on state rather than offering an
  /// action, which is what separates the speaker toggle from its neighbours.
  final Color? tint;

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
            child: Icon(icon, size: 18, color: tint ?? context.palette.textMuted),
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
    final voice = ref.watch(miloVoiceProvider);
    final canSend = _controller.text.trim().isNotEmpty &&
        !widget.isBusy &&
        !voice.isBusy;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (voice.error != null) ...[
              _VoiceError(
                message: voice.error!,
                onDismiss: () =>
                    ref.read(miloVoiceProvider.notifier).clearError(),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    // Typing over a recording would leave two half-finished
                    // inputs racing for the same turn.
                    enabled: !voice.isBusy,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: context.typography.ui(size: 14.5, height: 1.4),
                    decoration: appInputDecoration(
                      context,
                      hint: switch (voice.phase) {
                        MiloVoicePhase.listening => 'Listening…',
                        MiloVoicePhase.transcribing => 'Working out what you '
                            'said…',
                        MiloVoicePhase.idle => 'Ask Milo, or hold the mic',
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _ComposerAction(
                  isStreaming: widget.isBusy,
                  canSend: canSend,
                  voice: voice,
                  onSend: _send,
                  onStopReply: () =>
                      ref.read(miloConversationProvider.notifier).stop(),
                  onToggleVoice: () =>
                      ref.read(miloVoiceProvider.notifier).toggle(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The composer's one control.
///
/// Send, mic, and both kinds of stop are the same button, because there is
/// never a moment where two of them apply: an empty box can only offer
/// voice, a filled one can only offer send, and while either is in flight
/// the only thing left to do is stop it. A separate mic would be dead
/// weight two thirds of the time.
class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.isStreaming,
    required this.canSend,
    required this.voice,
    required this.onSend,
    required this.onStopReply,
    required this.onToggleVoice,
  });

  final bool isStreaming;
  final bool canSend;
  final MiloVoiceState voice;
  final VoidCallback onSend;
  final VoidCallback onStopReply;
  final VoidCallback onToggleVoice;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final (IconData icon, String label, VoidCallback? action, Color tint) =
        switch ((isStreaming, voice.phase, canSend)) {
      (true, _, _) => (
          PhLight.stopCircle,
          'Stop Milo',
          onStopReply,
          palette.accent,
        ),
      (_, MiloVoicePhase.listening, _) => (
          PhLight.stopCircle,
          'Stop listening and send',
          onToggleVoice,
          palette.danger,
        ),
      (_, MiloVoicePhase.transcribing, _) => (
          PhLight.waveform,
          'Working out what you said',
          null,
          palette.accent,
        ),
      (_, _, true) => (
          PhLight.paperPlaneRight,
          'Send to Milo',
          onSend,
          palette.accent,
        ),
      _ => (PhLight.microphone, 'Speak to Milo', onToggleVoice, palette.accent),
    };

    final enabled = action != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: action,
          child: SizedBox(
            width: minTouchTarget,
            height: minTouchTarget,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The ring is the only proof the microphone is actually
                  // hearing something. Without it a dead input device looks
                  // exactly like a quiet room, and the difference only shows
                  // up after the request has already failed.
                  if (voice.phase == MiloVoicePhase.listening)
                    _LevelRing(level: voice.level, colour: palette.danger),
                  AnimatedContainer(
                    duration: context.motion.fast,
                    curve: AppMotion.spring,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: enabled ? tint : palette.glassFill,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 17,
                      color: enabled ? palette.onAccent : palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring that grows with how loudly Milo is hearing you.
class _LevelRing extends StatelessWidget {
  const _LevelRing({required this.level, required this.colour});

  final double level;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    // Never fully collapses: a ring that vanishes in a pause reads as the
    // microphone dropping out rather than as silence.
    final size = 38 + 10 * level.clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colour.withValues(alpha: 0.45), width: 2),
      ),
    );
  }
}

/// Why the last spoken turn did not land, with a way to dismiss it.
class _VoiceError extends StatelessWidget {
  const _VoiceError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhLight.microphone, size: 15, color: palette.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: context.typography.ui(
                size: 12.5,
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Dismiss',
            child: GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(PhLight.x, size: 14, color: palette.textMuted),
              ),
            ),
          ),
        ],
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
