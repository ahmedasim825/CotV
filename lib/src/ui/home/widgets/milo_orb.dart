import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/milo_models.dart';
import '../../../providers/milo_providers.dart';
import '../../theme/app_theme.dart';

/// What Milo is doing, which the orb shows through its aura rather than
/// through a face.
enum MiloOrbState {
  /// Milo at rest, which is where it sits whenever nothing has been asked
  /// of it.
  idle,

  /// Milo listening.
  listening,

  /// Milo working on something.
  thinking;

  /// Announced by [MiloOrbWidget]'s [Semantics] so the state is not carried
  /// by the drawing alone.
  String get description {
    switch (this) {
      case MiloOrbState.idle:
        return 'resting';
      case MiloOrbState.listening:
        return 'listening';
      case MiloOrbState.thinking:
        return 'thinking';
    }
  }
}

/// The dashboard's Milo avatar, driven by what Milo is actually doing.
///
/// The mapping is the whole of this widget. Everything else — the drawing,
/// the animation, the gestures — lives in [MiloOrbWidget], which takes no
/// providers so it can be rendered and tested on its own.
///
///   * a turn in flight, or a recording being transcribed → thinking
///   * the microphone open → listening, pulsing
///   * anything else, including no keys configured → idle
class MiloOrb extends ConsumerWidget {
  const MiloOrb({super.key, this.diameter = 128});

  final double diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(miloVoiceProvider);
    final isBusy = ref.watch(
      miloConversationProvider.select((conversation) => conversation.isBusy),
    );

    // A failed recording reports itself in the panel's composer and nowhere
    // else, so a tap on the orb that cannot open the microphone — no
    // permission, no Groq key to transcribe with — would otherwise look
    // like a tap that did nothing.
    ref.listen(miloVoiceProvider, (previous, next) {
      if (previous?.error == null && next.error != null) {
        Scaffold.maybeOf(context)?.openEndDrawer();
      }
    });

    final MiloOrbState state;
    if (isBusy || voice.phase == MiloVoicePhase.transcribing) {
      state = MiloOrbState.thinking;
    } else if (voice.phase == MiloVoicePhase.listening) {
      state = MiloOrbState.listening;
    } else {
      state = MiloOrbState.idle;
    }

    return MiloOrbWidget(
      diameter: diameter,
      state: state,
      isListening: voice.phase == MiloVoicePhase.listening,
      onTap: () => ref.read(miloVoiceProvider.notifier).toggle(),
      onTextMilo: () => Scaffold.maybeOf(context)?.openEndDrawer(),
    );
  }
}

/// Milo's avatar: a breathing radial aura around a plain lit sphere — no
/// face. What Milo is doing is read off the aura (gated brighter while
/// listening) rather than off a pair of eyes.
///
/// The aura is built entirely from [AppPalette] tokens rather than a
/// per-theme `switch`, so it is one gradient rather than a table of them —
/// there is exactly one palette now, and this was already written that way
/// before the collapse.
///
/// [state] is set by the caller rather than owned here — it only feeds the
/// [Semantics] label now that there is no face to draw it on. [isListening]
/// layers a faster, deeper pulse on the resting breath, and also drives the
/// aura to full strength; at rest it sits dimmer, which is what makes
/// "active" a visible state rather than a permanent one.
///
/// [onTap] is the microphone. [onTextMilo] opens the text panel, on the
/// gesture the platform expects: double tap on Windows, long press on iOS,
/// and nothing anywhere else — a desktop pointer has no long press, and a
/// touch double-tap is not a gesture iOS users reach for.
class MiloOrbWidget extends StatefulWidget {
  const MiloOrbWidget({
    super.key,
    this.diameter = 128,
    this.state = MiloOrbState.idle,
    this.isListening = false,
    this.onTap,
    this.onTextMilo,
  });

  final double diameter;
  final MiloOrbState state;

  /// Whether the microphone is open right now.
  final bool isListening;

  final VoidCallback? onTap;

  /// Opens the panel where Milo is talked to in text.
  final VoidCallback? onTextMilo;

  @override
  State<MiloOrbWidget> createState() => _MiloOrbWidgetState();
}

class _MiloOrbWidgetState extends State<MiloOrbWidget>
    with TickerProviderStateMixin {
  /// The slow scale pulse on the aura. Runs forever, so nothing in a test
  /// should `pumpAndSettle` over this widget.
  late final AnimationController _breath;

  /// The listening pulse. Runs only while [MiloOrbWidget.isListening], so a
  /// resting orb costs no frames beyond the breath.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is only readable from here on, and the reduced-motion
    // answer can change while the widget is alive, so this re-runs rather
    // than being decided once in initState.
    _syncMotion();
  }

  @override
  void didUpdateWidget(MiloOrbWidget old) {
    super.didUpdateWidget(old);
    if (old.isListening != widget.isListening) _syncMotion();
  }

  @override
  void dispose() {
    _breath.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Starts and stops the two looping controllers to match the current
  /// state and the platform's reduced-motion setting.
  ///
  /// Under reduced motion the pulse is parked part-way open rather than
  /// closed: listening still has to look different from resting, it just
  /// stops moving to say so.
  void _syncMotion() {
    if (context.motion.isReduced) {
      _breath.stop();
      _breath.value = 0.5;
      _pulse.stop();
      _pulse.value = widget.isListening ? 0.6 : 0;
      return;
    }

    if (!_breath.isAnimating) _breath.repeat(reverse: true);

    if (widget.isListening) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  /// How the panel is opened on this platform, for the [Semantics] label.
  /// Empty where no gesture is wired.
  String _gestureHint(TargetPlatform platform) {
    if (widget.onTextMilo == null) return '';
    switch (platform) {
      case TargetPlatform.windows:
        return ' Double tap to open the Milo panel.';
      case TargetPlatform.iOS:
        return ' Long press to open the Milo panel.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.diameter;
    final platform = Theme.of(context).platform;

    // On the one light theme the dark-theme alphas read as grime on a warm
    // white ground, so the whole aura is pulled back rather than recoloured.
    final intensity = palette.isDark ? 1.0 : 0.55;

    final label = 'Milo, ${widget.state.description}.'
        '${widget.onTap == null ? '' : ' Tap to speak.'}'
        '${_gestureHint(platform)}';

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: widget.onTap,
        // Each recognizer is added only on the platform that wants it. A
        // double-tap recognizer holds the arena for kDoubleTapTimeout, so
        // wiring one everywhere would put ~300ms between the tap and the
        // microphone on platforms that never use it.
        onDoubleTap:
            platform == TargetPlatform.windows ? widget.onTextMilo : null,
        onLongPress: platform == TargetPlatform.iOS ? widget.onTextMilo : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          // The aura bleeds well past the core, so the box is roomier than
          // the orb itself and the glow is not clipped by a tight parent.
          width: size * 1.6,
          height: size * 1.6,
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _pulse]),
              builder: (context, _) {
                final breath = Curves.easeInOut.transform(_breath.value);
                final pulse = Curves.easeInOut.transform(_pulse.value);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      // A 4% swing at rest: enough to read as breathing
                      // across a 3.2s cycle, small enough not to jostle the
                      // layout. Listening adds up to 14% on top, at four
                      // times the rate.
                      scale: 0.96 + breath * 0.08 + pulse * 0.14,
                      child: _Aura(
                        diameter: size * 1.55,
                        palette: palette,
                        // Brightened as well as widened: on Monochrome and
                        // Titanium the accent barely separates from the
                        // surface, and scale alone would not read there.
                        intensity: intensity * (1 + pulse * 0.55),
                        isListening: widget.isListening,
                      ),
                    ),
                    _Core(diameter: size, palette: palette),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The soft radial falloff around the orb.
class _Aura extends StatelessWidget {
  const _Aura({
    required this.diameter,
    required this.palette,
    required this.intensity,
    required this.isListening,
  });

  final double diameter;
  final AppPalette palette;

  /// A multiplier on every alpha in here, above 1 while Milo is listening.
  /// Each product is clamped, since [Color.withValues] rejects an alpha
  /// past 1 and the brightest theme is already close to it.
  final double intensity;

  /// Whether the microphone is open right now.
  final bool isListening;

  /// The aura is the "active" signal, so it has to be visibly weaker at
  /// rest than while Milo is listening — painting it at full strength
  /// always would make "active" mean nothing. The rise to full strength
  /// while listening is carried by [intensity] (driven by `_pulse`); this
  /// is the floor it rises from.
  double get _auraOpacity => isListening ? 1.0 : 0.45;

  double _alpha(double base) =>
      (base * intensity * _auraOpacity).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              palette.accent.withValues(alpha: _alpha(0.34)),
              palette.glowPrimary.withValues(
                alpha: _alpha(palette.glowPrimary.a * 0.9),
              ),
              // `accentDeep`, not `secondary`: `secondary` is cyan, reserved
              // for data visualisation, and ramping the aura through it read
              // on screen as a blue halo around a purple sphere. This keeps
              // the whole glow inside the accent family.
              palette.accentDeep.withValues(alpha: _alpha(0.10)),
              palette.accent.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.36, 0.62, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: _alpha(0.22)),
              blurRadius: diameter * 0.42,
              spreadRadius: diameter * 0.02,
            ),
            BoxShadow(
              color: palette.accentDeep.withValues(alpha: _alpha(0.12)),
              blurRadius: diameter * 0.30,
            ),
          ],
        ),
      ),
    );
  }
}

/// The orb body: a sphere lit from above-left so it reads as a sphere
/// rather than a flat disc. No face — what Milo is doing is read off the
/// aura around it, not off a pair of eyes.
class _Core extends StatelessWidget {
  const _Core({required this.diameter, required this.palette});

  final double diameter;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 1.05,
          colors: [
            Color.alphaBlend(
              palette.accent.withValues(alpha: palette.isDark ? 0.30 : 0.20),
              palette.surfaceRaised,
            ),
            palette.surface,
          ],
        ),
        border: Border.all(
          color: palette.accent.withValues(alpha: palette.isDark ? 0.42 : 0.30),
          width: 1.2,
        ),
      ),
    );
  }
}
