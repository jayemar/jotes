import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:jotes/widgets/note_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Note _note(
  String id, {
  String title = '',
  DateTime? reminderAt,
  DateTime? updated,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    reminderAt: reminderAt,
    created: now,
    updated: updated ?? now,
  );
}

class _FakeNotesNotifier extends NotesNotifier {
  _FakeNotesNotifier(this._initial);
  final List<Note> _initial;

  @override
  Future<List<Note>> build() async => _initial;

  /// Lets a test simulate a reorder (e.g. an edit bumping a note to the
  /// top under "last edited, newest first") without going through a real
  /// addOrUpdate round-trip - see the card-grid reflow group below.
  void setNotes(List<Note> notes) => state = AsyncData(notes);
}

Future<_FakeNotesNotifier> _pumpNotes(
  WidgetTester tester,
  List<Note> notes, {
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final notifier = _FakeNotesNotifier(notes);
  final container = ProviderContainer(
    overrides: [notesProvider.overrideWith(() => notifier)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('notes_view_menu')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the overflow menu sits to the right of the sync indicator and shows '
    'the current filter/layout/sort choices',
    (tester) async {
      await _pumpNotes(tester, [_note('a', title: 'Only note')]);

      expect(
        tester.getCenter(find.byKey(const Key('notes_view_menu'))).dx,
        greaterThan(
          tester.getCenter(find.byKey(const Key('sync_indicator_button'))).dx,
        ),
      );

      await _openMenu(tester);

      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('All notes'), findsOneWidget);
      expect(find.text('Layout'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Sort by'), findsOneWidget);
      expect(find.text('Last edited (newest first)'), findsOneWidget);
    },
  );

  group('reminder visibility icon (search field)', () {
    testWidgets(
      'sits at the right edge of the search field and defaults to the '
      '"all notes" icon',
      (tester) async {
        await _pumpNotes(tester, [_note('a', title: 'Only note')]);

        final searchField = find.byKey(const Key('search_field'));
        final visibilityButton = find.byKey(
          const Key('reminder_visibility_button'),
        );
        expect(visibilityButton, findsOneWidget);
        expect(
          tester.getCenter(visibilityButton).dx,
          greaterThan(tester.getCenter(searchField).dx),
        );
        expect(
          tester.widget<Icon>(
            find.descendant(of: visibilityButton, matching: find.byType(Icon)),
          ).icon,
          Icons.visibility_outlined,
        );
      },
    );

    testWidgets(
      'tapping it opens the same filter picker as the overflow menu\'s '
      'Filter option, and choosing "With reminders" narrows the grid and '
      'updates the icon',
      (tester) async {
        await _pumpNotes(
          tester,
          [
            _note('no-reminder', title: 'No reminder'),
            _note(
              'has-reminder',
              title: 'Has reminder',
              reminderAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ],
          // Same overflow-triggered narrow-column overflow the Filter
          // group above sidesteps - see its own comment.
          initialPrefs: {'notes_view_layout': 'list'},
        );

        await tester.tap(find.byKey(const Key('reminder_visibility_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('notes_view_option_withReminders')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Has reminder'), findsOneWidget);
        expect(find.text('No reminder'), findsNothing);
        expect(
          tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('reminder_visibility_button')),
              matching: find.byType(Icon),
            ),
          ).icon,
          Icons.alarm,
        );

        // The overflow menu's own Filter option reflects the same choice -
        // one shared piece of state behind both entry points.
        await _openMenu(tester);
        expect(find.text('With reminders'), findsOneWidget);
      },
    );

    testWidgets(
      'opens as a popup anchored right next to the icon, not a bottom '
      'sheet rising from the bottom of the screen',
      (tester) async {
        await _pumpNotes(tester, [_note('a', title: 'Only note')]);

        final iconBottom = tester
            .getBottomLeft(find.byKey(const Key('reminder_visibility_button')))
            .dy;

        await tester.tap(find.byKey(const Key('reminder_visibility_button')));
        await tester.pumpAndSettle();

        final optionTop = tester
            .getTopLeft(find.byKey(const Key('notes_view_option_all')))
            .dy;

        // A bottom sheet's own first option would land near the bottom of
        // the 600pt-tall test surface (well past 400) regardless of where
        // the icon that opened it sits; an anchored popup's first option
        // instead lands close beneath the icon itself.
        expect(optionTop, lessThan(iconBottom + 100));
      },
    );

    testWidgets(
      'choosing "Without reminders" via the icon shows the eye-off icon',
      (tester) async {
        await _pumpNotes(tester, [
          _note('a', title: 'No reminder'),
        ]);

        await tester.tap(find.byKey(const Key('reminder_visibility_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('notes_view_option_withoutReminders')),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('reminder_visibility_button')),
              matching: find.byType(Icon),
            ),
          ).icon,
          Icons.visibility_off_outlined,
        );
      },
    );
  });

  group('Filter', () {
    testWidgets(
      'choosing "With reminders" narrows the grid to only notes with a '
      'reminder set',
      (tester) async {
        // Pre-seeded to list layout - the masonry card grid's narrow
        // (<=180dp) columns overflow the reminder chip's own Row at this
        // test window's default width, an unrelated rendering issue this
        // test isn't about.
        await _pumpNotes(
          tester,
          [
            _note('no-reminder', title: 'No reminder'),
            _note(
              'has-reminder',
              title: 'Has reminder',
              reminderAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ],
          initialPrefs: {'notes_view_layout': 'list'},
        );

        await _openMenu(tester);
        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('notes_view_option_withReminders')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Has reminder'), findsOneWidget);
        expect(find.text('No reminder'), findsNothing);
      },
    );

    testWidgets(
      'a filter that matches nothing shows a filter-specific empty message, '
      'not the "no notes yet" one',
      (tester) async {
        await _pumpNotes(tester, [
          _note('no-reminder', title: 'No reminder'),
        ]);

        await _openMenu(tester);
        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('notes_view_option_withReminders')),
        );
        await tester.pumpAndSettle();

        expect(find.text('No notes match this filter.'), findsOneWidget);
        expect(find.textContaining('No notes yet'), findsNothing);
      },
    );
  });

  group('Layout', () {
    testWidgets(
      'defaults to the masonry card grid',
      (tester) async {
        await _pumpNotes(tester, [_note('a', title: 'Note')]);

        expect(find.byType(SliverMasonryGrid), findsOneWidget);
        expect(find.byType(SliverList), findsNothing);
      },
    );

    testWidgets(
      'choosing List switches to a single-column list of the same NoteCards',
      (tester) async {
        await _pumpNotes(tester, [
          _note('a', title: 'First'),
          _note('b', title: 'Second'),
        ]);

        await _openMenu(tester);
        await tester.tap(find.text('Layout'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('notes_view_option_list')));
        await tester.pumpAndSettle();

        expect(find.byType(SliverList), findsOneWidget);
        expect(find.byType(SliverMasonryGrid), findsNothing);
        expect(find.byType(NoteCard), findsNWidgets(2));
        // Full-width column: both cards share the same left edge.
        final cards = find.byType(NoteCard);
        expect(
          tester.getTopLeft(cards.at(0)).dx,
          tester.getTopLeft(cards.at(1)).dx,
        );
      },
    );
  });

  group(
    'card grid reflow (see SliverMasonryGrid\'s key in _NoteGrid)',
    () {
      testWidgets(
        'the masonry grid is keyed on the current note order, so it gets '
        'a fresh key once that order changes (e.g. an edit bumping a note '
        'to the top under "last edited, newest first")',
        (tester) async {
          final notes = [
            _note('a', title: 'First'),
            _note('b', title: 'Second'),
            _note('c', title: 'Third'),
          ];
          final notifier = await _pumpNotes(tester, notes);

          final keyBefore = tester
              .widget<SliverMasonryGrid>(find.byType(SliverMasonryGrid))
              .key;

          // Same notes, same order - re-pumping shouldn't change the key.
          notifier.setNotes(List.of(notes));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<SliverMasonryGrid>(find.byType(SliverMasonryGrid))
                .key,
            keyBefore,
          );

          // "a" moves to the front - simulating exactly what happens when
          // editing the last-sorted note bumps its `updated` timestamp
          // ahead of everything else (the screen re-sorts by `updated`
          // regardless of the raw list order passed in here).
          final edited = notes[0].copyWith(
            updated: DateTime.now().add(const Duration(days: 1)),
          );
          notifier.setNotes([edited, notes[1], notes[2]]);
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<SliverMasonryGrid>(find.byType(SliverMasonryGrid))
                .key,
            isNot(keyBefore),
          );
        },
      );
    },
  );

  group('Sort by', () {
    testWidgets(
      'choosing Title (A-Z) reorders the grid alphabetically',
      (tester) async {
        final now = DateTime.now();
        await _pumpNotes(tester, [
          _note('c', title: 'Cherry', updated: now),
          _note('a', title: 'Apple', updated: now.subtract(const Duration(days: 1))),
          _note('b', title: 'Banana', updated: now.subtract(const Duration(days: 2))),
        ]);

        await _openMenu(tester);
        await tester.tap(find.text('Sort by'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('notes_view_option_titleAZ')));
        await tester.pumpAndSettle();

        final titles = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(NoteCard),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .toList();
        expect(titles, ['Apple', 'Banana', 'Cherry']);
      },
    );
  });

  testWidgets(
    'choices survive rebuilding the screen (persisted via SharedPreferences)',
    (tester) async {
      final notes = [
        _note('a', title: 'First'),
        _note('b', title: 'Second'),
      ];
      await _pumpNotes(tester, notes);

      await _openMenu(tester);
      await tester.tap(find.text('Layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes_view_option_list')));
      await tester.pumpAndSettle();

      expect(find.byType(SliverList), findsOneWidget);

      // A fresh NotesScreen instance (e.g. after navigating away and back)
      // reads the same persisted choice back from SharedPreferences - a
      // brand-new ProviderContainer/notes provider, but deliberately not a
      // fresh SharedPreferences mock, so whatever setLayout above actually
      // persisted is still there to read back.
      final container2 = ProviderContainer(
        overrides: [notesProvider.overrideWith(() => _FakeNotesNotifier(notes))],
      );
      addTearDown(container2.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container2,
          child: const MaterialApp(home: NotesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SliverList), findsOneWidget);
      expect(find.byType(SliverMasonryGrid), findsNothing);
    },
  );
}
