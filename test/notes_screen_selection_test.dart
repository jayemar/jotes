import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Note _note({required String title, int colorIndex = 0}) {
  final now = DateTime.now();
  return Note(
    id: _uuid.v4(),
    title: title,
    body: '',
    colorIndex: colorIndex,
    created: now,
    updated: now,
  );
}

/// Test double that keeps notes in memory only, so this file exercises the
/// selection UI's wiring to the notifier without touching real storage or
/// notifications - that persistence behavior is already covered by
/// notes_provider_test.dart. Real sembast file I/O doesn't resolve within
/// flutter_test's fake-async pump cycle, so mixing it into a widget test
/// just hangs pumpAndSettle.
class _FakeNotesNotifier extends NotesNotifier {
  _FakeNotesNotifier(this._initial);
  final List<Note> _initial;

  @override
  Future<List<Note>> build() async => _initial;

  @override
  Future<String?> addOrUpdate(Note note) async {
    final current = state.value ?? const <Note>[];
    state = AsyncData([
      for (final n in current)
        if (n.id != note.id) n,
      note,
    ]);
    return null;
  }

  @override
  Future<void> delete(Note note) async {
    final current = state.value ?? const <Note>[];
    state = AsyncData(current.where((n) => n.id != note.id).toList());
  }
}

Future<ProviderContainer> _pumpNotesScreen(
  WidgetTester tester,
  List<Note> notes,
) async {
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
  return container;
}

void main() {
  testWidgets('long-press enters selection mode and shows the toolbar',
      (tester) async {
    await _pumpNotesScreen(
      tester,
      [_note(title: 'Alpha'), _note(title: 'Beta')],
    );

    // The search field (not a plain "jotes" title) is now the app bar's
    // default, non-selection-mode content.
    expect(find.byKey(const Key('search_field')), findsOneWidget);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('tapping another note while selecting adds it to the selection',
      (tester) async {
    await _pumpNotesScreen(
      tester,
      [_note(title: 'Alpha'), _note(title: 'Beta')],
    );

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('tapping a selected note again deselects it', (tester) async {
    await _pumpNotesScreen(tester, [_note(title: 'Alpha')]);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // The search field (not a plain "jotes" title) is now the app bar's
    // default, non-selection-mode content.
    expect(find.byKey(const Key('search_field')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('close button clears selection without changing notes',
      (tester) async {
    await _pumpNotesScreen(tester, [_note(title: 'Alpha')]);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // The search field (not a plain "jotes" title) is now the app bar's
    // default, non-selection-mode content.
    expect(find.byKey(const Key('search_field')), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets(
      'system back while notes are selected clears the selection '
      'instead of popping the screen', (tester) async {
    await _pumpNotesScreen(
      tester,
      [_note(title: 'Alpha'), _note(title: 'Beta')],
    );

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    // Simulates the Android hardware/gesture back button, which is what
    // actually routes through PopScope on the root route - unlike
    // Navigator.maybePop(), which doesn't reflect real back-button behavior
    // for the sole/initial route in the stack.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // The search field (not a plain "jotes" title) is now the app bar's
    // default, non-selection-mode content.
    expect(find.byKey(const Key('search_field')), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('delete action removes only the selected notes',
      (tester) async {
    await _pumpNotesScreen(tester, [
      _note(title: 'Alpha'),
      _note(title: 'Beta'),
      _note(title: 'Gamma'),
    ]);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsOneWidget);
    // The search field (not a plain "jotes" title) is now the app bar's
    // default, non-selection-mode content.
    expect(find.byKey(const Key('search_field')), findsOneWidget);
  });

  testWidgets('color action recolors selected notes and clears selection',
      (tester) async {
    final container = await _pumpNotesScreen(tester, [
      _note(title: 'Alpha', colorIndex: 0),
      _note(title: 'Beta', colorIndex: 0),
      _note(title: 'Gamma', colorIndex: 0),
    ]);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color_swatch_1'))); // red
    await tester.pumpAndSettle();

    // The search field (not a plain "jotes" title) is now the app bar's
    // default, non-selection-mode content.
    expect(find.byKey(const Key('search_field')), findsOneWidget);

    final notes = container.read(notesProvider).value!;
    final byTitle = {for (final n in notes) n.title: n.colorIndex};
    expect(byTitle['Alpha'], 1);
    expect(byTitle['Beta'], 1);
    expect(byTitle['Gamma'], 0);
  });
}
