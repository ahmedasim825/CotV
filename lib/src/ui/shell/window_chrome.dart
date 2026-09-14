import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// The window operations the Windows title bar used to provide.
///
/// The runner reports the whole window as client area now (`WM_NCCALCSIZE` in
/// `windows/runner/win32_window.cpp`), so there is no caption to drag and no
/// buttons in the corner. Everything the caption did, the app does through
/// this channel instead.
const MethodChannel _channel = MethodChannel('cotv/window');

/// How tall the invisible strip across the top of the window is.
///
/// Matches the caption it replaces, so nothing on any screen moves. What
/// changes is what the strip is made of: the app's own background, continuous
/// with the page under it, instead of an opaque bar in a colour the app does
/// not choose.
const double windowChromeHeight = 32;

/// The app's name, a control for the rail, a drag handle, and the three window
/// buttons, laid over the top of the app.
///
/// Deliberately not a bar. It paints nothing — no fill, no rim — so the ground
/// runs unbroken to the top edge of the window, and the only marks in the strip
/// are the leading cluster and the three glyphs at its trailing end.
///
/// [onToggleSidebar] opens and closes the rail. It lives up here rather than in
/// the rail's own header because the rail can be closed, and a control that
/// closes something cannot reopen it from inside.
///
/// Mounted once, by `AppShell`, above the pane and the sidebar both.
class WindowChrome extends StatefulWidget {
  const WindowChrome({
    super.key,
    required this.onToggleSidebar,
    required this.sidebarIsHidden,
  });

  /// Opens the rail if it is closed, closes it if it is open.
  final VoidCallback onToggleSidebar;

  /// Drives the tooltip alone — the glyph is the same either way, because the
  /// rail beside it already says which state it is in.
  final bool sidebarIsHidden;

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome>
    with WidgetsBindingObserver {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The window can be maximized without this widget being touched — Snap
  /// Layouts, Win+Up, a double click on a resize edge — and the button has to
  /// show the right glyph afterwards. Every one of those resizes the window,
  /// so this is the callback that catches all of them.
  @override
  void didChangeMetrics() => _refreshMaximized();

  Future<void> _refreshMaximized() async {
    final maximized = await _invokeWindow<bool>('isMaximized') ?? false;
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: windowChromeHeight,
      // The last resort. Both floors below shed what they can, but three
      // window buttons are 138pt and nothing can shed those, so a narrower
      // window than that still has to degrade rather than throw.
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              // The wordmark leads, the control follows it.
              //
              // Dropped on a narrow window. Everything else in this strip is a
              // fixed width — three 46pt buttons, a 24pt control — and the drag
              // handle between them is the only thing that can give, so past the
              // point where it has nothing left the row would overflow. The
              // wordmark is what goes: the buttons are load-bearing.
              if (constraints.maxWidth >= _wordmarkFloor)
                Padding(
                  // No top inset, unlike the drag handle below: the Row centres
                  // its children, so the wordmark lands on the same line as the
                  // three window buttons.
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Text(
                    'Milo',
                    style: context.typography.display(
                      // The dock's wordmark, one step down: 17pt is sized for a
                      // section title, and this strip is 32pt tall.
                      size: 14,
                      weight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
              // Outside the drag handle rather than inside it: a `GestureDetector`
              // with `HitTestBehavior.opaque` claims every pointer in its box, so
              // a button placed within it would never see a tap.
              //
              // Goes the same way the wordmark does, one step further down: past
              // this the three window buttons are all that fits, and closing the
              // window matters more than opening the rail.
              if (constraints.maxWidth >= _toggleFloor)
                Tooltip(
                  message: widget.sidebarIsHidden
                      ? 'Show sidebar'
                      : 'Hide sidebar',
                  child: InkWell(
                    onTap: widget.onToggleSidebar,
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      // Full strip height, like the three window buttons, so the
                      // glyph centres on the same line they do. Not
                      // `minTouchTarget` — the strip is only 32pt tall.
                      width: 28,
                      height: windowChromeHeight,
                      child: Icon(
                        PhLight.sidebarSimple,
                        size: 16,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              Expanded(
                // Starts below the resize band, not at the window's top edge. The
                // bands are painted under this strip, so an opaque handle here
                // would swallow the top edge and leave the window unresizable from
                // the top. Leaving these 8pt unclaimed lets the hit test fall
                // through to the band beneath.
                child: Padding(
                  padding: const EdgeInsets.only(top: _resizeBand),
                  child: GestureDetector(
                    // `onPanStart`, not `onTap`: the drag is handed straight to
                    // the OS, which then owns the gesture until the mouse comes
                    // up, so there is no drag update to receive back.
                    onPanStart: (_) => _invokeWindow<void>('startDrag'),
                    onDoubleTap: () async {
                      await _invokeWindow<bool>('toggleMaximize');
                      await _refreshMaximized();
                    },
                    // Opaque so the empty strip is still a drag handle. This is
                    // the whole reason the row is laid out as Expanded + buttons
                    // rather than as a Stack: the buttons sit *beside* the handle,
                    // so they cannot be swallowed by it.
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              _WindowButton(
                glyph: _WindowGlyph.minimize,
                tooltip: 'Minimize',
                onTap: () => _invokeWindow<void>('minimize'),
              ),
              _WindowButton(
                glyph: _isMaximized
                    ? _WindowGlyph.restore
                    : _WindowGlyph.maximize,
                tooltip: _isMaximized ? 'Restore' : 'Maximize',
                onTap: () async {
                  await _invokeWindow<bool>('toggleMaximize');
                  await _refreshMaximized();
                },
              ),
              _WindowButton(
                glyph: _WindowGlyph.close,
                tooltip: 'Close',
                isClose: true,
                onTap: () => _invokeWindow<void>('close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four marks a window button can carry.
///
/// Drawn rather than set in a font. Windows itself uses Segoe MDL2 Assets for
/// these, but the app's glyphs are Phosphor and Phosphor has no window
/// controls — and borrowing a second icon font for three shapes this simple
/// buys nothing. A line, a square, two squares and a cross.
enum _WindowGlyph { minimize, maximize, restore, close }

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final _WindowGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;

  /// Close hovers red, as it does in every other window on the system. This
  /// is the one place the app should not invent its own convention.
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // 46x32 is the Windows caption button footprint. Matching it means muscle
    // memory for the corner of the screen still lands on the right control.
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: context.motion.hover,
              curve: Curves.easeOut,
              width: 46,
              height: windowChromeHeight,
              color: !_hovered
                  ? Colors.transparent
                  : widget.isClose
                  // Windows' own close red, not `palette.danger`: this
                  // button belongs to the system's vocabulary, not the
                  // app's.
                  ? const Color(0xFFC42B1C)
                  : palette.textPrimary.withValues(alpha: 0.08),
              child: Center(
                child: CustomPaint(
                  size: const Size(10, 10),
                  painter: _GlyphPainter(
                    glyph: widget.glyph,
                    color: _hovered && widget.isClose
                        ? palette.onAccent
                        : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.color});

  final _WindowGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Hairline, like the system's. Anything heavier reads as an app button
      // rather than window furniture.
      ..strokeWidth = 1;

    final rect = Offset.zero & size;

    switch (glyph) {
      case _WindowGlyph.minimize:
        canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          paint,
        );
      case _WindowGlyph.maximize:
        canvas.drawRect(rect, paint);
      case _WindowGlyph.restore:
        // The front pane, inset from the top-right, with the one behind it
        // showing above and to the right — the standard two-square mark.
        const offset = 2.5;
        canvas.drawRect(
          Rect.fromLTWH(0, offset, size.width - offset, size.height - offset),
          paint,
        );
        canvas.drawLine(Offset(offset, offset), Offset(offset, 0), paint);
        canvas.drawLine(Offset(offset, 0), Offset(size.width, 0), paint);
        canvas.drawLine(
          Offset(size.width, 0),
          Offset(size.width, size.height - offset),
          paint,
        );
        canvas.drawLine(
          Offset(size.width, size.height - offset),
          Offset(size.width - offset, size.height - offset),
          paint,
        );
      case _WindowGlyph.close:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// Which edge a resize drag is pulling, as its Win32 hit-test code.
///
/// The values are `HTLEFT` through `HTBOTTOMRIGHT` verbatim, because they are
/// handed straight to `WM_NCLBUTTONDOWN` — the runner checks the range but does
/// not translate them.
enum _ResizeEdge {
  left(10, SystemMouseCursors.resizeLeftRight),
  right(11, SystemMouseCursors.resizeLeftRight),
  top(12, SystemMouseCursors.resizeUpDown),
  topLeft(13, SystemMouseCursors.resizeUpLeftDownRight),
  topRight(14, SystemMouseCursors.resizeUpRightDownLeft),
  bottom(15, SystemMouseCursors.resizeUpDown),
  bottomLeft(16, SystemMouseCursors.resizeUpRightDownLeft),
  bottomRight(17, SystemMouseCursors.resizeUpLeftDownRight);

  const _ResizeEdge(this.hitTest, this.cursor);

  final int hitTest;
  final MouseCursor cursor;
}

/// How wide the grab band around the window is.
///
/// Windows' own is around 8pt. Wider would eat into the content; narrower is
/// hard to hit with a mouse.
const double _resizeBand = 8;

/// The narrowest strip that still has room for the wordmark: three 46pt window
/// buttons, the 28pt sidebar control, their padding, and enough left over that
/// the drag handle does not vanish entirely.
const double _wordmarkFloor = 260;

/// And the narrowest that still has room for the sidebar control. Below this
/// only the three window buttons are drawn — 138pt of them.
const double _toggleFloor = 200;

/// An invisible grab band around the window, so it can still be resized.
///
/// **Why this has to exist in Dart.** The runner reports the whole window as
/// client area, and the Flutter view is a child window filling all of it. A
/// child window receives mouse messages itself, so the parent's
/// `WM_NCHITTEST` — which does still answer `HTLEFT`, `HTTOP` and the rest
/// correctly — is never consulted for a cursor inside it. Every edge is
/// reported right and none of them is reachable. So the edges are hit-tested
/// here instead, and handed back to the OS through the same channel the drag
/// uses.
///
/// Costs nothing when the pointer is elsewhere: these are eight thin
/// [MouseRegion]s with no painting and no hit area of their own beyond the
/// band.
class WindowResizeBorders extends StatelessWidget {
  const WindowResizeBorders({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Corners first, so they win over the edges they overlap — dragging a
        // corner should resize both axes, not whichever edge was laid down
        // last.
        _band(_ResizeEdge.left, left: 0, top: 0, bottom: 0, width: _resizeBand),
        _band(
          _ResizeEdge.right,
          right: 0,
          top: 0,
          bottom: 0,
          width: _resizeBand,
        ),
        _band(_ResizeEdge.top, top: 0, left: 0, right: 0, height: _resizeBand),
        _band(
          _ResizeEdge.bottom,
          bottom: 0,
          left: 0,
          right: 0,
          height: _resizeBand,
        ),
        _band(
          _ResizeEdge.topLeft,
          top: 0,
          left: 0,
          width: _resizeBand,
          height: _resizeBand,
        ),
        _band(
          _ResizeEdge.topRight,
          top: 0,
          right: 0,
          width: _resizeBand,
          height: _resizeBand,
        ),
        _band(
          _ResizeEdge.bottomLeft,
          bottom: 0,
          left: 0,
          width: _resizeBand,
          height: _resizeBand,
        ),
        _band(
          _ResizeEdge.bottomRight,
          bottom: 0,
          right: 0,
          width: _resizeBand,
          height: _resizeBand,
        ),
      ],
    );
  }

  Widget _band(
    _ResizeEdge edge, {
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      key: ValueKey('resize-${edge.name}'),
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: edge.cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => _invokeWindow<void>(
            'startResize',
            <String, Object?>{'edge': edge.hitTest},
          ),
        ),
      ),
    );
  }
}

/// Shared by [WindowChrome] and [WindowResizeBorders].
///
/// Swallows the channel failing rather than letting it reach the user: the
/// runner registers its handler after the first frame, so an early call can
/// miss it, and a call arriving while the window is being destroyed answers
/// with an error by design. The worst case is a control that does nothing once.
Future<T?> _invokeWindow<T>(String method, [Object? arguments]) async {
  try {
    return await _channel.invokeMethod<T>(method, arguments);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
