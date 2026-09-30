import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

const _recurrenceFilterPrefsKey = 'reminders_view_recurrence_filter';
const _statusFilterPrefsKey = 'reminders_view_status_filter';

/// Which reminders RemindersScreen shows, narrowing by whether a note's
/// reminder repeats (see [Note.repeatRule]) - independent of
/// NoteReminderFilter (notes_view_provider.dart), which narrows the main
/// notes list by whether a reminder exists at all, not by how it fires.
enum ReminderRecurrenceFilter {
  all('All reminders'),
  recurringOnly('Recurring only'),
  singleFireOnly('Single-fire only');

  const ReminderRecurrenceFilter(this.label);

  /// Shown in the Reminders screen's own recurrence filter picker.
  final String label;
}

/// Whether RemindersScreen shows every active/pending reminder, or only
/// ones that have already fired and still need a response - the same
/// "unhandled" reminders a Dismiss/Snooze/Ignore popup would offer (see
/// showReminderPopup), as opposed to one that's merely upcoming and so
/// doesn't need anything from the user yet.
enum ReminderStatusFilter {
  all('All reminders'),
  unhandledOnly('Unhandled only');

  const ReminderStatusFilter(this.label);

  /// Shown in the Reminders screen's own status filter picker.
  final String label;
}

class RemindersViewState {
  final ReminderRecurrenceFilter recurrenceFilter;
  final ReminderStatusFilter statusFilter;

  const RemindersViewState({
    required this.recurrenceFilter,
    required this.statusFilter,
  });

  static const initial = RemindersViewState(
    recurrenceFilter: ReminderRecurrenceFilter.all,
    statusFilter: ReminderStatusFilter.all,
  );
}

/// Persisted (SharedPreferences, same pattern as NotesViewNotifier) so these
/// choices survive an app restart, matching how the main notes list's own
/// view preferences already do.
class RemindersViewNotifier extends Notifier<RemindersViewState> {
  @override
  RemindersViewState build() {
    _load();
    return RemindersViewState.initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final recurrenceFilter = ReminderRecurrenceFilter.values.firstWhere(
      (f) => f.name == prefs.getString(_recurrenceFilterPrefsKey),
      orElse: () => ReminderRecurrenceFilter.all,
    );
    final statusFilter = ReminderStatusFilter.values.firstWhere(
      (f) => f.name == prefs.getString(_statusFilterPrefsKey),
      orElse: () => ReminderStatusFilter.all,
    );
    state = RemindersViewState(
      recurrenceFilter: recurrenceFilter,
      statusFilter: statusFilter,
    );
  }

  Future<void> setRecurrenceFilter(ReminderRecurrenceFilter filter) async {
    state = RemindersViewState(
      recurrenceFilter: filter,
      statusFilter: state.statusFilter,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recurrenceFilterPrefsKey, filter.name);
  }

  Future<void> setStatusFilter(ReminderStatusFilter filter) async {
    state = RemindersViewState(
      recurrenceFilter: state.recurrenceFilter,
      statusFilter: filter,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusFilterPrefsKey, filter.name);
  }
}

final remindersViewProvider =
    NotifierProvider<RemindersViewNotifier, RemindersViewState>(
      RemindersViewNotifier.new,
    );

/// Applies [state]'s recurrence and status filters to [notes] - expected to
/// already be narrowed to notes with an active/pending reminder (see
/// notesWithActiveOrPendingReminders), same as [applyNotesView] is a pure
/// function pulled out for its own independent testability. [now] decides
/// which of [notes] count as "unhandled" under
/// [ReminderStatusFilter.unhandledOnly] - the same overdue check
/// RemindersScreen's own list rows use to choose their alarm/alarm_off icon.
List<Note> applyRemindersView(
  List<Note> notes,
  RemindersViewState state, {
  required DateTime now,
}) {
  final byRecurrence = switch (state.recurrenceFilter) {
    ReminderRecurrenceFilter.all => notes,
    ReminderRecurrenceFilter.recurringOnly =>
      notes.where((n) => n.repeatRule != null).toList(),
    ReminderRecurrenceFilter.singleFireOnly =>
      notes.where((n) => n.repeatRule == null).toList(),
  };
  return switch (state.statusFilter) {
    ReminderStatusFilter.all => byRecurrence,
    ReminderStatusFilter.unhandledOnly =>
      byRecurrence.where((n) => !n.reminderAt!.isAfter(now)).toList(),
  };
}
