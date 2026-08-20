import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/link_service.dart';
import 'note_links.dart';

/// Opens [url] (see LinkService), showing a brief SnackBar if it couldn't
/// be - a tapped link that silently does nothing would otherwise look
/// exactly like a tap that just failed to register. Shared by every place
/// that renders tappable links via [buildLinkSpans] (the note editor's
/// view mode, the "all notes" grid preview).
Future<void> openLink(BuildContext context, String url) async {
  final opened = await LinkService.instance.open(url);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
}

/// Splits [text] into [InlineSpan]s for [Text.rich]: plain runs in
/// [baseStyle], and any `[label](url)`/bare-URL link (see [parseLinks])
/// underlined in [linkColor] with a tap recognizer that calls [onTapLink].
/// Kept separate from note_links.dart's pure [parseLinks] so that stays
/// trivially unit-testable with no Flutter binding required.
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
        TextSpan(text: segment.text, style: baseStyle),
  ];
}
