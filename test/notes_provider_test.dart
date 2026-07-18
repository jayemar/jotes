import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Note _newNote({
  String? id,
  String title = 'Title',
  String body = 'Body',
  int colorIndex = 0,
  DateTime? reminderAt,
}) {
  final now = DateTime.now();
  return Note(
    id: id ?? _uuid.v4(),
    title: title,
    body: body,
    colorIndex: colorIndex,
    reminderAt: reminderAt,
    created: now,
    updated: now,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // DbService is a process-wide singleton with a cached connection, so wipe
  // its table between tests instead of trying to swap the instance out.
  setUp(() async {
    final existing = await DbService.instance.getAll();
    for (final note in existing) {
      await DbService.instance.delete(note.id);
    }
  });

  group('DbService', () {
    test('upsert creates a new row retrievable via getAll', () async {
      final note = _newNote(id: 'db-create', title: 'Groceries');
      await DbService.instance.upsert(note);

      final all = await DbService.instance.getAll();
      expect(all, hasLength(1));
      expect(all.single.id, 'db-create');
      expect(all.single.title, 'Groceries');
    });

    test('upsert with an existing id replaces the row instead of adding one',
        () async {
      final original = _newNote(id: 'db-update', title: 'Original');
      await DbService.instance.upsert(original);

      final updated = original.copyWith(title: 'Updated');
      await DbService.instance.upsert(updated);

      final all = await DbService.instance.getAll();
      expect(all, hasLength(1));
      expect(all.single.title, 'Updated');
    });

    test('delete removes the row', () async {
      final note = _newNote(id: 'db-delete');
      await DbService.instance.upsert(note);
      expect(await DbService.instance.getAll(), hasLength(1));

      await DbService.instance.delete(note.id);

      expect(await DbService.instance.getAll(), isEmpty);
    });

    test('getById returns the matching note', () async {
      await DbService.instance.upsert(_newNote(id: 'other'));
      final target = _newNote(id: 'db-get-by-id', title: 'Find me');
      await DbService.instance.upsert(target);

      final found = await DbService.instance.getById('db-get-by-id');

      expect(found, isNotNull);
      expect(found!.title, 'Find me');
    });

    test('getById returns null for an id that does not exist', () async {
      final found = await DbService.instance.getById('nope');
      expect(found, isNull);
    });
  });

  group('NotesNotifier', () {
    test('addOrUpdate creates a note visible in provider state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final note = _newNote(id: 'p-create', title: 'New note');
      await container.read(notesProvider.notifier).addOrUpdate(note);

      final state = await container.read(notesProvider.future);
      expect(state.map((n) => n.id), contains('p-create'));
    });

    test('addOrUpdate with the same id updates in place, no duplicate',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final note = _newNote(id: 'p-update', title: 'Before');
      await container.read(notesProvider.notifier).addOrUpdate(note);
      await container
          .read(notesProvider.notifier)
          .addOrUpdate(note.copyWith(title: 'After'));

      final state = await container.read(notesProvider.future);
      final matches = state.where((n) => n.id == 'p-update');
      expect(matches, hasLength(1));
      expect(matches.single.title, 'After');
    });

    test('delete removes the note from provider state and from storage',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final note = _newNote(id: 'p-delete');
      await container.read(notesProvider.notifier).addOrUpdate(note);
      expect(
        (await container.read(notesProvider.future)).map((n) => n.id),
        contains('p-delete'),
      );

      await container.read(notesProvider.notifier).delete(note);

      final state = await container.read(notesProvider.future);
      expect(state.map((n) => n.id), isNot(contains('p-delete')));

      // Assert against storage directly too, not just in-memory provider
      // state, so a delete that updates the UI but silently fails to
      // persist would still be caught.
      final persisted = await DbService.instance.getAll();
      expect(persisted.map((n) => n.id), isNot(contains('p-delete')));
    });

    test('addOrUpdate with a reminder does not prevent a later delete',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final note = _newNote(
        id: 'p-delete-with-reminder',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await container.read(notesProvider.notifier).addOrUpdate(note);

      await container.read(notesProvider.notifier).delete(note);

      final persisted = await DbService.instance.getAll();
      expect(
        persisted.map((n) => n.id),
        isNot(contains('p-delete-with-reminder')),
      );
    });

    test(
        'addOrUpdate returns the real scheduling error instead of silently '
        'swallowing it, while still saving the note - there is no '
        'registered notification platform in this test environment, so '
        'the real schedule() call genuinely throws here, exactly the class '
        'of failure that used to be invisible', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final note = _newNote(
        id: 'p-schedule-error',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final error =
          await container.read(notesProvider.notifier).addOrUpdate(note);

      expect(error, isNotNull);

      final persisted = await DbService.instance.getById('p-schedule-error');
      expect(persisted, isNotNull);
    });

    test(
        'addOrUpdate with no reminder returns no error, even though '
        'cancelling a stale notification also throws in this test '
        'environment - a cancel failure must not be mistaken for a '
        'schedule failure', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final note = _newNote(id: 'p-no-reminder');
      final error =
          await container.read(notesProvider.notifier).addOrUpdate(note);

      expect(error, isNull);
    });
  });
}
