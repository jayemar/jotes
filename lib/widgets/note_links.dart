/// Inline link detection for note body text - separate from
/// note_body_editor.dart's block-level parsing (checklists/bullets/numbered
/// lists), since this operates *within* a single block or checklist item's
/// text rather than classifying whole lines.
library;

final RegExp _markdownLinkPattern = RegExp(r'\[([^\]]*)\]\(([^\s()]+)\)');
final RegExp _bareUrlPattern = RegExp(
  r'https?://[^\s<>]+',
  caseSensitive: false,
);
// Trailing characters more likely to be sentence punctuation wrapped around
// a bare URL than part of the URL itself - "see https://x.com." shouldn't
// swallow the period into the link. Deliberately not stripped from a
// [text](url) markdown link, whose url is already explicitly delimited by
// the parens.
const _bareUrlTrailingPunctuation = '.,;:!?)]}\'"';

/// One run of a text block, in display order: either plain text ([url] is
/// null) or a link, where [text] is what's shown and [url] is what tapping
/// it should open. For a `[label](url)` markdown link, [text] is the label
/// (or the url itself if the label is empty); for a bare URL, both are the
/// same string (minus any trailing punctuation - see
/// [_bareUrlTrailingPunctuation]).
class LinkSegment {
  final String text;
  final String? url;

  LinkSegment(this.text, [this.url]);

  bool get isLink => url != null;
}

/// Splits [text] into plain-text and link segments - `[label](url)`
/// markdown links first, then bare `http(s)://` URLs in whatever plain text
/// is left over (so a URL already inside a markdown link's own parens is
/// never double-matched as a second, bare link). Adjacent plain-text
/// segments are not merged - callers that only care about the text (not
/// re-rendering each as a separate span) can just concatenate them.
List<LinkSegment> parseLinks(String text) {
  final segments = <LinkSegment>[];
  var cursor = 0;
  for (final match in _markdownLinkPattern.allMatches(text)) {
    if (match.start > cursor) {
      segments.addAll(_parseBareUrls(text.substring(cursor, match.start)));
    }
    final label = match.group(1)!;
    final url = match.group(2)!;
    segments.add(LinkSegment(label.isEmpty ? url : label, url));
    cursor = match.end;
  }
  if (cursor < text.length) {
    segments.addAll(_parseBareUrls(text.substring(cursor)));
  }
  return segments;
}

List<LinkSegment> _parseBareUrls(String text) {
  final segments = <LinkSegment>[];
  var cursor = 0;
  for (final match in _bareUrlPattern.allMatches(text)) {
    if (match.start > cursor) {
      segments.add(LinkSegment(text.substring(cursor, match.start)));
    }
    final raw = match.group(0)!;
    var end = raw.length;
    while (end > 0 && _bareUrlTrailingPunctuation.contains(raw[end - 1])) {
      end--;
    }
    final url = raw.substring(0, end);
    final trailing = raw.substring(end);
    if (url.isEmpty) {
      segments.add(LinkSegment(raw));
    } else {
      segments.add(LinkSegment(url, url));
      if (trailing.isNotEmpty) segments.add(LinkSegment(trailing));
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    segments.add(LinkSegment(text.substring(cursor)));
  }
  return segments;
}
