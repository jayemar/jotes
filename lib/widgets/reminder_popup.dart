import 'package:flutter/material.dart';
import '../models/note.dart';
import '../screens/note_editor_screen.dart';

/// Shown whenever a reminder actually fires and is opened - either by
/// tapping its tray notification, or via the full-screen takeover (see
/// AndroidNotificationDetails.fullScreenIntent in notification_service.dart),
/// which the plugin treats identically to a tap. A tray notification alone
/// is easy to miss or dismiss without reading; this is the "as well as"
/// the user asked for, not a replacement for it.
Future<void> showReminderPopup(BuildContext context, Note note) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.alarm, size: 40),
      title: Text(
        note.title.isEmpty ? 'Reminder' : note.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: note.body.isEmpty
          ? null
          : Text(
              note.body,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Dismiss'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoteEditorScreen(existing: note),
              ),
            );
          },
          child: const Text('Open note'),
        ),
      ],
    ),
  );
}
