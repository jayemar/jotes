import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/services/notification_service.dart';
import 'package:jotes/widgets/reminder_popup.dart';

Note _note({
  DateTime? reminderAt,
  RepeatInterval repeatInterval = RepeatInterval.none,
}) {
  final now = DateTime.now();
  return Note(
    id: 'reminder-note-1',
    title: 'Take out the trash',
    body: 'Bins go out on Tuesday night',
    reminderAt: reminderAt,
    created: now,
    updated: now,
    repeatInterval: repeatInterval,
  );
}

/// Records every addOrUpdate call in memory instead of touching real
/// storage - real sembast file I/O doesn't resolve within flutter_test's
/// fake-async pump cycle, so it hangs pumpAndSettle (see
/// notes_screen_selection_test.dart/note_editor_screen_test.dart for the
/// same lesson). Used for every test here now that Dismiss/Snooze both
/// persist through addOrUpdate (see Note.reminderResolved), not just Snooze.
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

class _Harness {
  final BuildContext context;
  final WidgetRef ref;
  final _RecordingNotesNotifier recorder;
  const _Harness(this.context, this.ref, this.recorder);
}

Future<_Harness> _pumpHost(WidgetTester tester) async {
  final recorder = _RecordingNotesNotifier();
  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notesProvider.overrideWith(() => recorder)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, child) {
            capturedContext = context;
            capturedRef = ref;
            return const Scaffold();
          },
        ),
      ),
    ),
  );
  return _Harness(capturedContext, capturedRef, recorder);
}

void main() {
  final canceledIds = <int>[];

  setUp(() {
    canceledIds.clear();
    NotificationService.instance.debugOnCancel = canceledIds.add;
  });

  tearDown(() {
    NotificationService.instance.debugOnCancel = null;
  });

  testWidgets('shows the note\'s title and body', (tester) async {
    final host = await _pumpHost(tester);
    final note = _note();

    showReminderPopup(host.context, host.ref, note);
    await tester.pumpAndSettle();

    expect(find.text('Take out the trash'), findsOneWidget);
    expect(find.text('Bins go out on Tuesday night'), findsOneWidget);
    expect(find.byIcon(Icons.alarm), findsOneWidget);
  });

  testWidgets('falls back to "Reminder" as the title when the note has none', (
    tester,
  ) async {
    final host = await _pumpHost(tester);
    final note = _note().copyWith(title: '');

    showReminderPopup(host.context, host.ref, note);
    await tester.pumpAndSettle();

    expect(find.text('Reminder'), findsOneWidget);
  });

  testWidgets('shows all four actions', (tester) async {
    final host = await _pumpHost(tester);

    showReminderPopup(host.context, host.ref, _note());
    await tester.pumpAndSettle();

    expect(find.text('Open note'), findsOneWidget);
    expect(find.text('Snooze'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
  });

  testWidgets(
    'Dismiss closes the popup, cancels the tray notification, and '
    'persists reminderResolved on the note so it syncs to other devices',
    (tester) async {
      final host = await _pumpHost(tester);
      final note = _note();

      showReminderPopup(host.context, host.ref, note);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reminder_popup_dismiss')));
      await tester.pumpAndSettle();

      expect(find.text('Take out the trash'), findsNothing);
      expect(find.byKey(const Key('title_field')), findsNothing);
      expect(canceledIds, contains(note.notificationId));
      expect(host.recorder.saved, hasLength(1));
      expect(host.recorder.saved.single.id, note.id);
      expect(host.recorder.saved.single.reminderResolved, isTrue);
    },
  );

  testWidgets(
    'Dismiss on a repeating reminder rolls reminderAt forward to its next '
    'occurrence instead of just marking it resolved',
    (tester) async {
      final host = await _pumpHost(tester);
      final reminderAt = DateTime.now().add(const Duration(hours: 1));
      final note = _note(
        reminderAt: reminderAt,
        repeatInterval: RepeatInterval.daily,
      );

      showReminderPopup(host.context, host.ref, note);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reminder_popup_dismiss')));
      await tester.pumpAndSettle();

      expect(canceledIds, contains(note.notificationId));
      expect(host.recorder.saved, hasLength(1));
      final saved = host.recorder.saved.single;
      expect(saved.reminderResolved, isFalse);
      expect(saved.reminderAt, nextOccurrence(reminderAt, RepeatInterval.daily));
    },
  );

  testWidgets(
    'Ignore closes the popup but leaves the tray notification alone, and '
    'does not mark the reminder resolved',
    (tester) async {
      final host = await _pumpHost(tester);
      final note = _note();

      showReminderPopup(host.context, host.ref, note);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reminder_popup_ignore')));
      await tester.pumpAndSettle();

      expect(find.text('Take out the trash'), findsNothing);
      expect(find.byKey(const Key('title_field')), findsNothing);
      expect(canceledIds, isEmpty);
      expect(host.recorder.saved, isEmpty);
    },
  );

  testWidgets('Open note closes the popup and navigates to the editor, without '
      'cancelling the tray notification or marking the reminder resolved - '
      'looking at a note isn\'t the same as deciding you\'re done with its '
      'reminder', (tester) async {
    final host = await _pumpHost(tester);
    final note = _note();

    showReminderPopup(host.context, host.ref, note);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();

    // The popup itself is gone, and the note editor (identified by its
    // title field) is now showing with the same note's title loaded.
    expect(find.byKey(const Key('title_field')), findsOneWidget);
    expect(find.text('Take out the trash'), findsOneWidget);
    expect(canceledIds, isEmpty);
    expect(host.recorder.saved, isEmpty);
  });

  testWidgets('Snooze cancels the tray notification, then picking a new time '
      'saves the note with the updated reminder', (tester) async {
    final host = await _pumpHost(tester);
    final note = _note();

    showReminderPopup(host.context, host.ref, note);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reminder_popup_snooze')));
    await tester.pumpAndSettle();

    // The popup itself closed immediately, before any picker interaction.
    expect(find.text('Take out the trash'), findsNothing);
    expect(canceledIds, contains(note.notificationId));
    // The snooze immediately persists reminderResolved: true as a safety
    // net (see _snooze's own doc comment) before the pickers even open -
    // this is the first of two addOrUpdate calls this flow makes.
    expect(host.recorder.saved, hasLength(1));
    expect(host.recorder.saved.single.reminderResolved, isTrue);

    // Confirm the date picker, then the time picker, each with their
    // pre-filled initial value (same flow as note_editor_screen_test.dart).
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(host.recorder.saved, hasLength(2));
    final finalSave = host.recorder.saved.last;
    expect(finalSave.id, note.id);
    expect(finalSave.reminderAt, isNotNull);
    expect(finalSave.reminderAt!.isAfter(DateTime.now()), isTrue);
    // The fresh cycle starts unresolved again - see Note.reminderResolved.
    expect(finalSave.reminderResolved, isFalse);
  });
}
