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
  SearchMode _mode = SearchMode.milo;

  @override
  void dispose() {
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

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        children: [
          Icon(PhLight.magnifyingGlass, size: 19, color: palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: _submit,
              style: context.typography.ui(size: 15, color: palette.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search..',
                hintStyle:
                    context.typography.ui(size: 15, color: palette.textMuted),
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
                    style: context.typography
                        .ui(size: 14, color: palette.textPrimary),
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhLight.caretDown, size: 15, color: palette.textMuted),
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
