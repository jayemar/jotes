import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../widgets/reminder_popup.dart';
import 'note_editor_screen.dart';

final _timeFormat = DateFormat('MMM d, h:mm a');

/// Every note with an active (already fired, not yet Dismissed/Snoozed) or
/// pending (upcoming) reminder, sorted oldest-first - the in-app equivalent
/// of the ReminderListWidget home-screen widget, sharing the same
/// [notesWithActiveOrPendingReminders] filter (see its own doc comment in
/// note.dart) so both always agree on what qualifies. Reached from the
/// drawer (see NotesScreen._buildDrawer).
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text("Couldn't load reminders: $error")),
        data: (notes) {
          final now = DateTime.now();
          final reminders = notesWithActiveOrPendingReminders(
            notes,
            now: now,
          );
          if (reminders.isEmpty) {
            return const Center(child: Text('No reminders'));
          }
          return ListView.separated(
            // Without this, the Scaffold's plain body (never wrapped in a
            // SafeArea) leaves the last row sitting flush against an
            // on-screen gesture/nav bar on an edge-to-edge display - same
            // fix as _NoteGrid's own bottomInset in notes_screen.dart.
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: reminders.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = reminders[index];
              final isOverdue = !note.reminderAt!.isAfter(now);
              return ListTile(
                key: ValueKey(note.id),
                leading: Icon(
                  isOverdue ? Icons.alarm_off : Icons.alarm,
                  color: isOverdue ? Colors.amber : Colors.green,
                ),
                title: Text(
                  note.title.isEmpty ? '(untitled)' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_timeFormat.format(note.reminderAt!)),
                // A small repeat glyph, not the rule's own full summary -
                // this list is a quick scan of what's active/pending, not
                // the place to review exactly how each one recurs (that's
                // ReminderEditScreen's job, reached by opening the note
                // itself). Same reasoning as note_card.dart's own
                // reminder chip.
                trailing: note.repeatRule != null
                    ? Icon(
                        Icons.repeat,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : null,
                // An overdue reminder is one that's already fired - the
                // same Open note/Snooze/Dismiss/Ignore choice as tapping
                // its actual tray notification would offer (see
                // reminder_popup.dart). An upcoming one hasn't fired yet,
                // so there's nothing to act on beyond looking at the note
                // itself, same as tapping it anywhere else in the app.
                onTap: () => isOverdue
                    ? showReminderPopup(context, ref, note)
                    : Navigator.push(
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
