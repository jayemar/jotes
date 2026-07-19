import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../screens/note_editor_screen.dart';
import '../services/notification_service.dart';

/// Shown whenever a reminder actually fires and is opened - either by
/// tapping its tray notification, or via the full-screen takeover (see
/// AndroidNotificationDetails.fullScreenIntent in notification_service.dart),
/// which the plugin treats identically to a tap. A tray notification alone
/// is easy to miss or dismiss without reading; this is the "as well as"
/// the user asked for, not a replacement for it.
Future<void> showReminderPopup(
  BuildContext context,
  WidgetRef ref,
  Note note,
) {
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
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('reminder_popup_snooze'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _snooze(context, ref, note);
              },
              child: const Text('Snooze'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('reminder_popup_dismiss'),
              onPressed: () async {
                // Not fatal - see addOrUpdate in notes_provider.dart for
                // the same reasoning; the popup must still close even if
                // the tray notification fails to cancel.
                try {
                  await NotificationService.instance
                      .cancel(note.notificationId);
                } catch (_) {}
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Dismiss'),
            ),
            TextButton(
              key: const Key('reminder_popup_ignore'),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Ignore'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Cancels the tray notification (note.notificationId is stable across
/// edits, so rescheduling under the same id below naturally replaces it -
/// see NotesNotifier.addOrUpdate) and opens the same date/time picker flow
/// as setting a reminder from the note editor, saving the result as soon
/// as it's picked rather than deferring - there's no editor screen open
/// here to defer to.
Future<void> _snooze(BuildContext context, WidgetRef ref, Note note) async {
  try {
    await NotificationService.instance.cancel(note.notificationId);
  } catch (_) {
    // Not fatal - see addOrUpdate in notes_provider.dart for the same
    // reasoning.
  }

  if (!context.mounted) return;
  final now = DateTime.now();
  final initial = now.add(const Duration(hours: 1));
  // ignore: use_build_context_synchronously
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365 * 5)),
  );
  if (date == null || !context.mounted) return;

  // ignore: use_build_context_synchronously
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return;

  final newReminderAt =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  await ref.read(notesProvider.notifier).addOrUpdate(
        note.copyWith(reminderAt: newReminderAt, updated: DateTime.now()),
      );
}
