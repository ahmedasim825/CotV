import 'package:flutter/widgets.dart';

/// Layout classes the app adapts between.
///
/// Chosen against the real device targets: an iPhone 14 Pro is 393pt wide
/// (compact in either orientation), an 11" iPad is 834pt in portrait
/// ([WindowSize.medium]) and 1194pt in landscape ([WindowSize.expanded]).
/// Split View on iPad lands in compact or medium depending on the split, so
/// the layout must key off the *window*, never the physical device.
enum WindowSize {
  /// Phones, and iPad Slide Over / narrow Split View.
  compact,

  /// iPad portrait, and half-and-half Split View.
  medium,

  /// iPad landscape and full-screen iPad.
  expanded,
}

/// Width thresholds, in logical pixels, matching Material 3's window size
/// classes.
class Breakpoints {
  const Breakpoints._();

  static const double medium = 600;
  static const double expanded = 1000;

  static WindowSize of(double width) {
    if (width >= expanded) return WindowSize.expanded;
    if (width >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }
}

extension WindowSizeX on WindowSize {
  bool get isCompact => this == WindowSize.compact;

  /// Medium and expanded both get a persistent navigation rail instead of a
  /// bottom bar.
  bool get usesNavigationRail => this != WindowSize.compact;

  /// Only expanded is wide enough to show schedule and tasks side by side
  /// without either pane becoming unusably narrow.
  bool get usesSplitView => this == WindowSize.expanded;

  /// Horizontal page padding — wider gutters as the window grows so line
  /// lengths stay readable rather than stretching edge to edge.
  double get pagePadding {
    switch (this) {
      case WindowSize.compact:
        return 20;
      case WindowSize.medium:
        return 32;
      case WindowSize.expanded:
        return 40;
    }
  }

  /// Vertical pixels per timeline hour. Larger windows can afford a taller,
  /// more legible timeline.
  double get hourExtent {
    switch (this) {
      case WindowSize.compact:
        return 76;
      case WindowSize.medium:
        return 88;
      case WindowSize.expanded:
        return 96;
    }
  }
}

/// Resolves the current [WindowSize] from the nearest [MediaQuery].
///
/// Uses the enclosing constraints where available (via [LayoutBuilder] in
/// [AdaptiveLayout]) rather than the raw screen width, so a pane inside a
/// split view sizes itself by the space it actually got.
WindowSize windowSizeOf(BuildContext context) =>
    Breakpoints.of(MediaQuery.sizeOf(context).width);

/// Rebuilds [builder] with the [WindowSize] of the space actually available,
/// which is what every adaptive decision in this app keys off.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({super.key, required this.builder});

  final Widget Function(BuildContext context, WindowSize size) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return builder(context, Breakpoints.of(width));
      },
    );
  }
}
