import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/services/notification_service.dart';
import 'package:jotes/widgets/reminder_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Records every addOrUpdate call in memory instead of touching real
/// storage - mirrors the same pattern in note_editor_screen_test.dart.
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
  const _Harness(this.context, this.ref);
}

Future<_Harness> _pumpHost(
  WidgetTester tester, {
  NotesNotifier Function()? notifier,
}) async {
  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (notifier != null) notesProvider.overrideWith(notifier)],
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
  return _Harness(capturedContext, capturedRef);
}

void main() {
  final canceledIds = <int>[];

  setUp(() {
    canceledIds.clear();
    NotificationService.instance.debugOnCancel = canceledIds.add;
    // markReminderResolved (Dismiss/Snooze/Open note) touches
    // SharedPreferences - unmocked, the plugin has no platform
    // implementation registered in this test environment.
    SharedPreferences.setMockInitialValues({});
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
    'Dismiss closes the popup, does not open the note, and cancels the '
    'tray notification',
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
      expect(
        await NotificationService.instance.debugIsReminderResolved(note.id),
        isTrue,
      );
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
      expect(
        await NotificationService.instance.debugIsReminderResolved(note.id),
        isFalse,
      );
    },
  );

  testWidgets(
    'Open note closes the popup, navigates to the editor, cancels the '
    'tray notification, and marks the reminder resolved',
    (tester) async {
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
      expect(canceledIds, contains(note.notificationId));
      expect(
        await NotificationService.instance.debugIsReminderResolved(note.id),
        isTrue,
      );
    },
  );

  testWidgets('Snooze cancels the tray notification, then picking a new time '
      'saves the note with the updated reminder', (tester) async {
    final recorder = _RecordingNotesNotifier();
    final host = await _pumpHost(tester, notifier: () => recorder);
    final note = _note();

    showReminderPopup(host.context, host.ref, note);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reminder_popup_snooze')));
    await tester.pumpAndSettle();

    // The popup itself closed immediately, before any picker interaction.
    expect(find.text('Take out the trash'), findsNothing);
    expect(canceledIds, contains(note.notificationId));
    expect(
      await NotificationService.instance.debugIsReminderResolved(note.id),
      isTrue,
    );

    // Confirm the date picker, then the time picker, each with their
    // pre-filled initial value (same flow as note_editor_screen_test.dart).
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(recorder.saved, hasLength(1));
    expect(recorder.saved.single.id, note.id);
    expect(recorder.saved.single.reminderAt, isNotNull);
    expect(recorder.saved.single.reminderAt!.isAfter(DateTime.now()), isTrue);
  });
}
