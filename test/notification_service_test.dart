import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/db_service.dart';
import 'package:jotes/services/notification_service.dart';
import 'package:jotes/services/snooze_settings.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

NotificationResponse _actionResponse({String? payload, String? actionId}) =>
    NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      payload: payload,
      actionId: actionId,
    );

Note _note({required String id, DateTime? reminderAt}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: 'Title',
    body: 'Body',
    reminderAt: reminderAt,
    created: now,
    updated: now,
  );
}

void main() {
  setUpAll(() {
    DbService.instance.debugFactory = databaseFactoryMemory;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final existing = await DbService.instance.getAll();
    for (final note in existing) {
      await DbService.instance.delete(note.id);
    }
  });

  tearDown(() {
    NotificationService.instance.debugOnShow = null;
    NotificationService.instance.debugOnSchedule = null;
    NotificationService.instance.debugOnCancel = null;
    NotificationService.instance.debugActiveNotificationIds = null;
  });

  group('resolved-reminder bookkeeping', () {
    test('a note is not resolved by default', () async {
      expect(
        await NotificationService.instance.isReminderResolved('a'),
        isFalse,
      );
    });

    test('markReminderResolved is reflected by isReminderResolved', () async {
      await NotificationService.instance.markReminderResolved('a');

      expect(
        await NotificationService.instance.isReminderResolved('a'),
        isTrue,
      );
    });

    test('marking one note resolved does not affect another', () async {
      await NotificationService.instance.markReminderResolved('a');

      expect(
        await NotificationService.instance.isReminderResolved('b'),
        isFalse,
      );
    });

    test('schedule() clears a previously-resolved flag, so a note reused for '
        'a new reminder cycle starts unresolved again', () async {
      await NotificationService.instance.markReminderResolved('reused-note');
      NotificationService.instance.debugOnSchedule = (_) {};

      await NotificationService.instance.schedule(
        _note(
          id: 'reused-note',
          reminderAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      expect(
        await NotificationService.instance.isReminderResolved('reused-note'),
        isFalse,
      );
    });
  });

  group('restoreUnresolvedReminders', () {
    test('(re)shows an overdue note that has not been resolved', () async {
      final shown = <String>[];
      NotificationService.instance.debugOnShow = (note) => shown.add(note.id);
      await DbService.instance.upsert(
        _note(
          id: 'unresolved-overdue',
          reminderAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );

      await NotificationService.instance.restoreUnresolvedReminders();

      expect(shown, contains('unresolved-overdue'));
    });

    test('does not show an overdue note the user already resolved', () async {
      final shown = <String>[];
      NotificationService.instance.debugOnShow = (note) => shown.add(note.id);
      await DbService.instance.upsert(
        _note(
          id: 'resolved-overdue',
          reminderAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      await NotificationService.instance.markReminderResolved(
        'resolved-overdue',
      );

      await NotificationService.instance.restoreUnresolvedReminders();

      expect(shown, isNot(contains('resolved-overdue')));
    });

    test(
      'does not show a note whose reminder is still in the future',
      () async {
        final shown = <String>[];
        NotificationService.instance.debugOnShow = (note) => shown.add(note.id);
        await DbService.instance.upsert(
          _note(
            id: 'future-reminder',
            reminderAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        await NotificationService.instance.restoreUnresolvedReminders();

        expect(shown, isNot(contains('future-reminder')));
      },
    );

    test('does not show a note with no reminder at all', () async {
      final shown = <String>[];
      NotificationService.instance.debugOnShow = (note) => shown.add(note.id);
      await DbService.instance.upsert(_note(id: 'no-reminder'));

      await NotificationService.instance.restoreUnresolvedReminders();

      expect(shown, isEmpty);
    });

    test('does not re-show (and thus re-alert) an overdue reminder that is '
        'already showing in the tray - so a normal app-open leaves a still-'
        'visible notification alone, unlike a post-reboot open where the tray '
        'is empty', () async {
      final shown = <String>[];
      NotificationService.instance.debugOnShow = (note) => shown.add(note.id);
      final note = _note(
        id: 'already-showing',
        reminderAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await DbService.instance.upsert(note);
      // Pretend this note's notification is currently in the tray.
      NotificationService.instance.debugActiveNotificationIds = () async => {
        note.notificationId,
      };

      await NotificationService.instance.restoreUnresolvedReminders();

      expect(shown, isEmpty);
    });

    test(
      'still shows an unresolved overdue reminder that is NOT currently '
      'in the tray (the post-reboot case, where the tray was wiped)',
      () async {
        final shown = <String>[];
        NotificationService.instance.debugOnShow = (note) => shown.add(note.id);
        await DbService.instance.upsert(
          _note(
            id: 'wiped-from-tray',
            reminderAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        );
        // Tray reports nothing active - as after a reboot.
        NotificationService.instance.debugActiveNotificationIds = () async =>
            <int>{};

        await NotificationService.instance.restoreUnresolvedReminders();

        expect(shown, contains('wiped-from-tray'));
      },
    );
  });

  group('handleBackgroundReminderAction', () {
    test('Dismiss cancels the tray notification and marks the reminder '
        'resolved without touching the note in the DB', () async {
      final cancelled = <int>[];
      NotificationService.instance.debugOnCancel = cancelled.add;
      final note = _note(
        id: 'dismiss-me',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await DbService.instance.upsert(note);

      await handleBackgroundReminderAction(
        _actionResponse(payload: 'dismiss-me', actionId: 'dismiss'),
      );

      expect(cancelled, [note.notificationId]);
      expect(
        await NotificationService.instance.isReminderResolved('dismiss-me'),
        isTrue,
      );
      final stored = await DbService.instance.getById('dismiss-me');
      expect(
        stored!.reminderAt!.millisecondsSinceEpoch,
        note.reminderAt!.millisecondsSinceEpoch,
      );
    });

    test('Dismiss for a note that has since been deleted still marks it '
        'resolved, with no notification to cancel', () async {
      final cancelled = <int>[];
      NotificationService.instance.debugOnCancel = cancelled.add;

      await handleBackgroundReminderAction(
        _actionResponse(payload: 'already-deleted', actionId: 'dismiss'),
      );

      expect(cancelled, isEmpty);
      expect(
        await NotificationService.instance.isReminderResolved(
          'already-deleted',
        ),
        isTrue,
      );
    });

    test("Snooze cancels the tray notification and updates the note's "
        "reminderAt using the default snooze duration (1 hour), then "
        'reschedules it', () async {
      final cancelled = <int>[];
      NotificationService.instance.debugOnCancel = cancelled.add;
      final scheduled = <Note>[];
      NotificationService.instance.debugOnSchedule = scheduled.add;
      final note = _note(
        id: 'snooze-default',
        reminderAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await DbService.instance.upsert(note);

      await handleBackgroundReminderAction(
        _actionResponse(payload: 'snooze-default', actionId: 'snooze'),
      );

      expect(cancelled, [note.notificationId]);
      final stored = await DbService.instance.getById('snooze-default');
      final expected = DateTime.now().add(const Duration(hours: 1));
      expect(
        stored!.reminderAt!.difference(expected).inSeconds.abs(),
        lessThan(5),
      );
      expect(scheduled, hasLength(1));
      expect(scheduled.single.id, 'snooze-default');
    });

    test('Snooze respects a configured custom delay', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.custom);
      await SnoozeSettings.instance.setCustomDelayMinutes(20);
      final scheduled = <Note>[];
      NotificationService.instance.debugOnSchedule = scheduled.add;
      final note = _note(
        id: 'snooze-custom',
        reminderAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await DbService.instance.upsert(note);

      await handleBackgroundReminderAction(
        _actionResponse(payload: 'snooze-custom', actionId: 'snooze'),
      );

      final stored = await DbService.instance.getById('snooze-custom');
      final expected = DateTime.now().add(const Duration(minutes: 20));
      expect(
        stored!.reminderAt!.difference(expected).inSeconds.abs(),
        lessThan(5),
      );
      expect(scheduled, hasLength(1));
    });

    test('Snooze respects a configured time-of-day', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.timeOfDay);
      await SnoozeSettings.instance.setTimeOfDayMinutes(9 * 60);
      final scheduled = <Note>[];
      NotificationService.instance.debugOnSchedule = scheduled.add;
      final note = _note(
        id: 'snooze-time-of-day',
        reminderAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await DbService.instance.upsert(note);

      await handleBackgroundReminderAction(
        _actionResponse(payload: 'snooze-time-of-day', actionId: 'snooze'),
      );

      final stored = await DbService.instance.getById('snooze-time-of-day');
      final now = DateTime.now();
      final today9am = DateTime(now.year, now.month, now.day, 9);
      final expected = today9am.isAfter(now)
          ? today9am
          : today9am.add(const Duration(days: 1));
      expect(stored!.reminderAt, expected);
      expect(scheduled, hasLength(1));
    });

    test('a snooze action for a note that has since been deleted is a '
        'harmless no-op', () async {
      NotificationService.instance.debugOnSchedule = (_) {};

      await expectLater(
        handleBackgroundReminderAction(
          _actionResponse(payload: 'does-not-exist', actionId: 'snooze'),
        ),
        completes,
      );
    });

    test('a response with no payload is a harmless no-op', () async {
      await expectLater(
        handleBackgroundReminderAction(
          _actionResponse(payload: null, actionId: 'dismiss'),
        ),
        completes,
      );
    });

    test('a response with no actionId is a harmless no-op', () async {
      await expectLater(
        handleBackgroundReminderAction(
          _actionResponse(payload: 'some-note', actionId: null),
        ),
        completes,
      );
    });

    test('an unrecognized actionId is a harmless no-op, not treated as a '
        'snooze or dismiss', () async {
      final note = _note(
        id: 'unrecognized-action',
        reminderAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await DbService.instance.upsert(note);

      await handleBackgroundReminderAction(
        _actionResponse(payload: 'unrecognized-action', actionId: 'nonsense'),
      );

      expect(
        await NotificationService.instance.isReminderResolved(
          'unrecognized-action',
        ),
        isFalse,
      );
      final stored = await DbService.instance.getById('unrecognized-action');
      expect(
        stored!.reminderAt!.millisecondsSinceEpoch,
        note.reminderAt!.millisecondsSinceEpoch,
      );
    });
  });
}
