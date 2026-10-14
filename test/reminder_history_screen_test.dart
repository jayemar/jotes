import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/models/repeat_rule.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/note_editor_screen.dart';
import 'package:jotes/screens/reminder_history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same in-memory test double pattern as reminders_screen_test.dart's own
/// _FakeNotesNotifier.
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
  DateTime? updated,
  RepeatRule? repeatRule,
  DateTime? reminderHandledAt,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    reminderAt: reminderAt,
    created: now,
    updated: updated ?? now,
    reminderResolved: reminderResolved,
    repeatRule: repeatRule,
    reminderHandledAt: reminderHandledAt,
  );
}

Future<ProviderContainer> _pumpHistoryScreen(
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
      child: const MaterialApp(home: ReminderHistoryScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  // Needed for NoteEditorScreen to build at all (see its own tests' setUp
  // for the same lesson) - only the "tapping opens the note" test below
  // actually pushes one, but this is harmless for the rest.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('resolvedReminders', () {
    test('includes only notes with a reminder that is actually resolved', () {
      final now = DateTime.now();
      final notes = [
        _note(id: 'resolved', reminderAt: now, reminderResolved: true),
        _note(id: 'unresolved', reminderAt: now, reminderResolved: false),
        _note(id: 'no-reminder', reminderResolved: true),
      ];

      final result = resolvedReminders(notes);

      expect(result.map((n) => n.id), ['resolved']);
    });

    test('sorts most-recently-handled (by reminderHandledAt) first', () {
      final now = DateTime.now();
      final notes = [
        _note(
          id: 'older',
          reminderAt: now,
          reminderResolved: true,
          reminderHandledAt: now.subtract(const Duration(days: 2)),
        ),
        _note(
          id: 'newer',
          reminderAt: now,
          reminderResolved: true,
          reminderHandledAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final result = resolvedReminders(notes);

      expect(result.map((n) => n.id), ['newer', 'older']);
    });

    test('falls back to sorting by updated for a note resolved before '
        'reminderHandledAt existed', () {
      final now = DateTime.now();
      final notes = [
        _note(
          id: 'older',
          reminderAt: now,
          reminderResolved: true,
          updated: now.subtract(const Duration(days: 2)),
        ),
        _note(
          id: 'newer',
          reminderAt: now,
          reminderResolved: true,
          reminderHandledAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final result = resolvedReminders(notes);

      expect(result.map((n) => n.id), ['newer', 'older']);
    });

    test('an empty note list produces an empty result', () {
      expect(resolvedReminders([]), isEmpty);
    });
  });

  testWidgets('shows "No resolved reminders yet" when there are none', (
    tester,
  ) async {
    await _pumpHistoryScreen(tester, [
      _note(id: 'a', title: 'Upcoming', reminderAt: DateTime.now()),
    ]);

    expect(find.text('No resolved reminders yet'), findsOneWidget);
  });

  testWidgets('lists resolved reminders, most recent first', (tester) async {
    final now = DateTime.now();
    await _pumpHistoryScreen(tester, [
      _note(
        id: 'a',
        title: 'Older',
        reminderAt: now,
        reminderResolved: true,
        reminderHandledAt: now.subtract(const Duration(days: 1)),
      ),
      _note(
        id: 'b',
        title: 'Newer',
        reminderAt: now,
        reminderResolved: true,
        reminderHandledAt: now,
      ),
      _note(id: 'c', title: 'Still upcoming', reminderAt: now),
    ]);

    expect(find.text('Still upcoming'), findsNothing);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles, hasLength(2));
    expect((tiles[0].title as Text).data, 'Newer');
    expect((tiles[1].title as Text).data, 'Older');
  });

  testWidgets(
    'shows both the reminder time and when it was handled',
    (tester) async {
      final reminderAt = DateTime(2026, 10, 9, 17, 32);
      final handledAt = DateTime(2026, 10, 11, 18, 27);
      await _pumpHistoryScreen(tester, [
        _note(
          id: 'a',
          title: 'Cancel Tidal',
          reminderAt: reminderAt,
          reminderResolved: true,
          reminderHandledAt: handledAt,
        ),
      ]);

      expect(find.textContaining('Reminder: Oct 9'), findsOneWidget);
      expect(find.textContaining('Handled: Oct 11'), findsOneWidget);
    },
  );

  testWidgets(
    'shows only the reminder time for a note resolved before '
    'reminderHandledAt existed',
    (tester) async {
      final reminderAt = DateTime(2026, 10, 9, 17, 32);
      await _pumpHistoryScreen(tester, [
        _note(
          id: 'a',
          title: 'Legacy resolve',
          reminderAt: reminderAt,
          reminderResolved: true,
        ),
      ]);

      expect(find.textContaining('Reminder: Oct 9'), findsOneWidget);
      expect(find.textContaining('Handled:'), findsNothing);
    },
  );

  testWidgets('a repeating resolved reminder shows a trailing repeat glyph', (
    tester,
  ) async {
    final now = DateTime.now();
    await _pumpHistoryScreen(tester, [
      _note(
        id: 'a',
        title: 'Repeating',
        reminderAt: now,
        reminderResolved: true,
        repeatRule: RepeatRule.preset(RepeatFrequency.daily),
      ),
    ]);

    expect(find.byIcon(Icons.repeat), findsOneWidget);
  });

  testWidgets('tapping a resolved reminder opens the note', (tester) async {
    final now = DateTime.now();
    await _pumpHistoryScreen(tester, [
      _note(
        id: 'a',
        title: 'Resolved note',
        reminderAt: now,
        reminderResolved: true,
      ),
    ]);

    await tester.tap(find.text('Resolved note'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditorScreen), findsOneWidget);
  });
}
