import 'package:flutter/material.dart';

import '../../../models/milo_models.dart';
import '../../../models/pc_command.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One line of the conversation.
///
/// A user turn is a tinted bubble, because it is a quotation. An assistant
/// turn is not: it is set as plain text on the panel's own surface, opened
/// by the routing rail that says which engine produced it.
class MiloTurn extends StatelessWidget {
  const MiloTurn({super.key, required this.message});

  final MiloMessage message;

  @override
  Widget build(BuildContext context) {
    return message.role == MiloRole.user
        ? _UserBubble(text: message.text)
        : _AssistantTurn(message: message);
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: palette.accentSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: context.typography.ui(size: 14.5, height: 1.45),
          ),
        ),
      ),
    );
  }
}

class _AssistantTurn extends StatelessWidget {
  const _AssistantTurn({required this.message});

  final MiloMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final routing = message.routing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (routing != null)
          RoutingRail(routing: routing, pcResult: message.pcResult),
        if (message.pcResult != null) ...[
          const SizedBox(height: 12),
          _PcReceipt(result: message.pcResult!),
        ],
        if (message.text.isNotEmpty || message.isStreaming) ...[
          const SizedBox(height: 12),
          _AnswerText(text: message.text, isStreaming: message.isStreaming),
        ],
        if (message.error != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhLight.warningCircle, size: 15, color: palette.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.error!,
                  style: context.typography.ui(
                    size: 12.5,
                    color: palette.danger,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The answer, with the caret riding the end of the last line while tokens
/// are still arriving.
class _AnswerText extends StatelessWidget {
  const _AnswerText({required this.text, required this.isStreaming});

  final String text;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final style = context.typography.ui(size: 14.5, height: 1.55);

    if (!isStreaming) return Text(text, style: style);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: 3),
              child: _StreamingCaret(),
            ),
          ),
        ],
      ),
      style: style,
    );
  }
}

/// A thin block that pulses while a reply streams, and stops the instant
/// the stream ends — so "still coming" is never guessed from stalled text.
class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret();

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: 2,
      height: 15,
      decoration: BoxDecoration(
        color: context.palette.accentBright,
        borderRadius: BorderRadius.circular(1),
      ),
    );

    // Reduced motion keeps the caret, loses the pulse: the marker still
    // says a reply is in flight, it just stops moving.
    if (context.motion.isReduced) return bar;

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: bar,
    );
  }
}

/// What the PC did, or why it did not.
class _PcReceipt extends StatelessWidget {
  const _PcReceipt({required this.result});

  final PcCommandResult result;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = result.ok ? palette.priorityLow : palette.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.ok ? PhLight.desktopTower : PhLight.wifiSlash,
            size: 16,
            color: tint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.command.summary,
                  style: context.typography.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result.message,
                  style: context.typography.ui(
                    size: 12,
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Milo's signature: the two engines and the PC as three nodes on a rail,
/// with the one that ran filled in and the others left as empty rings.
///
/// It is not ornament — the nodes come from the router's actual decision
/// and the line under them is the rule that produced it, so a wrong answer
/// can be told from a wrong route without opening a log.
class RoutingRail extends StatelessWidget {
  const RoutingRail({super.key, required this.routing, this.pcResult});

  final RoutingDecision routing;

  /// Adds the third node. Absent on turns that never touched the PC.
  final PcCommandResult? pcResult;

  static Color _hueOf(AppPalette palette, MiloEngine engine) {
    switch (engine) {
      case MiloEngine.groq:
        return palette.accentBright;
      case MiloEngine.gemini:
        return palette.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pc = pcResult;

    return Semantics(
      label: pc == null
          ? 'Answered by ${routing.engine.badge}. ${routing.reason}'
          : 'Answered by ${routing.engine.badge}. ${routing.reason}. '
              '${pc.command.summary}: ${pc.message}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final engine in MiloEngine.values) ...[
                _RailNode(
                  icon: engine == MiloEngine.groq
                      ? PhLight.lightning
                      : PhLight.brain,
                  label: engine.badge.toUpperCase(),
                  hue: _hueOf(palette, engine),
                  isActive: engine == routing.engine,
                ),
                const _RailLink(),
              ],
              if (pc == null)
                _RailNode(
                  icon: PhLight.desktopTower,
                  label: 'DONE ON PC',
                  hue: palette.priorityLow,
                  isActive: false,
                )
              else
                _RailNode(
                  icon: pc.ok ? PhLight.desktopTower : PhLight.wifiSlash,
                  label: pc.ok ? 'DONE ON PC' : 'PC FAILED',
                  hue: pc.ok ? palette.priorityLow : palette.danger,
                  isActive: true,
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            routing.reason,
            style: context.typography.ui(
              size: 11,
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The hairline between two nodes.
class _RailLink extends StatelessWidget {
  const _RailLink();

  @override
  Widget build(BuildContext context) {
    return Container(width: 10, height: 1, color: context.palette.hairline);
  }
}

/// A filled, labelled pill when its engine ran; a bare dimmed glyph when it
/// did not — so the eye lands on the one that answered.
class _RailNode extends StatelessWidget {
  const _RailNode({
    required this.icon,
    required this.label,
    required this.hue,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final Color hue;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: context.motion.fast,
      curve: AppMotion.spring,
      height: 24,
      padding: EdgeInsets.symmetric(horizontal: isActive ? 10 : 6),
      decoration: BoxDecoration(
        color: isActive ? hue.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? hue.withValues(alpha: 0.4) : palette.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isActive ? hue : palette.textMuted),
          if (isActive) ...[
            const SizedBox(width: 6),
            Text(label, style: context.typography.eyebrow(color: hue)),
          ],
        ],
      ),
    );
  }
}
