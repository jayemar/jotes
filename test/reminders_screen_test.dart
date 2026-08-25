import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/models/repeat_rule.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/note_editor_screen.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:jotes/screens/reminders_screen.dart';

/// Same in-memory test double pattern as notes_screen_sync_indicator_test.dart.
class _FakeNotesNotifier extends NotesNotifier {
  _FakeNotesNotifier(this._notes);
  final List<Note> _notes;

  @override
  Future<List<Note>> build() async => _notes;
}

Note _note({
  required String id,
  String title = '',
  DateTime? reminderAt,
  bool reminderResolved = false,
  RepeatRule? repeatRule,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    reminderAt: reminderAt,
    created: now,
    updated: now,
    reminderResolved: reminderResolved,
    repeatRule: repeatRule,
  );
}

Future<ProviderContainer> _pumpRemindersScreen(
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
      child: const MaterialApp(home: RemindersScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the drawer has a Reminders item that opens RemindersScreen', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [notesProvider.overrideWith(() => _FakeNotesNotifier(const []))],
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
    await tester.tap(find.byKey(const Key('reminders_drawer_item')));
    await tester.pumpAndSettle();

    expect(find.byType(RemindersScreen), findsOneWidget);
    expect(find.text('Reminders'), findsWidgets);
  });

  testWidgets('shows "No reminders" when nothing has a reminder set', (
    tester,
  ) async {
    await _pumpRemindersScreen(tester, [_note(id: 'a', title: 'Plain note')]);

    expect(find.text('No reminders'), findsOneWidget);
  });

  testWidgets(
    'lists notes with reminders sorted oldest-first, mixing overdue and '
    'upcoming, and excludes a resolved overdue one',
    (tester) async {
      final now = DateTime.now();
      await _pumpRemindersScreen(tester, [
        _note(
          id: 'upcoming',
          title: 'Upcoming',
          reminderAt: now.add(const Duration(hours: 2)),
        ),
        _note(
          id: 'overdue',
          title: 'Overdue',
          reminderAt: now.subtract(const Duration(hours: 1)),
        ),
        _note(
          id: 'resolved',
          title: 'Already handled',
          reminderAt: now.subtract(const Duration(days: 1)),
          reminderResolved: true,
        ),
      ]);

      expect(find.text('Already handled'), findsNothing);
      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .toList();
      expect(tiles, hasLength(2));
      // Oldest (overdue) first.
      expect((tiles[0].title as Text).data, 'Overdue');
      expect((tiles[1].title as Text).data, 'Upcoming');
    },
  );

  testWidgets('an untitled note falls back to "(untitled)"', (tester) async {
    await _pumpRemindersScreen(tester, [
      _note(id: 'a', reminderAt: DateTime.now().add(const Duration(hours: 1))),
    ]);

    expect(find.text('(untitled)'), findsOneWidget);
  });

  testWidgets(
    'tapping an overdue reminder opens the same Dismiss/Snooze/Ignore '
    'popup as tapping its actual tray notification would',
    (tester) async {
      await _pumpRemindersScreen(tester, [
        _note(
          id: 'overdue',
          title: 'Overdue reminder',
          reminderAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ]);

      await tester.tap(find.text('Overdue reminder'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reminder_popup_dismiss')), findsOneWidget);
      expect(find.byKey(const Key('reminder_popup_snooze')), findsOneWidget);
    },
  );

  testWidgets('tapping an upcoming reminder opens the note editor directly', (
    tester,
  ) async {
    await _pumpRemindersScreen(tester, [
      _note(
        id: 'upcoming',
        title: 'Upcoming reminder',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    ]);

    await tester.tap(find.text('Upcoming reminder'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.byKey(const Key('reminder_popup_dismiss')), findsNothing);
  });

  testWidgets('a repeating reminder shows a trailing repeat glyph, a '
      'non-repeating one does not', (tester) async {
    final now = DateTime.now();
    await _pumpRemindersScreen(tester, [
      _note(
        id: 'repeating',
        title: 'Repeating',
        reminderAt: now.add(const Duration(hours: 1)),
        repeatRule: RepeatRule.preset(RepeatFrequency.daily),
      ),
      _note(
        id: 'once',
        title: 'Once',
        reminderAt: now.add(const Duration(hours: 2)),
      ),
    ]);

    final repeatingTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Repeating'),
        matching: find.byType(ListTile),
      ),
    );
    final onceTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Once'), matching: find.byType(ListTile)),
    );

    expect(repeatingTile.trailing, isNotNull);
    expect(onceTile.trailing, isNull);
    expect(find.byIcon(Icons.repeat), findsOneWidget);
  });
}
