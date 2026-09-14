import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/milo_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// Where a query goes when it is submitted.
enum SearchMode {
  milo,
  chrome;

  String get label {
    switch (this) {
      case SearchMode.milo:
        return 'Search with Milo';
      // The user's own copy for this option — corrected only the behaviour
      // (the default browser, not literally Chrome) and kept the wording.
      case SearchMode.chrome:
        return 'Search on Chrome';
    }
  }
}

/// Opens [url] in the platform's handler. The signature [launchUrl] itself
/// satisfies, so a test can swap in a recording fake without a real browser
/// ever opening.
typedef UrlOpener = Future<bool> Function(Uri url, {LaunchMode mode});

/// The pill under the welcome header.
///
/// The mode lives here rather than in a provider: nothing outside this widget
/// reads it. Submitting sends the query one of two places: Milo mode opens
/// the end drawer and hands the text to [miloConversationProvider] — the
/// same path `MiloAssistantScreen`'s own composer uses — and Chrome mode
/// opens it as a web search in the platform's default browser via
/// [urlOpener], despite the dropdown's name for it.
///
/// One appearance, in every state. It used to gain a white halo under a pointer
/// and while it held the caret, animated in over the hover duration; both are
/// gone. The field is the one control on the page you reach for without looking
/// for it, and it turned out to need no help being found.
class HomeSearchBar extends ConsumerStatefulWidget {
  const HomeSearchBar({super.key, this.urlOpener = launchUrl});

  /// Overridable so a test can assert a launch was attempted without one
  /// reaching an actual browser.
  final UrlOpener urlOpener;

  @override
  ConsumerState<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends ConsumerState<HomeSearchBar> {
  final _controller = TextEditingController();

  /// Still held here rather than left to the [TextField], because `_submit`
  /// needs to hand focus back after a query goes out.
  final _focusNode = FocusNode();

  SearchMode _mode = SearchMode.milo;

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _controller.clear();

    switch (_mode) {
      case SearchMode.milo:
        Scaffold.of(context).openEndDrawer();
        ref.read(miloConversationProvider.notifier).send(query);
      case SearchMode.chrome:
        final url = Uri.https('www.google.com', '/search', {'q': query});
        await widget.urlOpener(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // On glass the pill collapses to the mock's shape: the mode's name becomes
    // the placeholder, the trailing label folds away behind the caret that was
    // already beside it, and the magnifier goes — three labels ("Search..",
    // the glyph, and "Search with Milo") saying one thing is two too many at
    // 393pt. The mode stays visible, just in the one place a search field
    // always has room for it.
    final glass = context.useLiquidGlass;

    return Container(
      // A plain Container, not an AnimatedContainer: there is nothing left to
      // animate between, and an implicit animation with no varying property
      // still rebuilds on every tick of its controller.
      //
      // 48 on glass, not 44. The caret is the only control left on that path
      // and needs a 44pt target of its own — which a 44pt pill cannot give it,
      // because its 1pt border takes the content box down to 42.
      height: glass ? 48 : 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _searchFill,
        borderRadius: BorderRadius.circular(_searchRadius),
        border: Border.all(color: _searchStroke),
      ),
      child: Row(
        children: [
          if (!glass) ...[
            Icon(PhLight.magnifyingGlass, size: 19, color: palette.textMuted),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onSubmitted: _submit,
              style: context.typography.ui(
                size: 15,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: glass ? _mode.label : 'Search..',
                hintStyle: context.typography.ui(
                  size: 15,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<SearchMode>(
            initialValue: _mode,
            tooltip: 'Where to search',
            color: palette.surfaceRaised,
            position: PopupMenuPosition.under,
            onSelected: (mode) => setState(() => _mode = mode),
            itemBuilder: (context) => [
              for (final mode in SearchMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Text(
                    mode.label,
                    style: context.typography.ui(
                      size: 14,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
            ],
            child: glass
                // The caret is the entire control on this path, so it has
                // to carry the touch target the label beside it used to
                // provide. Padded out rather than drawn larger — a 44pt
                // chevron would dominate a 44pt pill.
                ? SizedBox(
                    width: minTouchTarget,
                    height: minTouchTarget,
                    child: Center(
                      child: Icon(
                        PhLight.caretDown,
                        size: 15,
                        color: palette.textMuted,
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhLight.caretDown,
                        size: 15,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _mode.label,
                        style: context.typography.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The field's one appearance.
///
/// #D9D9D9 at 2% over the page, a #FFFFFF hairline at 10%, and a 10pt corner —
/// the same three values in every state. The fill used to be `surfaceRaised`,
/// which is opaque, so the field read as a slab sitting on the ground rather
/// than a shape cut into it.
const Color _searchFill = Color(0x05D9D9D9);
const Color _searchStroke = Color(0x1AFFFFFF);
const double _searchRadius = 10;
