import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/board.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/boards_provider.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/boards_screen.dart';
import 'package:jotes/screens/note_editor_screen.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Same in-memory test double as notes_screen_search_test.dart - filtering
/// (board scope included) is a pure client-side narrowing over provider
/// state, so it doesn't need real storage.
class _FakeNotesNotifier extends NotesNotifier {
  _FakeNotesNotifier(this._initial);
  final List<Note> _initial;

  @override
  Future<List<Note>> build() async => _initial;
}

/// Keeps the pushed BoardsScreen from touching real DbService I/O - this
/// file only cares that navigation happened, not anything BoardsScreen
/// itself does (that's covered by boards_screen_test.dart).
class _FakeEmptyBoardsNotifier extends BoardsNotifier {
  @override
  Future<List<Board>> build() async => [];
}

Note _note({required String title, String? boardId}) {
  final now = DateTime.now();
  return Note(
    id: _uuid.v4(),
    title: title,
    colorIndex: 0,
    created: now,
    updated: now,
    boardId: boardId,
  );
}

Board _board({String id = 'b1', String name = 'Groceries'}) {
  final now = DateTime.now();
  return Board(id: id, name: name, created: now, updated: now);
}

Future<void> _pumpNotesScreen(
  WidgetTester tester,
  List<Note> notes, {
  Board? board,
}) async {
  final container = ProviderContainer(
    overrides: [notesProvider.overrideWith(() => _FakeNotesNotifier(notes))],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: NotesScreen(board: board)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // NotificationAppearanceSettings (read whenever NoteEditorScreen builds -
  // see note_editor_screen_test.dart's own setUp for the same lesson) needs
  // a registered SharedPreferences mock to resolve at all, not just the
  // tests below that navigate into it.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with no board (default), shows every note', (tester) async {
    await _pumpNotesScreen(tester, [
      _note(title: 'In board', boardId: 'b1'),
      _note(title: 'Unfiled'),
    ]);

    expect(find.text('In board'), findsOneWidget);
    expect(find.text('Unfiled'), findsOneWidget);
  });

  testWidgets('scoped to a board, only shows that board\'s own notes', (
    tester,
  ) async {
    await _pumpNotesScreen(
      tester,
      [
        _note(title: 'In this board', boardId: 'b1'),
        _note(title: 'In another board', boardId: 'b2'),
        _note(title: 'Unfiled'),
      ],
      board: _board(id: 'b1'),
    );

    expect(find.text('In this board'), findsOneWidget);
    expect(find.text('In another board'), findsNothing);
    expect(find.text('Unfiled'), findsNothing);
  });

  testWidgets('search composes with the board scope', (tester) async {
    await _pumpNotesScreen(
      tester,
      [
        _note(title: 'Groceries', boardId: 'b1'),
        _note(title: 'Trip plan', boardId: 'b1'),
        _note(title: 'Groceries', boardId: 'b2'),
      ],
      // Deliberately distinct from any note title above - this board's own
      // name is also rendered as a header (see the header test below), and
      // reusing a note title here would make that header a second,
      // ambiguous match for find.text.
      board: _board(id: 'b1', name: 'Board one'),
    );

    await tester.enterText(find.byKey(const Key('search_field')), 'grocer');
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Trip plan'), findsNothing);
  });

  testWidgets(
    'scoped to a board, the board\'s name is shown as a header',
    (tester) async {
      await _pumpNotesScreen(
        tester,
        [_note(title: 'A note', boardId: 'b1')],
        board: _board(id: 'b1', name: 'Groceries'),
      );

      expect(find.text('Groceries'), findsOneWidget);
    },
  );

  testWidgets(
    'with no board, there is no name header (nothing to disambiguate)',
    (tester) async {
      await _pumpNotesScreen(tester, [_note(title: 'A note')]);

      expect(find.text('Groceries'), findsNothing);
    },
  );

  group('the leading icon', () {
    testWidgets('with no board, is the hamburger menu', (tester) async {
      await _pumpNotesScreen(tester, [_note(title: 'A note')]);

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('scoped to a board, is a back arrow instead', (tester) async {
      await _pumpNotesScreen(
        tester,
        [_note(title: 'A note', boardId: 'b1')],
        board: _board(id: 'b1'),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
    });

    testWidgets('tapping the back arrow pops the screen', (tester) async {
      final container = ProviderContainer(
        overrides: [
          notesProvider.overrideWith(
            () => _FakeNotesNotifier([_note(title: 'A note', boardId: 'b1')]),
          ),
        ],
      );
      addTearDown(container.dispose);
      // A single root route with a button that pushes NotesScreen(board:
      // ...) on top of it - MaterialApp already supplies its own Navigator,
      // so the back arrow's Navigator.pop has somewhere real to go, without
      // introducing a second, ambiguous Navigator of our own.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotesScreen(board: _board(id: 'b1')),
                  ),
                ),
                child: const Text('root'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('root'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(NotesScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });
  });

  group('the drawer', () {
    testWidgets('with no board, is reachable and has a Boards entry', (
      tester,
    ) async {
      await _pumpNotesScreen(tester, [_note(title: 'A note')]);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('boards_drawer_item')), findsOneWidget);
    });

    testWidgets('tapping Boards pushes BoardsScreen', (tester) async {
      final container = ProviderContainer(
        overrides: [
          notesProvider.overrideWith(
            () => _FakeNotesNotifier([_note(title: 'A note')]),
          ),
          boardsProvider.overrideWith(_FakeEmptyBoardsNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('boards_drawer_item')));
      await tester.pumpAndSettle();

      expect(find.byType(BoardsScreen), findsOneWidget);
    });

    testWidgets('scoped to a board, there is no drawer at all', (
      tester,
    ) async {
      await _pumpNotesScreen(
        tester,
        [_note(title: 'A note', boardId: 'b1')],
        board: _board(id: 'b1'),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNull);
    });
  });

  group('creating a note while scoped to a board', () {
    testWidgets('defaults the new note\'s board to the one being viewed', (
      tester,
    ) async {
      final board = _board(id: 'b1');
      await _pumpNotesScreen(tester, [], board: board);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final editor = tester.widget<NoteEditorScreen>(
        find.byType(NoteEditorScreen),
      );
      expect(editor.existing, isNull);
      expect(editor.initialBoardId, 'b1');
    });

    testWidgets(
      'opening an existing note from within a board does not override its '
      'own board (initialBoardId is only for brand-new notes)',
      (tester) async {
        final note = _note(title: 'Existing', boardId: 'b1');
        await _pumpNotesScreen(tester, [note], board: _board(id: 'b1'));

        await tester.tap(find.text('Existing'));
        await tester.pumpAndSettle();

        final editor = tester.widget<NoteEditorScreen>(
          find.byType(NoteEditorScreen),
        );
        expect(editor.existing?.id, note.id);
        expect(editor.initialBoardId, isNull);
      },
    );
  });
}
