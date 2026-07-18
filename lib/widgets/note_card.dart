import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';

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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.blue
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2.5 : 0.5,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.title.isNotEmpty) ...[
                  Text(
                    note.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                ],
                if (note.body.isNotEmpty)
                  Flexible(
                    child: Text(
                      note.body,
                      style: TextStyle(
                        fontSize: 13,
                        color: textColor.withAlpha(220),
                      ),
                      maxLines: 10,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                if (note.reminderAt != null) ...[
                  const SizedBox(height: 8),
                  _ReminderChip(
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

class _ReminderChip extends StatelessWidget {
  final DateTime reminderAt;
  final Color textColor;

  const _ReminderChip({required this.reminderAt, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final isPast = reminderAt.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPast ? Colors.red.withAlpha(40) : Colors.green.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPast ? Icons.alarm_off : Icons.alarm,
            size: 12,
            color: textColor,
          ),
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
