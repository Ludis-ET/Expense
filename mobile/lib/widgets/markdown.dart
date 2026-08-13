import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';


/// Minimal GitHub-flavoured Markdown for AI answers and guides.
///
/// Supports headings, paragraphs, bold/italic/code, lists, blockquotes,
/// horizontal rules, and simple pipe tables — enough for Santim replies
/// without pulling a heavy package.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody(
    this.content, {
    super.key,
    this.textColor,
    this.dense = false,
  });

  final String content;
  final Color? textColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = textColor ?? t.foreground;
    final blocks = _parse(content.replaceAll('\r\n', '\n'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) Gap(dense ? 6 : 10),
          _BlockView(block: blocks[i], color: color, dense: dense),
        ],
      ],
    );
  }
}

sealed class _Block {}

class _Heading extends _Block {
  _Heading(this.level, this.text);
  final int level;
  final String text;
}

class _Paragraph extends _Block {
  _Paragraph(this.text);
  final String text;
}

class _Bullet extends _Block {
  _Bullet(this.items);
  final List<String> items;
}

class _Numbered extends _Block {
  _Numbered(this.items);
  final List<String> items;
}

class _Quote extends _Block {
  _Quote(this.lines);
  final List<String> lines;
}

class _Rule extends _Block {}

class _Table extends _Block {
  _Table(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

class _Code extends _Block {
  _Code(this.text);
  final String text;
}

List<_Block> _parse(String raw) {
  final lines = raw.split('\n');
  final out = <_Block>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    if (line.trim().startsWith('```')) {
      i++;
      final buf = <String>[];
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      out.add(_Code(buf.join('\n')));
      continue;
    }

    final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      out.add(_Heading(heading.group(1)!.length, heading.group(2)!));
      i++;
      continue;
    }

    if (RegExp(r'^---+$').hasMatch(line.trim())) {
      out.add(_Rule());
      i++;
      continue;
    }

    if (line.contains('|') &&
        i + 1 < lines.length &&
        RegExp(r'^\s*\|?[-:\s|]+\|?\s*$').hasMatch(lines[i + 1])) {
      final header = _cells(line);
      i += 2;
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].contains('|')) {
        rows.add(_cells(lines[i]));
        i++;
      }
      out.add(_Table(header, rows));
      continue;
    }

    if (line.trimLeft().startsWith('>')) {
      final qs = <String>[];
      while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
        qs.add(lines[i].replaceFirst(RegExp(r'^\s*>\s?'), ''));
        i++;
      }
      out.add(_Quote(qs));
      continue;
    }

    if (RegExp(r'^\s*[-*•]\s+').hasMatch(line)) {
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*[-*•]\s+').hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(RegExp(r'^\s*[-*•]\s+'), ''));
        i++;
      }
      out.add(_Bullet(items));
      continue;
    }

    if (RegExp(r'^\s*\d+[.)]\s+').hasMatch(line)) {
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*\d+[.)]\s+').hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(RegExp(r'^\s*\d+[.)]\s+'), ''));
        i++;
      }
      out.add(_Numbered(items));
      continue;
    }

    final para = <String>[line];
    i++;
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !lines[i].trim().startsWith('#') &&
        !lines[i].trim().startsWith('>') &&
        !lines[i].trim().startsWith('```') &&
        !RegExp(r'^\s*[-*•]\s+').hasMatch(lines[i]) &&
        !RegExp(r'^\s*\d+[.)]\s+').hasMatch(lines[i]) &&
        !RegExp(r'^---+$').hasMatch(lines[i].trim())) {
      para.add(lines[i]);
      i++;
    }
    out.add(_Paragraph(para.join(' ')));
  }

  return out;
}

List<String> _cells(String row) => row
    .replaceAll(RegExp(r'^\||\|$'), '')
    .split('|')
    .map((c) => c.trim())
    .toList();

class _BlockView extends StatelessWidget {
  const _BlockView({
    required this.block,
    required this.color,
    required this.dense,
  });

  final _Block block;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return switch (block) {
      _Heading(:final level, :final text) => _InlineText(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1.25,
            fontSize: switch (level) {
              1 => dense ? 18.0 : 20.0,
              2 => dense ? 16.0 : 17.5,
              3 => dense ? 15.0 : 16.0,
              _ => dense ? 14.0 : 15.0,
            },
          ),
        ),
      _Paragraph(:final text) => _InlineText(
          text,
          style: TextStyle(
            color: color,
            height: 1.5,
            fontSize: dense ? AppType.bodySm : AppType.body,
          ),
        ),
      _Bullet(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: t.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _InlineText(
                        item,
                        style: TextStyle(
                          color: color,
                          height: 1.45,
                          fontSize: dense ? AppType.bodySm : AppType.body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      _Numbered(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var n = 0; n < items.length; n++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${n + 1}.',
                        style: TextStyle(
                          color: t.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: dense ? AppType.bodySm : AppType.body,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _InlineText(
                        items[n],
                        style: TextStyle(
                          color: color,
                          height: 1.45,
                          fontSize: dense ? AppType.bodySm : AppType.body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      _Quote(:final lines) => Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: t.primary.withValues(alpha: 0.55), width: 3),
            ),
            color: t.primary.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
          ),
          child: _InlineText(
            lines.join(' '),
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              height: 1.45,
              fontStyle: FontStyle.italic,
              fontSize: dense ? AppType.bodySm : AppType.body,
            ),
          ),
        ),
      _Rule() => Divider(color: t.border.withValues(alpha: 0.8), height: 16),
      _Code(:final text) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: t.border.withValues(alpha: 0.7)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.45,
              color: color,
            ),
          ),
        ),
      _Table(:final header, :final rows) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(
              horizontalInside: BorderSide(color: t.border.withValues(alpha: 0.6)),
              bottom: BorderSide(color: t.border.withValues(alpha: 0.6)),
            ),
            children: [
              TableRow(
                children: [
                  for (final c in header)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                      child: _InlineText(
                        c,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    for (final c in row)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                        child: _InlineText(
                          c,
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
    };
  }
}

class _InlineText extends StatelessWidget {
  const _InlineText(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final spans = <InlineSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)');
    var start = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (tok.startsWith('*')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: t.surfaceMuted,
            fontSize: (style.fontSize ?? 14) * 0.92,
          ),
        ));
      }
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return Text.rich(TextSpan(style: style, children: spans));
  }
}
