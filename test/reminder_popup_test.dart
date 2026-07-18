import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/widgets/reminder_popup.dart';

Note _note() {
  final now = DateTime.now();
  return Note(
    id: 'reminder-note-1',
    title: 'Take out the trash',
    body: 'Bins go out on Tuesday night',
    created: now,
    updated: now,
  );
}

/// build() only - nothing in this test saves or deletes, so no need for
/// the full recording-notifier machinery used in note_editor_screen_test.
class _StubNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => const [];
}

Future<BuildContext> _pumpHostAndGetContext(WidgetTester tester) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notesProvider.overrideWith(_StubNotesNotifier.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const Scaffold();
          },
        ),
      ),
    ),
  );
  return capturedContext;
}

void main() {
  testWidgets('shows the note\'s title and body', (tester) async {
    final context = await _pumpHostAndGetContext(tester);
    final note = _note();

    showReminderPopup(context, note);
    await tester.pumpAndSettle();

    expect(find.text('Take out the trash'), findsOneWidget);
    expect(find.text('Bins go out on Tuesday night'), findsOneWidget);
    expect(find.byIcon(Icons.alarm), findsOneWidget);
  });

  testWidgets('falls back to "Reminder" as the title when the note has none',
      (tester) async {
    final context = await _pumpHostAndGetContext(tester);
    final note = _note().copyWith(title: '');

    showReminderPopup(context, note);
    await tester.pumpAndSettle();

    expect(find.text('Reminder'), findsOneWidget);
  });

  testWidgets('Dismiss closes the popup without opening the note',
      (tester) async {
    final context = await _pumpHostAndGetContext(tester);

    showReminderPopup(context, _note());
    await tester.pumpAndSettle();
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Take out the trash'), findsNothing);
    expect(find.byKey(const Key('title_field')), findsNothing);
  });

  testWidgets('Open note closes the popup and navigates to the editor',
      (tester) async {
    final context = await _pumpHostAndGetContext(tester);

    showReminderPopup(context, _note());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();

    // The popup itself is gone, and the note editor (identified by its
    // title field) is now showing with the same note's title loaded.
    expect(find.byKey(const Key('title_field')), findsOneWidget);
    expect(find.text('Take out the trash'), findsOneWidget);
  });
}
