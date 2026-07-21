import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/db_service.dart';
import 'package:jotes/services/notification_service.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  group('resolved-reminder bookkeeping', () {
    test('a note is not resolved by default', () async {
      expect(
        await NotificationService.instance.debugIsReminderResolved('a'),
        isFalse,
      );
    });

    test(
      'markReminderResolved is reflected by debugIsReminderResolved',
      () async {
        await NotificationService.instance.markReminderResolved('a');

        expect(
          await NotificationService.instance.debugIsReminderResolved('a'),
          isTrue,
        );
      },
    );

    test('marking one note resolved does not affect another', () async {
      await NotificationService.instance.markReminderResolved('a');

      expect(
        await NotificationService.instance.debugIsReminderResolved('b'),
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
        await NotificationService.instance.debugIsReminderResolved(
          'reused-note',
        ),
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
  });
}
