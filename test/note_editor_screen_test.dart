import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/note_editor_screen.dart';
import 'package:jotes/widgets/note_body_editor.dart';

Note _existingNote({String body = 'One line'}) {
  final now = DateTime.now();
  return Note(
    id: 'existing-1',
    title: 'Title',
    body: body,
    colorIndex: 0,
    created: now,
    updated: now,
  );
}

/// Records every addOrUpdate call in memory instead of touching real
/// storage - real sqflite_common_ffi I/O doesn't resolve within
/// flutter_test's fake-async pump cycle, so it hangs pumpAndSettle (see
/// notes_screen_selection_test.dart for the same lesson).
class _RecordingNotesNotifier extends NotesNotifier {
  final List<Note> saved = [];

  @override
  Future<List<Note>> build() async => const [];

  @override
  Future<String?> addOrUpdate(Note note) async {
    saved.add(note);
    state = AsyncData([note]);
    return null;
  }
}

void main() {
  testWidgets(
      'tapping the blank space below the body text focuses it and '
      'places the cursor at the end', (tester) async {
    final note = _existingNote(body: 'One line');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: NoteEditorScreen(existing: note)),
      ),
    );
    await tester.pumpAndSettle();

    // Editing an existing note does not autofocus, so nothing should be
    // focused/have the keyboard up yet.
    expect(tester.testTextInput.isVisible, isFalse);

    // Tap near the bottom of the body editor's box, well below where a
    // single line of text renders.
    final bodyBox = tester.getRect(find.byType(NoteBodyEditor));
    await tester.tapAt(Offset(bodyBox.center.dx, bodyBox.bottom - 4));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.testTextInput.editingState?['selectionBase'],
      note.body.length,
    );
  });

  testWidgets('tapping directly on existing body text places the cursor '
      'at the tapped offset, not just the end', (tester) async {
    final note = _existingNote(body: 'abcdefghij');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: NoteEditorScreen(existing: note)),
      ),
    );
    await tester.pumpAndSettle();

    // Tap right at the start of the visible text (top-left of the body
    // editor, where the first character renders) rather than in blank
    // space below it.
    final bodyBox = tester.getRect(find.byType(NoteBodyEditor));
    await tester.tapAt(Offset(bodyBox.left + 2, bodyBox.top + 8));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.editingState?['selectionBase'], lessThan(10));
  });

  testWidgets(
      'setting a reminder shows a confirmation snackbar with the chosen '
      'time', (tester) async {
    final notifier = _RecordingNotesNotifier();
    final container = ProviderContainer(
      overrides: [notesProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NoteEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set reminder'));
    await tester.pumpAndSettle();

    // Confirm the date picker, then the time picker, each with their
    // pre-filled initial value.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reminder set for'), findsOneWidget);
  });

  testWidgets(
      'a brand-new note with only a reminder set (no title or body) is '
      'saved and scheduled immediately, not deferred until the screen is '
      'popped, and not discarded as an empty note', (tester) async {
    final notifier = _RecordingNotesNotifier();
    final container = ProviderContainer(
      overrides: [notesProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NoteEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Never navigated back / popped the screen - if the save were still
    // deferred to PopScope, this would be empty.
    expect(notifier.saved, hasLength(1));
    expect(notifier.saved.single.title, isEmpty);
    expect(notifier.saved.single.body, isEmpty);
    expect(notifier.saved.single.reminderAt, isNotNull);
  });
}
