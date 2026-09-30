/// Inline Markdown formatting detection for note body text - same
/// "operates within a single block/checklist item's text" scope as
/// note_links.dart's own link detection, and deliberately kept just as
/// flat/non-recursive: a matched span's own text isn't re-scanned for
/// further formatting (so e.g. a link label can't itself contain bold
/// text), matching this app's existing level of Markdown support rather
/// than a full CommonMark-nesting implementation.
///
/// Deliberately supports only the asterisk/tilde/backtick forms
/// (`**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``) - not the
/// underscore variants (`__bold__`, `_italic_`), which would otherwise
/// misfire on ordinary text containing underscores (file_names,
/// snake_case identifiers, ...).
library;

enum InlineFormat { bold, italic, strikethrough, code }

/// One run of a text block, in display order: [formats] is empty for a
/// plain run, or carries exactly one of [InlineFormat] for a formatted one
/// (a run is never both bold and italic - see this library's own doc
/// comment on why `***triple***` combinations aren't specially supported).
class FormatSegment {
  final String text;
  final Set<InlineFormat> formats;

  FormatSegment(this.text, [this.formats = const {}]);
}

// Alternatives are tried in this exact order at each position - bold before
// italic matters: both start with "*", so trying bold's "**...**" first
// means a genuine bold run is never instead consumed as two adjacent
// italic runs. Each inner character class excludes its own marker
// character, so a match never swallows past where its closing marker
// should be (and, for italic specifically, never matches into a "**" pair
// it isn't actually part of).
final RegExp _inlinePattern = RegExp(
  r'\*\*(?<bold>[^\n*]+?)\*\*'
  r'|~~(?<strike>[^\n~]+?)~~'
  r'|`(?<code>[^`\n]+?)`'
  r'|\*(?<italic>[^\n*]+?)\*',
);

/// Splits [text] into plain-text and formatted segments - see
/// [FormatSegment]. Adjacent plain-text segments are not merged, same
/// convention as [note_links.dart]'s parseLinks.
List<FormatSegment> parseInlineFormatting(String text) {
  final segments = <FormatSegment>[];
  var cursor = 0;
  for (final match in _inlinePattern.allMatches(text)) {
    if (match.start > cursor) {
      segments.add(FormatSegment(text.substring(cursor, match.start)));
    }
    final bold = match.namedGroup('bold');
    final strike = match.namedGroup('strike');
    final code = match.namedGroup('code');
    final italic = match.namedGroup('italic');
    if (bold != null) {
      segments.add(FormatSegment(bold, const {InlineFormat.bold}));
    } else if (strike != null) {
      segments.add(FormatSegment(strike, const {InlineFormat.strikethrough}));
    } else if (code != null) {
      segments.add(FormatSegment(code, const {InlineFormat.code}));
    } else if (italic != null) {
      segments.add(FormatSegment(italic, const {InlineFormat.italic}));
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    segments.add(FormatSegment(text.substring(cursor)));
  }
  return segments;
}
