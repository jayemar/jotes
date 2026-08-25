import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

const _filterPrefsKey = 'notes_view_filter';
const _layoutPrefsKey = 'notes_view_layout';
const _sortOrderPrefsKey = 'notes_view_sort_order';

/// Which notes the grid/list shows, independent of the free-text search bar
/// (see NotesScreen._filterNotes) - this narrows by whether a reminder is
/// set at all, not by content.
enum NoteReminderFilter {
  all('All notes'),
  withoutReminders('Without reminders'),
  withReminders('With reminders');

  const NoteReminderFilter(this.label);

  /// Shown in the overflow menu's Filter option and its own picker sheet.
  final String label;
}

/// How notes are arranged - the existing staggered masonry grid
/// (SliverMasonryGrid, variable card heights packed into columns) or a
/// single full-width column, one note after another.
enum NoteLayout {
  card('Card'),
  list('List');

  const NoteLayout(this.label);

  /// Shown in the overflow menu's Layout option and its own picker sheet.
  final String label;
}

/// [updatedNewest] matches DbService's own default fetch order (see its
/// Finder) - the default here mirrors that instead of introducing a second,
/// different "default" sort.
enum NoteSortOrder {
  updatedNewest('Last edited (newest first)'),
  updatedOldest('Last edited (oldest first)'),
  createdNewest('Date created (newest first)'),
  createdOldest('Date created (oldest first)'),
  titleAZ('Title (A-Z)'),
  titleZA('Title (Z-A)');

  const NoteSortOrder(this.label);

  /// Shown in the overflow menu's Sort option and its own picker sheet.
  final String label;
}

class NotesViewState {
  final NoteReminderFilter filter;
  final NoteLayout layout;
  final NoteSortOrder sortOrder;

  const NotesViewState({
    required this.filter,
    required this.layout,
    required this.sortOrder,
  });

  static const initial = NotesViewState(
    filter: NoteReminderFilter.all,
    layout: NoteLayout.card,
    sortOrder: NoteSortOrder.updatedNewest,
  );
}

/// Persisted (SharedPreferences, same pattern as AppearanceNotifier) so the
/// notes screen's own view preferences - not note data itself - survive an
/// app restart, matching how font/text-size choices already do.
class NotesViewNotifier extends Notifier<NotesViewState> {
  @override
  NotesViewState build() {
    _load();
    return NotesViewState.initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final filter = NoteReminderFilter.values.firstWhere(
      (f) => f.name == prefs.getString(_filterPrefsKey),
      orElse: () => NoteReminderFilter.all,
    );
    final layout = NoteLayout.values.firstWhere(
      (l) => l.name == prefs.getString(_layoutPrefsKey),
      orElse: () => NoteLayout.card,
    );
    final sortOrder = NoteSortOrder.values.firstWhere(
      (s) => s.name == prefs.getString(_sortOrderPrefsKey),
      orElse: () => NoteSortOrder.updatedNewest,
    );
    state = NotesViewState(filter: filter, layout: layout, sortOrder: sortOrder);
  }

  Future<void> setFilter(NoteReminderFilter filter) async {
    state = NotesViewState(
      filter: filter,
      layout: state.layout,
      sortOrder: state.sortOrder,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterPrefsKey, filter.name);
  }

  Future<void> setLayout(NoteLayout layout) async {
    state = NotesViewState(
      filter: state.filter,
      layout: layout,
      sortOrder: state.sortOrder,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_layoutPrefsKey, layout.name);
  }

  Future<void> setSortOrder(NoteSortOrder sortOrder) async {
    state = NotesViewState(
      filter: state.filter,
      layout: state.layout,
      sortOrder: sortOrder,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortOrderPrefsKey, sortOrder.name);
  }
}

final notesViewProvider = NotifierProvider<NotesViewNotifier, NotesViewState>(
  NotesViewNotifier.new,
);

/// Applies [state]'s reminder filter and sort order to [notes] - pulled out
/// of NotesScreen as a pure function so both are independently testable
/// without pumping the whole screen. Composes with (runs after) the
/// separate free-text search filter in NotesScreen._filterNotes; sort
/// always applies last, regardless of what's already been narrowed out.
/// Ties within a sort (e.g. two notes with the same title) keep their
/// relative order from [notes] - Dart's List.sort is not guaranteed stable,
/// but DbService's own fetch order (updated desc) makes "newest edit wins
/// a tie" the practically-observed behavior for every sort here except
/// updatedNewest/updatedOldest themselves, where a tie is moot anyway.
List<Note> applyNotesView(List<Note> notes, NotesViewState state) {
  final filtered = switch (state.filter) {
    NoteReminderFilter.all => notes,
    NoteReminderFilter.withoutReminders =>
      notes.where((n) => n.reminderAt == null).toList(),
    NoteReminderFilter.withReminders =>
      notes.where((n) => n.reminderAt != null).toList(),
  };

  final sorted = [...filtered];
  sorted.sort((a, b) {
    return switch (state.sortOrder) {
      NoteSortOrder.updatedNewest => b.updated.compareTo(a.updated),
      NoteSortOrder.updatedOldest => a.updated.compareTo(b.updated),
      NoteSortOrder.createdNewest => b.created.compareTo(a.created),
      NoteSortOrder.createdOldest => a.created.compareTo(b.created),
      NoteSortOrder.titleAZ =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      NoteSortOrder.titleZA =>
        b.title.toLowerCase().compareTo(a.title.toLowerCase()),
    };
  });
  return sorted;
}
