import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/models/repeat_rule.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/note_editor_screen.dart';
import 'package:jotes/widgets/note_body_editor.dart';

void main() {
  _mainWidgetTests();
}

Note _existingNote({
  String body = 'One line',
  DateTime? reminderAt,
  RepeatRule? repeatRule,
  bool pinned = false,
}) {
  final now = DateTime.now();
  return Note(
    id: 'existing-1',
    title: 'Title',
    body: body,
    colorIndex: 0,
    reminderAt: reminderAt,
    created: now,
    updated: now,
    repeatRule: repeatRule,
    pinned: pinned,
  );
}

/// Records every addOrUpdate call in memory instead of touching real
/// storage - real sembast file I/O doesn't resolve within flutter_test's
/// fake-async pump cycle, so it hangs pumpAndSettle (see
/// notes_screen_selection_test.dart for the same lesson).
class _RecordingNotesNotifier extends NotesNotifier {
  _RecordingNotesNotifier([this._initial = const []]);
  final List<Note> _initial;
  final List<Note> saved = [];
  final List<Note> deleted = [];

  @override
  Future<List<Note>> build() async => _initial;

  @override
  Future<String?> addOrUpdate(Note note) async {
    saved.add(note);
    state = AsyncData([note]);
    return null;
  }

  @override
  Future<void> delete(Note note) async {
    deleted.add(note);
    state = const AsyncData([]);
  }

  /// Simulates an update landing through the realtime sync subscription
  /// from another device - see SyncNotifier._handleRemoteEvent, which ends
  /// the same way (an upsert into the local store followed by invalidating
  /// notesProvider) but isn't itself exercised here; this only needs to
  /// look, from NoteEditorScreen's point of view, like notesProvider's
  /// state changed out from under it.
  void pushRemoteUpdate(Note note) {
    state = AsyncData([note]);
  }
}

void _mainWidgetTests() {
  testWidgets('tapping the blank space below the body text focuses it and '
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
    'tapping the reminder pill for a brand-new note opens New reminder, '
    'pre-filled about an hour from now with no repeat and no delete icon '
    '(nothing exists yet to remove), and Save persists it immediately - '
    'not deferred until the screen is popped, and not discarded as an '
    'empty note',
    (tester) async {
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

      expect(find.text('New reminder'), findsOneWidget);
      expect(find.text('Does not repeat'), findsOneWidget);
      expect(find.byKey(const Key('reminder_edit_delete')), findsNothing);

      await tester.tap(find.byKey(const Key('reminder_edit_save')));
      await tester.pumpAndSettle();

      // Back on the note editor screen - never navigated further/popped
      // it, so if the save were still deferred to PopScope this would be
      // empty.
      expect(find.text('New reminder'), findsNothing);
      expect(notifier.saved, hasLength(1));
      expect(notifier.saved.single.title, isEmpty);
      expect(notifier.saved.single.body, isEmpty);
      expect(notifier.saved.single.reminderAt, isNotNull);
      expect(
        notifier.saved.single.reminderAt!.isAfter(DateTime.now()),
        isTrue,
      );
      expect(notifier.saved.single.repeatRule, isNull);
    },
  );

  testWidgets(
    'tapping the Date and Time rows opens their native pickers, and '
    'confirming a choice does not auto-advance off the reminder screen',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: NoteEditorScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Set reminder'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reminder_edit_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('New reminder'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reminder_edit_time')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('New reminder'), findsOneWidget);
    },
  );

  testWidgets(
    'picking Daily from the Repeat row before saving shows it selected in '
    'the sheet and updates the row, then carries both reminderAt and '
    'repeatRule together in the same save',
    (tester) async {
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
      await tester.tap(find.byKey(const Key('reminder_edit_repeat')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ListTile>(
              find.descendant(
                of: find.byKey(const Key('repeat_option_none')),
                matching: find.byType(ListTile),
              ),
            )
            .trailing,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('repeat_option_daily')));
      await tester.pumpAndSettle();

      expect(find.text('Daily'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reminder_edit_save')));
      await tester.pumpAndSettle();

      // A single save carrying both fields together, not a separate one
      // for the repeat setting.
      expect(notifier.saved, hasLength(1));
      expect(notifier.saved.single.reminderAt, isNotNull);
      expect(
        notifier.saved.single.repeatRule,
        RepeatRule.preset(RepeatFrequency.daily),
      );
    },
  );

  testWidgets(
    'tapping the close button discards any in-progress changes without '
    'saving',
    (tester) async {
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
      await tester.tap(find.byKey(const Key('reminder_edit_repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repeat_option_daily')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New reminder'), findsNothing);
      expect(notifier.saved, isEmpty);
    },
  );

  testWidgets(
    'tapping the reminder pill for an existing upcoming reminder opens '
    'Edit reminder, pre-filled with its current date/time/repeat, with a '
    'delete icon to remove it',
    (tester) async {
      final note = _existingNote(
        reminderAt: DateTime.now().add(const Duration(hours: 3)),
        repeatRule: RepeatRule.preset(RepeatFrequency.weekly),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.alarm));
      await tester.pumpAndSettle();

      expect(find.text('Edit reminder'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.byKey(const Key('reminder_edit_delete')), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the delete icon removes the reminder and saves immediately, '
    'not deferred until the screen is popped',
    (tester) async {
      final note = _existingNote(
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final notifier = _RecordingNotesNotifier();
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.alarm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminder_edit_delete')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.alarm), findsNothing);
      expect(find.byIcon(Icons.alarm_off), findsNothing);
      // Never navigated back / popped the screen - if the save were still
      // deferred to PopScope, this would be empty (same reasoning as the
      // brand-new-note-with-reminder test above).
      expect(notifier.saved, hasLength(1));
      expect(notifier.saved.single.reminderAt, isNull);
    },
  );

  testWidgets(
    'the reminder pill for an expired reminder still opens Edit reminder, '
    'pre-filled about an hour from now rather than the stale past time '
    "(which would crash the date picker's own initialDate/firstDate "
    'constraint), and Save succeeds with a new future time',
    (tester) async {
      final note = _existingNote(
        reminderAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final notifier = _RecordingNotesNotifier();
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      // The pill itself should already reflect the expired state.
      expect(find.byIcon(Icons.alarm_off), findsOneWidget);

      await tester.tap(find.byIcon(Icons.alarm_off));
      await tester.pumpAndSettle();

      expect(find.text('Edit reminder'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reminder_edit_save')));
      await tester.pumpAndSettle();

      expect(notifier.saved, isNotEmpty);
      expect(notifier.saved.last.reminderAt!.isAfter(DateTime.now()), isTrue);
    },
  );

  testWidgets(
    'the toolbar Undo button is disabled until a structural checklist '
    'change happens, then reverts it when tapped',
    (tester) async {
      final note = _existingNote(body: '- [ ] keep me\n- [ ] remove me');
      final notifier = _RecordingNotesNotifier();
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      Finder undoButton() => find.widgetWithIcon(IconButton, Icons.undo);

      expect(tester.widget<IconButton>(undoButton()).onPressed, isNull);

      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(find.text('remove me'), findsNothing);
      expect(tester.widget<IconButton>(undoButton()).onPressed, isNotNull);

      await tester.tap(undoButton());
      await tester.pumpAndSettle();

      expect(find.text('remove me'), findsOneWidget);
      expect(tester.widget<IconButton>(undoButton()).onPressed, isNull);
    },
  );

  testWidgets('the toolbar has a three-dot menu on the far right that reveals '
      '"Export as Markdown", rather than a direct icon button for it', (
    tester,
  ) async {
    final note = _existingNote(body: 'plain text');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: NoteEditorScreen(existing: note)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.ios_share_outlined), findsNothing);
    expect(find.byKey(const Key('note_more_menu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('note_more_menu')));
    await tester.pumpAndSettle();

    expect(find.text('Export as Markdown'), findsOneWidget);
  });

  testWidgets(
    'the three-dot menu also offers Share, Duplicate, and Delete for an '
    'existing note',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'the color picker lives in the overflow menu, not a direct toolbar '
    'icon button',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.palette_outlined), findsNothing);

      final menuBottom = tester
          .getBottomLeft(find.byKey(const Key('note_more_menu')))
          .dy;

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Change color'), findsOneWidget);

      await tester.tap(find.text('Change color'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('color_swatch_2')), findsOneWidget);

      // Opens as a popup anchored near the overflow menu button, not a
      // bottom sheet rising from the bottom of the screen.
      final swatchTop = tester
          .getTopLeft(find.byKey(const Key('color_swatch_2')))
          .dy;
      expect(swatchTop, lessThan(menuBottom + 150));

      await tester.tap(find.byKey(const Key('color_swatch_2')));
      await tester.pumpAndSettle();
      // Change color only marks the note dirty and starts the same
      // debounced autosave as typing does - it doesn't save immediately.
      await tester.pump(const Duration(seconds: 3));

      expect(notifier.saved.single.colorIndex, 2);
    },
  );

  testWidgets(
    'the overflow menu offers Pin for an unpinned note, and tapping it '
    'saves immediately (not deferred to the debounced autosave) since '
    'pinning is meant to be seen back on the notes list right away',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Unpin'), findsNothing);

      await tester.tap(find.text('Pin'));
      // No debounce wait - a save should already have happened.
      await tester.pumpAndSettle();

      expect(notifier.saved.single.pinned, isTrue);
    },
  );

  testWidgets(
    'the overflow menu offers Unpin (not Pin) for an already-pinned note, '
    'and tapping it unpins',
    (tester) async {
      final note = _existingNote(body: 'plain text', pinned: true);
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Unpin'), findsOneWidget);
      expect(find.text('Pin'), findsNothing);

      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();

      expect(notifier.saved.single.pinned, isFalse);
    },
  );

  testWidgets(
    'the move-line toolbar buttons are disabled until the body is actively '
    'being edited, then move the current line past its neighbor',
    (tester) async {
      final note = _existingNote(body: 'First line\nSecond line');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      Finder upButton() =>
          find.widgetWithIcon(IconButton, Icons.arrow_upward_outlined);
      expect(tester.widget<IconButton>(upButton()).onPressed, isNull);

      // "First line\nSecond line" has no checklist markers, so it parses as
      // one combined text block - focusBody() gives a deterministic cursor
      // position (offset 0, on "First line") rather than relying on
      // exactly where a tap on the whole two-line block happens to land.
      final bodyState = tester.state<NoteBodyEditorState>(
        find.byType(NoteBodyEditor),
      );
      bodyState.focusBody();
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(upButton()).onPressed, isNotNull);

      await tester.tap(find.byIcon(Icons.arrow_downward_outlined));
      await tester.pumpAndSettle();

      expect(
        tester.testTextInput.editingState?['text'],
        'Second line\nFirst line',
      );
    },
  );

  testWidgets(
    'Duplicate and Delete are offered right away for a brand-new, '
    'never-saved note, not just once it has been saved',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: NoteEditorScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'choosing Duplicate on a brand-new, never-saved note persists it '
    'immediately (rather than requiring the autosave debounce to have '
    'already fired) before duplicating it',
    (tester) async {
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

      await tester.enterText(
        find.byKey(const Key('title_field')),
        'Brand new note',
      );
      // Not saved yet - the autosave debounce hasn't elapsed.
      expect(notifier.saved, isEmpty);

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // The original was persisted immediately as part of opening the
      // Duplicate flow, before the title dialog's own save.
      expect(notifier.saved, hasLength(1));
      expect(notifier.saved.single.title, 'Brand new note');

      await tester.tap(find.widgetWithText(FilledButton, 'Duplicate'));
      await tester.pumpAndSettle();

      expect(notifier.saved, hasLength(2));
      final copy = notifier.saved.last;
      expect(copy.id, isNot(notifier.saved.first.id));
      expect(copy.title, 'Brand new note');
    },
  );

  testWidgets(
    'choosing Delete on a brand-new note that is still completely empty '
    'just closes the screen, with no confirmation and nothing persisted - '
    "there's nothing to delete yet",
    (tester) async {
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

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete note?'), findsNothing);
      expect(notifier.saved, isEmpty);
      expect(notifier.deleted, isEmpty);
      expect(find.byKey(const Key('title_field')), findsNothing);
    },
  );

  testWidgets(
    'choosing Delete on a brand-new note that has content persists it '
    'immediately, then deletes it after confirmation',
    (tester) async {
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

      await tester.enterText(
        find.byKey(const Key('title_field')),
        'Delete me',
      );
      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Persisted before the confirmation dialog even shows.
      expect(notifier.saved, hasLength(1));
      expect(notifier.saved.single.title, 'Delete me');
      expect(find.text('Delete note?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(notifier.deleted, hasLength(1));
      expect(notifier.deleted.single.id, notifier.saved.single.id);
      expect(find.byKey(const Key('title_field')), findsNothing);
    },
  );

  testWidgets(
    'choosing Duplicate from the menu prompts for a title (pre-filled with '
    "the original note's own title), then saves a duplicate with a fresh "
    'id and no reminder, staying on the original note',
    (tester) async {
      final note = _existingNote(
        body: 'plain text',
      ).copyWith(reminderAt: DateTime.now().add(const Duration(hours: 1)));
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      expect(notifier.saved, isEmpty); // not saved until the title's confirmed
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('duplicate_note_title_field')),
            )
            .controller!
            .text,
        note.title,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Duplicate'));
      await tester.pumpAndSettle();

      expect(notifier.saved, hasLength(1));
      final copy = notifier.saved.single;
      expect(copy.id, isNot(note.id));
      expect(copy.title, note.title);
      expect(copy.body, note.body);
      expect(copy.reminderAt, isNull);
      expect(find.text('Note duplicated'), findsOneWidget);

      // Still on the original note, not navigated away.
      expect(find.byTooltip('Reminder options'), findsOneWidget);
    },
  );

  testWidgets(
    'editing the pre-filled title before confirming Duplicate uses the '
    'edited title, not the original',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('duplicate_note_title_field')),
        'A distinct duplicate title',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Duplicate'));
      await tester.pumpAndSettle();

      expect(notifier.saved.single.title, 'A distinct duplicate title');
    },
  );

  testWidgets(
    'cancelling the Duplicate title dialog does not create a duplicate',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(notifier.saved, isEmpty);
      expect(find.byKey(const Key('duplicate_note_title_field')), findsNothing);
    },
  );

  testWidgets(
    'choosing Delete asks for confirmation first; cancelling leaves the '
    'note untouched and the screen open',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete note?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(notifier.deleted, isEmpty);
      expect(find.byKey(const Key('title_field')), findsOneWidget);
    },
  );

  testWidgets('confirming Delete removes the note and closes the screen', (
    tester,
  ) async {
    final note = _existingNote(body: 'plain text');
    final notifier = _RecordingNotesNotifier([note]);
    final container = ProviderContainer(
      overrides: [notesProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NoteEditorScreen(existing: note),
                    ),
                  ),
                  child: const Text('open note'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open note'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('note_more_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final deleteButtons = find.widgetWithText(FilledButton, 'Delete');
    await tester.tap(deleteButtons);
    await tester.pumpAndSettle();

    expect(notifier.deleted, [note]);
    // Back on the launcher screen, note screen popped.
    expect(find.text('open note'), findsOneWidget);
    expect(find.byKey(const Key('title_field')), findsNothing);
  });

  testWidgets(
    'pressing Enter/Next in the title field moves focus into the note '
    'body, landing at its very start',
    (tester) async {
      final note = _existingNote(body: 'existing body text');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('title_field')));
      await tester.pumpAndSettle();

      final bodyState = tester.state<NoteBodyEditorState>(
        find.byType(NoteBodyEditor),
      );
      expect(bodyState.isEditingBody, isFalse);

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      expect(bodyState.isEditingBody, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body_edit_field')))
            .controller!
            .selection,
        const TextSelection.collapsed(offset: 0),
      );
    },
  );

  testWidgets(
    'the back button while the body editor is mid-edit backs out of edit '
    'mode instead of popping (and saving) the whole note screen',
    (tester) async {
      final note = _existingNote(body: 'plain text');
      final notifier = _RecordingNotesNotifier();
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('plain text'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);

      // Simulates the Android hardware/gesture back button, which is what
      // actually routes through PopScope on the root route - see the same
      // pattern/reasoning in notes_screen_selection_test.dart.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Still on the note screen (not popped/saved) - the reminder pill
      // button is only present on this screen, not wherever a pop would
      // have gone.
      expect(find.byTooltip('Set reminder'), findsOneWidget);
      expect(notifier.saved, isEmpty);

      // A second back press now genuinely pops (and saves) the screen,
      // confirming the first press only consumed the edit-mode exit.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(notifier.saved, hasLength(1));
    },
  );

  group('live sync while a note is open', () {
    testWidgets(
      'typing autosaves after a short pause, without needing to close the '
      'note - previously an open note only ever saved when the screen was '
      'popped',
      (tester) async {
        final note = _existingNote(body: 'original body');
        final notifier = _RecordingNotesNotifier([note]);
        final container = ProviderContainer(
          overrides: [notesProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: NoteEditorScreen(existing: note)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('title_field')),
          'New title',
        );
        // Not saved immediately - only after the debounce elapses.
        expect(notifier.saved, isEmpty);

        await tester.pump(const Duration(seconds: 3));

        expect(notifier.saved, hasLength(1));
        expect(notifier.saved.single.title, 'New title');
      },
    );

    testWidgets('an update to this note made on another device is applied live '
        "while this device's copy is open and untouched, so a second "
        'device can follow along as it changes', (tester) async {
      final note = _existingNote(body: 'original body');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      final remoteNote = note.copyWith(
        title: 'Edited elsewhere',
        body: 'new body from another device',
        updated: note.updated.add(const Duration(seconds: 1)),
      );
      notifier.pushRemoteUpdate(remoteNote);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('title_field')))
            .controller!
            .text,
        'Edited elsewhere',
      );
      expect(find.text('new body from another device'), findsOneWidget);
    });

    testWidgets('a remote update is not applied while this device has its own '
        "unsaved edits in flight, so it can't clobber what's being typed", (
      tester,
    ) async {
      final note = _existingNote(body: 'original body');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('title_field')),
        'Not yet saved',
      );
      await tester.pump();

      final remoteNote = note.copyWith(
        title: 'Edited elsewhere',
        updated: note.updated.add(const Duration(seconds: 1)),
      );
      notifier.pushRemoteUpdate(remoteNote);
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('title_field')))
            .controller!
            .text,
        'Not yet saved',
      );
    });

    testWidgets(
      'a remote update is not applied while the title field is focused, '
      'even with nothing typed yet, since resetting a focused field out '
      "from under the user's cursor would be jarring",
      (tester) async {
        final note = _existingNote(body: 'original body');
        final notifier = _RecordingNotesNotifier([note]);
        final container = ProviderContainer(
          overrides: [notesProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: NoteEditorScreen(existing: note)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('title_field')));
        await tester.pumpAndSettle();

        final remoteNote = note.copyWith(
          title: 'Edited elsewhere',
          updated: note.updated.add(const Duration(seconds: 1)),
        );
        notifier.pushRemoteUpdate(remoteNote);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('title_field')))
              .controller!
              .text,
          'Title',
        );
      },
    );

    testWidgets("this screen's own save echoing back through the realtime "
        'subscription is not reapplied to itself (it would be a harmless '
        'no-op content-wise, but would still reset the focused title '
        "field's cursor for no reason)", (tester) async {
      final note = _existingNote(body: 'original body');
      final notifier = _RecordingNotesNotifier([note]);
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteEditorScreen(existing: note)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('title_field')),
        'Saved by me',
      );
      await tester.pump(const Duration(seconds: 3));
      expect(notifier.saved, hasLength(1));

      // Focus the field again, as if the user tapped back into it right
      // after the autosave landed - the echoed update (already pushed
      // to `saved` above, mirroring what the real subscribe() -> upsert
      // -> invalidate chain would do) must not disturb it.
      await tester.tap(find.byKey(const Key('title_field')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('title_field')))
            .controller!
            .text,
        'Saved by me',
      );
    });
  });

  group('pre-filled from a share (see ShareIntentService)', () {
    testWidgets('the title and body fields are pre-filled from initialTitle/'
        'initialBody', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NoteEditorScreen(
              initialTitle: 'Shared title',
              initialBody: 'Shared body text',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('title_field')))
            .controller!
            .text,
        'Shared title',
      );
      expect(find.text('Shared body text'), findsOneWidget);
    });

    testWidgets(
      'a note pre-filled with shared text saves itself immediately, not '
      'deferred until the screen is popped - a share the user never even '
      'got a chance to reject must not be silently discarded if the app '
      'is left via the home button/task switcher instead of back',
      (tester) async {
        final notifier = _RecordingNotesNotifier();
        final container = ProviderContainer(
          overrides: [notesProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: NoteEditorScreen(initialBody: 'Shared body text'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(notifier.saved, hasLength(1));
        expect(notifier.saved.single.body, 'Shared body text');
      },
    );

    testWidgets(
      'initialTitle/initialBody are ignored for an existing note - only a '
      'brand-new note can be pre-filled from a share',
      (tester) async {
        final note = _existingNote(body: 'existing body');
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: NoteEditorScreen(
                existing: note,
                initialTitle: 'should be ignored',
                initialBody: 'should also be ignored',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('title_field')))
              .controller!
              .text,
          note.title,
        );
        expect(find.text('existing body'), findsOneWidget);
        expect(find.text('should be ignored'), findsNothing);
      },
    );
  });
}
