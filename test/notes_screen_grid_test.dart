import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:jotes/widgets/note_card.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Note _note(String title) {
  final now = DateTime.now();
  return Note(
    id: _uuid.v4(),
    title: title,
    body: '',
    colorIndex: 0,
    created: now,
    updated: now,
  );
}

class _FakeNotesNotifier extends NotesNotifier {
  _FakeNotesNotifier(this._initial);
  final List<Note> _initial;

  @override
  Future<List<Note>> build() async => _initial;
}

Future<void> _pumpAtWidth(
  WidgetTester tester,
  double width,
  List<Note> notes,
) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

/// Counts how many NoteCards share the same top y-offset as the first one,
/// i.e. how many columns actually got laid out in the first row.
int _columnsInFirstRow(WidgetTester tester) {
  final cards = find.byType(NoteCard);
  final count = tester.widgetList(cards).length;
  final firstY = tester.getTopLeft(cards.at(0)).dy;
  var columns = 0;
  for (var i = 0; i < count; i++) {
    if (tester.getTopLeft(cards.at(i)).dy != firstY) break;
    columns++;
  }
  return columns;
}

void main() {
  // Column counts below are exact consequences of
  // SliverGridDelegateWithMaxCrossAxisExtent's own formula -
  // ceil(crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing)) - given
  // this grid's maxCrossAxisExtent: 180, crossAxisSpacing: 8, and the
  // SliverPadding.all(8) around the grid (16px off the raw screen width),
  // not values chosen to match observed output.

  testWidgets('a narrow (~360dp) screen lays out 2 columns', (tester) async {
    final notes = List.generate(6, (i) => _note('Note $i'));
    await _pumpAtWidth(tester, 360, notes);

    expect(_columnsInFirstRow(tester), 2);
  });

  testWidgets(
      'a wider (~400dp) screen automatically lays out 3 columns, with no '
      'hardcoded column count', (tester) async {
    final notes = List.generate(6, (i) => _note('Note $i'));
    await _pumpAtWidth(tester, 400, notes);

    expect(_columnsInFirstRow(tester), 3);
  });

  testWidgets('a wide viewport (e.g. web/tablet) lays out even more columns',
      (tester) async {
    final notes = List.generate(10, (i) => _note('Note $i'));
    await _pumpAtWidth(tester, 900, notes);

    expect(_columnsInFirstRow(tester), 5);
  });
}
