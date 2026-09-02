import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Renders the markdown subset the journal writer produces.
///
/// Deliberately hand-rolled rather than pulled from a package: the whole
/// point of the theme picker is that every surface re-colours with the
/// palette, and a general-purpose markdown widget would need its own style
/// sheet threaded through anyway. Keeping it here also means the writer's
/// toolbar and the renderer can never drift apart about what is supported.
///
/// Supported:
///   * `#`, `##`, `###` headings
///   * `-` / `*` / `+` bullet lists, `1.` ordered lists
///   * `>` block quotes
///   * ``` fenced code blocks
///   * `---` horizontal rules
///   * inline `**bold**`, `*italic*`, `` `code` `` and `[label](target)`
///
/// Not supported (and not offered by the toolbar): tables, images, nested
/// lists, and emphasis nested inside other emphasis. A link renders as
/// styled text rather than a tappable target — the app has no URL launcher.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdownBlocks(data);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          _BlockView(block: blocks[i]),
          if (i != blocks.length - 1)
            SizedBox(height: _gapAfter(blocks[i], blocks[i + 1])),
        ],
      ],
    );
  }

  /// Tighter spacing between consecutive items of the same list, wider
  /// between a paragraph and the heading that follows it.
  double _gapAfter(MarkdownBlock current, MarkdownBlock next) {
    final bothListItems = current.kind == MarkdownBlockKind.bullet &&
        next.kind == MarkdownBlockKind.bullet;
    if (bothListItems) return 6;
    if (next.kind == MarkdownBlockKind.heading) return 22;
    return 12;
  }
}

enum MarkdownBlockKind { heading, paragraph, bullet, quote, code, rule }

@immutable
class MarkdownBlock {
  const MarkdownBlock({
    required this.kind,
    this.text = '',
    this.level = 0,
    this.marker,
  });

  final MarkdownBlockKind kind;
  final String text;

  /// Heading level, 1-3.
  final int level;

  /// The rendered list marker — a bullet glyph, or `1.` for ordered items.
  final String? marker;
}

final RegExp _headingPattern = RegExp(r'^(#{1,3})\s+(.*)$');
final RegExp _bulletPattern = RegExp(r'^\s{0,3}[-*+]\s+(.*)$');
final RegExp _orderedPattern = RegExp(r'^\s{0,3}(\d+)\.\s+(.*)$');
final RegExp _quotePattern = RegExp(r'^\s{0,3}>\s?(.*)$');
final RegExp _rulePattern = RegExp(r'^\s{0,3}([-*_])\s*\1\s*\1[\s*_-]*$');
final RegExp _fencePattern = RegExp(r'^\s{0,3}```');

/// Splits [source] into renderable blocks. Consecutive plain lines join into
/// one paragraph; a blank line ends it.
List<MarkdownBlock> parseMarkdownBlocks(String source) {
  final blocks = <MarkdownBlock>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');

  final paragraph = <String>[];
  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(MarkdownBlock(
      kind: MarkdownBlockKind.paragraph,
      text: paragraph.join(' ').trim(),
    ));
    paragraph.clear();
  }

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];

    if (_fencePattern.hasMatch(line)) {
      flushParagraph();
      final code = <String>[];
      index++;
      while (index < lines.length && !_fencePattern.hasMatch(lines[index])) {
        code.add(lines[index]);
        index++;
      }
      // Skip the closing fence when there is one; an unterminated block just
      // runs to the end of the document rather than failing.
      if (index < lines.length) index++;
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.code,
        text: code.join('\n'),
      ));
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
      index++;
      continue;
    }

    if (_rulePattern.hasMatch(line)) {
      flushParagraph();
      blocks.add(const MarkdownBlock(kind: MarkdownBlockKind.rule));
      index++;
      continue;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.heading,
        level: heading.group(1)!.length,
        text: heading.group(2)!.trim(),
      ));
      index++;
      continue;
    }

    final quote = _quotePattern.firstMatch(line);
    if (quote != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.quote,
        text: quote.group(1)!.trim(),
      ));
      index++;
      continue;
    }

    final ordered = _orderedPattern.firstMatch(line);
    if (ordered != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.bullet,
        text: ordered.group(2)!.trim(),
        marker: '${ordered.group(1)}.',
      ));
      index++;
      continue;
    }

    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.bullet,
        text: bullet.group(1)!.trim(),
        marker: '•',
      ));
      index++;
      continue;
    }

    paragraph.add(line.trim());
    index++;
  }

  flushParagraph();
  return List.unmodifiable(blocks);
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final MarkdownBlock block;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final typography = context.typography;

    switch (block.kind) {
      case MarkdownBlockKind.rule:
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: palette.hairline,
        );

      case MarkdownBlockKind.heading:
        final sizes = {1: 24.0, 2: 19.0, 3: 16.0};
        return Text.rich(
          _inlineSpans(
            context,
            block.text,
            typography.display(
              size: sizes[block.level] ?? 16,
              weight: FontWeight.w500,
              color: palette.textPrimary,
              letterSpacing: -0.4,
              height: 1.25,
            ),
          ),
        );

      case MarkdownBlockKind.paragraph:
        return Text.rich(
          _inlineSpans(context, block.text, _bodyStyle(context)),
        );

      case MarkdownBlockKind.bullet:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                block.marker ?? '•',
                style: typography.ui(
                  size: 13.5,
                  color: palette.accent,
                  weight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
            Expanded(
              child: Text.rich(
                _inlineSpans(context, block.text, _bodyStyle(context)),
              ),
            ),
          ],
        );

      case MarkdownBlockKind.quote:
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: palette.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: palette.accent, width: 2.5),
            ),
          ),
          child: Text.rich(
            _inlineSpans(
              context,
              block.text,
              _bodyStyle(context).copyWith(
                fontStyle: FontStyle.italic,
                color: palette.textSecondary,
              ),
            ),
          ),
        );

      case MarkdownBlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.glassBorder),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.text,
              style: typography.mono(
                size: 12.5,
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        );
    }
  }

  TextStyle _bodyStyle(BuildContext context) => context.typography.ui(
        size: 14.5,
        color: context.palette.textSecondary,
        weight: FontWeight.w400,
        height: 1.6,
      );
}

/// Matches, in priority order: inline code, bold, italic, link.
final RegExp _inlinePattern = RegExp(
  r'`([^`]+)`'
  r'|\*\*([^*]+)\*\*'
  r'|__([^_]+)__'
  r'|\*([^*]+)\*'
  r'|_([^_]+)_'
  r'|\[([^\]]*)\]\(([^)]*)\)',
);

/// Splits [text] into styled spans over [base].
TextSpan _inlineSpans(BuildContext context, String text, TextStyle base) {
  final palette = context.palette;
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in _inlinePattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }

    if (match.group(1) != null) {
      spans.add(TextSpan(
        text: match.group(1),
        style: context.typography.mono(
          size: (base.fontSize ?? 14) - 1,
          color: palette.accent,
        ),
      ));
    } else if (match.group(2) != null || match.group(3) != null) {
      spans.add(TextSpan(
        text: match.group(2) ?? match.group(3),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ));
    } else if (match.group(4) != null || match.group(5) != null) {
      spans.add(TextSpan(
        text: match.group(4) ?? match.group(5),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
    } else {
      // Styled, not tappable: the app ships no URL launcher, and a link
      // that looks live but does nothing is worse than one that does not.
      spans.add(TextSpan(
        text: match.group(6)?.isNotEmpty == true
            ? match.group(6)
            : match.group(7),
        style: TextStyle(
          color: palette.accent,
          decoration: TextDecoration.underline,
          decorationColor: palette.accent.withValues(alpha: 0.5),
        ),
      ));
    }

    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }

  return TextSpan(style: base, children: spans);
}
