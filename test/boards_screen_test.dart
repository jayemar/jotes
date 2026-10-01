import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/board.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/boards_provider.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/boards_screen.dart';
import 'package:jotes/screens/notes_screen.dart';

/// Keeps the pushed NotesScreen from touching real DbService I/O - this
/// file only cares that navigation happened with the right board, not
/// anything NotesScreen itself does (that's covered by its own tests).
class _FakeEmptyNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => [];
}

/// Same in-memory test double pattern as reminders_screen_test.dart's
/// _FakeNotesNotifier - avoids real DbService/PocketBase I/O (and any
/// notesProvider fan-out delete() does to un-file a board's notes) hanging
/// pumpAndSettle.
class _FakeBoardsNotifier extends BoardsNotifier {
  _FakeBoardsNotifier(this._boards);
  final List<Board> _boards;
  final List<Board> addedOrUpdated = [];
  final List<Board> deleted = [];

  @override
  Future<List<Board>> build() async => _boards;

  @override
  Future<void> addOrUpdate(Board board) async {
    addedOrUpdated.add(board);
    state = AsyncData([
      ..._boards.where((b) => b.id != board.id),
      board,
    ]);
  }

  @override
  Future<void> delete(Board board) async {
    deleted.add(board);
    state = AsyncData(_boards.where((b) => b.id != board.id).toList());
  }
}

Board _board({String id = 'b1', String name = 'Groceries'}) {
  final now = DateTime.now();
  return Board(id: id, name: name, created: now, updated: now);
}

Future<ProviderContainer> _pumpBoardsScreen(
  WidgetTester tester,
  List<Board> boards,
) async {
  final container = ProviderContainer(
    overrides: [boardsProvider.overrideWith(() => _FakeBoardsNotifier(boards))],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BoardsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows "No boards yet" when there are none', (tester) async {
    await _pumpBoardsScreen(tester, []);

    expect(find.text('No boards yet - tap + to create one'), findsOneWidget);
  });

  testWidgets('lists each board by name', (tester) async {
    await _pumpBoardsScreen(tester, [
      _board(id: 'a', name: 'Groceries'),
      _board(id: 'b', name: 'Work'),
    ]);

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('tapping a board pushes NotesScreen scoped to it', (
    tester,
  ) async {
    final board = _board(id: 'a', name: 'Groceries');
    final container = ProviderContainer(
      overrides: [
        boardsProvider.overrideWith(() => _FakeBoardsNotifier([board])),
        notesProvider.overrideWith(_FakeEmptyNotesNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BoardsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    final notesScreen = tester.widget<NotesScreen>(find.byType(NotesScreen));
    expect(notesScreen.board?.id, 'a');
  });

  group('creating a board', () {
    testWidgets('the "+" button opens a name dialog', (tester) async {
      await _pumpBoardsScreen(tester, []);

      await tester.tap(find.byKey(const Key('boards_create_fab')));
      await tester.pumpAndSettle();

      expect(find.text('New board'), findsOneWidget);
      expect(find.byKey(const Key('board_name_field')), findsOneWidget);
    });

    testWidgets('saving a name calls addOrUpdate and the board then appears', (
      tester,
    ) async {
      final container = await _pumpBoardsScreen(tester, []);

      await tester.tap(find.byKey(const Key('boards_create_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('board_name_field')),
        'Chores',
      );
      await tester.tap(find.byKey(const Key('board_name_save')));
      await tester.pumpAndSettle();

      final notifier =
          container.read(boardsProvider.notifier) as _FakeBoardsNotifier;
      expect(notifier.addedOrUpdated.map((b) => b.name), ['Chores']);
      expect(find.text('Chores'), findsOneWidget);
    });

    testWidgets('an empty name is not saved', (tester) async {
      final container = await _pumpBoardsScreen(tester, []);

      await tester.tap(find.byKey(const Key('boards_create_fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('board_name_save')));
      await tester.pumpAndSettle();

      final notifier =
          container.read(boardsProvider.notifier) as _FakeBoardsNotifier;
      expect(notifier.addedOrUpdated, isEmpty);
    });
  });

  group('the per-board menu', () {
    testWidgets('long-pressing a board opens Rename/Delete', (tester) async {
      await _pumpBoardsScreen(tester, [_board(id: 'a', name: 'Groceries')]);

      await tester.longPress(find.text('Groceries'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('board_menu_rename')), findsOneWidget);
      expect(find.byKey(const Key('board_menu_delete')), findsOneWidget);
    });

    testWidgets('the trailing menu button opens the same menu', (
      tester,
    ) async {
      await _pumpBoardsScreen(tester, [_board(id: 'a', name: 'Groceries')]);

      await tester.tap(find.byKey(const Key('board_menu_button_a')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('board_menu_rename')), findsOneWidget);
    });

    testWidgets(
      'Rename opens a dialog pre-filled with the current name; saving '
      'calls addOrUpdate with the new one',
      (tester) async {
        final container = await _pumpBoardsScreen(tester, [
          _board(id: 'a', name: 'Groceries'),
        ]);

        await tester.longPress(find.text('Groceries'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('board_menu_rename')));
        await tester.pumpAndSettle();

        expect(find.text('Rename board'), findsOneWidget);
        final field = tester.widget<TextField>(
          find.byKey(const Key('board_name_field')),
        );
        expect(field.controller?.text, 'Groceries');

        await tester.enterText(
          find.byKey(const Key('board_name_field')),
          'Shopping',
        );
        await tester.tap(find.byKey(const Key('board_name_save')));
        await tester.pumpAndSettle();

        final notifier =
            container.read(boardsProvider.notifier) as _FakeBoardsNotifier;
        expect(notifier.addedOrUpdated.single.name, 'Shopping');
        expect(find.text('Shopping'), findsOneWidget);
      },
    );

    testWidgets(
      'Delete asks for confirmation, mentioning notes go back to unsorted; '
      'cancelling leaves the board untouched',
      (tester) async {
        final container = await _pumpBoardsScreen(tester, [
          _board(id: 'a', name: 'Groceries'),
        ]);

        await tester.longPress(find.text('Groceries'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('board_menu_delete')));
        await tester.pumpAndSettle();

        expect(find.text('Delete "Groceries"?'), findsOneWidget);
        expect(
          find.textContaining('go back to unsorted'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Groceries'), findsOneWidget);
        final notifier =
            container.read(boardsProvider.notifier) as _FakeBoardsNotifier;
        expect(notifier.deleted, isEmpty);
      },
    );

    testWidgets('confirming Delete calls delete and removes the board', (
      tester,
    ) async {
      final container = await _pumpBoardsScreen(tester, [
        _board(id: 'a', name: 'Groceries'),
      ]);

      await tester.longPress(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('board_menu_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      final notifier =
          container.read(boardsProvider.notifier) as _FakeBoardsNotifier;
      expect(notifier.deleted.map((b) => b.id), ['a']);
      expect(find.text('No boards yet - tap + to create one'), findsOneWidget);
    });
  });
}
