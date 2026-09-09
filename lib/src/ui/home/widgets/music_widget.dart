import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/media_providers.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'home_card_note.dart';

/// The now-playing card in the top-right of the dashboard.
class MusicWidget extends ConsumerWidget {
  const MusicWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final playing = ref.watch(nowPlayingProvider);

    if (playing == null) {
      return GlassCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: HomeCardNote(
          icon: PhLight.musicNotes,
          message: 'Nothing playing',
        ),
      );
    }

    final controller = ref.read(nowPlayingProvider.notifier);

    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: palette.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Playing on ${playing.sourceApp}',
                style: context.typography.ui(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Artwork(url: playing.artworkUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      playing.artist,
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
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _TransportButton(
                icon: PhLight.skipBack,
                tooltip: 'Previous',
                onTap: controller.previous,
              ),
              _TransportButton(
                icon: playing.isPlaying ? PhLight.pause : PhLight.play,
                tooltip: playing.isPlaying ? 'Pause' : 'Play',
                onTap: controller.togglePlayPause,
              ),
              _TransportButton(
                icon: PhLight.skipForward,
                tooltip: 'Next',
                onTap: controller.next,
              ),
              const Spacer(),
              _VolumeControl(
                volume: playing.volume,
                onChanged: controller.setVolume,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 40,
        child: url == null
            ? ColoredBox(
                color: palette.surfaceRaised,
                child: Icon(PhLight.musicNotes,
                    size: 18, color: palette.textMuted),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                // A dead artwork URL must not take the card down with it.
                errorBuilder: (context, error, stack) => ColoredBox(
                  color: palette.surfaceRaised,
                  child: Icon(PhLight.musicNotes,
                      size: 18, color: palette.textMuted),
                ),
              ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 30,
          child: Icon(icon, size: 19, color: context.palette.textSecondary),
        ),
      ),
    );
  }
}

/// A speaker glyph that opens a slider.
///
/// The slider is in a popup rather than inline: the card is roughly 260pt
/// wide and a track long enough to be usable would crowd out the transport.
///
/// Stateful, and the drag position is held here rather than read back from
/// the provider: the popup route is a separate subtree that does not rebuild
/// when the card does, so a slider reading [volume] straight through would
/// snap back to its old value on every frame of the drag.
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
  void didUpdateWidget(_VolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.volume != oldWidget.volume) {
      _value = widget.volume;
    }
  }

  IconData get _icon {
    if (_value <= 0.01) return PhLight.speakerNone;
    if (_value < 0.5) return PhLight.speakerLow;
    return PhLight.speakerHigh;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return PopupMenuButton<void>(
      tooltip: 'Volume',
      color: palette.surfaceRaised,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            width: 150,
            child: StatefulBuilder(
              builder: (context, setPopupState) => Slider(
                value: _value,
                activeColor: palette.accentBright,
                inactiveColor: palette.meterTrack,
                onChanged: (next) {
                  // Both: the popup redraws its own track, and the card
                  // swaps the speaker glyph.
                  setPopupState(() {});
                  setState(() => _value = next);
                  widget.onChanged(next);
                },
              ),
            ),
          ),
        ),
      ],
      child: SizedBox(
        width: 34,
        height: 30,
        child: Icon(_icon, size: 19, color: palette.textSecondary),
      ),
    );
  }
}
