#version 460 core

// Apple's Liquid Glass: a rounded rect that refracts what is behind it.
//
// Run as the `outer` half of `ImageFilter.compose(outer: shader, inner: blur)`
// inside a BackdropFilter, so `uBackdrop` arrives already blurred and this
// stage only has to bend it. See lib/src/ui/components/liquid_glass.dart for
// the Dart side and for what every uniform means.
//
// ---------------------------------------------------------------------------
// The one genuinely surprising thing about writing a filter shader
// ---------------------------------------------------------------------------
// `FlutterFragCoord()` is NOT in the filtered widget's coordinate space. It
// spans the *input texture*, and when the inner filter is a blur that texture
// is bigger than the widget: a Gaussian blur sets
// `needs_rasterization_for_runtime_effects`, which makes Impeller re-rasterise
// the input to `Rect::MakeLTRB(entity_offset.x, entity_offset.y,
// coverage.GetRight(), coverage.GetBottom())`
// (impeller/entity/contents/filters/runtime_effect_filter_contents.cc).
//
// That re-rasterisation is why the Dart side nests the blur above this shader
// instead of composing the two into one filter. Composed, a coordinate probe
// on Impeller GLES measured the input texture at 647x975 device px for a
// 520x71 pill — the whole page — with FlutterFragCoord() in page coordinates
// and nothing handed to the shader capable of locating the surface within it.
//
// Nested, the input is an ordinary translated snapshot, the branch above never
// runs, and the probe measures uSize == the surface's own device size with the
// origin on its top-left. So:
//
//     topLeft = uSize - uGlassPx = (0, 0)
//
// The subtraction is kept rather than hard-coded to zero because it is still
// the honest expression of where the rect is, and it costs nothing.

#include <flutter/runtime_effect.glsl>

// Float uniforms are indexed in declaration order; samplers are counted
// separately, so interleaving one costs nothing. Indices are load-bearing —
// the Dart side writes them by number.
uniform vec2 uSize;          // 0,1  ENGINE-OWNED: input texture size, device px
uniform sampler2D uBackdrop; //      ENGINE-OWNED: the (already blurred) input
uniform vec2 uGlassPx;       // 2,3  this surface's own size, device px
uniform vec4 uShape;         // 4-7  corner, edge band, displacement, aberration
uniform vec4 uLight;         // 8-11 light dir xy, specular strength, rim width
uniform vec4 uTune;          // 12-15 specular power, edge darken, rim gain, mode

out vec4 fragColor;

// Signed distance to a rounded rect centred on the origin. Negative inside.
float sdRoundRect(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

// One backdrop fetch.
//
// The clamp is not defensive tidiness. The inner blur is *bounded*: it returns
// transparent black for anything outside the surface, so a displaced sample
// that wanders off the texture comes back as a black notch in the rim — which
// is precisely where the displacement is largest and the artefact most
// visible. Clamping to a half-texel inset keeps every sample on the texture.
vec4 sampleBackdrop(vec2 px) {
  vec2 uv = px / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 halfTexel = 0.5 / uSize;
  return texture(uBackdrop, clamp(uv, halfTexel, 1.0 - halfTexel));
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;

  vec2 halfGlass = uGlassPx * 0.5;

  // See the header. No #ifdef here, and that is a measured fact rather than an
  // assumption: on Impeller's OpenGLES backend the calibration grid lands on
  // the same coordinates it does elsewhere, so `FlutterFragCoord()` and the
  // geometry are NOT mirrored. Only the texture read is — see sampleBackdrop.
  // An earlier version mirrored this y term too and put the rect off the
  // surface entirely, which renders as glass that simply does nothing.
  vec2 centre = uSize - halfGlass;

  // Every geometric uniform is a ratio of the short side, so one spec fits a
  // 56pt pill and a 380pt drawer and no device pixel ratio reaches the shader.
  float shortSide = min(uGlassPx.x, uGlassPx.y);
  float radius = min(uShape.x * shortSide, min(halfGlass.x, halfGlass.y));
  float band = max(uShape.y * shortSide, 1.0);

  vec2 p = fragCoord - centre;
  float dist = sdRoundRect(p, halfGlass, radius);

  // 0 at band depth and deeper, 1 at the rim. Smoothstepped so the inner end
  // of the band has no visible boundary.
  float edge = smoothstep(0.0, 1.0, clamp(1.0 + dist / band, 0.0, 1.0));

  int mode = int(uTune.w + 0.5);

  // Calibration. Flipped on from Dart with kDebugCalibrateLiquidGlass, to
  // answer the two questions this shader cannot answer by reasoning: does the
  // rect derived above land on the widget, and is the texture read the right
  // way up? Both are backend-dependent, so re-run this on any backend the app
  // has not been seen on.
  if (mode == 2) {
    float inside = 1.0 - step(0.0, dist);
    float rimLine = 1.0 - smoothstep(0.0, 2.0, abs(dist));

    // Left half: where the SDF believes the glass is. Green inside, red
    // outside, white on the rim. Green filling the half with the line hugging
    // the border means the rect is anchored.
    vec3 sdf = mix(vec3(0.65, 0.08, 0.08), vec3(0.08, 0.75, 0.2), inside);

    // Right half: the backdrop sampled with no displacement, brightened. It
    // should continue the page behind the surface. Mirrored top-to-bottom
    // means the y-flip in sampleBackdrop is on the wrong backend.
    vec3 raw = clamp(sampleBackdrop(fragCoord).rgb * 4.0, 0.0, 1.0);

    float half_ = step(0.5, (fragCoord.x - (centre.x - halfGlass.x)) /
        max(uGlassPx.x, 1.0));
    fragColor = vec4(mix(sdf, raw, half_) + rimLine, 1.0);
    return;
  }

  // The interior is the overwhelming majority of the surface and costs exactly
  // one fetch. Everything expensive below runs only in the rim band, which is
  // what makes a per-pixel effect affordable on a control-sized surface.
  if (mode == 0 || edge <= 0.001) {
    fragColor = sampleBackdrop(fragCoord);
    return;
  }

  // Outward surface normal, by central difference on the analytic SDF. Four
  // extra SDF evaluations and zero extra texture fetches — much cheaper than
  // the arithmetic makes it look.
  vec2 gradient = vec2(
    sdRoundRect(p + vec2(1.0, 0.0), halfGlass, radius) -
        sdRoundRect(p - vec2(1.0, 0.0), halfGlass, radius),
    sdRoundRect(p + vec2(0.0, 1.0), halfGlass, radius) -
        sdRoundRect(p - vec2(0.0, 1.0), halfGlass, radius)
  );
  float gradientLength = length(gradient);
  vec2 normal = gradientLength > 1e-5
      ? gradient / gradientLength
      : vec2(0.0, -1.0);

  // The bevel profile: flat through the interior, steepening hard at the rim.
  // Squaring is what hides the inner end of the band — a linear ramp leaves a
  // visible tide line where the displacement starts.
  float slope = edge * edge;

  // Sampling *inward* along the normal drags interior content out toward the
  // rim, which is what a lens does and what reads as glass having thickness.
  vec2 displacement = -normal * slope * (uShape.z * shortSide);

  vec4 colour;
  float aberration = uShape.w;
  if (aberration > 0.001) {
    // Real glass disperses. Splitting the fetch three ways puts a faint warm
    // and cool fringe on opposite sides of the rim; a little reads as depth.
    vec4 mid = sampleBackdrop(fragCoord + displacement);
    colour = vec4(
      sampleBackdrop(fragCoord + displacement * (1.0 + aberration)).r,
      mid.g,
      sampleBackdrop(fragCoord + displacement * (1.0 - aberration)).b,
      mid.a
    );
  } else {
    colour = sampleBackdrop(fragCoord + displacement);
  }

  // uLight.xy points from the surface toward the light. No GLES flip, for the
  // same reason the centre has none: the geometry arrives the right way up on
  // every backend, so the normal this is dotted against does too.
  vec2 lightDir = normalize(uLight.xy);

  float specular =
      pow(max(dot(normal, lightDir), 0.0), uTune.x) * slope * uLight.z;

  // A thin bright line right at the perimeter, independent of light
  // direction. This is the part the eye reads as "edge of a pane".
  float rim = smoothstep(1.0 - uLight.w, 1.0, edge) * uTune.z;

  // Flutter fragment output is premultiplied, so added light has to carry
  // alpha with it or it blooms over transparent pixels.
  colour.rgb += (specular + rim) * colour.a;

  // Slight darkening just inside the rim. Peaks mid-band rather than at the
  // edge, so it sits under the specular instead of fighting it, and gives the
  // glass a sense of thickness the highlight alone does not.
  colour.rgb *= 1.0 - uTune.y * slope * (1.0 - edge);

  fragColor = colour;
}
