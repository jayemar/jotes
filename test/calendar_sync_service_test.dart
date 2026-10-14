import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/calendar_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Note _note({
  required String id,
  String title = 'Title',
  String body = 'Body',
  DateTime? reminderAt,
  bool deleted = false,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    body: body,
    reminderAt: reminderAt,
    created: now,
    updated: now,
    deleted: deleted,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CalendarSyncService.instance.debugRequestPermission = () async => true;
  });

  tearDown(() {
    CalendarSyncService.instance.debugRequestPermission = null;
    CalendarSyncService.instance.debugAvailableCalendars = null;
    CalendarSyncService.instance.debugCreateOrUpdateEvent = null;
    CalendarSyncService.instance.debugDeleteEvent = null;
  });

  group('isEnabled/setEnabled', () {
    test('defaults to false', () async {
      expect(await CalendarSyncService.instance.isEnabled(), isFalse);
    });

    test('enabling persists the chosen calendar id', () async {
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );

      expect(await CalendarSyncService.instance.isEnabled(), isTrue);
      expect(
        await CalendarSyncService.instance.selectedCalendarId(),
        'cal-1',
      );
    });

    test('disabling persists false', () async {
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      await CalendarSyncService.instance.setEnabled(false);

      expect(await CalendarSyncService.instance.isEnabled(), isFalse);
    });

    test('enabling backfills every note with an active/pending reminder, '
        'skipping a resolved overdue one', () async {
      final created = <String>[];
      CalendarSyncService.instance.debugCreateOrUpdateEvent = (event) async {
        created.add(event.title ?? '');
        return 'event-${created.length}';
      };
      final now = DateTime.now();
      final notes = [
        Note(
          id: 'upcoming',
          title: 'Upcoming',
          created: now,
          updated: now,
          reminderAt: now.add(const Duration(hours: 1)),
        ),
        Note(
          id: 'resolved',
          title: 'Resolved',
          created: now,
          updated: now,
          reminderAt: now.subtract(const Duration(hours: 1)),
          reminderResolved: true,
        ),
        Note(id: 'no-reminder', title: 'No reminder', created: now, updated: now),
      ];

      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: notes,
      );

      expect(created, ['Upcoming']);
    });

    test('disabling deletes every previously-created event and forgets '
        'the mapping', () async {
      CalendarSyncService.instance.debugCreateOrUpdateEvent =
          (event) async => 'event-1';
      final deleted = <(String, String)>[];
      CalendarSyncService.instance.debugDeleteEvent = (calendarId, eventId) async {
        deleted.add((calendarId, eventId));
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: [
          _note(id: 'a', reminderAt: DateTime.now().add(const Duration(hours: 1))),
        ],
      );

      await CalendarSyncService.instance.setEnabled(false);

      expect(deleted, [('cal-1', 'event-1')]);

      // A second note later, with sync re-enabled fresh, must not reuse
      // the forgotten link - confirms the mapping was actually cleared,
      // not just that delete was called once.
      CalendarSyncService.instance.debugCreateOrUpdateEvent = null;
      String? capturedExistingEventId = 'unset';
      CalendarSyncService.instance.debugCreateOrUpdateEvent = (event) async {
        capturedExistingEventId = event.eventId;
        return 'event-2';
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: [
          _note(id: 'a', reminderAt: DateTime.now().add(const Duration(hours: 1))),
        ],
      );
      expect(capturedExistingEventId, isNull);
    });
  });

  group('reconcile', () {
    test('does nothing while sync is disabled', () async {
      var called = false;
      CalendarSyncService.instance.debugCreateOrUpdateEvent = (event) async {
        called = true;
        return 'event-1';
      };
      final note = _note(
        id: 'a',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await CalendarSyncService.instance.reconcile(null, note);

      expect(called, isFalse);
    });

    test('creates an event for a brand-new note with a reminder, once '
        'enabled', () async {
      final created = <String>[];
      CalendarSyncService.instance.debugCreateOrUpdateEvent = (event) async {
        created.add(event.title ?? '');
        return 'event-1';
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      final note = _note(
        id: 'a',
        title: 'Groceries',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await CalendarSyncService.instance.reconcile(null, note);

      expect(created, ['Groceries']);
    });

    test('an edit to an unrelated field (e.g. color) does not touch the '
        'calendar at all', () async {
      var called = false;
      CalendarSyncService.instance.debugCreateOrUpdateEvent = (event) async {
        called = true;
        return 'event-1';
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      final note = _note(
        id: 'a',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await CalendarSyncService.instance.reconcile(null, note);
      called = false;

      await CalendarSyncService.instance.reconcile(note, note);

      expect(called, isFalse);
    });

    test('a title change updates the existing event in place rather than '
        'creating a second one', () async {
      final events = <dynamic>[];
      CalendarSyncService.instance.debugCreateOrUpdateEvent = (event) async {
        events.add(event);
        return event.eventId ?? 'event-1';
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      final note = _note(
        id: 'a',
        title: 'Original',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await CalendarSyncService.instance.reconcile(null, note);

      final renamed = note.copyWith(title: 'Renamed');
      await CalendarSyncService.instance.reconcile(note, renamed);

      expect(events, hasLength(2));
      expect(events[0].eventId, isNull);
      expect(events[1].eventId, 'event-1');
      expect(events[1].title, 'Renamed');
    });

    test('clearing a reminder removes its calendar event', () async {
      CalendarSyncService.instance.debugCreateOrUpdateEvent =
          (event) async => 'event-1';
      final deleted = <(String, String)>[];
      CalendarSyncService.instance.debugDeleteEvent = (calendarId, eventId) async {
        deleted.add((calendarId, eventId));
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      final note = _note(
        id: 'a',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await CalendarSyncService.instance.reconcile(null, note);

      final cleared = note.copyWith(reminderAt: null);
      await CalendarSyncService.instance.reconcile(note, cleared);

      expect(deleted, [('cal-1', 'event-1')]);
    });

    test('a note marked deleted removes its calendar event', () async {
      CalendarSyncService.instance.debugCreateOrUpdateEvent =
          (event) async => 'event-1';
      final deleted = <(String, String)>[];
      CalendarSyncService.instance.debugDeleteEvent = (calendarId, eventId) async {
        deleted.add((calendarId, eventId));
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      final note = _note(
        id: 'a',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await CalendarSyncService.instance.reconcile(null, note);

      final tombstoned = _note(id: 'a', reminderAt: note.reminderAt, deleted: true);
      await CalendarSyncService.instance.reconcile(note, tombstoned);

      expect(deleted, [('cal-1', 'event-1')]);
    });
  });

  group('removeForNote', () {
    test('a note that was never linked is a harmless no-op', () async {
      var called = false;
      CalendarSyncService.instance.debugDeleteEvent = (calendarId, eventId) async {
        called = true;
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );

      await CalendarSyncService.instance.removeForNote(_note(id: 'never-linked'));

      expect(called, isFalse);
    });

    test('removing twice only calls deleteEvent once - the link is '
        'forgotten after the first removal', () async {
      CalendarSyncService.instance.debugCreateOrUpdateEvent =
          (event) async => 'event-1';
      var deleteCalls = 0;
      CalendarSyncService.instance.debugDeleteEvent = (calendarId, eventId) async {
        deleteCalls++;
      };
      await CalendarSyncService.instance.setEnabled(
        true,
        calendarId: 'cal-1',
        notes: const [],
      );
      final note = _note(
        id: 'a',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await CalendarSyncService.instance.reconcile(null, note);

      await CalendarSyncService.instance.removeForNote(note);
      await CalendarSyncService.instance.removeForNote(note);

      expect(deleteCalls, 1);
    });
  });
}
