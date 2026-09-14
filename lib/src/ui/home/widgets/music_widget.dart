import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/now_playing.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/media_palette_providers.dart';
import '../../../providers/media_providers.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'home_card_note.dart';
import 'media_scrubber.dart';

/// Whatever the machine is playing, with the controls to drive it.
///
/// Reads the Windows media session, so the source is whichever app last took
/// the system transport — Spotify, a browser tab, a game. Not built on iOS;
/// `home_screen.dart` leaves it out of the glass path entirely.
///
/// The card borrows its ground from the album art rather than carrying a fixed
/// accent, which is why it takes no `rim`: the artwork is the colour, and a
/// violet rim around a cover that is not violet reads as a mistake.
class MusicWidget extends ConsumerWidget {
  const MusicWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final playing = ref.watch(nowPlayingProvider);

    // Loading and error both render as idle. There is no useful difference to
    // a reader between "the bridge has not answered yet" and "nothing is
    // playing", and a spinner on a card that is idle most of the day is worse
    // than a line of text.
    final track = playing.value;
    if (track == null) {
      return GlassCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: HomeCardNote(
          message: playing.hasError
              ? 'Media controls are unavailable'
              : 'Nothing playing',
        ),
      );
    }

    final borrowed =
        ref.watch(mediaPaletteProvider).value ?? MediaPalette.fallback;
    final media = resolveMediaPalette(context, borrowed);
    final transport = ref.read(mediaTransportProvider);

    // The position arrives as a reading plus a timestamp, not a live value, so
    // it is advanced here off the app's one-second ticker. Same split the
    // prayer countdowns use: the source updates rarely, the leaf renders often.
    final now = ref.watch(nowTickerProvider).value ?? DateTime.now();
    final position = track.livePosition(now);

    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      // The album art's colour. `tint` overrides the fill outright, which is
      // what makes the card take the cover's ground rather than the page's.
      tint: media.tint,
      // Two bands, not three. The transport used to sit on a row of its own
      // under the timeline, which cost the card ~36pt of height to show four
      // glyphs across a third of the width. Beside the text it costs nothing,
      // and the card comes out shorter — the trade is that it needs the width,
      // which is why `home_screen.dart` gives it 420 rather than 340.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Artwork(track: track),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SourceLine(sourceApp: track.sourceApp),
                    const SizedBox(height: 4),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 14,
                        weight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      track.artist.isEmpty ? track.album : track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TransportRow(track: track, transport: transport),
            ],
          ),
          const SizedBox(height: 6),
          _TimelineRow(
            position: position,
            duration: track.duration,
            color: media.edge,
            onSeek: transport.seek,
            volume: track.volume,
            onVolume: transport.setVolume,
          ),
        ],
      ),
    );
  }
}

/// The elapsed figure, the bar, and the total.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.position,
    required this.duration,
    required this.color,
    required this.onSeek,
    required this.volume,
    required this.onVolume,
  });

  final Duration position;
  final Duration? duration;
  final Color color;
  final ValueChanged<Duration> onSeek;
  final double volume;
  final ValueChanged<double> onVolume;

  @override
  Widget build(BuildContext context) {
    final style = context.typography.mono(
      size: 10.5,
      color: context.palette.textMuted,
    );

    return Row(
      children: [
        Text(formatTrackTime(position), style: style),
        const SizedBox(width: 8),
        Expanded(
          child: MediaScrubber(
            position: position,
            duration: duration,
            color: color,
            onSeek: onSeek,
          ),
        ),
        const SizedBox(width: 8),
        Text(formatTrackTime(duration), style: style),
        // Down here rather than beside the transport: it balances the two time
        // figures, and up there it was taking width the title needed.
        _VolumeControl(volume: volume, onChanged: onVolume),
      ],
    );
  }
}

/// "Playing on Spotify", with the live dot.
///
/// The app, never the website: the media session API carries no origin, so a
/// YouTube tab and a news site in the same browser are the same session as far
/// as Windows is concerned.
class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.sourceApp});

  final String sourceApp;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: palette.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Playing on $sourceApp',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.ui(
              size: 10.5,
              weight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The cover, or a plate when the source offered none.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});

  final NowPlaying track;

  // 48, not 56: the header band is the taller of the cover and the three
  // lines of text beside it, and at 56 the cover was setting that height on
  // its own for no gain.
  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final bytes = track.artwork;
    final url = track.artworkUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _size,
        height: _size,
        child: bytes != null
            ? Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => const _ArtworkPlate(),
              )
            : url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const _ArtworkPlate(),
              )
            : const _ArtworkPlate(),
      ),
    );
  }
}

/// The stand-in when there is no cover to show.
///
/// A light plate rather than the app's dark surface, so it reads as "no
/// artwork" rather than as a hole in the card.
class _ArtworkPlate extends StatelessWidget {
  const _ArtworkPlate();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFC9C9CE),
      child: Icon(
        PhFill.musicNotes,
        size: 22,
        color: Colors.black.withValues(alpha: 0.35),
      ),
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.track, required this.transport});

  final NowPlaying track;
  final MediaTransportController transport;

  @override
  Widget build(BuildContext context) {
    // Sized to its contents and sitting at the end of the header row, so the
    // card's height is the artwork's rather than the artwork's plus a row of
    // buttons. The dead spacer that used to balance the volume control against
    // the trio went with the row it was centring.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TransportButton(
          icon: PhFill.skipBack,
          tooltip: 'Previous',
          enabled: track.canGoPrevious,
          onTap: transport.previous,
        ),
        _TransportButton(
          icon: track.isPlaying ? PhFill.pause : PhFill.play,
          tooltip: track.isPlaying ? 'Pause' : 'Play',
          size: 22,
          onTap: transport.playPause,
        ),
        _TransportButton(
          icon: PhFill.skipForward,
          tooltip: 'Next',
          enabled: track.canGoNext,
          onTap: transport.next,
        ),
      ],
    );
  }
}

const double _transportButtonWidth = 32;
const double _transportButtonHeight = 30;

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 18,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  /// The session says which verbs it accepts. A greyed skip is honest about a
  /// source that has no queue; a live one that does nothing is not.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: _transportButtonWidth,
          height: _transportButtonHeight,
          child: Icon(
            icon,
            size: size,
            color: enabled
                ? palette.textPrimary
                : palette.textMuted.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// System output level, in a popup.
///
/// The scrubber already has the full width of the card, so an inline volume
/// track would have to come out of the transport's space. The popup keeps both,
/// and keeps the control the same size as the three transport buttons it sits
/// beside.
///
/// System-wide, not this app's: the media session API has no volume of its own,
/// so this goes through Core Audio's default output endpoint.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  late double _value = widget.volume;

  @override
  void didUpdateWidget(_VolumeControl old) {
    super.didUpdateWidget(old);
    if (old.volume != widget.volume) _value = widget.volume;
  }

  IconData get _icon {
    if (_value <= 0.01) return PhFill.speakerNone;
    if (_value < 0.5) return PhFill.speakerLow;
    return PhFill.speakerHigh;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return PopupMenuButton<void>(
      tooltip: 'System volume',
      color: palette.surfaceRaised,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            width: 150,
            // The popup is an Overlay-rooted subtree that does not rebuild
            // with the card, so the slider drives its own state and the card's
            // value is only a starting point.
            child: StatefulBuilder(
              builder: (context, setPopupState) => Slider(
                value: _value,
                activeColor: palette.accentBright,
                inactiveColor: palette.meterTrack,
                onChanged: (next) {
                  setPopupState(() {});
                  setState(() => _value = next);
                  widget.onChanged(next);
                },
              ),
            ),
          ),
        ),
      ],
      // Smaller than a transport button. It sits on the timeline row now,
      // beside 10.5pt figures, and at the transport's 30pt it was setting that
      // row's height on its own.
      child: SizedBox(
        width: 26,
        height: 22,
        child: Icon(_icon, size: 15, color: palette.textSecondary),
      ),
    );
  }
}
