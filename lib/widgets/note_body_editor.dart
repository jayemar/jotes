import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter;

import '../models/note.dart';
import 'note_body_view.dart';
import 'note_link_picker.dart';

// Standard GitHub-Flavored-Markdown task list syntax ("- [ ] text" /
// "- [x] text"), so a note's body stays plain, portable Markdown rather
// than a jotes-specific convention - it renders correctly as checklists in
// other markdown tools too. Leading indent spaces are handled separately
// (see parseBodyWithOffsets) - this only matches the part after them.
// The text is optional so a bare "- [ ]"/"- [x]" (no trailing space, no
// text) is still recognized as a valid empty item, matching how GitHub
// and most other Markdown tools treat it - previously the trailing space
// was required even for an empty item, so a note ending in a bare
// "- [ ]" silently fell through to plain text instead of a checkbox.
final RegExp _checklistLinePattern = RegExp(r'^- \[( |x)\](?: (.*))?$');

// Plain Markdown list markers - "- text"/"* text" for an unordered item,
// "1. text" for an ordered one (checked only once _checklistLinePattern has
// already ruled out a checklist line, so "- [ ] text" is never misread as a
// bullet whose text happens to start with "[ ]"). Bare "-"/"*"/"1." (no
// trailing space or text) are valid too, same as a bare checklist marker -
// see applyEnterOnChecklistLine.
final RegExp _bulletLinePattern = RegExp(r'^([-*])(?: (.*))?$');
final RegExp _numberedLinePattern = RegExp(r'^(\d+)\.(?: (.*))?$');

final RegExp _leadingSpacesPattern = RegExp(r'^( *)');

/// Result of classifying one line (with its leading indent already
/// stripped) as a checklist item or not.
class ChecklistLineMatch {
  final bool checked;
  final String text;
  // Raw characters consumed before [text] starts, within the line as
  // given (i.e. not counting indent) - "- [ ] " is 6, a bare "- [ ]" is
  // 5. Needed so a tap can be mapped back to an exact offset in the raw
  // body string (see note_body_view.dart) using the *actual* source
  // line, not a recomputed "canonical" prefix length that might not
  // match an irregular/hand-edited one.
  final int rawPrefixLength;

  ChecklistLineMatch({
    required this.checked,
    required this.text,
    required this.rawPrefixLength,
  });
}

/// Classifies [lineAfterIndent] (indent spaces already stripped by the
/// caller) as a checklist item or not.
ChecklistLineMatch? matchChecklistLine(String lineAfterIndent) {
  final match = _checklistLinePattern.firstMatch(lineAfterIndent);
  if (match == null) return null;
  final text = match.group(2) ?? '';
  return ChecklistLineMatch(
    checked: match.group(1) == 'x',
    text: text,
    rawPrefixLength: lineAfterIndent.length - text.length,
  );
}

/// Generalizes [ChecklistLineMatch] to any of the three list-marker types
/// this editor recognizes (checklist, bullet, numbered) - used by
/// [toggleLineMarker], which only needs to know "is this line already some
/// kind of list item, and if so, how much of it is marker versus text,"
/// not which specific kind.
class LineMarkerMatch {
  final String text;
  final int rawPrefixLength;
  LineMarkerMatch(this.text, this.rawPrefixLength);
}

/// Classifies [lineAfterIndent] (indent already stripped, same convention
/// as [matchChecklistLine]) as whichever list-marker type is present, if
/// any.
LineMarkerMatch? matchAnyLineMarker(String lineAfterIndent) {
  final checklist = matchChecklistLine(lineAfterIndent);
  if (checklist != null) {
    return LineMarkerMatch(checklist.text, checklist.rawPrefixLength);
  }
  final bullet = _bulletLinePattern.firstMatch(lineAfterIndent);
  if (bullet != null) {
    final text = bullet.group(2) ?? '';
    return LineMarkerMatch(text, lineAfterIndent.length - text.length);
  }
  final numbered = _numberedLinePattern.firstMatch(lineAfterIndent);
  if (numbered != null) {
    final text = numbered.group(2) ?? '';
    return LineMarkerMatch(text, lineAfterIndent.length - text.length);
  }
  return null;
}

/// Toggles the line containing [cursorOffset] in [text] between plain text
/// and a list item using [marker] ("- [ ] " for a checklist item, "- " for
/// a bullet) - the core logic behind the toolbar's checkbox/list tools (see
/// NoteBodyEditorState.toggleChecklistLine/toggleBulletLine). Already using
/// that exact marker removes it, back to plain text; already using a
/// *different* marker (e.g. tapping the bullet tool on a checklist line)
/// switches it over rather than stacking a second one; otherwise the
/// marker is simply added. The cursor stays anchored to the same character
/// of the line's own text content (past whatever marker precedes it), not
/// a raw offset that a changed marker length would otherwise leave
/// pointing at the wrong character.
TextEditingValue toggleLineMarker({
  required String text,
  required int cursorOffset,
  required String marker,
}) {
  // lastIndexOf's start argument can't be negative - a cursor at the very
  // beginning of the text (offset 0) trivially has its line start there
  // too, with nothing before it to search.
  final lineStart = cursorOffset <= 0
      ? 0
      : text.lastIndexOf('\n', cursorOffset - 1) + 1;
  final nextNewline = text.indexOf('\n', lineStart);
  final lineEnd = nextNewline == -1 ? text.length : nextNewline;
  final line = text.substring(lineStart, lineEnd);
  final leadingSpaces = _leadingSpacesPattern.firstMatch(line)!.group(1) ?? '';
  final lineAfterIndent = line.substring(leadingSpaces.length);
  final existing = matchAnyLineMarker(lineAfterIndent);
  final existingText = existing?.text ?? lineAfterIndent;
  final existingMarkerLength = existing?.rawPrefixLength ?? 0;

  final removingThisMarker =
      existing != null && lineAfterIndent.startsWith(marker);
  final newLineAfterIndent = removingThisMarker
      ? existingText
      : '$marker$existingText';
  final newMarkerLength = removingThisMarker ? 0 : marker.length;

  final cursorInText =
      (cursorOffset - lineStart - leadingSpaces.length - existingMarkerLength)
          .clamp(0, existingText.length);
  final newCursor =
      lineStart + leadingSpaces.length + newMarkerLength + cursorInText;

  final newText = text.replaceRange(
    lineStart,
    lineEnd,
    '$leadingSpaces$newLineAfterIndent',
  );
  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newCursor),
  );
}

/// Swaps the line containing [cursorOffset] in [text] with the adjacent
/// line in [direction] (-1 for up, +1 for down) - the core logic behind
/// the toolbar's move-line tools (see NoteBodyEditorState.moveLineUp/
/// moveLineDown). Returns null if there's no adjacent line to swap with in
/// that direction (already the first/last line). The cursor stays at the
/// same character offset *within* the moved line's own text, following it
/// to its new position rather than staying at a raw offset that would now
/// land in whatever line ended up there instead.
TextEditingValue? swapLine({
  required String text,
  required int cursorOffset,
  required int direction,
}) {
  // lastIndexOf's start argument can't be negative - a cursor at the very
  // beginning of the text (offset 0) trivially has its line start there
  // too, with nothing before it to search.
  final lineStart = cursorOffset <= 0
      ? 0
      : text.lastIndexOf('\n', cursorOffset - 1) + 1;
  final nextNewline = text.indexOf('\n', lineStart);
  final lineEnd = nextNewline == -1 ? text.length : nextNewline;
  final cursorInLine = cursorOffset - lineStart;

  final int otherStart;
  final int otherEnd;
  if (direction < 0) {
    if (lineStart == 0) return null;
    otherEnd = lineStart - 1; // the '\n' just before this line
    otherStart = text.lastIndexOf('\n', otherEnd - 1) + 1;
  } else {
    if (lineEnd == text.length) return null;
    otherStart = lineEnd + 1; // just past the '\n' after this line
    final afterNewline = text.indexOf('\n', otherStart);
    otherEnd = afterNewline == -1 ? text.length : afterNewline;
  }

  final thisLine = text.substring(lineStart, lineEnd);
  final otherLine = text.substring(otherStart, otherEnd);

  final String newText;
  final int newCursor;
  if (direction < 0) {
    // otherLine, '\n', thisLine -> thisLine, '\n', otherLine
    newText = text.replaceRange(otherStart, lineEnd, '$thisLine\n$otherLine');
    newCursor = otherStart + cursorInLine;
  } else {
    // thisLine, '\n', otherLine -> otherLine, '\n', thisLine
    newText = text.replaceRange(lineStart, otherEnd, '$otherLine\n$thisLine');
    newCursor = lineStart + otherLine.length + 1 + cursorInLine;
  }

  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newCursor),
  );
}

/// The whole line containing [cursorOffset] in [text], cut out entirely
/// (not just cleared) - the core logic behind the toolbar's Cut line tool
/// (see NoteBodyEditorState.cutLine, which copies [cutText] to the
/// clipboard; this only computes the resulting text/cursor). Removes the
/// line's own trailing newline if there's a following line to close the
/// gap with, or the preceding newline otherwise, so cutting never leaves a
/// stray blank line behind; cutting the only line in the whole note leaves
/// an empty body. The cursor lands at the start of whatever line now
/// occupies that position.
class CutLineResult {
  final TextEditingValue value;
  final String cutText;
  CutLineResult(this.value, this.cutText);
}

CutLineResult cutLineAt({required String text, required int cursorOffset}) {
  final lineStart = cursorOffset <= 0
      ? 0
      : text.lastIndexOf('\n', cursorOffset - 1) + 1;
  final nextNewline = text.indexOf('\n', lineStart);
  final lineEnd = nextNewline == -1 ? text.length : nextNewline;
  final line = text.substring(lineStart, lineEnd);

  final String newText;
  final int newCursor;
  if (nextNewline != -1) {
    newText = text.replaceRange(lineStart, lineEnd + 1, '');
    newCursor = lineStart;
  } else if (lineStart > 0) {
    newText = text.replaceRange(lineStart - 1, lineEnd, '');
    newCursor = lineStart - 1;
  } else {
    newText = '';
    newCursor = 0;
  }

  return CutLineResult(
    TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    ),
    line,
  );
}

/// Inserts [insertion] into [text] at [selection] - replacing the current
/// selection if it isn't collapsed, matching how a normal paste behaves.
/// The cursor lands right after the inserted text. The core logic behind
/// the toolbar's Paste tool (see NoteBodyEditorState.pasteAtCursor, which
/// reads the clipboard; this only computes the resulting text/cursor).
TextEditingValue insertTextAt({
  required String text,
  required TextSelection selection,
  required String insertion,
}) {
  final newText = text.replaceRange(selection.start, selection.end, insertion);
  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(
      offset: selection.start + insertion.length,
    ),
  );
}

/// Removes a just-emptied list marker entirely, leaving a blank line where
/// the item was - built from [oldText], discarding the Enter keypress
/// entirely, rather than from the already-"\n"-inserted new text, which
/// would leave both the now-marker-less item *and* a fresh blank line below
/// it, when the user only expects the one blank line the item itself
/// becomes.
TextEditingValue _exitList(String oldText, int lineStart, int prefixLength) {
  final text =
      oldText.substring(0, lineStart) +
      oldText.substring(lineStart + prefixLength);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: lineStart),
  );
}

/// Inserts [continuation] (a fresh list marker) right at the cursor, which
/// is where [newText] already has the Enter keypress's "\n".
TextEditingValue _continueList(
  String newText,
  int newCursorOffset,
  String continuation,
) {
  final text = newText.replaceRange(
    newCursorOffset,
    newCursorOffset,
    continuation,
  );
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(
      offset: newCursorOffset + continuation.length,
    ),
  );
}

/// If the edit from [oldText] to [newText] was exactly "the user pressed
/// Enter at the end of a list line" (cursor now at [newCursorOffset]),
/// returns the value to actually apply instead - continuing the list with
/// a fresh marker (indent preserved, matching Keep and most other
/// list-capable editors): "- [ ] " for a checklist item, the same "-"/"*"
/// bullet for an unordered item, or the next number + ". " for an ordered
/// one. If that line's own item was empty, its marker is removed entirely
/// instead, leaving a blank line - the standard "Enter on an empty bullet
/// exits the list" convention, without which an empty item would have no
/// way to stop the list except deleting the marker by hand.
/// Returns null for every other edit (Enter pressed mid-line, editing
/// elsewhere, pasting multiple characters, backspacing, an IME
/// autocorrect substitution landing alongside the newline, etc.) -
/// deliberately narrow to exactly that one case, everything else is left
/// as plain, unassisted typing.
TextEditingValue? applyEnterOnChecklistLine({
  required String oldText,
  required String newText,
  required int newCursorOffset,
}) {
  // A bare Enter keypress inserts exactly one "\n" at the (collapsed)
  // cursor - anything else in flight (a paste, a selection replaced by
  // typing, autocorrect) changes more than that and is left alone.
  if (newText.length != oldText.length + 1) return null;
  final oldCursorOffset = newCursorOffset - 1;
  if (oldCursorOffset < 0 || oldCursorOffset > oldText.length) return null;
  if (newText[oldCursorOffset] != '\n') return null;
  if (newText.substring(0, oldCursorOffset) !=
          oldText.substring(0, oldCursorOffset) ||
      newText.substring(newCursorOffset) !=
          oldText.substring(oldCursorOffset)) {
    return null;
  }

  final lineStart = oldText.lastIndexOf('\n', oldCursorOffset - 1) + 1;
  final nextNewline = oldText.indexOf('\n', lineStart);
  final lineEnd = nextNewline == -1 ? oldText.length : nextNewline;
  if (oldCursorOffset != lineEnd) return null; // not at the end of the line

  final line = oldText.substring(lineStart, oldCursorOffset);
  final leadingSpaces = _leadingSpacesPattern.firstMatch(line)!.group(1) ?? '';
  final lineAfterIndent = line.substring(leadingSpaces.length);

  final checklistMatch = matchChecklistLine(lineAfterIndent);
  if (checklistMatch != null) {
    if (checklistMatch.text.isEmpty) {
      return _exitList(
        oldText,
        lineStart,
        leadingSpaces.length + checklistMatch.rawPrefixLength,
      );
    }
    return _continueList(newText, newCursorOffset, '$leadingSpaces- [ ] ');
  }

  final bulletMatch = _bulletLinePattern.firstMatch(lineAfterIndent);
  if (bulletMatch != null) {
    final marker = bulletMatch.group(1)!;
    final text = bulletMatch.group(2) ?? '';
    if (text.isEmpty) {
      // lineAfterIndent.length - text.length (not just marker.length) so a
      // trailing space before the cursor - "- " left empty, not just a
      // bare "-" - is consumed too, same trick matchChecklistLine's own
      // rawPrefixLength relies on.
      return _exitList(
        oldText,
        lineStart,
        leadingSpaces.length + lineAfterIndent.length - text.length,
      );
    }
    return _continueList(newText, newCursorOffset, '$leadingSpaces$marker ');
  }

  final numberedMatch = _numberedLinePattern.firstMatch(lineAfterIndent);
  if (numberedMatch != null) {
    final digits = numberedMatch.group(1)!;
    final text = numberedMatch.group(2) ?? '';
    if (text.isEmpty) {
      return _exitList(
        oldText,
        lineStart,
        leadingSpaces.length + lineAfterIndent.length - text.length,
      );
    }
    final nextNumber = int.parse(digits) + 1;
    return _continueList(
      newText,
      newCursorOffset,
      '$leadingSpaces$nextNumber. ',
    );
  }

  return null;
}

/// If the edit from [oldText] to [newText] was exactly "the user typed a
/// second `[` completing `[[` at the cursor" (cursor now at
/// [newCursorOffset]), returns the raw-text range that pair occupies - the
/// trigger for popping up the note-link picker (see
/// NoteBodyEditorState._handleNoteLinkTrigger). `[[` is only ever a
/// trigger gesture here, never stored - a note link is always inserted as
/// plain `[Title](id)` markdown (see [NoteBodyEditorState.insertNoteLink]).
/// Returns null for every other edit (pasting `[[` as one multi-character
/// change, backspacing, typing a lone `[`, editing elsewhere, etc.) -
/// deliberately as narrow as [applyEnterOnChecklistLine]'s own single-
/// keystroke check, for the same reason.
({int start, int end})? detectNoteLinkTrigger({
  required String oldText,
  required String newText,
  required int newCursorOffset,
}) {
  if (newText.length != oldText.length + 1) return null;
  final insertedAt = newCursorOffset - 1;
  if (insertedAt < 1 || insertedAt >= newText.length) return null;
  if (newText[insertedAt] != '[') return null;
  if (newText.substring(0, insertedAt) != oldText.substring(0, insertedAt) ||
      newText.substring(newCursorOffset) != oldText.substring(insertedAt)) {
    return null;
  }
  if (newText[insertedAt - 1] != '[') return null;
  return (start: insertedAt - 1, end: newCursorOffset);
}

/// Only two levels are supported - a top-level item (0) or a sub-item (1)
/// of the nearest preceding top-level item, matching how most checklist
/// apps handle nesting (flat sub-items, not an arbitrarily deep outline).
/// checklistIndentStepPx is how many pixels of left padding a sub-item
/// gets - both in the editor (see _ChecklistRow) and in the read-only card
/// preview (see note_card.dart's _ChecklistPreviewRow).
const maxChecklistIndent = 1;
const checklistIndentStepPx = 20.0;

/// A block of a note body: a run of plain text (possibly spanning several
/// `\n`-joined lines), a single checklist item, or a single plain
/// (bullet/numbered) list item. Notes can mix all of these freely, unlike
/// Google Keep, where a note is entirely a checklist or entirely plain
/// text.
sealed class BodyBlock {}

class TextBodyBlock extends BodyBlock {
  final String text;
  TextBodyBlock(this.text);
}

class ChecklistBodyBlock extends BodyBlock {
  final bool checked;
  final String text;
  final int indent;
  ChecklistBodyBlock({
    required this.checked,
    required this.text,
    this.indent = 0,
  });
}

/// A plain (non-checklist) unordered list item - "- text" or "* text" (see
/// _bulletLinePattern). Indent follows the same top-level/sub-item
/// convention as [ChecklistBodyBlock].
class BulletBodyBlock extends BodyBlock {
  final String text;
  final int indent;
  BulletBodyBlock({required this.text, this.indent = 0});
}

/// An ordered list item - "N. text" (see _numberedLinePattern). [number]
/// is whatever literal number the line was written with; unlike some
/// Markdown renderers, this doesn't renumber a run of items sequentially -
/// it displays exactly what's in the source, same as [ChecklistBodyBlock]
/// displays exactly whatever checked state is in the source.
class NumberedBodyBlock extends BodyBlock {
  final int number;
  final String text;
  final int indent;
  NumberedBodyBlock({
    required this.number,
    required this.text,
    this.indent = 0,
  });
}

/// One block from [parseBodyWithOffsets], carrying its position in the
/// raw source string alongside the parsed [block] itself - lets a tap on
/// the rendered (read-only) block map back to an exact cursor offset in
/// the raw body when switching into edit mode (see note_body_view.dart).
class ParsedBlock {
  final BodyBlock block;
  final int start; // inclusive offset of the raw line(s) in the body
  final int end; // exclusive
  // Offset where the block's own displayed text begins - equals [start]
  // for a TextBodyBlock; for a ChecklistBodyBlock, [start] plus however
  // many raw characters (indent + "- [ ] ") come before the text.
  final int textStart;

  ParsedBlock({
    required this.block,
    required this.start,
    required this.end,
    required this.textStart,
  });
}

/// Parses a stored [Note.body] string into blocks. A line matching
/// `- [ ] text` / `- [x] text` (optionally indented - see
/// matchChecklistLine/_leadingSpacesPattern) becomes its own
/// [ChecklistBodyBlock]; a plain `- text` / `* text` becomes a
/// [BulletBodyBlock] and `N. text` a [NumberedBodyBlock] (checked first
/// against the checklist pattern, so `- [ ] text` is never misread as a
/// bullet whose text happens to start with "[ ]"); runs of non-matching
/// lines are merged into a single [TextBodyBlock]. This is the same
/// Markdown task-list convention KeepImportService writes for imported
/// Keep checklists (always unindented), so previously-imported checklists
/// become interactive here for free.
List<ParsedBlock> parseBodyWithOffsets(String body) {
  final result = <ParsedBlock>[];
  final textLines = <String>[];
  var textStart = 0;
  var textEnd = 0;
  var offset = 0;

  void flushText() {
    if (textLines.isNotEmpty) {
      result.add(
        ParsedBlock(
          block: TextBodyBlock(textLines.join('\n')),
          start: textStart,
          end: textEnd,
          textStart: textStart,
        ),
      );
      textLines.clear();
    }
  }

  for (final line in body.split('\n')) {
    final leadingSpaces =
        _leadingSpacesPattern.firstMatch(line)!.group(1) ?? '';
    final lineAfterIndent = line.substring(leadingSpaces.length);
    final checklistMatch = matchChecklistLine(lineAfterIndent);
    final lineEnd = offset + line.length;
    // Integer division rather than requiring an exact multiple of 2 -
    // defensive against hand-edited/irregularly-indented markdown (e.g. a
    // stray odd space) rather than crashing or misparsing entirely. Shared
    // by all three list-marker block types below.
    final indent = (leadingSpaces.length ~/ 2).clamp(0, maxChecklistIndent);

    if (checklistMatch != null) {
      flushText();
      result.add(
        ParsedBlock(
          block: ChecklistBodyBlock(
            checked: checklistMatch.checked,
            text: checklistMatch.text,
            indent: indent,
          ),
          start: offset,
          end: lineEnd,
          textStart:
              offset + leadingSpaces.length + checklistMatch.rawPrefixLength,
        ),
      );
      offset = lineEnd + 1;
      continue;
    }

    final bulletMatch = _bulletLinePattern.firstMatch(lineAfterIndent);
    if (bulletMatch != null) {
      flushText();
      final text = bulletMatch.group(2) ?? '';
      final rawPrefixLength = lineAfterIndent.length - text.length;
      result.add(
        ParsedBlock(
          block: BulletBodyBlock(text: text, indent: indent),
          start: offset,
          end: lineEnd,
          textStart: offset + leadingSpaces.length + rawPrefixLength,
        ),
      );
      offset = lineEnd + 1;
      continue;
    }

    final numberedMatch = _numberedLinePattern.firstMatch(lineAfterIndent);
    if (numberedMatch != null) {
      flushText();
      final text = numberedMatch.group(2) ?? '';
      final rawPrefixLength = lineAfterIndent.length - text.length;
      result.add(
        ParsedBlock(
          block: NumberedBodyBlock(
            number: int.parse(numberedMatch.group(1)!),
            text: text,
            indent: indent,
          ),
          start: offset,
          end: lineEnd,
          textStart: offset + leadingSpaces.length + rawPrefixLength,
        ),
      );
      offset = lineEnd + 1;
      continue;
    }

    if (textLines.isEmpty) textStart = offset;
    textLines.add(line);
    textEnd = lineEnd;

    // +1 accounts for the '\n' separator consumed between lines; this
    // overcounts past body.length after the very last line, but offset
    // is never read again once the loop ends.
    offset = lineEnd + 1;
  }
  flushText();

  return result;
}

/// See [parseBodyWithOffsets] - this is that, minus the offsets, for
/// callers (like the read-only card preview) that only need the blocks.
List<BodyBlock> parseBody(String body) =>
    parseBodyWithOffsets(body).map((p) => p.block).toList();

/// Inverse of [parseBody].
String serializeBody(List<BodyBlock> blocks) {
  return blocks
      .map((b) {
        return switch (b) {
          ChecklistBodyBlock() =>
            '${'  ' * b.indent}- [${b.checked ? 'x' : ' '}] ${b.text}',
          BulletBodyBlock() => '${'  ' * b.indent}- ${b.text}',
          NumberedBodyBlock() => '${'  ' * b.indent}${b.number}. ${b.text}',
          TextBodyBlock() => b.text,
        };
      })
      .join('\n');
}

/// Applies [applyEnterOnChecklistLine] (despite the name, it now handles
/// every list marker it recognizes - checklist, bullet, and numbered) as
/// the edit-mode TextField's own text-editing pipeline (see
/// NoteBodyEditor.build) rather than from inside onChanged - a
/// TextInputFormatter gets old/new value with selections already attached
/// and is guaranteed to run exactly once per genuine edit, without the
/// ambiguity of re-entering onChanged by assigning back to the controller
/// from inside itself.
class _ListContinuationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return applyEnterOnChecklistLine(
          oldText: oldValue.text,
          newText: newValue.text,
          newCursorOffset: newValue.selection.end,
        ) ??
        newValue;
  }
}

/// Editable note body supporting mixed plain-text and checklist blocks.
/// Renders in one of two modes (see NoteBodyEditorState):
///  - View mode (the default): read-only-styled rendering via
///    [NoteBodyView] - tappable checkboxes, draggable reorder/indent
///    handles, plain text - nothing here has a live TextEditingController.
///  - Edit mode (entered by tapping into a block's text): a single plain
///    multiline TextField bound directly to the raw body string, so
///    there's no parsing while actively typing.
/// Call [addChecklistItem] via a `GlobalKey<NoteBodyEditorState>` to
/// append a new item (e.g. from a toolbar button).
class NoteBodyEditor extends StatefulWidget {
  final String initialBody;
  // The note currently being edited's own id - used only to exclude it
  // from its own note-link picker (see NoteBodyEditorState._handleNoteLinkTrigger),
  // so a note can't accidentally link to itself. Defaults to '' (excludes
  // nothing) so the many existing tests that don't exercise note-linking
  // don't need to pass a real id.
  final String noteId;
  final Color textColor;
  final Color hintColor;
  final Color linkColor;
  final ValueChanged<String> onChanged;
  final bool autofocusFirst;
  // Fired on every view/edit mode transition - separate from [onChanged],
  // which also marks the note dirty and (re)starts autosave (see
  // NoteEditorScreen._markDirty), neither of which switching modes alone
  // should trigger. Lets a parent toolbar (see NoteEditorScreen's move-up/
  // move-down buttons) stay in sync with [NoteBodyEditorState.isEditingBody]
  // as soon as it changes, rather than only on the next unrelated rebuild.
  final VoidCallback? onModeChanged;

  const NoteBodyEditor({
    super.key,
    required this.initialBody,
    this.noteId = '',
    required this.textColor,
    required this.hintColor,
    required this.linkColor,
    required this.onChanged,
    this.autofocusFirst = false,
    this.onModeChanged,
  });

  @override
  State<NoteBodyEditor> createState() => NoteBodyEditorState();
}

enum _Mode { view, edit }

class NoteBodyEditorState extends State<NoteBodyEditor> {
  // Single source of truth - everything else (view-mode blocks, the edit
  // controller's text) is derived from this and recomputed after every
  // mutation, never hand-mutated in place, so nothing can drift out of
  // sync with it.
  late String _rawBody;
  _Mode _mode = _Mode.view;

  late final TextEditingController _editController;
  final FocusNode _editFocusNode = FocusNode();

  // Snapshots taken just before a structural action (checklist delete/
  // reorder/indent/check-uncheck, or Cut line) - see _pushUndoSnapshot.
  // Deliberately NOT pushed for plain text typing, which already has its
  // own undo via the keyboard/IME (a single shared TextField's worth, now
  // that edit mode is one field over the raw body rather than one per
  // item); this stack is for actions that have no other way to undo.
  // [cursorOffset] only matters for a snapshot taken in edit mode (Cut
  // line) - see _commitBody, which uses it to put the cursor back roughly
  // where the action happened rather than at some arbitrary position; a
  // view-mode-only action (everything else) just passes 0, since there's
  // no cursor to restore there in the first place.
  final List<({String body, int cursorOffset})> _undoStack = [];
  static const _maxUndoSteps = 50;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get isEditingBody => _mode == _Mode.edit;

  @override
  void initState() {
    super.initState();
    _rawBody = widget.initialBody;
    _editController = TextEditingController(text: _rawBody);
    _editFocusNode.addListener(_onEditFocusChanged);
    if (widget.autofocusFirst) {
      // A brand-new note has nothing to view yet - go straight to typing
      // instead of making the user tap into an empty view first.
      _mode = _Mode.edit;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _editFocusNode.removeListener(_onEditFocusChanged);
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onEditFocusChanged() {
    if (_mode == _Mode.edit && !_editFocusNode.hasFocus) {
      setState(() => _mode = _Mode.view);
      widget.onModeChanged?.call();
    }
  }

  /// Switches to edit mode with the cursor at [cursorOffset] into the raw
  /// body - called for a tap on a block's text, a tap on the blank space
  /// below the last block (with `cursorOffset: _rawBody.length`), and
  /// [addChecklistItem]. Safe to call while already in edit mode - just
  /// re-syncs the controller/selection in place rather than tearing
  /// anything down, since it's the same persistent controller either way.
  void _enterEditMode(int cursorOffset) {
    setState(() {
      _mode = _Mode.edit;
      _editController.value = TextEditingValue(
        text: _rawBody,
        selection: TextSelection.collapsed(
          offset: cursorOffset.clamp(0, _rawBody.length),
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocusNode.requestFocus();
    });
    widget.onModeChanged?.call();
  }

  /// Switches into edit mode with the cursor at the very start of the body
  /// and gives it focus - called when Enter is pressed in the title field
  /// (see NoteEditorScreen), so title -> body flows like tabbing to the next
  /// field rather than dismissing the keyboard.
  void focusBody() => _enterEditMode(0);

  /// Returns to view mode without saving anything further (there's
  /// nothing to save - [_onEditChanged] already keeps [_rawBody] current
  /// on every keystroke). Exposed for `NoteEditorScreen`'s back-button
  /// handling: a pop attempt while edit mode is active should back out of
  /// edit mode, not pop the whole note screen.
  void exitEditMode() {
    if (_mode != _Mode.edit) return;
    _editFocusNode.unfocus();
    setState(() => _mode = _Mode.view);
    widget.onModeChanged?.call();
  }

  void _onEditChanged(String value) {
    // No setState - edit mode's own TextField already reflects what was
    // just typed via its controller; nothing else on screen depends on
    // _rawBody reactively while typing, which is the whole point of not
    // parsing on every keystroke.
    final previous = _rawBody;
    _rawBody = value;
    widget.onChanged(_rawBody);

    final trigger = detectNoteLinkTrigger(
      oldText: previous,
      newText: value,
      newCursorOffset: _editController.selection.end,
    );
    if (trigger != null) {
      unawaited(_handleNoteLinkTrigger(trigger.start, trigger.end));
    }
  }

  /// Pops up the note-link picker for a just-typed `[[` spanning
  /// [start, end) in the raw body (see [detectNoteLinkTrigger]), replacing
  /// it with `[Title](id)` for whichever note is picked - or leaving it
  /// untouched if the picker is dismissed without one.
  Future<void> _handleNoteLinkTrigger(int start, int end) async {
    final note = await pickNoteToLink(context, excludeNoteId: widget.noteId);
    if (note == null || !mounted) return;

    // The picker is a modal dialog - nothing else can have edited the body
    // while it was open - but this is cheap insurance against replacing the
    // wrong range if that ever stops being true. Checked against _rawBody,
    // not the edit TextField's own controller - showing the dialog steals
    // its focus, which flips this editor to view mode (see
    // _onEditFocusChanged) and stops the controller being kept in sync
    // (see _commitBody), so it's _rawBody that's guaranteed current here.
    if (end > _rawBody.length || _rawBody.substring(start, end) != '[[') {
      return;
    }
    _applyNoteLink(note, TextSelection(baseOffset: start, extentOffset: end));
  }

  /// Inserts a link to [note] at the current cursor - the core logic
  /// behind the toolbar's "Insert note link" button (see
  /// NoteEditorScreen._insertNoteLink). Works regardless of the mode this
  /// editor is *currently* in - showing the note-link picker's own dialog
  /// (awaited by both this method's and [_handleNoteLinkTrigger]'s callers
  /// before either ever runs) steals focus from this editor's TextField,
  /// which flips it to view mode the moment the dialog opens (see
  /// _onEditFocusChanged); [_applyNoteLink] switches back to edit mode
  /// itself once the link is inserted, so that flip is transparent here.
  void insertNoteLink(Note note) {
    final selection = _editController.selection;
    final cursor = selection.isValid
        ? selection.start.clamp(0, _rawBody.length)
        : _rawBody.length;
    _applyNoteLink(note, TextSelection.collapsed(offset: cursor));
  }

  /// Shared by [insertNoteLink] and [_handleNoteLinkTrigger]: replaces
  /// [replaceRange] of [_rawBody] with a markdown link to [note], then
  /// (re-)enters edit mode with the cursor right after the inserted link -
  /// exactly where a typed link would leave it, and where the user almost
  /// certainly wants to keep typing next.
  void _applyNoteLink(Note note, TextSelection replaceRange) {
    final newValue = insertTextAt(
      text: _rawBody,
      selection: replaceRange,
      insertion: _noteLinkMarkdown(note),
    );
    _rawBody = newValue.text;
    widget.onChanged(_rawBody);
    _enterEditMode(newValue.selection.baseOffset);
  }

  String _noteLinkMarkdown(Note note) =>
      '[${note.title.isEmpty ? 'Untitled' : note.title}](${note.id})';

  /// Replaces the body with [newBody] from an external source - a note
  /// open on this device receiving a newer edit made on another device
  /// (see NoteEditorScreen._maybeApplyRemoteUpdate), not a local edit made
  /// here. The caller is expected to only call this while in view mode
  /// (isEditingBody is false); re-checked here too, since overwriting a
  /// live edit-mode TextField's controller out from under a focused cursor
  /// would be jarring and could discard in-flight keystrokes.
  void applyExternalBody(String newBody) {
    if (_mode == _Mode.edit) return;
    setState(() {
      _rawBody = newBody;
      _editController.text = newBody;
    });
  }

  /// Captures the current raw body (the state just *before* a structural
  /// action mutates it) - undo() restores exactly this. [cursorOffset] is
  /// only meaningful for an edit-mode action (see the field doc on
  /// [_undoStack]).
  void _pushUndoSnapshot({int cursorOffset = 0}) {
    _undoStack.add((body: _rawBody, cursorOffset: cursorOffset));
    if (_undoStack.length > _maxUndoSteps) {
      _undoStack.removeAt(0);
    }
  }

  /// Reverts the most recent structural action (see _pushUndoSnapshot) -
  /// general, not just for checklists (despite the toolbar icon's own
  /// history/tooltip): checklist toggle/delete/drag and Cut line all push
  /// a snapshot here, so this undoes whichever of those happened last.
  void undo() {
    if (_undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    _commitBody(snapshot.body, cursorOffset: snapshot.cursorOffset);
  }

  void _commitBlocks(List<BodyBlock> blocks) =>
      _commitBody(serializeBody(blocks));

  /// Applies [newBody] as the note's new raw body - shared by
  /// [_commitBlocks] (a fresh checklist mutation) and [undo] (restoring a
  /// snapshot). Also re-syncs the edit-mode TextField's own controller
  /// when currently editing: undoing a Cut line can happen without ever
  /// leaving edit mode (unlike every other undo-tracked action, which
  /// only ever happens in view mode), so [_rawBody] alone isn't
  /// necessarily what's actually on screen. [cursorOffset] places the
  /// cursor precisely when given (undo), otherwise at the end.
  void _commitBody(String newBody, {int? cursorOffset}) {
    setState(() {
      _rawBody = newBody;
      if (_mode == _Mode.edit) {
        _editController.value = TextEditingValue(
          text: newBody,
          selection: TextSelection.collapsed(
            offset: (cursorOffset ?? newBody.length).clamp(0, newBody.length),
          ),
        );
      }
    });
    widget.onChanged(_rawBody);
  }

  /// Appends a new empty checklist item and switches to edit mode with
  /// the cursor right after its "- [ ] " prefix - a brand-new item is
  /// empty, so the user almost certainly wants to type its text right
  /// away, unlike toggle/reorder/indent/delete, which all stay in view
  /// mode. Exposed for a parent toolbar button via
  /// `GlobalKey<NoteBodyEditorState>`. Always appends at the very end,
  /// not at any current cursor position.
  void addChecklistItem() => _appendItem('- [ ] ');

  /// Same as [addChecklistItem], but appends a plain bullet ("- ") rather
  /// than a checkbox - exposed for the toolbar's "add list item" button,
  /// alongside "add checklist item".
  void addBulletItem() => _appendItem('- ');

  void _appendItem(String marker) {
    final needsNewline = _rawBody.isNotEmpty && !_rawBody.endsWith('\n');
    final newBody = '$_rawBody${needsNewline ? '\n' : ''}$marker';
    setState(() => _rawBody = newBody);
    widget.onChanged(_rawBody);
    _enterEditMode(newBody.length);
  }

  /// Toggles whether the line the cursor is currently on is a checklist
  /// item (see [toggleLineMarker]) - falls back to appending a brand-new
  /// empty checklist item at the end (the old, mode-independent behavior -
  /// see [addChecklistItem]) when not currently editing a specific line,
  /// since there's no "current line" to toggle without an active cursor.
  /// Exposed for the toolbar's checkbox button via
  /// `GlobalKey<NoteBodyEditorState>`.
  void toggleChecklistLine() => _toggleCurrentLine('- [ ] ');

  /// Same as [toggleChecklistLine], but for a plain bullet ("- ") -
  /// exposed for the toolbar's list button.
  void toggleBulletLine() => _toggleCurrentLine('- ');

  void _toggleCurrentLine(String marker) {
    if (_mode != _Mode.edit) {
      _appendItem(marker);
      return;
    }
    final selection = _editController.selection;
    if (!selection.isValid) return;

    final newValue = toggleLineMarker(
      text: _editController.text,
      cursorOffset: selection.baseOffset,
      marker: marker,
    );
    _rawBody = newValue.text;
    setState(() => _editController.value = newValue);
    widget.onChanged(_rawBody);
  }

  /// Moves the line the cursor is currently on up/down past its neighbor
  /// (see [swapLine]) - a no-op while not editing a specific line (see
  /// [_toggleCurrentLine]'s same reasoning) or already at the first/last
  /// line. Exposed for the toolbar's move-up/move-down buttons via
  /// `GlobalKey<NoteBodyEditorState>`.
  void moveLineUp() => _moveLine(-1);

  /// See [moveLineUp].
  void moveLineDown() => _moveLine(1);

  void _moveLine(int direction) {
    if (_mode != _Mode.edit) return;
    final selection = _editController.selection;
    if (!selection.isValid) return;

    final newValue = swapLine(
      text: _editController.text,
      cursorOffset: selection.baseOffset,
      direction: direction,
    );
    if (newValue == null) return;
    _rawBody = newValue.text;
    setState(() => _editController.value = newValue);
    widget.onChanged(_rawBody);
  }

  /// Cuts the entire line the cursor is currently on (not just a
  /// selection) to the clipboard - a no-op while not editing a specific
  /// line, same reasoning as [moveLineUp]/[moveLineDown]. Pushes an undo
  /// snapshot first (see [undo]), unlike the other edit-mode tools here -
  /// cutting a whole line is destructive enough (and easy enough to hit
  /// by accident) to be worth an explicit way back, the same reasoning
  /// checklist delete already gets. Exposed for the toolbar's Cut line
  /// button via `GlobalKey<NoteBodyEditorState>`.
  void cutLine() {
    if (_mode != _Mode.edit) return;
    final selection = _editController.selection;
    if (!selection.isValid) return;

    final result = cutLineAt(
      text: _editController.text,
      cursorOffset: selection.baseOffset,
    );
    _pushUndoSnapshot(cursorOffset: selection.baseOffset);
    unawaited(Clipboard.setData(ClipboardData(text: result.cutText)));
    _commitBody(
      result.value.text,
      cursorOffset: result.value.selection.baseOffset,
    );
  }

  /// Inserts the clipboard's text at the cursor, replacing any selection -
  /// a no-op while not editing a specific line, same reasoning as
  /// [cutLine], or if the clipboard has no text to paste. Exposed for the
  /// toolbar's Paste button via `GlobalKey<NoteBodyEditorState>`.
  Future<void> pasteAtCursor() async {
    if (_mode != _Mode.edit) return;
    final selection = _editController.selection;
    if (!selection.isValid) return;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null || pasted.isEmpty || !mounted) return;

    final newValue = insertTextAt(
      text: _editController.text,
      selection: selection,
      insertion: pasted,
    );
    _rawBody = newValue.text;
    setState(() => _editController.value = newValue);
    widget.onChanged(_rawBody);
  }

  /// Checking an item sinks it to the bottom of its own contiguous
  /// checklist run (same run boundaries drag-reorder respects - a checked
  /// item never crosses a paragraph into a separate checklist group),
  /// matching Keep's own "checked items sink to the bottom" behavior.
  /// Unchecking does *not* move it back - it stays wherever it currently
  /// sits until manually reordered, same as Keep.
  void _toggleChecked(int index) {
    final blocks = parseBody(_rawBody);
    final target = blocks[index] as ChecklistBodyBlock;
    final becomingChecked = !target.checked;
    _pushUndoSnapshot();

    final toggled = ChecklistBodyBlock(
      checked: becomingChecked,
      text: target.text,
      indent: target.indent,
    );

    if (becomingChecked) {
      final runEnd = _checklistRunEnd(blocks, index);
      blocks.removeAt(index);
      blocks.insert(runEnd - 1, toggled);
      // The checked item may have been the sole top-level item its own
      // sub-items depended on - same orphan cleanup the delete/drag paths
      // already do.
      _fixOrphanedIndents(blocks);
    } else {
      blocks[index] = toggled;
    }

    _commitBlocks(blocks);
  }

  /// Exclusive end index of the maximal run of consecutive
  /// [ChecklistBodyBlock]s starting at [index] (which must itself be one) -
  /// e.g. for `[text, check, check, check, text]`, index 1 returns 4.
  int _checklistRunEnd(List<BodyBlock> blocks, int index) {
    var i = index;
    while (i < blocks.length && blocks[i] is ChecklistBodyBlock) {
      i += 1;
    }
    return i;
  }

  void _deleteBlock(int index) {
    final blocks = parseBody(_rawBody);
    final target = blocks[index] as ChecklistBodyBlock;
    // A deleted checklist item's text is otherwise gone for good - copying
    // it means "delete" doubles as "cut" without needing a separate
    // control, so the text can still be pasted somewhere else. Copies the
    // full "- [ ] text" markdown line (via the same serializeBody() a save
    // uses), not just the bare text, so pasting it into another checklist
    // (here or in another markdown-aware tool) still renders as a checkbox
    // instead of a plain line.
    unawaited(Clipboard.setData(ClipboardData(text: serializeBody([target]))));
    _pushUndoSnapshot();
    blocks.removeAt(index);
    _mergeAdjacentTextBlocksAround(blocks, index);
    _fixOrphanedIndents(blocks);
    if (blocks.isEmpty) blocks.add(TextBodyBlock(''));
    _commitBlocks(blocks);
  }

  /// Applies one drag-handle gesture's resolved outcome (see
  /// note_body_view.dart, which does the actual drag-position geometry -
  /// this just applies the result): move the block at [fromIndex] to
  /// [toIndex] (both absolute indices into `parseBody(_rawBody)`) and set
  /// its indent to [newIndent] - both from the same single drag, matching
  /// how Keep's own drag handle works, rather than two separate controls.
  void _commitChecklistDrag(int fromIndex, int toIndex, int newIndent) {
    final blocks = parseBody(_rawBody);
    final target = blocks[fromIndex] as ChecklistBodyBlock;

    // Only worth an undo step if the drag actually changed something - a
    // drag that starts and ends without crossing any threshold shouldn't
    // clutter the undo stack with a no-op entry.
    if (fromIndex != toIndex || newIndent != target.indent) {
      _pushUndoSnapshot();
    }

    if (fromIndex != toIndex) {
      blocks.removeAt(fromIndex);
      blocks.insert(toIndex, target);
    }
    blocks[toIndex] = ChecklistBodyBlock(
      checked: target.checked,
      text: target.text,
      indent: newIndent,
    );
    _fixOrphanedIndents(blocks);
    _commitBlocks(blocks);
  }

  /// A run's first item can never be a sub-item - there's nothing above it
  /// in that run to attach to. Reordering or removing items can otherwise
  /// leave a former sub-item stranded at the front of its run (its
  /// top-level parent moved/removed out from under it); this resets any
  /// such orphan back to indent 0 so it never renders - or serializes - as
  /// an indented item with nothing above it.
  void _fixOrphanedIndents(List<BodyBlock> blocks) {
    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];
      if (block is! ChecklistBodyBlock) {
        i += 1;
        continue;
      }
      if (block.indent != 0) {
        blocks[i] = ChecklistBodyBlock(
          checked: block.checked,
          text: block.text,
          indent: 0,
        );
      }
      while (i < blocks.length && blocks[i] is ChecklistBodyBlock) {
        i += 1;
      }
    }
  }

  /// After removing the block that was at [removedIndex], the blocks that
  /// used to sit on either side of it - if both are plain text, not
  /// checklist items - are now directly adjacent. Left unmerged, they'd
  /// stay two separate blocks that only look like consecutive lines of one
  /// paragraph: e.g. deleting a checklist item that split "Words here"
  /// from a blank line below it would otherwise leave that blank line
  /// impossible to backspace into the line above once in edit mode, since
  /// they'd still serialize with the checklist item's line gone but as
  /// two separately-joined text runs rather than one.
  void _mergeAdjacentTextBlocksAround(
    List<BodyBlock> blocks,
    int removedIndex,
  ) {
    if (removedIndex <= 0 || removedIndex >= blocks.length) return;
    final before = blocks[removedIndex - 1];
    final after = blocks[removedIndex];
    if (before is! TextBodyBlock || after is! TextBodyBlock) return;

    blocks[removedIndex - 1] = TextBodyBlock('${before.text}\n${after.text}');
    blocks.removeAt(removedIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _Mode.edit) {
      return TextField(
        key: const Key('body_edit_field'),
        controller: _editController,
        focusNode: _editFocusNode,
        style: TextStyle(fontSize: 15, color: widget.textColor),
        decoration: InputDecoration(
          hintText: 'Note',
          hintStyle: TextStyle(color: widget.hintColor),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        maxLines: null,
        // Without this, the field only occupies its own content's height
        // (e.g. a single short line for a mostly-empty note) rather than
        // the full space its Expanded parent (see note_editor_screen.dart)
        // actually gives it - leaving the rest of the visible note area
        // untappable, unlike view mode's own ListView, which is tappable
        // everywhere via its own catch-all GestureDetector (see
        // note_body_view.dart). expands makes this field's box (and thus
        // its tap-to-position-cursor hit area) fill that space instead.
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [_ListContinuationFormatter()],
        onChanged: _onEditChanged,
      );
    }

    return NoteBodyView(
      body: _rawBody,
      textColor: widget.textColor,
      hintColor: widget.hintColor,
      linkColor: widget.linkColor,
      onEnterEditAt: _enterEditMode,
      onToggle: _toggleChecked,
      onDelete: _deleteBlock,
      onDragCommit: _commitChecklistDrag,
    );
  }
}
