import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/reminders_view_provider.dart';
import '../widgets/reminder_popup.dart';
import 'note_editor_screen.dart';

final _timeFormat = DateFormat('MMM d, h:mm a');

/// Icon for the AppBar's own recurrence filter button, reflecting the
/// current [ReminderRecurrenceFilter] - same reasoning as notes_screen.dart's
/// own _reminderVisibilityIcon, a glance at the button alone should already
/// hint at what's currently hidden.
IconData _recurrenceFilterIcon(ReminderRecurrenceFilter filter) =>
    switch (filter) {
      ReminderRecurrenceFilter.all => Icons.filter_list,
      ReminderRecurrenceFilter.recurringOnly => Icons.repeat,
      ReminderRecurrenceFilter.singleFireOnly => Icons.filter_1,
    };

/// Icon for the AppBar's own status filter button - alarm_off (this list's
/// own icon for an overdue/unhandled row, see the trailing leading icon
/// below) when only unhandled reminders are shown, so the button's icon
/// already looks like the rows it's narrowing down to.
IconData _statusFilterIcon(ReminderStatusFilter filter) => switch (filter) {
  ReminderStatusFilter.all => Icons.filter_list,
  ReminderStatusFilter.unhandledOnly => Icons.alarm_off,
};

/// Every note with an active (already fired, not yet Dismissed/Snoozed) or
/// pending (upcoming) reminder, sorted oldest-first - the in-app equivalent
/// of the ReminderListWidget home-screen widget, sharing the same
/// [notesWithActiveOrPendingReminders] filter (see its own doc comment in
/// note.dart) so both always agree on what qualifies, further narrowed by
/// the AppBar's own recurring/single-fire and unhandled-only filters (see
/// reminders_view_provider.dart). Reached from the drawer (see
/// NotesScreen._buildDrawer).
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);
    final viewState = ref.watch(remindersViewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          PopupMenuButton<ReminderRecurrenceFilter>(
            key: const Key('reminders_recurrence_filter'),
            icon: Icon(_recurrenceFilterIcon(viewState.recurrenceFilter)),
            tooltip: 'Filter by recurrence',
            onSelected: (selected) => ref
                .read(remindersViewProvider.notifier)
                .setRecurrenceFilter(selected),
            itemBuilder: (context) => [
              for (final option in ReminderRecurrenceFilter.values)
                PopupMenuItem(
                  key: Key('reminders_recurrence_filter_option_${option.name}'),
                  value: option,
                  child: Row(
                    children: [
                      Expanded(child: Text(option.label)),
                      if (option == viewState.recurrenceFilter)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
          ),
          PopupMenuButton<ReminderStatusFilter>(
            key: const Key('reminders_status_filter'),
            icon: Icon(_statusFilterIcon(viewState.statusFilter)),
            tooltip: 'Filter by status',
            onSelected: (selected) => ref
                .read(remindersViewProvider.notifier)
                .setStatusFilter(selected),
            itemBuilder: (context) => [
              for (final option in ReminderStatusFilter.values)
                PopupMenuItem(
                  key: Key('reminders_status_filter_option_${option.name}'),
                  value: option,
                  child: Row(
                    children: [
                      Expanded(child: Text(option.label)),
                      if (option == viewState.statusFilter)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text("Couldn't load reminders: $error")),
        data: (notes) {
          final now = DateTime.now();
          final allReminders = notesWithActiveOrPendingReminders(
            notes,
            now: now,
          );
          if (allReminders.isEmpty) {
            return const Center(child: Text('No reminders'));
          }
          final reminders = applyRemindersView(
            allReminders,
            viewState,
            now: now,
          );
          if (reminders.isEmpty) {
            return const Center(child: Text('No matching reminders'));
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
