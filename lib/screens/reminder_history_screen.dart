import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import 'note_editor_screen.dart';

final _timeFormat = DateFormat('MMM d, h:mm a');

/// Every note whose reminder has actually been resolved (Dismiss, or a
/// repeating rule running its own course - see [Note.reminderResolved]'s
/// own doc comment), most-recently-resolved first.
///
/// This is a snapshot of current note state, not a true event log - jotes
/// doesn't keep one. A one-time reminder stays frozen here forever once
/// resolved, since nothing ever touches it again, but a *repeating*
/// reminder's own history is overwritten by its own next cycle the moment
/// it's dismissed again (reminderAt moves forward and reminderResolved
/// resets to false - see noteAfterDismiss) - so a repeat only ever shows
/// its most recently fired-and-resolved cycle here, never every past one.
List<Note> resolvedReminders(List<Note> notes) {
  final resolved =
      notes.where((n) => n.reminderAt != null && n.reminderResolved).toList()
        // Falls back to `updated` only for a note resolved before
        // reminderHandledAt existed - every new Dismiss/Snooze sets it, so
        // this is purely a one-time migration gap, not an ongoing
        // substitute (see Note.reminderHandledAt's own doc comment for why
        // `updated` alone isn't reliable enough to use normally).
        ..sort(
          (a, b) => (b.reminderHandledAt ?? b.updated).compareTo(
            a.reminderHandledAt ?? a.updated,
          ),
        );
  return resolved;
}

/// Every reminder that's already been handled, for reference - as opposed
/// to RemindersScreen's own list, which drops a reminder the moment
/// there's nothing left to act on (see notesWithActiveOrPendingReminders).
/// Reached from RemindersScreen's own AppBar.
class ReminderHistoryScreen extends ConsumerWidget {
  const ReminderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminder history')),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text("Couldn't load history: $error")),
        data: (notes) {
          final history = resolvedReminders(notes);
          if (history.isEmpty) {
            return const Center(child: Text('No resolved reminders yet'));
          }
          return ListView.separated(
            // Same reasoning as RemindersScreen's own bottomInset - the
            // Scaffold's plain body isn't wrapped in a SafeArea.
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = history[index];
              return ListTile(
                key: ValueKey(note.id),
                leading: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                ),
                title: Text(
                  note.title.isEmpty ? '(untitled)' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  note.reminderHandledAt != null
                      ? 'Reminder: ${_timeFormat.format(note.reminderAt!)}\n'
                            'Handled: ${_timeFormat.format(note.reminderHandledAt!)}'
                      // Resolved before reminderHandledAt existed - only
                      // the reminder time itself is known.
                      : 'Reminder: ${_timeFormat.format(note.reminderAt!)}',
                  maxLines: 2,
                ),
                isThreeLine: note.reminderHandledAt != null,
                trailing: note.repeatRule != null
                    ? Icon(
                        Icons.repeat,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : null,
                // Nothing left to act on (that's the whole point of this
                // screen) - same as tapping an upcoming reminder in
                // RemindersScreen itself, this just opens the note.
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(existing: note),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
