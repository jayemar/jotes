import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Note _note({required String title, String body = ''}) {
  final now = DateTime.now();
  return Note(
    id: _uuid.v4(),
    title: title,
    body: body,
    colorIndex: 0,
    created: now,
    updated: now,
  );
}

/// Same in-memory test double used in notes_screen_selection_test.dart -
/// search is a pure client-side filter over provider state, so it doesn't
/// need real storage either.
class _FakeNotesNotifier extends NotesNotifier {
  _FakeNotesNotifier(this._initial);
  final List<Note> _initial;

  @override
  Future<List<Note>> build() async => _initial;
}

Future<void> _pumpNotesScreen(WidgetTester tester, List<Note> notes) async {
  final container = ProviderContainer(
    overrides: [notesProvider.overrideWith(() => _FakeNotesNotifier(notes))],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the search field is present by default, with no toggle icon '
      'needed to open it', (tester) async {
    await _pumpNotesScreen(tester, [_note(title: 'Alpha')]);

    expect(find.byKey(const Key('search_field')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('typing filters notes by title', (tester) async {
    await _pumpNotesScreen(
      tester,
      [_note(title: 'Groceries'), _note(title: 'Trip plan')],
    );

    await tester.enterText(find.byKey(const Key('search_field')), 'trip');
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsNothing);
    expect(find.text('Trip plan'), findsOneWidget);
  });

  testWidgets('typing also matches body content, case-insensitively',
      (tester) async {
    await _pumpNotesScreen(
      tester,
      [
        _note(title: 'Note A', body: 'remember the Milk'),
        _note(title: 'Note B', body: 'nothing relevant'),
      ],
    );

    await tester.enterText(find.byKey(const Key('search_field')), 'MILK');
    await tester.pumpAndSettle();

    expect(find.text('Note A'), findsOneWidget);
    expect(find.text('Note B'), findsNothing);
  });

  testWidgets('no matches shows a search-specific empty message',
      (tester) async {
    await _pumpNotesScreen(tester, [_note(title: 'Alpha')]);

    await tester.enterText(
      find.byKey(const Key('search_field')),
      'nothing matches this',
    );
    await tester.pumpAndSettle();

    expect(find.text('No notes match your search.'), findsOneWidget);
    expect(find.text('No notes yet.\nTap + to create one.'), findsNothing);
  });

  testWidgets('the clear button empties the search field and restores '
      'the full list', (tester) async {
    await _pumpNotesScreen(
      tester,
      [_note(title: 'Alpha'), _note(title: 'Beta')],
    );

    await tester.enterText(find.byKey(const Key('search_field')), 'Alpha');
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets('the search box is rounded and uses the default note color',
      (tester) async {
    await _pumpNotesScreen(tester, [_note(title: 'Alpha')]);

    final containerFinder = find
        .ancestor(
          of: find.byKey(const Key('search_field')),
          matching: find.byType(Container),
        )
        .first;
    final container = tester.widget<Container>(containerFinder);
    final decoration = container.decoration as BoxDecoration;

    expect(
      decoration.color,
      noteColorFor(tester.element(containerFinder), 0),
    );
    final radius = decoration.borderRadius as BorderRadius;
    expect(radius.topLeft.x, greaterThan(0));
  });

  testWidgets('the hamburger menu opens a drawer with the jotes header and '
      'the Keep import action', (tester) async {
    await _pumpNotesScreen(tester, [_note(title: 'Alpha')]);

    expect(find.text('jotes'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('jotes'), findsOneWidget);
    expect(find.text('Import from Google Keep'), findsOneWidget);
  });
}
