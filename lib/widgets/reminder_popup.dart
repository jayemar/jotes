import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../screens/note_editor_screen.dart';
import '../services/notification_service.dart';

/// Shown when a fired reminder's tray notification is tapped (see
/// onNoteTapped/getLaunchNoteId in main.dart) - not shown automatically the
/// moment a reminder fires; see AndroidNotificationDetails.fullScreenIntent
/// in notification_service.dart, deliberately false, for why.
Future<void> showReminderPopup(BuildContext context, WidgetRef ref, Note note) {
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
          : Text(note.body, maxLines: 6, overflow: TextOverflow.ellipsis),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () {
                // Deliberately does not cancel the tray notification or
                // mark the reminder resolved - opening a note to look at
                // it isn't the same as deciding you're done with its
                // reminder. Only Dismiss/Snooze do that.
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
                // Explicit cancel first, not left to addOrUpdate's own
                // unconditional one below (which would cover it too, but
                // only for a NotesNotifier that actually calls through to
                // it - a test override might not) - same reasoning as
                // _snooze's own explicit cancel.
                try {
                  await NotificationService.instance.cancel(
                    note.notificationId,
                  );
                } catch (_) {}
                // Persisting reminderResolved: true (rather than the old
                // local-only markReminderResolved) is what makes Dismiss
                // sync: PbService.upsert pushes it to the server, the
                // realtime subscription carries it to every other device,
                // and SyncNotifier._handleRemoteEvent already cancels each
                // of their tray notifications on any note update - see
                // Note.reminderResolved's own doc comment. noteAfterDismiss
                // instead rolls reminderAt forward when the note repeats -
                // see its own doc comment.
                await ref
                    .read(notesProvider.notifier)
                    .addOrUpdate(noteAfterDismiss(note));
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
  // Marked resolved as soon as the old notification is cancelled, not only
  // once a new time is actually picked below - if the user backs out of
  // the pickers without choosing one, the old cycle is still done and
  // shouldn't reappear on a later restart or resync. (If they do pick a
  // new time, the addOrUpdate below sets reminderResolved back to false
  // for the fresh cycle.) Synced (not the old local-only
  // markReminderResolved) for the same cross-device reason as the Dismiss
  // button above - see Note.reminderResolved's own doc comment.
  await ref
      .read(notesProvider.notifier)
      .addOrUpdate(
        note.copyWith(reminderResolved: true, updated: DateTime.now()),
      );

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

  final newReminderAt = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  await ref
      .read(notesProvider.notifier)
      .addOrUpdate(
        note.copyWith(
          reminderAt: newReminderAt,
          reminderResolved: false,
          updated: DateTime.now(),
        ),
      );
}
