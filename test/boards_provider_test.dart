import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/board.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/boards_provider.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/services/db_service.dart';
import 'package:jotes/services/widget_service.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Board _newBoard({String? id, String name = 'Board'}) {
  final now = DateTime.now();
  return Board(id: id ?? _uuid.v4(), name: name, created: now, updated: now);
}

Note _newNote({String? id, String? boardId}) {
  final now = DateTime.now();
  return Note(id: id ?? _uuid.v4(), created: now, updated: now, boardId: boardId);
}

void main() {
  setUpAll(() {
    DbService.instance.debugFactory = databaseFactoryMemory;
    WidgetService.instance.debugSyncAll = (_) async {};
  });

  // DbService is a process-wide singleton with a cached connection, so wipe
  // its tables between tests instead of trying to swap the instance out -
  // same reasoning as notes_provider_test.dart's own setUp.
  setUp(() async {
    for (final board in await DbService.instance.getAllBoards()) {
      await DbService.instance.deleteBoard(board.id);
    }
    for (final note in await DbService.instance.getAll()) {
      await DbService.instance.delete(note.id);
    }
  });

  group('DbService boards', () {
    test('upsertBoard creates a new row retrievable via getAllBoards', () async {
      final board = _newBoard(id: 'db-create', name: 'Groceries');
      await DbService.instance.upsertBoard(board);

      final all = await DbService.instance.getAllBoards();
      expect(all, hasLength(1));
      expect(all.single.id, 'db-create');
      expect(all.single.name, 'Groceries');
    });

    test(
      'upsertBoard with an existing id replaces the row instead of adding '
      'one',
      () async {
        final original = _newBoard(id: 'db-update', name: 'Original');
        await DbService.instance.upsertBoard(original);

        await DbService.instance.upsertBoard(
          original.copyWith(name: 'Updated'),
        );

        final all = await DbService.instance.getAllBoards();
        expect(all, hasLength(1));
        expect(all.single.name, 'Updated');
      },
    );

    test('deleteBoard removes the row', () async {
      final board = _newBoard(id: 'db-delete');
      await DbService.instance.upsertBoard(board);
      expect(await DbService.instance.getAllBoards(), hasLength(1));

      await DbService.instance.deleteBoard(board.id);

      expect(await DbService.instance.getAllBoards(), isEmpty);
    });
  });

  group('BoardsNotifier', () {
    test('addOrUpdate creates a board visible in provider state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final board = _newBoard(id: 'p-create', name: 'New board');
      await container.read(boardsProvider.notifier).addOrUpdate(board);

      final state = await container.read(boardsProvider.future);
      expect(state.map((b) => b.id), contains('p-create'));
    });

    test(
      'addOrUpdate with the same id updates in place, no duplicate',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final board = _newBoard(id: 'p-update', name: 'Before');
        await container.read(boardsProvider.notifier).addOrUpdate(board);
        await container
            .read(boardsProvider.notifier)
            .addOrUpdate(board.copyWith(name: 'After'));

        final state = await container.read(boardsProvider.future);
        final matches = state.where((b) => b.id == 'p-update');
        expect(matches, hasLength(1));
        expect(matches.single.name, 'After');
      },
    );

    test(
      'delete removes the board from provider state and from storage',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final board = _newBoard(id: 'p-delete');
        await container.read(boardsProvider.notifier).addOrUpdate(board);

        await container.read(boardsProvider.notifier).delete(board);

        final state = await container.read(boardsProvider.future);
        expect(state.map((b) => b.id), isNot(contains('p-delete')));
        final persisted = await DbService.instance.getAllBoards();
        expect(persisted.map((b) => b.id), isNot(contains('p-delete')));
      },
    );

    test(
      'delete un-files every note that was in the board, rather than '
      'leaving them pointing at a board id that no longer exists',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final board = _newBoard(id: 'p-delete-with-notes');
        await container.read(boardsProvider.notifier).addOrUpdate(board);

        await container
            .read(notesProvider.notifier)
            .addOrUpdate(_newNote(id: 'in-board', boardId: board.id));
        await container
            .read(notesProvider.notifier)
            .addOrUpdate(_newNote(id: 'in-other-board', boardId: 'other'));
        await container
            .read(notesProvider.notifier)
            .addOrUpdate(_newNote(id: 'unfiled'));

        await container.read(boardsProvider.notifier).delete(board);

        final notes = await container.read(notesProvider.future);
        final byId = {for (final n in notes) n.id: n};
        expect(byId['in-board']!.boardId, isNull);
        // Unaffected - not in the deleted board.
        expect(byId['in-other-board']!.boardId, 'other');
        expect(byId['unfiled']!.boardId, isNull);
      },
    );
  });
}
