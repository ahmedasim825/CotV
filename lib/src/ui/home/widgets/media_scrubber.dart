import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The music card's progress bar, draggable.
///
/// Deliberately not a [Slider]. Two reasons, and the second is the load-bearing
/// one: Material's slider brings a thumb overlay, a focus ring and a 48pt hit
/// slab that all have to be fought back down to fit a 6pt bar; and
/// `music_widget_test.dart` finds the volume popup's slider with an unqualified
/// `find.byType(Slider)`, which a second one in the same card turns into an
/// ambiguous-finder crash rather than an honest failure.
///
/// Matches `MeterBar`'s look — same track colour, same rounded ends — because
/// the two appear on the same page and a progress bar that disagrees with the
/// other progress bars reads as a different kind of thing.
class MediaScrubber extends StatefulWidget {
  const MediaScrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.color,
    required this.onSeek,
  });

  final Duration position;

  /// Null for a live stream, which has no end to scrub toward.
  final Duration? duration;

  final Color color;

  final ValueChanged<Duration> onSeek;

  @override
  State<MediaScrubber> createState() => _MediaScrubberState();
}

class _MediaScrubberState extends State<MediaScrubber> {
  /// Where the bar is held while a drag is in flight, 0..1.
  ///
  /// Held locally because the position it is dragging against keeps arriving
  /// from the player a second at a time — following that mid-drag would make
  /// the bar fight the pointer.
  double? _dragging;

  bool _hovered = false;

  /// Hovered, or being dragged — the bar stays lit through a drag that has
  /// wandered off it, which a pointer-only test would drop.
  bool get _active => _hovered || _dragging != null;

  /// Anything with a known length takes a drag.
  ///
  /// Deliberately not gated on the session's `IsPlaybackPositionEnabled`. That
  /// flag is the source advertising seek support, and plenty of apps that
  /// honour a seek never set it — Apple Music among them, which left this bar
  /// dead there while it worked in Spotify and Chrome. Attempting the seek and
  /// having it ignored is the better failure: it costs nothing, and the
  /// alternative disabled the control on sources that did support it.
  bool get _seekable =>
      widget.duration != null && widget.duration! > Duration.zero;

  double get _fraction {
    if (_dragging != null) return _dragging!;
    final total = widget.duration;
    if (total == null || total <= Duration.zero) return 0;
    return (widget.position.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  void _setFromLocal(double dx, double width) {
    if (width <= 0) return;
    setState(() => _dragging = (dx / width).clamp(0.0, 1.0));
  }

  void _commit() {
    final fraction = _dragging;
    final total = widget.duration;
    setState(() => _dragging = null);
    if (fraction == null || total == null) return;
    widget.onSeek(
      Duration(milliseconds: (total.inMilliseconds * fraction).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return MouseRegion(
          cursor: _seekable
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _seekable
                ? (details) {
                    _setFromLocal(details.localPosition.dx, width);
                    _commit();
                  }
                : null,
            onHorizontalDragStart: _seekable
                ? (details) => _setFromLocal(details.localPosition.dx, width)
                : null,
            onHorizontalDragUpdate: _seekable
                ? (details) => _setFromLocal(details.localPosition.dx, width)
                : null,
            onHorizontalDragEnd: _seekable ? (_) => _commit() : null,
            onHorizontalDragCancel: _seekable
                ? () => setState(() => _dragging = null)
                : null,
            child: SizedBox(
              // The bar is 4pt; the rest is grab room. A 4pt drag target is
              // not one, and the padding costs nothing visually.
              height: 18,
              child: CustomPaint(
                painter: _ScrubberPainter(
                  fraction: _fraction,
                  // Lights, thickens and glows under the pointer rather than
                  // growing a handle. The bar is the control, so the whole of
                  // it has to look grabbable — a 4pt line that does not react
                  // reads as a readout.
                  color: _active
                      ? Color.lerp(widget.color, Colors.white, 0.35)!
                      : widget.color,
                  track: _active
                      ? Color.lerp(palette.meterTrack, Colors.white, 0.08)!
                      : palette.meterTrack,
                  active: _active,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  const _ScrubberPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.active,
  });

  final double fraction;
  final Color color;
  final Color track;

  /// Under a pointer, or mid-drag.
  final bool active;

  static const double _barHeight = 4;
  static const double _activeBarHeight = 7;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;

    // Edge to edge. There is no handle to keep clear of any more — the bar is
    // the control, and the row's own padding does the spacing.
    final double y = size.height / 2;
    final double height = active ? _activeBarHeight : _barHeight;
    final double filled = size.width * fraction.clamp(0.0, 1.0);

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, y - height / 2, size.width, y + height / 2),
      Radius.circular(height),
    );
    canvas.drawRRect(rrect, Paint()..color = track);

    if (filled <= 0) return;

    final filledRect = Rect.fromLTRB(0, y - height / 2, filled, y + height / 2);

    if (active) {
      // Under the bar, not clipped to it, so the light spills past the edges.
      // Drawn first so the solid fill sits on top of its own glow rather than
      // being washed out by it.
      canvas.drawRRect(
        RRect.fromRectAndRadius(filledRect, Radius.circular(height)),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(filledRect, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.active != active;
}

/// `m:ss`, or `-:--` when there is no figure to show.
///
/// Hours only appear once there is an hour, so a three-minute track does not
/// carry a leading `0:`.
String formatTrackTime(Duration? value) {
  if (value == null || value.isNegative) return '-:--';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
