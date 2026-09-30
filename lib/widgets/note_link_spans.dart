import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../screens/note_editor_screen.dart';
import '../services/link_service.dart';
import 'note_inline_format.dart';
import 'note_links.dart';

/// Opens [url]: a scheme-less target (see [isInternalLinkTarget]) is
/// resolved as another note's id and opened in-app; anything else goes
/// through LinkService as before, showing a brief SnackBar if it couldn't
/// be opened - a tapped link that silently does nothing would otherwise
/// look exactly like a tap that just failed to register. Shared by every
/// place that renders tappable links via [buildLinkSpans] (the note
/// editor's view mode, the "all notes" grid preview).
Future<void> openLink(BuildContext context, String url) async {
  if (isInternalLinkTarget(url)) {
    final notes = ProviderScope.containerOf(context).read(notesProvider).value;
    Note? note;
    for (final candidate in notes ?? const <Note>[]) {
      if (candidate.id == url) {
        note = candidate;
        break;
      }
    }
    if (note != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("That note no longer exists")));
    return;
  }

  final opened = await LinkService.instance.open(url);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
}

/// Splits [text] into [InlineSpan]s for [Text.rich]: plain runs in
/// [baseStyle] (further split by any `**bold**`/`*italic*`/`~~strike~~`/
/// `` `code` `` formatting - see [parseInlineFormatting]), and any
/// `[label](url)`/bare-URL link (see [parseLinks]) underlined in
/// [linkColor] with a tap recognizer that calls [onTapLink]. A link's own
/// label isn't itself re-scanned for inline formatting, same non-nesting
/// scope as [parseInlineFormatting]'s own doc comment. Kept separate from
/// note_links.dart's pure [parseLinks] so that stays trivially
/// unit-testable with no Flutter binding required.
List<InlineSpan> buildLinkSpans({
  required String text,
  required TextStyle baseStyle,
  required Color linkColor,
  required ValueChanged<String> onTapLink,
}) {
  return [
    for (final segment in parseLinks(text))
      if (segment.isLink)
        TextSpan(
          text: segment.text,
          // Combines with (rather than replaces) baseStyle's own
          // decoration - a checked checklist item's link still needs its
          // strikethrough (see _ChecklistViewRowState.build), not just the
          // underline every link gets.
          style: baseStyle.copyWith(
            color: linkColor,
            decoration: TextDecoration.combine([
              baseStyle.decoration ?? TextDecoration.none,
              TextDecoration.underline,
            ]),
            decorationColor: linkColor,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onTapLink(segment.url!),
        )
      else
        for (final formatted in parseInlineFormatting(segment.text))
          TextSpan(
            text: formatted.text,
            style: _applyInlineFormats(baseStyle, formatted.formats),
          ),
  ];
}

/// [baseStyle] with each of [formats] layered on - combining with (rather
/// than replacing) [baseStyle]'s own decoration for strikethrough, same
/// reasoning as [buildLinkSpans]' own underline-combining for a link.
TextStyle _applyInlineFormats(TextStyle baseStyle, Set<InlineFormat> formats) {
  var style = baseStyle;
  if (formats.contains(InlineFormat.bold)) {
    style = style.copyWith(fontWeight: FontWeight.bold);
  }
  if (formats.contains(InlineFormat.italic)) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (formats.contains(InlineFormat.strikethrough)) {
    style = style.copyWith(
      decoration: TextDecoration.combine([
        style.decoration ?? TextDecoration.none,
        TextDecoration.lineThrough,
      ]),
    );
  }
  if (formats.contains(InlineFormat.code)) {
    style = style.copyWith(fontFamily: 'monospace');
  }
  return style;
}
