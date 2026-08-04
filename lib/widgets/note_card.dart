import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../services/notification_service.dart';
import 'note_body_editor.dart'
    show ChecklistBodyBlock, TextBodyBlock, checklistIndentStepPx, parseBody;

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
                  _NoteBodyPreview(body: note.body, textColor: textColor),
                if (note.reminderAt != null) ...[
                  const SizedBox(height: 8),
                  _ReminderChip(
                    noteId: note.id,
                    reminderAt: note.reminderAt!,
                    textColor: textColor,
                  ),
                ],
              ],
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

  const _NoteBodyPreview({required this.body, required this.textColor});

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
            _ChecklistPreviewRow(block: block, textColor: textColor),
          );
          linesUsed += 1;
        case TextBodyBlock():
          final remaining = _maxPreviewLines - linesUsed;
          children.add(
            Text(
              block.text,
              style: TextStyle(fontSize: 13, color: textColor.withAlpha(220)),
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

  const _ChecklistPreviewRow({required this.block, required this.textColor});

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              block.text,
              style: TextStyle(
                fontSize: 13,
                color: textColor.withAlpha(block.checked ? 140 : 220),
                decoration: block.checked ? TextDecoration.lineThrough : null,
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
/// (untriggered); amber once it's passed but nothing's been done about it
/// yet (Dismiss/Snooze - see NotificationService.isReminderResolved); red
/// once the user has acted on it (complete). A future reminder is always
/// green without needing the resolved check at all - schedule() already
/// clears any stale resolved flag when a note's next cycle begins, so
/// "still in the future" and "resolved" never meaningfully coexist.
class _ReminderChip extends StatelessWidget {
  final String noteId;
  final DateTime reminderAt;
  final Color textColor;

  const _ReminderChip({
    required this.noteId,
    required this.reminderAt,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isPast = reminderAt.isBefore(DateTime.now());
    if (!isPast) {
      return _chip(color: Colors.green, icon: Icons.alarm);
    }

    return FutureBuilder<bool>(
      future: NotificationService.instance.isReminderResolved(noteId),
      builder: (context, snapshot) {
        // Defaults to "not yet resolved" while the check is still pending -
        // safer to briefly under-claim completion than to flash red before
        // the real answer comes back.
        final resolved = snapshot.data ?? false;
        return _chip(
          color: resolved ? Colors.red : Colors.amber,
          icon: Icons.alarm_off,
        );
      },
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
        ],
      ),
    );
  }
}
