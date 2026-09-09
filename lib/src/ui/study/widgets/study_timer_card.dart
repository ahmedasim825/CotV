import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/study_view.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/study_providers.dart';
import '../../components/components.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_shell.dart';
import '../../widgets/ph_light_icons.dart';
import '../subject_colors.dart';

/// The session in flight, or the one that just finished.
///
/// Reads the time left off [nowTickerProvider] and the session's stored end
/// instant, the same way [FocusSessionOverlay] does — nothing here counts
/// down, so backgrounding the app costs exactly the time it took.
class StudyTimerCard extends ConsumerWidget {
  const StudyTimerCard({super.key, required this.accent});

  /// The subject's colour, so a running session is visibly the one the user
  /// started.
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final study = ref.watch(studyProvider);

    if (study.phase == StudyPhase.completed) {
      return _CompletedCard(accent: accent);
    }

    final session = study.session;
    if (session == null) return const SizedBox.shrink();

    final isPaused = study.phase == StudyPhase.paused;
    // A paused session holds a fixed remainder, so every reading below is
    // independent of `now` — and watching the ticker would keep it alive
    // once a second for a countdown that is not moving.
    final now = isPaused
        ? DateTime.now()
        : (ref.watch(nowTickerProvider).value ?? DateTime.now());

    final remaining = session.remainingAt(now);
    final notifier = ref.read(studyProvider.notifier);

    return GlassShell(
      outerRadius: 30,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountdownRing(
            progress: session.progressAt(now),
            accent: accent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.subjectName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.eyebrow(
                    color: context.palette.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatCountdown(remaining),
                  style: context.typography.display(size: 42, color: accent),
                ),
                const SizedBox(height: 6),
                Text(
                  isPaused
                      ? 'Paused'
                      : 'of ${formatStudyMinutes(session.planned.inMinutes)}',
                  style: context.typography.ui(
                    size: 12,
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: isPaused ? 'Resume' : 'Pause',
                  icon: isPaused ? PhLight.playCircle : PhLight.pauseCircle,
                  variant: ButtonVariant.outline,
                  expand: true,
                  onPressed: isPaused ? notifier.resume : notifier.pause,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: 'End',
                  icon: PhLight.check,
                  expand: true,
                  onPressed: notifier.stop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            // Says what ending now would record, so stopping early is an
            // informed choice rather than a guess at what gets kept.
            _endNote(session.elapsedAt(now)),
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 11.5,
              color: context.palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _endNote(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    return minutes < 1
        ? 'Ending now logs nothing — under a minute studied.'
        : 'Ending now logs ${formatStudyMinutes(minutes)}.';
  }
}

/// What was recorded, shown until dismissed.
class _CompletedCard extends ConsumerWidget {
  const _CompletedCard({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final log = ref.watch(studyProvider).completed;
    if (log == null) return const SizedBox.shrink();

    return CustomCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(PhLight.check, size: 20, color: accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatStudyMinutes(log.durationMinutes)} logged',
                  style: context.typography.ui(
                    size: 15,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${log.subjectName} · ${formatClock(log.timestamp)}',
                  style: context.typography.ui(
                    size: 12.5,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PrimaryButton(
            label: 'Done',
            size: ButtonSize.compact,
            variant: ButtonVariant.outline,
            onPressed: ref.read(studyProvider.notifier).dismiss,
          ),
        ],
      ),
    );
  }
}

/// A progress ring with [child] centred inside it.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.progress,
    required this.accent,
    required this.child,
    this.diameter = 208,
    this.strokeWidth = 10,
  });

  /// 0..1. Values outside that are clamped by the painter.
  final double progress;
  final Color accent;
  final Widget child;
  final double diameter;

  /// How thick the ring is drawn. The default is deliberately heavy: a
  /// hairline ring reads as a loading spinner, and these are measurements.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        // Matches the second the ticker advances on, so the sweep is
        // continuous rather than stepping once per rebuild.
        duration: const Duration(milliseconds: 900),
        curve: Curves.linear,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            progress: value,
            accent: accent,
            track: palette.meterTrack,
            stroke: strokeWidth,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: diameter * 0.16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color accent;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(centre, radius, trackPaint);

    if (progress <= 0) return;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = accent;

    // Twelve o'clock, clockwise — the direction a clock face already
    // teaches, so the sweep needs no explaining.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.track != track ||
      old.stroke != stroke;
}

/// The colour a session should draw in: the subject's own if it still
/// exists, otherwise the theme accent.
///
/// A session outlives its subject — the subject can be deleted while the
/// timer runs — so this resolves by id and falls back rather than assuming.
Color studyAccentFor(BuildContext context, WidgetRef ref) {
  final session = ref.watch(studyProvider).session;
  final subjectId = session?.subjectId ??
      ref.watch(studyProvider).completed?.subjectId;
  if (subjectId == null) return context.palette.accent;

  final subjects = ref.watch(subjectListProvider).value;
  final match = subjects?.where((s) => s.id == subjectId).firstOrNull;
  return match == null ? context.palette.accent : subjectColor(match.colorValue);
}
