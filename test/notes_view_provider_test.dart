import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_view_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Note _note({
  required String id,
  String title = '',
  DateTime? reminderAt,
  DateTime? created,
  DateTime? updated,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    reminderAt: reminderAt,
    created: created ?? now,
    updated: updated ?? now,
  );
}

void main() {
  group('applyNotesView', () {
    test('all filter keeps every note, regardless of reminder', () {
      final notes = [
        _note(id: 'a'),
        _note(id: 'b', reminderAt: DateTime(2026, 1, 1)),
      ];

      final result = applyNotesView(notes, NotesViewState.initial);

      expect(result.map((n) => n.id), containsAll(['a', 'b']));
    });

    test('withoutReminders keeps only notes with no reminder set', () {
      final notes = [
        _note(id: 'no-reminder'),
        _note(id: 'has-reminder', reminderAt: DateTime(2026, 1, 1)),
      ];

      final result = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.withoutReminders,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.updatedNewest,
        ),
      );

      expect(result.map((n) => n.id), ['no-reminder']);
    });

    test('withReminders keeps only notes with a reminder set', () {
      final notes = [
        _note(id: 'no-reminder'),
        _note(id: 'has-reminder', reminderAt: DateTime(2026, 1, 1)),
      ];

      final result = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.withReminders,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.updatedNewest,
        ),
      );

      expect(result.map((n) => n.id), ['has-reminder']);
    });

    test('updatedNewest sorts by updated, most recent first', () {
      final notes = [
        _note(id: 'oldest', updated: DateTime(2026, 1, 1)),
        _note(id: 'newest', updated: DateTime(2026, 3, 1)),
        _note(id: 'middle', updated: DateTime(2026, 2, 1)),
      ];

      final result = applyNotesView(notes, NotesViewState.initial);

      expect(result.map((n) => n.id), ['newest', 'middle', 'oldest']);
    });

    test('updatedOldest sorts by updated, oldest first', () {
      final notes = [
        _note(id: 'oldest', updated: DateTime(2026, 1, 1)),
        _note(id: 'newest', updated: DateTime(2026, 3, 1)),
      ];

      final result = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.all,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.updatedOldest,
        ),
      );

      expect(result.map((n) => n.id), ['oldest', 'newest']);
    });

    test('createdNewest/createdOldest sort by created, not updated', () {
      final notes = [
        _note(
          id: 'created-first-edited-last',
          created: DateTime(2026, 1, 1),
          updated: DateTime(2026, 5, 1),
        ),
        _note(
          id: 'created-last-edited-first',
          created: DateTime(2026, 4, 1),
          updated: DateTime(2026, 4, 2),
        ),
      ];

      final newestFirst = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.all,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.createdNewest,
        ),
      );
      expect(newestFirst.map((n) => n.id), [
        'created-last-edited-first',
        'created-first-edited-last',
      ]);

      final oldestFirst = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.all,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.createdOldest,
        ),
      );
      expect(oldestFirst.map((n) => n.id), [
        'created-first-edited-last',
        'created-last-edited-first',
      ]);
    });

    test('titleAZ/titleZA sort case-insensitively', () {
      final notes = [
        _note(id: 'banana', title: 'banana'),
        _note(id: 'Apple', title: 'Apple'),
        _note(id: 'cherry', title: 'cherry'),
      ];

      final az = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.all,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.titleAZ,
        ),
      );
      expect(az.map((n) => n.id), ['Apple', 'banana', 'cherry']);

      final za = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.all,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.titleZA,
        ),
      );
      expect(za.map((n) => n.id), ['cherry', 'banana', 'Apple']);
    });

    test('filter and sort compose together', () {
      final notes = [
        _note(
          id: 'no-reminder-newer',
          updated: DateTime(2026, 2, 1),
        ),
        _note(
          id: 'no-reminder-older',
          updated: DateTime(2026, 1, 1),
        ),
        _note(
          id: 'has-reminder',
          reminderAt: DateTime(2026, 1, 1),
          updated: DateTime(2026, 3, 1),
        ),
      ];

      final result = applyNotesView(
        notes,
        const NotesViewState(
          filter: NoteReminderFilter.withoutReminders,
          layout: NoteLayout.card,
          sortOrder: NoteSortOrder.updatedOldest,
        ),
      );

      expect(result.map((n) => n.id), [
        'no-reminder-older',
        'no-reminder-newer',
      ]);
    });
  });

  group('NotesViewNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to all/card/updatedNewest when nothing is persisted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(notesViewProvider);
      expect(state.filter, NoteReminderFilter.all);
      expect(state.layout, NoteLayout.card);
      expect(state.sortOrder, NoteSortOrder.updatedNewest);
    });

    test('setFilter/setLayout/setSortOrder each update independently',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(notesViewProvider.notifier);

      await notifier.setFilter(NoteReminderFilter.withReminders);
      await notifier.setLayout(NoteLayout.list);
      await notifier.setSortOrder(NoteSortOrder.titleAZ);

      final state = container.read(notesViewProvider);
      expect(state.filter, NoteReminderFilter.withReminders);
      expect(state.layout, NoteLayout.list);
      expect(state.sortOrder, NoteSortOrder.titleAZ);
    });

    test('choices persist for a freshly-built notifier', () async {
      final container1 = ProviderContainer();
      await container1
          .read(notesViewProvider.notifier)
          .setFilter(NoteReminderFilter.withoutReminders);
      await container1.read(notesViewProvider.notifier).setLayout(NoteLayout.list);
      await container1
          .read(notesViewProvider.notifier)
          .setSortOrder(NoteSortOrder.createdOldest);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      // NotifierProviders build lazily on first read - read once to trigger
      // build() (which kicks off an unawaited async load from
      // SharedPreferences), then give that load a turn to complete.
      container2.read(notesViewProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container2.read(notesViewProvider);
      expect(state.filter, NoteReminderFilter.withoutReminders);
      expect(state.layout, NoteLayout.list);
      expect(state.sortOrder, NoteSortOrder.createdOldest);
    });
  });
}
