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
    // Narrowed to the one field this widget reads. `miloVoiceProvider` emits
    // a fresh state per amplitude sample while the microphone is open — every
    // 120ms, per `VoiceCapture.onAmplitudeChanged` — and watching the whole
    // object rebuilt the orb at that rate for a phase that changes a handful
    // of times per recording. `error` is not read here; it is handled by the
    // `ref.listen` below, which does not rebuild.
    final phase = ref.watch(miloVoiceProvider.select((voice) => voice.phase));
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
    if (isBusy || phase == MiloVoicePhase.transcribing) {
      state = MiloOrbState.thinking;
    } else if (phase == MiloVoicePhase.listening) {
      state = MiloOrbState.listening;
    } else {
      state = MiloOrbState.idle;
    }

    return MiloOrbWidget(
      diameter: diameter,
      state: state,
      isListening: phase == MiloVoicePhase.listening,
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

    final label =
        'Milo, ${widget.state.description}.'
        '${widget.onTap == null ? '' : ' Tap to speak.'}'
        '${_gestureHint(platform)}';

    // Two boundaries, each doing a different job. This outer one keeps the
    // breath's repaint from re-recording the sidebar chrome it shares a
    // display list with: the nav rows, the divider and the footer are static.
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: widget.onTap,
          // Each recognizer is added only on the platform that wants it. A
          // double-tap recognizer holds the arena for kDoubleTapTimeout, so
          // wiring one everywhere would put ~300ms between the tap and the
          // microphone on platforms that never use it.
          onDoubleTap: platform == TargetPlatform.windows
              ? widget.onTextMilo
              : null,
          onLongPress: platform == TargetPlatform.iOS
              ? widget.onTextMilo
              : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            // The aura bleeds well past the core, so the box is roomier than
            // the orb itself and the glow is not clipped by a tight parent.
            width: size * 1.6,
            height: size * 1.6,
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_breath, _pulse]),
                // The core answers to neither controller, so it is built once
                // and handed through rather than rebuilt with every breath.
                child: _Core(diameter: size, palette: palette),
                builder: (context, core) {
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
                        // The inner boundary, and the one that matters. The
                        // aura carries two shadow blurs, ~83pt and ~60pt wide
                        // at the expanded dock. Its decoration is value-equal
                        // between frames while resting, so it never dirties
                        // itself — but a repainting ancestor re-runs the whole
                        // subtree's paint, so without this the blurs were
                        // re-drawn every frame anyway. Behind a boundary they
                        // rasterize once and the breath scales the retained
                        // layer at composite time.
                        child: RepaintBoundary(
                          child: _Aura(
                            diameter: size * _auraSpread,
                            // Brightened as well as widened, so the listening
                            // state reads as more light rather than only as a
                            // wider halo.
                            intensity: intensity * (1 + pulse * 0.55),
                            isListening: widget.isListening,
                          ),
                        ),
                      ),
                      core!,
                    ],
                  );
                },
              ),
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
    required this.intensity,
    required this.isListening,
  });

  final double diameter;

  /// A multiplier on every alpha in here, above 1 while Milo is listening.
  /// Each product is clamped, since [Color.withValues] rejects an alpha
  /// past 1 and the brightest theme is already close to it.
  final double intensity;

  /// Whether the microphone is open right now.
  final bool isListening;

  /// The aura is the "active" signal, so it stays weaker at rest than while
  /// Milo is listening — painting it at full strength always would make
  /// "active" mean nothing. The rise to full strength while listening is
  /// carried by [intensity] (driven by `_pulse`); this is the floor it rises
  /// from. Lifted from 0.45 in the redesign: at that value the glow read as
  /// absent rather than as idle, and the resting orb looked unlit.
  double get _auraOpacity => isListening ? 1.0 : 0.75;

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
          // White light spilling off the orb, falling away to nothing.
          //
          // The gradient is the whole glow. There were two [BoxShadow]s under
          // it as well — a drop shadow is a blurred silhouette of the orb
          // painted behind it, which on Milo's near-white section ground read
          // as a grey smudge under the sphere rather than as light.
          //
          // Every stop lives past 0.645, and that is the whole trick: this box
          // is [_auraSpread] times the core's diameter, so the core hides the
          // inner 1/[_auraSpread] of it. Stops inside that are invisible. The
          // violet version of this glow put two stops at 0.0 and 0.36 and got
          // away with it because its box shadows carried the halo; in white and
          // black the only band left showing was the dark one, which read as a
          // shadow around the orb rather than as light coming off it.
          gradient: RadialGradient(
            colors: [
              _orbLight.withValues(alpha: _alpha(0.50)),
              _orbLight.withValues(alpha: _alpha(0.42)),
              _orbLight.withValues(alpha: _alpha(0.20)),
              _orbLight.withValues(alpha: 0),
            ],
            stops: const [0.0, _coreEdge, 0.84, 1.0],
          ),
        ),
      ),
    );
  }
}

/// The orb body: a white-to-black ramp running top-left to bottom-right, so it
/// reads as a sphere lit from above-left rather than as a flat disc. No face —
/// what Milo is doing is read off the aura around it, not off a pair of eyes.
///
/// A [LinearGradient] rather than the radial one this used to carry, and
/// monochrome rather than violet: the accent moved out to the rail's active
/// tab in the redesign, and two violet signals competed.
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_orbLight, _orbShadowed],
        ),
        // No border. The violet rim that used to sit here separated a violet
        // sphere from a slate ground; in white it drew a hard outline around
        // the gradient and flattened it into a disc.
      ),
    );
  }
}

/// The lit end of the orb, and the near half of its glow.
const Color _orbLight = Color(0xFFFFFFFF);

/// The unlit end of the orb: black at half alpha, so the ground shows through
/// the shadowed side instead of punching a hole in it.
const Color _orbShadowed = Color(0x80000000);

/// How much wider the glow is than the orb it comes off.
const double _auraSpread = 1.55;

/// Where the core's edge falls across the glow's own radius.
///
/// The core hides everything inside this, so a gradient stop below it paints
/// nothing. Kept as a name so the two stay in step.
const double _coreEdge = 1 / _auraSpread;
