import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import 'note_body_editor.dart'
    show
        BulletBodyBlock,
        ChecklistBodyBlock,
        NumberedBodyBlock,
        TextBodyBlock,
        checklistIndentStepPx,
        parseBody;
import 'note_link_spans.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const NoteCard({
    super.key,
    required this.note,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = noteColorFor(context, note.colorIndex);
    final isDark =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    // Same fixed link-blue convention as note_editor_screen.dart's own
    // linkColor - see its comment for why this doesn't derive from the
    // note's own background color.
    final linkColor = isDark ? Colors.lightBlueAccent : Colors.blue;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.blue
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2.5 : 0.5,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (note.title.isNotEmpty) ...[
                  Text(
                    note.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                ],
                if (note.body.isNotEmpty)
                  _NoteBodyPreview(
                    body: note.body,
                    textColor: textColor,
                    linkColor: linkColor,
                    // Links are only tappable outside selection mode - a
                    // card's whole area is a toggle-selection target while
                    // selecting (see the onTap passed in from
                    // notes_screen.dart), and a link recognizer winning the
                    // gesture arena over that would silently break
                    // multi-select on any card whose preview happens to
                    // contain one.
                    linksTappable: !selectionMode,
                  ),
                if (note.reminderAt != null) ...[
                  const SizedBox(height: 8),
                  _ReminderChip(
                    reminderAt: note.reminderAt!,
                    resolved: note.reminderResolved,
                    repeats: note.repeatRule != null,
                    textColor: textColor,
                  ),
                ],
              ],
            ),
            // Not shown alongside the selection indicator below - they'd
            // occupy the same corner, and which notes are selected is the
            // more immediate question once selecting has actually started.
            if (note.pinned && !selectionMode)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.push_pin,
                  color: textColor.withAlpha(150),
                  size: 16,
                ),
              ),
            if (selectionMode)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? Colors.blue : textColor.withAlpha(150),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders a note's body as mixed text/checklist blocks, matching how it
/// actually edits (see NoteBodyEditor) - a checklist item shows a real
/// (read-only; tapping the whole card opens the note, not the box) checkbox
/// glyph rather than the raw "- [ ] " markdown syntax, the same way Google
/// Keep's own card previews do. Capped at a modest total line count so one
/// very long note doesn't dominate the masonry grid.
class _NoteBodyPreview extends StatelessWidget {
  final String body;
  final Color textColor;
  final Color linkColor;
  final bool linksTappable;

  const _NoteBodyPreview({
    required this.body,
    required this.textColor,
    required this.linkColor,
    required this.linksTappable,
  });

  static const _maxPreviewLines = 8;

  @override
  Widget build(BuildContext context) {
    final blocks = parseBody(body);
    final children = <Widget>[];
    var linesUsed = 0;

    for (final block in blocks) {
      if (linesUsed >= _maxPreviewLines) break;

      switch (block) {
        case ChecklistBodyBlock():
          children.add(
            _ChecklistPreviewRow(
              block: block,
              textColor: textColor,
              linkColor: linkColor,
              linksTappable: linksTappable,
            ),
          );
          linesUsed += 1;
        case BulletBodyBlock():
          children.add(
            _ListMarkerPreviewRow(
              marker: '•',
              text: block.text,
              indent: block.indent,
              textColor: textColor,
              linkColor: linkColor,
              linksTappable: linksTappable,
            ),
          );
          linesUsed += 1;
        case NumberedBodyBlock():
          children.add(
            _ListMarkerPreviewRow(
              marker: '${block.number}.',
              text: block.text,
              indent: block.indent,
              textColor: textColor,
              linkColor: linkColor,
              linksTappable: linksTappable,
            ),
          );
          linesUsed += 1;
        case TextBodyBlock():
          final remaining = _maxPreviewLines - linesUsed;
          final baseStyle = TextStyle(
            fontSize: 13,
            color: textColor.withAlpha(220),
          );
          children.add(
            Text.rich(
              TextSpan(
                children: linksTappable
                    ? buildLinkSpans(
                        text: block.text,
                        baseStyle: baseStyle,
                        linkColor: linkColor,
                        onTapLink: (url) => openLink(context, url),
                      )
                    : [TextSpan(text: block.text, style: baseStyle)],
              ),
              maxLines: remaining,
              overflow: TextOverflow.ellipsis,
            ),
          );
          linesUsed += block.text.split('\n').length.clamp(0, remaining);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _ChecklistPreviewRow extends StatelessWidget {
  final ChecklistBodyBlock block;
  final Color textColor;
  final Color linkColor;
  final bool linksTappable;

  const _ChecklistPreviewRow({
    required this.block,
    required this.textColor,
    required this.linkColor,
    required this.linksTappable,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 13,
      color: textColor.withAlpha(block.checked ? 140 : 220),
      decoration: block.checked ? TextDecoration.lineThrough : null,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: block.indent * checklistIndentStepPx,
        top: 1,
        bottom: 1,
      ),
      child: Row(
        // .center, not .start - see note_body_view.dart's own
        // _ChecklistViewRow for why top-aligning a checkbox/icon next to
        // text reliably looks like the checkbox is floating higher than
        // it should.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            block.checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 15,
            color: textColor.withAlpha(180),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: linksTappable
                    ? buildLinkSpans(
                        text: block.text,
                        baseStyle: baseStyle,
                        linkColor: linkColor,
                        onTapLink: (url) => openLink(context, url),
                      )
                    : [TextSpan(text: block.text, style: baseStyle)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only preview row for a [BulletBodyBlock]/[NumberedBodyBlock] - a
/// plain [marker] ("•" or "N.") followed by the item's text, the same
/// layout shape as [_ChecklistPreviewRow] but with a text marker instead
/// of a checkbox icon and no strikethrough (plain list items don't have a
/// checked state).
class _ListMarkerPreviewRow extends StatelessWidget {
  final String marker;
  final String text;
  final int indent;
  final Color textColor;
  final Color linkColor;
  final bool linksTappable;

  const _ListMarkerPreviewRow({
    required this.marker,
    required this.text,
    required this.indent,
    required this.textColor,
    required this.linkColor,
    required this.linksTappable,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(fontSize: 13, color: textColor.withAlpha(220));
    return Padding(
      padding: EdgeInsets.only(
        left: indent * checklistIndentStepPx,
        top: 1,
        bottom: 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // minWidth only, no maxWidth - see note_body_view.dart's own
          // _buildListMarkerBlock for why a numbered marker (unbounded
          // digit count) must never be squeezed into a fixed width.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 14),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(marker, style: baseStyle),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: linksTappable
                    ? buildLinkSpans(
                        text: text,
                        baseStyle: baseStyle,
                        linkColor: linkColor,
                        onTapLink: (url) => openLink(context, url),
                      )
                    : [TextSpan(text: text, style: baseStyle)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three states, not two: green while [reminderAt] is still in the future
/// (untriggered); amber once it's passed but [resolved] is still false
/// (Dismiss/Snooze - see Note.reminderResolved); red once the user has
/// acted on it (complete). A future reminder is always green without
/// needing to check [resolved] at all - a fresh reminder cycle always
/// starts with reminderResolved: false (see Note.reminderResolved's own
/// doc comment), so "still in the future" and "resolved" never
/// meaningfully coexist. Synced, so this reflects Dismiss/Snooze acted on
/// from any device, not just this one.
class _ReminderChip extends StatelessWidget {
  final DateTime reminderAt;
  final bool resolved;
  // Whether Note.repeatRule is set - shown as a small repeat glyph inside
  // the chip so a recurring reminder reads as such at a glance, not just
  // like any other one-off reminder (see the same reasoning in
  // reminders_screen.dart's own list item).
  final bool repeats;
  final Color textColor;

  const _ReminderChip({
    required this.reminderAt,
    required this.resolved,
    required this.repeats,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isPast = reminderAt.isBefore(DateTime.now());
    if (!isPast) {
      return _chip(color: Colors.green, icon: Icons.alarm);
    }

    return _chip(
      color: resolved ? Colors.red : Colors.amber,
      icon: Icons.alarm_off,
    );
  }

  Widget _chip({required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            DateFormat('MMM d, h:mm a').format(reminderAt),
            style: TextStyle(fontSize: 11, color: textColor),
          ),
          if (repeats) ...[
            const SizedBox(width: 4),
            Icon(Icons.repeat, size: 12, color: textColor),
          ],
        ],
      ),
    );
  }
}
