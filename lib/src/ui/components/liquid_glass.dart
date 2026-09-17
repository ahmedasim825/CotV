// The render object below forwards six named constructor parameters straight
// into private fields, which `prefer_initializing_formals` flags. It cannot be
// satisfied: `this._field` is only legal for *positional* parameters, because
// a named argument may not start with an underscore. Positional would fix the
// lint and introduce a real hazard — several are bare doubles, and
// transposing two of them at the single call site would still compile.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

/// Where the shader lives. Declared under `flutter: shaders:` in pubspec.yaml.
const String _kShaderAsset = 'shaders/liquid_glass.frag';

/// Flip to true to draw every glass surface in calibration mode instead.
///
/// The shader recovers its own rect from the input texture's size, because
/// `FlutterFragCoord()` spans that texture rather than the widget — see the
/// header of `liquid_glass.frag`. The derivation is read off the engine's
/// source and is correct by construction, but "correct by construction" and
/// "correct on this GPU" are different claims. This draws the shader's idea
/// of its own geometry directly: the left half of every surface goes green
/// where the SDF believes the glass is and red where it does not, with a
/// white line on the rim; the right half shows the backdrop sampled with no
/// displacement, which should line up seamlessly with the page around it.
///
/// Green filling the left half with the line hugging the border means the
/// rect is anchored. The right half matching its surroundings — rather than
/// appearing mirrored top-to-bottom — means the texture read is the right way
/// up. Both are backend-dependent: it was this that caught an OpenGLES y-flip
/// on the geometry that does not actually happen, and which had put the rect
/// off the surface entirely. Worth re-running on any backend the app has not
/// been seen on.
const bool kDebugCalibrateLiquidGlass = false;

/// Apple's Liquid Glass, as far as Flutter can be made to draw it.
///
/// **What separates this from frosted glass.** A frosted pane blurs what is
/// behind it and stops there; every pane of it in the app looks the same and
/// sits flat. Real glass is a *lens* — it bends light at its edge, where the
/// surface curves away, and leaves the middle alone. That bend is the whole
/// read, and it is why [GlassCard]'s blur never looked like iOS 26 no matter
/// what the fill was set to. Here the rim genuinely refracts: the background
/// is sampled at a displaced coordinate that grows toward the edge, so
/// whatever is behind the glass slides and stretches under its border as the
/// page scrolls past.
///
/// **This is the control layer's material, and only the control layer's.**
/// The app draws two: this, for things that float over the page and stay put
/// while it moves — the nav pill, the search field, the Milo drawer — and
/// [GlassCard]'s plain frosted fill for content that scrolls. Apple's guidance
/// is emphatic that glass is chrome, not content, and there is a second reason
/// here: a fragment shader is pure shading area, and the pill is roughly a
/// tenth the area of the home screen's cards. See `orb_field_background.dart`
/// for what this app has already measured about fill rate.
///
/// **It degrades to exactly what it replaced.** Everything optical lives in
/// one fragment shader, and the shader is absent whenever
/// [ui.ImageFilter.isShaderFilterSupported] is false — under `flutter_test`,
/// on Skia, on an engine too old to have it. What is left is the bounded blur
/// plus a drawn top bevel, which is the pill's current material. There is no
/// second implementation to keep in step: the blur is not a fallback *for* the
/// shader, it is the shader's own input, and it simply becomes the whole
/// filter when there is no shader to wrap it in.
///
/// One inherited constraint, the same one [GlassCard.glass] carries: **no
/// ancestor may push a save layer**, or the filter samples that buffer rather
/// than the page and the glass refracts nothing. [Opacity] is the usual
/// culprit — `RenderOpacity.alwaysNeedsCompositing` is true at every non-zero
/// alpha — so fades above this widget must be written as colour-alpha tweens,
/// never as layer opacity. `Clip.antiAliasWithSaveLayer` is the other one.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    required this.radius,
    this.spec = LiquidGlassSpec.control,
    this.clipBorderRadius,
    this.fill,
    this.gradient,
    this.blurSigma = 30,
    this.debugCalibrate = false,
  });

  final Widget child;

  /// The corner radius the shader rounds its rect to, in logical pixels.
  ///
  /// The SDF takes a single radius for all four corners. That is not a
  /// simplification that can be lifted casually — the OpenGLES path mirrors
  /// the geometry, and a symmetric rect is what lets the shader get away with
  /// flipping only the sampling and the light. A surface that wants unequal
  /// corners (the Milo drawer) passes its dominant radius here and its real
  /// shape to [clipBorderRadius]; the corners the clip throws away were
  /// offscreen anyway.
  final double radius;

  /// The shape actually clipped, when it differs from `circular(radius)`.
  final BorderRadius? clipBorderRadius;

  /// The optical tuning. See [LiquidGlassSpec].
  final LiquidGlassSpec spec;

  /// The tint laid over the refracted backdrop. Defaults to the palette's
  /// glass fill blended with itself — a control sits over live, moving
  /// content and needs more separation than a card resting on the ground.
  final Color? fill;

  /// A gradient laid over the refracted backdrop instead of [fill].
  ///
  /// A flat tint is right for a small control, but across a wide capsule it
  /// reads as a grey slab: real glass is brighter where the light strikes it
  /// and falls to almost nothing at the far corner. Takes precedence over
  /// [fill] when both are given.
  final Gradient? gradient;

  /// How far the backdrop is blurred before it is refracted.
  final double blurSigma;

  /// Draw this surface's geometry instead of its glass.
  /// See [kDebugCalibrateLiquidGlass], which forces it on everywhere.
  final bool debugCalibrate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final BorderRadius clip =
        clipBorderRadius ?? BorderRadius.circular(radius);
    final Color effectiveFill =
        fill ?? Color.alphaBlend(palette.glassFill, palette.glassFill);

    // Null off Impeller, in a widget test, or with the kill switch thrown.
    final ui.FragmentProgram? program = LiquidGlassScope.maybeOf(context);

    // A gradient rim, not a flat hairline: a real glass edge catches light
    // along the side facing it and falls away on the opposite one, so the
    // stroke runs bright at the top-leading corner to nearly nothing at the
    // bottom-trailing one. It traces the whole shape rather than laying a
    // straight line across the top, which is what used to read as a seam.
    //
    // Drawn on *both* paths. It is what defines the edge when there is no
    // shader, and under one it sits beneath a specular that is directional
    // and per-pixel, so the two describe the same light rather than fighting.
    final Widget surface = CustomPaint(
      foregroundPainter: _GradientRim(
        radius: clip,
        from: palette.rimLit,
        to: palette.rimShade,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: clip,
          // BoxDecoration takes one or the other, never both.
          color: gradient == null ? effectiveFill : null,
          gradient: gradient,
        ),
        child: child,
      ),
    );

    // Two nested filters rather than one composed one, and the reason is
    // measured rather than stylistic.
    //
    // `ImageFilter.compose(outer: shader, inner: blur)` is the obvious
    // spelling and it renders — but a Gaussian blur sets
    // `needs_rasterization_for_runtime_effects`, which makes Impeller
    // re-rasterise the input before the shader runs. A coordinate probe on
    // Impeller GLES put the resulting texture at 647x975 device px for a
    // 520x71 pill — the whole page — with `FlutterFragCoord()` in *page*
    // coordinates. The shader then has no way to find its own rect: neither
    // `uSize` nor anything the engine hands it locates the surface, and the
    // SDF lands off the widget entirely.
    //
    // Nested, the shader's input is an ordinary translated snapshot, so that
    // branch never runs and `FlutterFragCoord()` spans the surface itself.
    // The cost is a second backdrop snapshot, which is why this material is
    // reserved for the control layer.
    Widget refracted = _LiquidGlassBackdrop(
      program: program,
      spec: spec,
      radius: radius,
      calibrate: debugCalibrate || kDebugCalibrateLiquidGlass,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: surface,
    );

    return ClipRRect(
      // Left at the default `Clip.antiAlias` deliberately.
      // `antiAliasWithSaveLayer` would push the very save layer that stops
      // the filter beneath it from seeing the page.
      borderRadius: clip,
      child: BackdropFilter(
        // Apple's sampling model: read only from inside the surface and
        // renormalise, rather than dragging the page in under the edge.
        filterConfig: ImageFilterConfig.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          bounded: true,
        ),
        child: refracted,
      ),
    );
  }
}

/// The optical tuning of one glass surface.
///
/// Every geometric field is a **ratio of the surface's short side**, not a
/// pixel count. That is what lets one spec describe a 56pt pill and a 380pt
/// drawer without either looking wrong, and it keeps the device pixel ratio
/// out of the shader entirely — it is folded in once, in Dart, when the
/// uniforms are written.
@immutable
class LiquidGlassSpec {
  const LiquidGlassSpec({
    required this.edge,
    required this.refraction,
    required this.aberration,
    required this.lightDirection,
    required this.specular,
    required this.rimWidth,
    required this.rimGain,
    required this.specularPower,
    required this.edgeDarken,
  });

  /// How deep the lensing band reaches in from the rim. Beyond it the shader
  /// early-outs to a single texture fetch, so this is also the cost dial.
  final double edge;

  /// Peak displacement at the rim — how far the background is dragged.
  final double refraction;

  /// Chromatic split. Real glass disperses; a little of this reads as
  /// thickness. Zero skips two of the three texture fetches.
  final double aberration;

  /// Where the light comes from. Apple lights from the top, slightly leading.
  final Offset lightDirection;

  /// Strength of the specular lobe.
  final double specular;

  /// Width of the bright line tracing the very edge, as a fraction of [edge].
  final double rimWidth;

  /// Strength of that line.
  final double rimGain;

  /// Tightness of the specular lobe. Higher is glassier, lower is waxier.
  final double specularPower;

  /// How much the glass darkens just inside the rim, which is what gives the
  /// edge its sense of thickness.
  final double edgeDarken;

  /// The default: a floating control over a dark, softly lit page.
  ///
  /// These are the design's Figma Glass settings, carried across rather than
  /// eyeballed. Figma states each on a 0-100 scale; the mapping is:
  ///
  ///   Light -45deg, 80%  ->  lightDirection (-1,-1) normalised, specular
  ///   Refraction 80      ->  refraction
  ///   Depth 20           ->  edge  (how far in the bevel reaches)
  ///   Dispersion 50      ->  aberration
  ///   Frost 4            ->  the surface's blurSigma, set at the call site
  ///   Splay 0            ->  not modelled; nothing spreads outward
  ///
  /// Frost 4 is the one that matters most and the one most easily got wrong:
  /// it is nearly *no* blur. A heavy blur is what makes glass read as a grey
  /// slab instead of something you can see through.
  static const LiquidGlassSpec control = LiquidGlassSpec(
    edge: 0.20,
    refraction: 0.20,
    aberration: 0.015,
    // -45 degrees: up and to the left, so the rim lights along the top and
    // leading edges and falls away at the bottom-trailing corner.
    lightDirection: Offset(-1, -1),
    specular: 0.45,
    rimWidth: 0.30,
    rimGain: 0.12,
    specularPower: 6,
    edgeDarken: 0.04,
  );

  /// A larger pane — the Milo drawer — where the same numbers would read as
  /// a thick bottle rim rather than a sheet.
  static const LiquidGlassSpec sheet = LiquidGlassSpec(
    edge: 0.05,
    refraction: 0.05,
    aberration: 0.006,
    lightDirection: Offset(-1, -1),
    specular: 0.30,
    rimWidth: 0.34,
    rimGain: 0.08,
    specularPower: 6,
    edgeDarken: 0.03,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassSpec &&
          other.edge == edge &&
          other.refraction == refraction &&
          other.aberration == aberration &&
          other.lightDirection == lightDirection &&
          other.specular == specular &&
          other.rimWidth == rimWidth &&
          other.rimGain == rimGain &&
          other.specularPower == specularPower &&
          other.edgeDarken == edgeDarken;

  @override
  int get hashCode => Object.hash(
    edge,
    refraction,
    aberration,
    lightDirection,
    specular,
    rimWidth,
    rimGain,
    specularPower,
    edgeDarken,
  );
}

/// Carries the compiled shader program down the tree.
///
/// An [InheritedWidget] rather than a provider, for two reasons. The program
/// is an immutable process-global with no reactive state, so there is nothing
/// for Riverpod to be good at here; and making [LiquidGlass] a `ConsumerWidget`
/// would force a `ProviderScope` into every test that pumps one. Absent scope
/// means null means fallback, which is the behaviour a bare widget test wants
/// anyway.
class LiquidGlassScope extends InheritedWidget {
  const LiquidGlassScope({
    super.key,
    required this.program,
    required super.child,
  });

  final ui.FragmentProgram? program;

  static ui.FragmentProgram? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LiquidGlassScope>()
      ?.program;

  @override
  bool updateShouldNotify(LiquidGlassScope oldWidget) =>
      oldWidget.program != program;
}

/// Compiles the glass shader, or returns null if this engine cannot run it.
///
/// Called once from `main`, alongside the database. The support check comes
/// **before** the asset load on purpose: under `flutter_test` the shader is
/// not in the bundle at all, so asking for it would throw rather than return
/// the null that means "draw the fallback".
Future<ui.FragmentProgram?> loadLiquidGlassProgram() async {
  if (!ui.ImageFilter.isShaderFilterSupported) return null;
  try {
    return await ui.FragmentProgram.fromAsset(_kShaderAsset);
  } catch (error, stack) {
    // A missing or uncompilable shader costs the refraction, not the app.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'liquid glass',
        context: ErrorDescription('loading $_kShaderAsset'),
      ),
    );
    return null;
  }
}

class _LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  const _LiquidGlassBackdrop({
    required this.program,
    required this.spec,
    required this.radius,
    required this.calibrate,
    required this.devicePixelRatio,
    required Widget super.child,
  });

  final ui.FragmentProgram? program;
  final LiquidGlassSpec spec;
  final double radius;
  final bool calibrate;
  final double devicePixelRatio;

  @override
  _RenderLiquidGlassBackdrop createRenderObject(BuildContext context) =>
      _RenderLiquidGlassBackdrop(
        program: program,
        spec: spec,
        radius: radius,
        calibrate: calibrate,
        devicePixelRatio: devicePixelRatio,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidGlassBackdrop renderObject,
  ) {
    renderObject
      ..program = program
      ..spec = spec
      ..radius = radius
      ..calibrate = calibrate
      ..devicePixelRatio = devicePixelRatio;
  }
}

/// Pushes the backdrop layer, and owns the shader's lifetime.
///
/// **A render object rather than a `BackdropFilter` under a `LayoutBuilder`**,
/// for two reasons that both come down to needing the *painted* size. A
/// `LayoutBuilder` reports incoming constraints, and the nav pill shrink-wraps
/// inside loose ones, so its constraints say "up to the whole screen". And a
/// bounded blur needs `offset & size` in the canvas coordinate space, which
/// only exists at paint time.
///
/// **Not a subclass of `RenderBackdropFilter`.** Its `paint` calls
/// `context.pushLayer(layer!, super.paint, offset)`, where `super.paint` means
/// `RenderProxyBoxMixin.paint`. In a subclass that same expression resolves to
/// `RenderBackdropFilter.paint` and recurses until the stack goes. The dozen
/// lines are replicated instead.
class _RenderLiquidGlassBackdrop extends RenderProxyBox {
  _RenderLiquidGlassBackdrop({
    required ui.FragmentProgram? program,
    required LiquidGlassSpec spec,
    required double radius,
    required bool calibrate,
    required double devicePixelRatio,
  }) : _program = program,
       _spec = spec,
       _radius = radius,
       _calibrate = calibrate,
       _devicePixelRatio = devicePixelRatio;

  ui.FragmentProgram? _program;
  set program(ui.FragmentProgram? value) {
    if (_program == value) return;
    _program = value;
    // The old shader belonged to the old program and cannot be reused.
    _shader?.dispose();
    _shader = null;
    _invalidate();
  }

  LiquidGlassSpec _spec;
  set spec(LiquidGlassSpec value) {
    if (_spec == value) return;
    _spec = value;
    _invalidate();
  }

  double _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    _invalidate();
  }

  bool _calibrate;
  set calibrate(bool value) {
    if (_calibrate == value) return;
    _calibrate = value;
    _invalidate();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _invalidate();
  }

  ui.FragmentShader? _shader;

  /// The last filter built, and the geometry it was built for.
  ///
  /// Worth caching because the uniforms are *copied* into the filter when it
  /// is constructed — see [_buildFilter] — so a filter has to be rebuilt
  /// whenever anything feeding it moves. Rebuilding one that would come out
  /// identical is not merely wasted work: `BackdropFilterLayer.filter`'s
  /// setter compares before assigning, and an equal filter skips
  /// `markNeedsAddToScene`.
  ui.ImageFilter? _cachedFilter;
  Rect? _cachedBounds;

  void _invalidate() {
    _cachedFilter = null;
    markNeedsPaint();
  }

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  /// Writes the uniforms and wraps the shader.
  ///
  /// `uSize` — floats 0 and 1 — is **the engine's**, not ours: it is
  /// overwritten with the size of the texture being filtered just before the
  /// draw. Ours start at index 2.
  ///
  /// Everything geometric goes in as a ratio of the short side, so the shader
  /// never sees a device pixel ratio; `uGlassPx` is the one exception, and it
  /// is there to tell the shader *where its own rect is* inside a texture
  /// that may be larger than it.
  ui.ImageFilter? _buildFilter(Rect bounds) {
    final ui.FragmentProgram? program = _program;
    if (program == null) return null;

    final ui.FragmentShader shader = _shader ??= program.fragmentShader();
    final double dpr = _devicePixelRatio;
    final Size px = bounds.size * dpr;
    final double shortSide = px.shortestSide;
    final LiquidGlassSpec s = _spec;

    // Clamped so a surface can never ask for a corner larger than it is.
    final double radiusPx = math.min(_radius * dpr, px.shortestSide / 2);

    final Offset light = s.lightDirection;
    final double lightLength = light.distance == 0 ? 1 : light.distance;

    shader
      ..setFloat(2, px.width)
      ..setFloat(3, px.height)
      // uShape: corner, edge band, displacement, aberration.
      ..setFloat(4, shortSide == 0 ? 0 : radiusPx / shortSide)
      ..setFloat(5, s.edge)
      ..setFloat(6, s.refraction)
      ..setFloat(7, s.aberration)
      // uLight: direction, specular strength, rim width.
      ..setFloat(8, light.dx / lightLength)
      ..setFloat(9, light.dy / lightLength)
      ..setFloat(10, s.specular)
      ..setFloat(11, s.rimWidth)
      // uTune: specular exponent, edge darkening, rim gain, enable.
      ..setFloat(12, s.specularPower)
      ..setFloat(13, s.edgeDarken)
      ..setFloat(14, s.rimGain)
      ..setFloat(15, _calibrate ? 2 : 1);

    // `ImageFilter.shader` memcpy's the uniform buffer as it is built, so
    // this wrap must happen after every write and cannot be hoisted out of
    // the rebuild. Mutating `shader` afterwards changes nothing.
    return ui.ImageFilter.shader(shader);
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _program != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    // With no shader there is nothing for this render object to do. It does
    // not fall back to a blur: the blur is a separate widget above it, which
    // stays whatever happens here.
    if (child == null || _program == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }

    assert(needsCompositing);
    final Rect bounds = offset & size;
    if (_cachedFilter == null || _cachedBounds != bounds) {
      _cachedFilter = _buildFilter(bounds);
      _cachedBounds = bounds;
    }

    layer ??= BackdropFilterLayer();
    layer!.filter = _cachedFilter;
    context.pushLayer(layer!, super.paint, offset);
    assert(() {
      layer!.debugCreator = debugCreator;
      return true;
    }());
  }

  @override
  void dispose() {
    // After `super.dispose()`, which releases the layer holding the filter
    // that holds this shader's uniform copy.
    super.dispose();
    _shader?.dispose();
    _shader = null;
    _cachedFilter = null;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty(
        'refracting',
        value: _program != null,
        ifTrue: 'refracting',
        ifFalse: 'blur only (no shader)',
      ),
    );
    properties.add(DoubleProperty('radius', _radius));
  }
}

/// The lit edge of a pane of glass.
///
/// [BoxDecoration] has no gradient border and [ShapeDecoration] no gradient
/// side, so the rim is stroked by hand. A stroke sits astride the path, so the
/// rect is inset by half the width to keep all of it inside the clip — an
/// un-inset stroke loses its outer half and reads as a half-width, half-bright
/// line.
class _GradientRim extends CustomPainter {
  const _GradientRim({
    required this.radius,
    required this.from,
    required this.to,
  });

  final BorderRadius radius;
  final Color from;
  final Color to;

  /// Apple's rim is a hairline at any size — it does not thicken with the
  /// surface, which is part of why the glass reads as thin.
  static const double width = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect rrect = radius
        .toRRect(rect)
        .deflate(width / 2);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [from, to],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GradientRim old) =>
      old.radius != radius || old.from != from || old.to != to;
}
